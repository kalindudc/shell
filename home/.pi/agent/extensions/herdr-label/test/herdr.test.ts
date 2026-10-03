import { after, before, describe, it } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import net from "node:net";
import { tmpdir } from "node:os";
import path from "node:path";
import { reportTokens } from "../herdr.ts";

type Reply = (request: any) => unknown;

/** A fake Herdr socket that records each request line and answers with `reply`. */
function fakeHerdr(socketPath: string, reply: Reply) {
	const requests: any[] = [];
	const server = net.createServer((socket) => {
		let buf = "";
		socket.on("data", (chunk) => {
			buf += chunk;
			const newline = buf.indexOf("\n");
			if (newline === -1) return;
			const request = JSON.parse(buf.slice(0, newline));
			requests.push(request);
			const answer = reply(request);
			if (answer !== undefined) socket.write(`${JSON.stringify(answer)}\n`);
		});
	});
	return { server, requests, listen: () => new Promise<void>((r) => server.listen(socketPath, () => r())) };
}

describe("reportTokens", () => {
	let dir: string;
	before(() => {
		dir = mkdtempSync(path.join(tmpdir(), "herdr-label-"));
	});
	after(() => rmSync(dir, { recursive: true, force: true }));

	it("sends one pane.report_metadata request for this pane and resolves on ok", async () => {
		const socketPath = path.join(dir, "ok.sock");
		const fake = fakeHerdr(socketPath, (req) => ({ id: req.id, result: { type: "ok" } }));
		await fake.listen();
		try {
			const result = await reportTokens({ socketPath, paneId: "w1:p1" }, { goal: "Fix it", cortex: null });
			assert.deepEqual(result, {});
			assert.equal(fake.requests.length, 1);
			const [req] = fake.requests;
			assert.equal(req.method, "pane.report_metadata");
			assert.equal(req.params.pane_id, "w1:p1");
			assert.equal(req.params.source, "user:pi-herdr-label");
			assert.deepEqual(req.params.tokens, { goal: "Fix it", cortex: null });
			assert.equal(typeof req.id, "string");
		} finally {
			fake.server.close();
		}
	});

	it("sends a strictly increasing seq so Herdr drops reports that arrive late", async () => {
		const socketPath = path.join(dir, "seq.sock");
		const fake = fakeHerdr(socketPath, (req) => ({ id: req.id, result: { type: "ok" } }));
		await fake.listen();
		try {
			const target = { socketPath, paneId: "w1:p1" };
			await reportTokens(target, { goal: "a", cortex: null });
			await reportTokens(target, { goal: "b", cortex: null });
			const [first, second] = fake.requests.map((r) => r.params.seq);
			assert.ok(Number.isSafeInteger(first) && Number.isSafeInteger(second));
			assert.ok(second > first, `${second} should be greater than ${first}`);
		} finally {
			fake.server.close();
		}
	});

	it("returns Herdr's error code and message", async () => {
		const socketPath = path.join(dir, "err.sock");
		const fake = fakeHerdr(socketPath, (req) => ({ id: req.id, error: { code: "pane_not_found", message: "no pane" } }));
		await fake.listen();
		try {
			const result = await reportTokens({ socketPath, paneId: "w1:p9" }, { goal: null, cortex: null });
			assert.deepEqual(result, { error: "pane_not_found: no pane" });
		} finally {
			fake.server.close();
		}
	});

	it("returns an error instead of throwing when the socket is missing", async () => {
		const result = await reportTokens({ socketPath: path.join(dir, "missing.sock"), paneId: "w1:p1" }, { goal: null, cortex: null });
		assert.match(result.error ?? "", /ENOENT/);
	});

	it("returns a timeout error when Herdr never answers", async () => {
		const socketPath = path.join(dir, "silent.sock");
		const fake = fakeHerdr(socketPath, () => undefined);
		await fake.listen();
		try {
			const result = await reportTokens({ socketPath, paneId: "w1:p1" }, { goal: null, cortex: null }, 50);
			assert.match(result.error ?? "", /timed out/);
		} finally {
			fake.server.closeAllConnections?.();
			fake.server.close();
		}
	});
});
