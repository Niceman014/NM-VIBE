import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createMusicServer } from './server.mjs';

const env = {};
const updateMetadata = {
  releases: {
    windows: {
      stable: {
        version: '1.1.0+2',
        minSupportedVersion: '1.0.0+1',
        releaseNotes: 'Security and stability improvements.',
        sha256: 'a'.repeat(64),
        sizeBytes: 123456,
        downloadUrl: 'PHASE_4C_DOWNLOAD_URL_PENDING',
      },
    },
  },
};

async function withServer(server, run) {
  server.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  try {
    await run(`http://127.0.0.1:${server.address().port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test('health endpoint returns service status without provider configuration', async () => {
  const server = createMusicServer({ env });
  await withServer(server, async (baseUrl) => {
    const response = await fetch(`${baseUrl}/health`);
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { status: 'ok' });
  });
});

test('retired catalog routes are unavailable', async () => {
  const server = createMusicServer({ env });
  await withServer(server, async (baseUrl) => {
    for (const path of ['/v1/music/search?q=ambient', '/v1/music/stream/42']) {
      const response = await fetch(`${baseUrl}${path}`);
      assert.equal(response.status, 404);
      assert.deepEqual(await response.json(), { error: 'Not found.' });
    }
  });
});

test('latest Windows update returns validated metadata', async () => {
  const server = createMusicServer({ env, updateManifest: updateMetadata });
  await withServer(server, async (baseUrl) => {
    const response = await fetch(
      `${baseUrl}/v1/updates/latest?platform=windows&channel=stable`,
    );
    assert.equal(response.status, 200);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.deepEqual(await response.json(), {
      platform: 'windows',
      channel: 'stable',
      version: '1.1.0+2',
      minSupportedVersion: '1.0.0+1',
      releaseNotes: 'Security and stability improvements.',
      sha256: 'a'.repeat(64),
      sizeBytes: 123456,
      downloadUrl: 'PHASE_4C_DOWNLOAD_URL_PENDING',
      downloadConfigured: false,
    });
  });
});

test('update endpoint validates platform, channel, and secure manifest fields', async () => {
  const server = createMusicServer({ env, updateManifest: updateMetadata });
  await withServer(server, async (baseUrl) => {
    const endpoint = `${baseUrl}/v1/updates/latest`;
    assert.equal(
      (await fetch(`${endpoint}?platform=unknown&channel=stable`)).status,
      400,
    );
    assert.equal(
      (await fetch(`${endpoint}?platform=windows&channel=nightly`)).status,
      400,
    );
  });

  const insecure = structuredClone(updateMetadata);
  insecure.releases.windows.stable.downloadUrl = 'http://updates.invalid/app.exe';
  const invalidServer = createMusicServer({ env, updateManifest: insecure });
  await withServer(invalidServer, async (baseUrl) => {
    const response = await fetch(
      `${baseUrl}/v1/updates/latest?platform=windows&channel=stable`,
    );
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), {
      error: 'Update metadata is not configured or is invalid.',
    });
  });
});

test('update metadata is cached briefly and requests are rate limited', async () => {
  const metadata = structuredClone(updateMetadata);
  const server = createMusicServer({
    env,
    requestLimit: 2,
    updateManifest: metadata,
  });
  await withServer(server, async (baseUrl) => {
    const endpoint = `${baseUrl}/v1/updates/latest?platform=windows&channel=stable`;
    const first = await fetch(endpoint);
    assert.equal(first.status, 200);
    metadata.releases.windows.stable.version = '1.2.0';

    const cached = await fetch(endpoint);
    assert.equal(cached.status, 200);
    assert.equal((await cached.json()).version, '1.1.0+2');

    const blocked = await fetch(endpoint);
    assert.equal(blocked.status, 429);
    assert.deepEqual(await blocked.json(), {
      error: 'Too many requests. Try again shortly.',
    });
  });
});

test('CORS rejects unknown origins and supports preflight for configured origins', async () => {
  const server = createMusicServer({ env: { CORS_ORIGINS: 'https://app.example' } });
  await withServer(server, async (baseUrl) => {
    const denied = await fetch(`${baseUrl}/health`, {
      headers: { origin: 'https://other.example' },
    });
    assert.equal(denied.status, 403);

    const preflight = await fetch(`${baseUrl}/health`, {
      method: 'OPTIONS',
      headers: { origin: 'https://app.example' },
    });
    assert.equal(preflight.status, 204);
    assert.equal(preflight.headers.get('access-control-allow-origin'), 'https://app.example');
  });
});
