import { createReadStream, statSync } from 'node:fs';
import { createServer } from 'node:http';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('./public/', import.meta.url));
const port = Number(process.env.WEB_ADMIN_PORT ?? 4750);
const types = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
};

createServer((req, res) => {
  const pathname = decodeURIComponent(new URL(req.url ?? '/', 'http://localhost').pathname);
  const relative = pathname === '/' ? 'index.html' : pathname.replace(/^\/+/, '');
  const candidate = normalize(join(root, relative));
  let file = candidate.startsWith(root) ? candidate : join(root, 'index.html');
  try {
    if (!statSync(file).isFile()) file = join(root, 'index.html');
  } catch {
    file = join(root, 'index.html');
  }
  res.writeHead(200, {
    'Content-Type': types[extname(file)] ?? 'application/octet-stream',
    'Cache-Control': extname(file) === '.html' ? 'no-store' : 'no-cache',
    'Content-Security-Policy': "default-src 'self'; connect-src 'self' http: https:; img-src 'self' data:; style-src 'self'; script-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'",
    'Referrer-Policy': 'no-referrer',
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
  });
  createReadStream(file).pipe(res);
}).listen(port, '127.0.0.1', () => {
  console.log(`FaceAttendance web admin: http://127.0.0.1:${port}`);
});
