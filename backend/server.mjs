import { createServer } from 'node:http';

export function createAppServer() {
  return createServer((request, response) => {
    if (request.method === 'GET' && request.url === '/health') {
      response.writeHead(200, { 'content-type': 'application/json; charset=utf-8' });
      response.end('{"status":"ok"}');
      return;
    }

    response.writeHead(404);
    response.end();
  });
}

if (process.argv[1]?.endsWith('server.mjs')) {
  const port = Number(process.env.PORT ?? 3000);
  createAppServer().listen(port, '0.0.0.0');
}
