import Fastify, { type FastifyInstance } from 'fastify';
import cors from '@fastify/cors';
import rateLimit from '@fastify/rate-limit';
import { config } from './config.js';
import { deviceRoutes } from './routes/device.js';
import { updateRoutes } from './routes/update.js';
import { adminAuthRoutes } from './routes/admin-auth.js';
import { employeeRoutes } from './routes/employees.js';
import { attendanceRoutes } from './routes/attendance.js';
import { correctionRoutes } from './routes/corrections.js';
import { adminMiscRoutes } from './routes/admin-misc.js';
import { leaveRoutes } from './routes/leave.js';
import { appError } from './auth/guards.js';
import { runRollover } from './services/attendance/service.js';

export async function buildApp(): Promise<FastifyInstance> {
  const app = Fastify({
    logger: { level: process.env.LOG_LEVEL ?? 'info' },
    ajv: { customOptions: { strictTypes: false } },
  });

  await app.register(cors, { origin: true });
  await app.register(rateLimit, {
    global: false,
  });

  app.get('/health', async () => ({ ok: true, time: new Date().toISOString() }));
  app.get('/', async () => ({ ok: true, service: 'faceattendance-api' }));

  deviceRoutes(app);
  updateRoutes(app);
  adminAuthRoutes(app);
  employeeRoutes(app);
  attendanceRoutes(app);
  correctionRoutes(app);
  adminMiscRoutes(app);
  leaveRoutes(app);

  app.setErrorHandler((err, req, reply) => {
    appError(reply, err);
  });

  return app;
}

let rolloverTimer: NodeJS.Timeout | null = null;

export function startRollover(app: FastifyInstance): void {
  const run = async () => {
    try {
      const n = await runRollover();
      if (n > 0) app.log.info({ closed: n }, 'rollover closed stale session(s)');
    } catch (err) {
      app.log.error({ err }, 'rollover failed');
    }
  };
  rolloverTimer = setInterval(run, 15 * 60 * 1000);
  void run();
}

export function main(): void {
  buildApp().then((app) => {
    app.addHook('onClose', () => {
      if (rolloverTimer) clearInterval(rolloverTimer);
    });
    app.listen({ port: config.port, host: '0.0.0.0' }, (err) => {
      if (err) {
        app.log.error(err);
        process.exit(1);
      }
      startRollover(app);
      app.log.info(`FaceAttendance API listening on :${config.port}`);
    });
  }).catch((err) => {
    console.error('app bootstrap failed', err);
    process.exit(1);
  });
}
