#!/usr/bin/env python3
"""Accuracy calibration harness for the FaceAttendance face model.

Runs the bundled InsightFace MobileFaceNet (app/assets/models/w600k_mbf.onnx)
against real face photos under simulated kiosk conditions and reports
genuine vs impostor cosine-similarity distributions. Used to calibrate
kAcceptThreshold / kAmbiguityMargin (see docs/accuracy.md).

Requirements: pip install insightface onnxruntime numpy opencv-python
The detector model is downloaded on first run (~15 MB).

Usage (from repo root):
    python scripts/bench/bench.py
"""
import os
import sys
import warnings

warnings.filterwarnings('ignore')

import numpy as np
import cv2
import onnxruntime as ort

ort.set_default_logger_severity(3)
from insightface.model_zoo import get_model
from insightface.utils import face_align

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REC = os.path.join(ROOT, 'app', 'assets', 'models', 'w600k_mbf.onnx')
WORK = os.path.dirname(os.path.abspath(__file__))
IMG_DIR = os.path.join(WORK, 'imgs')

TARGET = np.array([[38.2946, 51.6963], [73.5318, 51.5014], [56.0252, 71.7366],
                   [41.5493, 92.3655], [70.7299, 92.2041]], dtype=np.float64)


def load_session():
    return ort.InferenceSession(REC, providers=['CPUExecutionProvider'])


def umeyama(src, dst):
    sx, dx = src.mean(0), dst.mean(0)
    s, d = src - sx, dst - dx
    a = (s[:, 0] * d[:, 0] + s[:, 1] * d[:, 1]).sum()
    b = (s[:, 0] * d[:, 1] - s[:, 1] * d[:, 0]).sum()
    ss, dd = (s * s).sum(), (d * d).sum()
    scale = np.sqrt(dd / ss)
    theta = np.arctan2(b, a)
    c, sn = scale * np.cos(theta), scale * np.sin(theta)
    return np.array([[c, -sn, dx[0] - c * sx[0] + sn * sx[1]],
                     [sn, c, dx[1] - sn * sx[0] - c * sx[1]]], dtype=np.float64)


def embed(sess, img, lm):
    crop = cv2.warpAffine(img, umeyama(lm, TARGET), (112, 112),
                          flags=cv2.INTER_LINEAR, borderValue=(0, 0, 0, 0))
    x = (crop[:, :, 0:3].astype(np.float32) / 127.5 - 1.0).transpose(2, 0, 1)[None, ...]
    out = sess.run(['516'], {'input.1': x})[0][0].astype(np.float64)
    n = np.linalg.norm(out)
    return out / n if n else out


def nv21_degrade(bgr):
    h, w = bgr.shape[:2]
    h -= h % 2
    w -= w % 2
    bgr = bgr[:h, :w]
    yuv = cv2.cvtColor(bgr, cv2.COLOR_BGR2YUV_I420)
    y = yuv[:h].reshape(h, w)
    c = yuv[h:].reshape(h // 2, w // 2, 2)
    i420 = np.concatenate([y.flatten(), c[:, :, 0].flatten(), c[:, :, 1].flatten()]).astype(np.uint8)
    return cv2.cvtColor(i420.reshape(h * 3 // 2, w), cv2.COLOR_YUV2BGR_I420)


def collect(det):
    imgs = {}
    for f in sorted(os.listdir(IMG_DIR)):
        if not f.lower().endswith(('.jpg', '.jpeg', '.png')):
            continue
        img = cv2.imread(os.path.join(IMG_DIR, f))
        if img is None:
            continue
        _, kps = det.detect(img)
        if kps is None or len(kps) == 0:
            continue
        imgs[f] = (img, kps[0])
    return imgs


def report(sess, det, imgs, label, transform=None, jitter=0.0):
    files = list(imgs)
    person = [f.rsplit('-', 1)[0] for f in files]
    rows = []
    rng = np.random.default_rng(42)
    for f in files:
        img, kps = imgs[f]
        if transform:
            img = transform(img)
            _, k2 = det.detect(img)
            if k2 is not None and len(k2):
                lm = k2[0]
            else:
                lm = kps
        else:
            lm = kps
        if jitter:
            lm = lm + rng.normal(0, jitter, lm.shape)
        rows.append(embed(sess, img, lm))
    n = len(rows)
    M = np.zeros((n, n))
    for i in range(n):
        for j in range(n):
            M[i, j] = float(np.dot(rows[i], rows[j]))
    imp = [M[i, j] for i in range(n) for j in range(n)
           if i != j and person[i] != person[j]]
    gen = [M[i, j] for i in range(n) for j in range(n)
           if i != j and person[i] == person[j]]
    print(f'{label:34s} impostor max={max(imp):.3f} p95={np.percentile(imp, 95):.3f} '
          f'| genuine min={min(gen):.3f} mean={np.mean(gen):.3f} max={max(gen):.3f}')


def main():
    os.makedirs(IMG_DIR, exist_ok=True)
    from insightface.utils import storage as ifstorage
    if not os.path.exists(os.path.join(ROOT, 'app', 'assets', 'models', 'w600k_mbf.onnx')):
        print('model not found:', REC)
        sys.exit(1)
    ifstorage.download_onnx('models', 'buffalo_sc', root=os.path.join(WORK, 'zoo'),
                            download_zip=True)
    det = get_model(os.path.join(WORK, 'zoo', 'models', 'det_500m.onnx'))
    det.prepare(ctx_id=-1, det_thresh=0.5)
    sess = load_session()
    imgs = collect(det)
    if len(imgs) < 6:
        print(f'place at least 6 face photos in {IMG_DIR} '
              '(filename format: <person>-N.jpg, 2+ per person)')
        return
    report(sess, det, imgs, 'clean photos')
    report(sess, det, imgs, '640px + NV21 4:2:0',
           lambda img: nv21_degrade(cv2.resize(
               img, (640, int(img.shape[0] * 640 / img.shape[1])),
               interpolation=cv2.INTER_AREA)) if img.shape[1] > 640 else nv21_degrade(img))
    report(sess, det, imgs, '320px + NV21 4:2:0',
           lambda img: nv21_degrade(cv2.resize(
               img, (320, int(img.shape[0] * 320 / img.shape[1])),
               interpolation=cv2.INTER_AREA)) if img.shape[1] > 320 else nv21_degrade(img))
    report(sess, det, imgs, 'landmark noise 8px', jitter=8.0)


if __name__ == '__main__':
    main()