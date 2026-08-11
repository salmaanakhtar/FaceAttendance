import { SignJWT, jwtVerify } from 'jose';
import { config } from '../config.js';

export type TokenKind = 'device' | 'admin';

export interface TokenPayload {
  sub: string;
  org: string;
  kind: TokenKind;
}

const secret = new TextEncoder().encode(config.jwtSecret);

export async function signToken(payload: TokenPayload, ttlSec: number): Promise<string> {
  return new SignJWT({ org: payload.org, kind: payload.kind })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(payload.sub)
    .setIssuedAt()
    .setExpirationTime(`${ttlSec}s`)
    .sign(secret);
}

export async function verifyToken(token: string): Promise<TokenPayload | null> {
  try {
    const { payload } = await jwtVerify(token, secret);
    const kind = payload.kind;
    if (kind !== 'device' && kind !== 'admin') return null;
    if (typeof payload.sub !== 'string' || typeof payload.org !== 'string') return null;
    return { sub: payload.sub, org: payload.org, kind };
  } catch {
    return null;
  }
}

export function signDeviceToken(deviceId: string, orgId: string): Promise<string> {
  return signToken({ sub: deviceId, org: orgId, kind: 'device' }, config.jwtDeviceTtlSec);
}

export function signAdminAccessToken(adminId: string, orgId: string): Promise<string> {
  return signToken({ sub: adminId, org: orgId, kind: 'admin' }, config.jwtAdminTtlSec);
}
