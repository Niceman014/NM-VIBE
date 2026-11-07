import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const rateWindowMs = 60_000;
const maxRequestsPerWindow = 60;
const updateCacheWindowMs = 60_000;
const updateUrlPlaceholder = 'PHASE_4C_DOWNLOAD_URL_PENDING';

function json(response, status, body, headers = {}) {
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    ...headers,
  });
  response.end(JSON.stringify(body));
}

export function createMusicServer({
  env = process.env,
  requestLimit = maxRequestsPerWindow,
  updateManifest,
  updateManifestFile,
} = {}) {
  const requests = new Map();
  const updateResponses = new Map();
  const allowedOrigins = new Set(
    (env.CORS_ORIGINS ?? '')
      .split(',')
      .map((origin) => origin.trim())
      .filter(Boolean),
  );

  async function getLatestUpdate(platform, channel) {
    const key = `${platform}:${channel}`;
    const cached = updateResponses.get(key);
    if (cached && cached.expiresAt > Date.now()) return cached.value;
    if (cached) updateResponses.delete(key);

    let manifest = updateManifest;
    if (manifest == null) {
      const configPath = updateManifestFile ?? env.UPDATE_MANIFEST_FILE ??
        resolve(fileURLToPath(new URL('.', import.meta.url)), 'private', 'updates.json');
      try {
        manifest = JSON.parse(await readFile(configPath, 'utf8'));
      } catch {
        const error = new Error('Update metadata is not configured.');
        error.statusCode = 503;
        throw error;
      }
    }

    const release = manifest?.releases?.[platform]?.[channel];
    if (!release || typeof release !== 'object') {
      const error = new Error('No update is configured for this platform and channel.');
      error.statusCode = 404;
      throw error;
    }

    const { version, minSupportedVersion, releaseNotes, sha256, sizeBytes } = release;
    const downloadUrl = release.downloadUrl ?? updateUrlPlaceholder;
    const validVersion = (value) => {
      if (typeof value !== 'string') return false;
      const match = value.match(
        /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$/,
      );
      return Boolean(match) && !match[4]?.split('.').some((part) => /^0\d+$/.test(part));
    };
    let secureUrl = false;
    if (downloadUrl === updateUrlPlaceholder) {
      secureUrl = true;
    } else if (typeof downloadUrl === 'string') {
      try {
        const parsedUrl = new URL(downloadUrl);
        secureUrl = parsedUrl.protocol === 'https:' && parsedUrl.hostname.length > 0 &&
          parsedUrl.username.length === 0 && parsedUrl.password.length === 0;
      } catch {
        secureUrl = false;
      }
    }
    if (!validVersion(version) || !validVersion(minSupportedVersion) ||
        typeof releaseNotes !== 'string' || releaseNotes.length > 5000 ||
        typeof sha256 !== 'string' || !/^[a-f0-9]{64}$/i.test(sha256) ||
        !Number.isSafeInteger(sizeBytes) || sizeBytes < 1 ||
        sizeBytes > 2 * 1024 * 1024 * 1024 || !secureUrl) {
      const error = new Error('Update metadata is invalid.');
      error.statusCode = 503;
      throw error;
    }

    const value = {
      platform,
      channel,
      version,
      minSupportedVersion,
      releaseNotes,
      sha256: sha256.toLowerCase(),
      sizeBytes,
      downloadUrl,
      downloadConfigured: downloadUrl !== updateUrlPlaceholder,
    };
    updateResponses.set(key, { value, expiresAt: Date.now() + updateCacheWindowMs });
    return value;
  }

  return createServer(async (request, response) => {
    const origin = request.headers.origin;
    const corsHeaders = {};
    if (origin) {
      if (!allowedOrigins.has(origin)) {
        json(response, 403, { error: 'Origin is not allowed.' });
        return;
      }
      corsHeaders['access-control-allow-origin'] = origin;
      corsHeaders.vary = 'Origin';
    }
    if (request.method === 'OPTIONS') {
      response.writeHead(204, {
        ...corsHeaders,
        'access-control-allow-methods': 'GET, OPTIONS',
        'access-control-allow-headers': 'content-type',
        'access-control-max-age': '600',
      });
      response.end();
      return;
    }
    if (request.method !== 'GET') {
      json(response, 405, { error: 'Method not allowed.' }, corsHeaders);
      return;
    }

    const now = Date.now();
    const client = request.socket.remoteAddress ?? 'unknown';
    const rate = requests.get(client);
    if (!rate || now - rate.startedAt >= rateWindowMs) {
      requests.set(client, { startedAt: now, count: 1 });
    } else if (++rate.count > requestLimit) {
      json(response, 429, { error: 'Too many requests. Try again shortly.' }, corsHeaders);
      return;
    }
    if (requests.size > 2000) {
      for (const [key, value] of requests) {
        if (now - value.startedAt >= rateWindowMs) requests.delete(key);
      }
    }

    const url = new URL(request.url, 'http://localhost');
    if (url.pathname === '/health') {
      json(response, 200, { status: 'ok' }, corsHeaders);
      return;
    }

    try {
      if (url.pathname === '/v1/updates/latest') {
        const platform = url.searchParams.get('platform') ?? '';
        const channel = url.searchParams.get('channel') ?? '';
        if (platform !== 'windows') {
          json(response, 400, { error: 'Invalid update platform.' }, corsHeaders);
          return;
        }
        if (!['stable', 'beta'].includes(channel)) {
          json(response, 400, { error: 'Invalid update channel.' }, corsHeaders);
          return;
        }
        const update = await getLatestUpdate(platform, channel);
        json(response, 200, update, corsHeaders);
        return;
      }

      json(response, 404, { error: 'Not found.' }, corsHeaders);
    } catch (error) {
      const status = Number.isInteger(error.statusCode) ? error.statusCode : 502;
      json(response, status, {
        error: status === 503
          ? 'Update metadata is not configured or is invalid.'
          : status === 404
            ? 'No update is configured for this platform and channel.'
            : status === 502
              ? 'The service could not complete the request.'
              : 'The request failed.',
      }, corsHeaders);
    }
  });
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const server = createMusicServer();
  const port = Number.parseInt(process.env.PORT ?? '8787', 10);
  const host = process.env.HOST ?? '127.0.0.1';
  server.listen(port, host, () => {
    process.stdout.write(`NM VIBE service listening on http://${host}:${port}\n`);
  });
}
