import { spawn } from 'node:child_process';
import type { FastifyInstance } from 'fastify';
import { requireDevice } from '../auth/guards.js';
import { badRequest, notFound } from '../lib/errors.js';
import { audit } from '../services/audit.js';

/**
 * GitHub-based auto-update for kiosk APKs.
 * The phone cannot reach the private repo, so the backend (which has `gh`
 * authenticated) proxies both the release check and the APK download.
 * GitHub remains the source of truth.
 */

const REPO = 'salmaanakhtar/FaceAttendance';

interface ReleaseAsset {
  id: number;
  name: string;
  size: number;
}

function ghJson(args: string[]): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const child = spawn('gh', args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let out = '';
    let err = '';
    child.stdout.on('data', (d) => (out += d));
    child.stderr.on('data', (d) => (err += d));
    child.on('error', (e) => reject(new Error(`gh not available: ${e.message}`)));
    child.on('close', (code) => {
      if (code !== 0) return reject(new Error(`gh failed (${code}): ${err.slice(0, 300)}`));
      try {
        resolve(JSON.parse(out));
      } catch {
        reject(new Error('gh returned invalid JSON'));
      }
    });
  });
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
      const release = (await ghJson([
        'api',
        `repos/${REPO}/releases/latest`,
        '--jq',
        '{tag_name, name, assets: [.assets[] | {id, name, size}]}',
      ])) as { tag_name: string; name: string; assets: ReleaseAsset[] };
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
      const child = spawn(
        'gh',
        ['api', '-H', 'Accept: application/octet-stream', `repos/${REPO}/releases/assets/${assetId}`],
        { stdio: ['ignore', 'pipe', 'pipe'] },
      );
      reply.header('Content-Type', 'application/vnd.android.package-archive');
      reply.header('Content-Disposition', 'attachment; filename="faceattendance.apk"');
      reply.hijack();
      reply.raw.on('close', () => child.kill());
      child.stderr.on('data', () => {});
      child.on('error', () => reply.raw.destroy());
      child.stdout.pipe(reply.raw);
    } catch (err) {
      app.log.warn({ err }, 'update download failed');
      throw notFound('release asset not found');
    }
  });
}
