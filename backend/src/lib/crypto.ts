import { randomBytes, scryptSync, timingSafeEqual, createCipheriv, createDecipheriv, createHash } from 'node:crypto';

const SCRYPT_KEYLEN = 64;

export function randomId(bytes = 16): string {
  return randomBytes(bytes).toString('hex');
}

export function sha256Hex(input: string): string {
  return createHash('sha256').update(input).digest('hex');
}

export function hashSecret(secret: string): string {
  const salt = randomBytes(16).toString('hex');
  const hash = scryptSync(secret, salt, SCRYPT_KEYLEN);
  return `scrypt$${salt}$${hash.toString('hex')}`;
}

export function verifySecret(secret: string, stored: string): boolean {
  const [scheme, salt, hashHex] = stored.split('$');
  if (scheme !== 'scrypt' || !salt || !hashHex) return false;
  const hash = scryptSync(secret, salt, SCRYPT_KEYLEN);
  const storedBuf = Buffer.from(hashHex, 'hex');
  return storedBuf.length === hash.length && timingSafeEqual(storedBuf, hash);
}

const IV_LEN = 12;

export function encryptAesGcm(plain: Buffer, key: Buffer): Buffer {
  const iv = randomBytes(IV_LEN);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const enc = Buffer.concat([cipher.update(plain), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, enc]);
}

export function decryptAesGcm(data: Buffer, key: Buffer): Buffer {
  if (data.length < IV_LEN + 16) throw new Error('ciphertext too short');
  const iv = data.subarray(0, IV_LEN);
  const tag = data.subarray(IV_LEN, IV_LEN + 16);
  const enc = data.subarray(IV_LEN + 16);
  const decipher = createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(enc), decipher.final()]);
}

/** Deterministic key derivation from org-level secret: never store raw key beside data. */
export function deriveOrgKey(orgSecret: string): Buffer {
  return scryptSync(`faceatt:org:${orgSecret}`, 'faceatt-org-salt', 32);
}
