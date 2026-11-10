import { Readable } from 'node:stream';
import type { FastifyInstance } from 'fastify';
import { requireDevice } from '../auth/guards.js';
import { badRequest, notFound } from '../lib/errors.js';
import { audit } from '../services/audit.js';

/**
 * GitHub-backed auto-update for kiosk APKs.
 *
 * The kiosk cannot reach GitHub directly, so the backend proxies the release
 * lookup and the APK download. This uses the public GitHub REST API rather
 * than the `gh` CLI so it works inside the container image. The repository is
 * public; `GITHUB_TOKEN` is optional and only raises the API rate limit.
 */

const REPO = 'salmaanakhtar/FaceAttendance';

interface ReleaseAsset {
  id: number;
  name: string;
  size: number;
  browser_download_url: string;
}

interface Release {
  tag_name: string;
  name: string;
  assets: ReleaseAsset[];
}

function githubHeaders(accept = 'application/vnd.github+json'): Record<string, string> {
  const headers: Record<string, string> = {
    Accept: accept,
    'User-Agent': 'yabil-timekeep-updater',
  };
  const token = process.env.GITHUB_TOKEN?.trim();
  if (token) headers.Authorization = `Bearer ${token}`;
  return headers;
}

async function latestRelease(): Promise<Release> {
  const res = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
    headers: githubHeaders(),
  });
  if (!res.ok) throw new Error(`GitHub release lookup failed (${res.status})`);
  return (await res.json()) as Release;
}

function parseTag(tag: string): number[] {
  const m = tag.replace(/^v/, '').split('.').map((n) => parseInt(n, 10));
  return m.every((n) => !Number.isNaN(n)) ? m : [0, 0, 0];
}

export function updateRoutes(app: FastifyInstance): void {
  // Check for a newer release than the app's current tag.
  app.get('/api/v1/device/update', { preHandler: requireDevice }, async (req, reply) => {
    const q = req.query as { currentTag?: string };
    try {
      const release = await latestRelease();
      const apk = release.assets.find((a) => a.name.endsWith('.apk'));
      if (!apk) {
        return reply.send({ upToDate: true, latest: release.tag_name, asset: null });
      }
      const current = q.currentTag ? parseTag(q.currentTag) : [0, 0, 0];
      const latest = parseTag(release.tag_name);
      const newer =
        latest[0]! > current[0]! ||
        (latest[0] === current[0] && latest[1]! > current[1]!) ||
        (latest[0] === current[0] && latest[1] === current[1] && latest[2]! > current[2]!);
      await audit({
        orgId: req.device!.orgId,
        actorType: 'device',
        actorId: req.device!.id,
        action: 'update_check',
        details: { currentTag: q.currentTag ?? null, latest: release.tag_name, newer },
      });
      return reply.send({
        upToDate: !newer,
        latest: release.tag_name,
        releaseName: release.name,
        asset: { id: apk.id, name: apk.name, size: apk.size },
      });
    } catch (err) {
      // GitHub unreachable — treat as "no update available", never block the kiosk.
      app.log.warn({ err }, 'update check failed');
      return reply.send({ upToDate: true, latest: null, asset: null, error: 'github unreachable' });
    }
  });

  // Stream the APK binary for the release asset.
  app.get('/api/v1/device/update/download', { preHandler: requireDevice }, async (req, reply) => {
    const q = req.query as { assetId?: string };
    const assetId = Number(q.assetId);
    if (!Number.isInteger(assetId) || assetId <= 0) throw badRequest('assetId required');
    try {
      await audit({
        orgId: req.device!.orgId,
        actorType: 'device',
        actorId: req.device!.id,
        action: 'update_download',
        details: { assetId },
      });
      const release = await latestRelease();
      const asset = release.assets.find((a) => a.id === assetId);
      if (!asset) throw notFound('release asset not found');

      const upstream = await fetch(asset.browser_download_url, {
        headers: githubHeaders('application/octet-stream'),
        redirect: 'follow',
      });
      if (!upstream.ok || !upstream.body) throw notFound('release asset not found');

      reply.header('Content-Type', 'application/vnd.android.package-archive');
      reply.header('Content-Disposition', 'attachment; filename="faceattendance.apk"');
      reply.header('Content-Length', String(asset.size));
      reply.hijack();
      Readable.fromWeb(upstream.body as import('node:stream/web').ReadableStream).pipe(reply.raw);
    } catch (err) {
      app.log.warn({ err }, 'update download failed');
      throw notFound('release asset not found');
    }
  });
}
