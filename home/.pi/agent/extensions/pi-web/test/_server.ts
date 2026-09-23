/**
 * Tiny local HTTP server for tests (node:http only).
 * Routes are plain functions; the server binds to 127.0.0.1 on a random port.
 */

import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";

export type Route = (req: IncomingMessage, res: ServerResponse, url: URL) => void | Promise<void>;

export interface TestServer {
	url: string;
	server: Server;
	requests: Array<{ method: string; path: string; headers: IncomingMessage["headers"] }>;
	close(): Promise<void>;
}

export async function startServer(routes: Record<string, Route>): Promise<TestServer> {
	const requests: TestServer["requests"] = [];
	const server = createServer(async (req, res) => {
		const url = new URL(req.url ?? "/", "http://127.0.0.1");
		requests.push({ method: req.method ?? "GET", path: url.pathname + url.search, headers: req.headers });
		const route = routes[url.pathname];
		if (!route) {
			res.writeHead(404, { "content-type": "text/html" });
			res.end("<html><head><title>Not Found</title></head><body><h1>404</h1></body></html>");
			return;
		}
		try {
			await route(req, res, url);
		} catch (err) {
			res.writeHead(500, { "content-type": "text/plain" });
			res.end(String(err));
		}
	});
	await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
	const { port } = server.address() as AddressInfo;
	return {
		url: `http://127.0.0.1:${port}`,
		server,
		requests,
		close: () => new Promise<void>((resolve, reject) => server.close((e) => (e ? reject(e) : resolve()))),
	};
}

export function html(res: ServerResponse, body: string, status = 200, headers: Record<string, string> = {}): void {
	res.writeHead(status, { "content-type": "text/html; charset=utf-8", ...headers });
	res.end(body);
}
