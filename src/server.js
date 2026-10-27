'use strict';
/**
 * Servidor estático mínimo (sin dependencias) para Azure App Service Linux (Node).
 * - Sirve el build de Angular desde este mismo directorio.
 * - Fallback de SPA: rutas sin extensión devuelven index.html.
 * - Aplica las cabeceras de seguridad HTTP a todas las respuestas.
 * - /healthz responde 200 para las pruebas de humo.
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const ROOT = __dirname;
const PORT = process.env.PORT || process.env.WEBSITES_PORT || 8080;

const SECURITY_HEADERS = {
  'Content-Security-Policy':
    "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com data:; img-src 'self' data: https://assets.pokemon.com; connect-src 'self' https://pokeapi.co https://beta.pokeapi.co; object-src 'none'; base-uri 'self'; form-action 'self'; frame-ancestors 'none'; upgrade-insecure-requests",
  'Strict-Transport-Security': 'max-age=63072000; includeSubDomains',
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'Permissions-Policy':
    'accelerometer=(), camera=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), payment=(), usb=()',
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Resource-Policy': 'same-origin',
};

// SOLO PARA LA PRÁCTICA: permite medir la calificación "antes" en securityheaders.com.
// Con DISABLE_SECURITY_HEADERS=true no se envían las cabeceras. En producción debe estar sin definir.
const ACTIVE_HEADERS = process.env.DISABLE_SECURITY_HEADERS === 'true' ? {} : SECURITY_HEADERS;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
};
const COMPRESSIBLE = new Set(['.html', '.js', '.css', '.json', '.txt', '.svg']);
const HASHED = /\.[0-9a-f]{16}\.(js|css|png|ttf|woff2?)$/;

function send(res, status, headers, body) {
  res.writeHead(status, { ...ACTIVE_HEADERS, ...headers });
  res.end(body);
}

function resolveFile(urlPath) {
  let decoded;
  try {
    decoded = decodeURIComponent(urlPath);
  } catch (e) {
    return null;
  }
  const candidate = path.normalize(path.join(ROOT, decoded));
  if (candidate !== ROOT && !candidate.startsWith(ROOT + path.sep)) return null;
  return candidate;
}

const server = http.createServer((req, res) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return send(res, 405, { Allow: 'GET, HEAD' }, 'Method Not Allowed');
  }
  const urlPath = (req.url || '/').split('?')[0];

  if (urlPath === '/healthz') {
    return send(
      res,
      200,
      { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' },
      'ok'
    );
  }

  let file = resolveFile(urlPath);
  if (file === null) return send(res, 400, { 'Content-Type': 'text/plain' }, 'Bad Request');
  // Nunca servir el propio servidor ni archivos de configuración del hosting.
  const base = path.basename(file);
  if (base === 'server.js' || base === 'web.config') file = path.join(ROOT, 'index.html');

  let stat = fs.existsSync(file) ? fs.statSync(file) : null;
  if (stat && stat.isDirectory()) {
    file = path.join(file, 'index.html');
    stat = fs.existsSync(file) ? fs.statSync(file) : null;
  }
  if (!stat) {
    if (path.extname(urlPath)) {
      return send(res, 404, { 'Content-Type': 'text/plain; charset=utf-8' }, 'Not Found');
    }
    file = path.join(ROOT, 'index.html'); // fallback de SPA
    stat = fs.statSync(file);
  }

  const ext = path.extname(file).toLowerCase();
  const headers = { 'Content-Type': MIME[ext] || 'application/octet-stream' };
  headers['Cache-Control'] = HASHED.test(file) ? 'public, max-age=31536000, immutable' : 'no-cache';

  const wantsGzip = COMPRESSIBLE.has(ext) && /\bgzip\b/.test(req.headers['accept-encoding'] || '');
  if (wantsGzip) {
    headers['Content-Encoding'] = 'gzip';
    headers['Vary'] = 'Accept-Encoding';
  } else {
    headers['Content-Length'] = stat.size;
  }
  res.writeHead(200, { ...ACTIVE_HEADERS, ...headers });
  if (req.method === 'HEAD') return res.end();
  const stream = fs.createReadStream(file);
  stream.on('error', () => res.destroy());
  (wantsGzip ? stream.pipe(zlib.createGzip()) : stream).pipe(res);
});

server.listen(PORT, () => console.log(`PokeDex escuchando en el puerto ${PORT}`));
