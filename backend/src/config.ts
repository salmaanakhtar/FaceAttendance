import 'dotenv/config';

export const config = {
  port: Number(process.env.PORT ?? 4747),
  databaseUrl: process.env.DATABASE_URL ?? 'postgres://postgres@127.0.0.1:5434/faceattendance',
  jwtSecret: process.env.JWT_SECRET ?? 'dev-secret-change-me',
  jwtAdminTtlSec: Number(process.env.JWT_ADMIN_TTL_SEC ?? 30 * 60),
  jwtDeviceTtlSec: Number(process.env.JWT_DEVICE_TTL_SEC ?? 7 * 24 * 3600),
  adminSessionTtlSec: Number(process.env.ADMIN_SESSION_TTL_SEC ?? 4 * 3600),
  orgKey: process.env.ORG_ENCRYPTION_KEY ?? 'dev-encryption-key-change-me',
  deviceAuthRateLimit: Number(process.env.DEVICE_AUTH_RATE_LIMIT ?? 10),
};
