import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { brotliCompressSync, gzipSync } from "node:zlib";
import {
	NetError,
	createLimiter,
	decodeText,
	isBlockedAddress,
	isBlockedIPv4,
	isBlockedIPv6,
	mimeType,
	parseIPv6,
	pinnedLookup,
	readBodyLimited,
	safeFetch,
	validateUrl,
} from "../net.ts";
import { type TestServer, html, startServer } from "./_server.ts";

describe("address classification", () => {
	it("blocks loopback, private, link-local, CGNAT, multicast and reserved IPv4", () => {
		for (const ip of ["127.0.0.1", "127.255.255.255", "10.1.2.3", "172.16.0.1", "172.31.255.255", "192.168.1.1", "169.254.169.254", "100.64.0.1", "0.0.0.0", "224.0.0.1", "255.255.255.255", "192.0.2.1", "198.51.100.7", "203.0.113.9"]) {
			assert.equal(isBlockedIPv4(ip), true, ip);
		}
	});
	it("allows public IPv4", () => {
		for (const ip of ["8.8.8.8", "1.1.1.1", "172.32.0.1", "172.15.0.1", "100.128.0.1", "93.184.216.34"]) {
			assert.equal(isBlockedIPv4(ip), false, ip);
		}
	});
	it("rejects malformed IPv4", () => {
		assert.equal(isBlockedIPv4("1.2.3"), true);
		assert.equal(isBlockedIPv4("1.2.3.999"), true);
	});
	it("parses IPv6 including :: compression and embedded IPv4", () => {
		assert.deepEqual(parseIPv6("::1"), [0, 0, 0, 0, 0, 0, 0, 1]);
		assert.deepEqual(parseIPv6("2001:db8::ff00:42:8329"), [0x2001, 0xdb8, 0, 0, 0, 0xff00, 0x42, 0x8329]);
		assert.deepEqual(parseIPv6("::ffff:127.0.0.1"), [0, 0, 0, 0, 0, 0xffff, 0x7f00, 1]);
		assert.equal(parseIPv6("1:2:3:4:5:6:7:8:9"), null);
		assert.equal(parseIPv6("::1::2"), null);
	});
	it("blocks loopback, unspecified, ULA, link-local, multicast and mapped-private IPv6", () => {
		for (const ip of ["::1", "::", "fc00::1", "fd12:3456::1", "fe80::1", "ff02::1", "::ffff:127.0.0.1", "::ffff:10.0.0.1", "::ffff:192.168.0.1", "64:ff9b::7f00:1", "2001:db8::1"]) {
			assert.equal(isBlockedIPv6(ip), true, ip);
		}
	});
	it("allows public IPv6", () => {
		for (const ip of ["2606:4700:4700::1111", "2a00:1450:4001:80b::200e", "::ffff:8.8.8.8"]) {
			assert.equal(isBlockedIPv6(ip), false, ip);
		}
	});
	it("treats non-IP strings as blocked", () => {
		assert.equal(isBlockedAddress("not-an-ip"), true);
	});
});

describe("validateUrl", () => {
	const publicResolver = async () => [{ address: "93.184.216.34", family: 4 }];
	const privateResolver = async () => [{ address: "93.184.216.34", family: 4 }, { address: "10.0.0.5", family: 4 }];

	it("rejects non-http schemes and credentials", async () => {
		await assert.rejects(validateUrl("ftp://example.com/"), (e: unknown) => e instanceof NetError && e.kind === "blocked");
		await assert.rejects(validateUrl("file:///etc/passwd"), NetError);
		await assert.rejects(validateUrl("https://user:pw@example.com/"), /credentials/);
		await assert.rejects(validateUrl("not a url"), /Invalid URL/);
	});
	it("blocks localhost and literal private addresses without DNS", async () => {
		await assert.rejects(validateUrl("http://localhost:3000/"), /local network/);
		await assert.rejects(validateUrl("http://foo.localhost/"), /local network/);
		await assert.rejects(validateUrl("http://127.0.0.1/"), /Blocked address/);
		await assert.rejects(validateUrl("http://[::1]/"), /Blocked address/);
		await assert.rejects(validateUrl("http://169.254.169.254/latest/meta-data"), /Blocked address/);
	});
	it("blocks hostnames whose resolved address set includes any private address", async () => {
		await assert.rejects(validateUrl("https://evil.example/", { resolver: privateResolver }), /resolves to 10\.0\.0\.5/);
	});
	it("allows hostnames that resolve to public addresses", async () => {
		const url = await validateUrl("https://example.com/path?q=1", { resolver: publicResolver });
		assert.equal(url.href, "https://example.com/path?q=1");
	});
	it("allows everything private when allowPrivateNetwork is set (still enforcing scheme)", async () => {
		const url = await validateUrl("http://127.0.0.1:8080/", { allowPrivateNetwork: true });
		assert.equal(url.port, "8080");
		await assert.rejects(validateUrl("gopher://127.0.0.1/", { allowPrivateNetwork: true }), NetError);
	});
	it("reports DNS failures as network errors", async () => {
		await assert.rejects(
			validateUrl("https://nope.invalid/", { resolver: async () => { throw new Error("ENOTFOUND"); } }),
			(e: unknown) => e instanceof NetError && e.kind === "network",
		);
	});
});

describe("safeFetch + readBodyLimited (local server)", () => {
	let server: TestServer;
	before(async () => {
		server = await startServer({
			"/ok": (_req, res) => html(res, "<p>ok</p>"),
			"/redir1": (_req, res) => { res.writeHead(302, { location: "/redir2" }); res.end(); },
			"/redir2": (_req, res) => { res.writeHead(301, { location: "/ok" }); res.end(); },
			"/loop": (_req, res) => { res.writeHead(302, { location: "/loop" }); res.end(); },
			"/noloc": (_req, res) => { res.writeHead(302); res.end(); },
			"/external": (_req, res) => { res.writeHead(302, { location: "http://169.254.169.254/" }); res.end(); },
			"/big": (_req, res) => { res.writeHead(200, { "content-type": "text/plain" }); res.end("x".repeat(10_000)); },
			"/big-declared": (_req, res) => { res.writeHead(200, { "content-type": "text/plain", "content-length": "10000" }); res.end("x".repeat(10_000)); },
			"/slow": (_req, res) => { setTimeout(() => { res.writeHead(200); res.end("late"); }, 2000); },
			"/latin1": (_req, res) => { res.writeHead(200, { "content-type": "text/plain; charset=iso-8859-1" }); res.end(Buffer.from([0x63, 0x61, 0x66, 0xe9])); },
			"/gzip": (_req, res) => { const body = gzipSync(Buffer.from("gzipped body ".repeat(100))); res.writeHead(200, { "content-type": "text/plain", "content-encoding": "gzip", "content-length": String(body.length) }); res.end(body); },
			"/br": (_req, res) => { res.writeHead(200, { "content-type": "text/plain", "content-encoding": "br" }); res.end(brotliCompressSync(Buffer.from("brotli body"))); },
			"/bad-gzip": (_req, res) => { res.writeHead(200, { "content-type": "text/plain", "content-encoding": "gzip" }); res.end(Buffer.from("this is not gzip")); },
			"/host": (req, res) => { res.writeHead(200, { "content-type": "text/plain" }); res.end(String(req.headers.host)); },
			"/nocontent": (_req, res) => { res.writeHead(204); res.end(); },
			"/post": async (req, res) => {
				let body = "";
				for await (const chunk of req) body += chunk;
				res.writeHead(200, { "content-type": "application/json" });
				res.end(JSON.stringify({ method: req.method, body }));
			},
		});
	});
	after(() => server.close());

	const opts = { timeoutMs: 5000, maxBytes: 1_000_000, allowPrivateNetwork: true };

	it("refuses to fetch a loopback server unless allowPrivateNetwork is set", async () => {
		await assert.rejects(safeFetch(`${server.url}/ok`, { ...opts, allowPrivateNetwork: false }), /Blocked address/);
	});
	it("follows redirect chains manually and reports the final URL", async () => {
		const { response, finalUrl, redirects } = await safeFetch(`${server.url}/redir1`, opts);
		assert.equal(response.status, 200);
		assert.equal(finalUrl, `${server.url}/ok`);
		assert.equal(redirects, 2);
		assert.equal(new TextDecoder().decode(await readBodyLimited(response, 1000)), "<p>ok</p>");
	});
	it("caps redirects and rejects missing Location", async () => {
		await assert.rejects(safeFetch(`${server.url}/loop`, { ...opts, maxRedirects: 3 }), /Too many redirects/);
		await assert.rejects(safeFetch(`${server.url}/noloc`, opts), /without Location/);
	});
	it("re-validates every redirect hop against the SSRF policy", async () => {
		await assert.rejects(safeFetch(`${server.url}/external`, { ...opts, allowPrivateNetwork: false }), /Blocked/);
	});
	it("enforces the byte limit while streaming and via content-length", async () => {
		const a = await safeFetch(`${server.url}/big`, opts);
		await assert.rejects(readBodyLimited(a.response, 5000), (e: unknown) => e instanceof NetError && e.kind === "too-large");
		const b = await safeFetch(`${server.url}/big-declared`, opts);
		await assert.rejects(readBodyLimited(b.response, 5000), /exceeds limit/);
	});
	it("times out slow servers with a clear message", async () => {
		await assert.rejects(safeFetch(`${server.url}/slow`, { ...opts, timeoutMs: 300 }), (e: unknown) => e instanceof NetError && e.kind === "timeout");
	});
	it("propagates caller aborts as 'aborted'", async () => {
		const ac = new AbortController();
		setTimeout(() => ac.abort(), 50);
		await assert.rejects(safeFetch(`${server.url}/slow`, { ...opts, signal: ac.signal }), (e: unknown) => e instanceof NetError && e.kind === "aborted");
	});
	it("sends POST bodies and custom headers", async () => {
		const { response } = await safeFetch(`${server.url}/post`, { ...opts, method: "POST", body: '{"a":1}', headers: { "x-test": "1" } });
		const json = JSON.parse(new TextDecoder().decode(await readBodyLimited(response, 1000)));
		assert.deepEqual(json, { method: "POST", body: '{"a":1}' });
		assert.equal(server.requests.at(-1)?.headers["x-test"], "1");
	});
	it("decodes non-UTF-8 charsets from Content-Type", async () => {
		const { response } = await safeFetch(`${server.url}/latin1`, opts);
		assert.equal(decodeText(await readBodyLimited(response, 100), response.headers.get("content-type")), "café");
	});
	it("transparently decodes gzip and brotli bodies and drops the encoding headers", async () => {
		const g = await safeFetch(`${server.url}/gzip`, opts);
		assert.equal(g.response.headers.get("content-encoding"), null);
		assert.equal(g.response.headers.get("content-length"), null);
		assert.equal(new TextDecoder().decode(await readBodyLimited(g.response, 100_000)), "gzipped body ".repeat(100));
		const b = await safeFetch(`${server.url}/br`, opts);
		assert.equal(new TextDecoder().decode(await readBodyLimited(b.response, 1000)), "brotli body");
	});
	it("reports corrupt compressed bodies as network errors", async () => {
		const { response } = await safeFetch(`${server.url}/bad-gzip`, opts);
		await assert.rejects(readBodyLimited(response, 1000), (e: unknown) => e instanceof NetError && e.kind === "network");
	});
	it("handles null-body statuses", async () => {
		const { response } = await safeFetch(`${server.url}/nocontent`, opts);
		assert.equal(response.status, 204);
		assert.equal((await readBodyLimited(response, 10)).byteLength, 0);
	});

	describe("DNS pinning", () => {
		it("connects to the address returned by the vetting resolver, not a second system lookup", async () => {
			// `pinned.invalid` cannot resolve via system DNS; the only way this request can
			// reach the local server is through the pinned lookup.
			let lookups = 0;
			const resolver = async (hostname: string) => {
				lookups++;
				assert.equal(hostname, "pinned.invalid");
				return [{ address: "127.0.0.1", family: 4 }];
			};
			const port = new URL(server.url).port;
			const { response, finalUrl } = await safeFetch(`http://pinned.invalid:${port}/host`, { ...opts, resolver });
			assert.equal(response.status, 200);
			assert.equal(finalUrl, `http://pinned.invalid:${port}/host`);
			assert.equal(new TextDecoder().decode(await readBodyLimited(response, 1000)), `pinned.invalid:${port}`, "Host header keeps the hostname");
			assert.equal(lookups, 1, "exactly one resolution per hop");
		});
		it("re-resolves and re-pins on every redirect hop", async () => {
			const seen: string[] = [];
			const resolver = async (hostname: string) => {
				seen.push(hostname);
				return [{ address: "127.0.0.1", family: 4 }];
			};
			const port = new URL(server.url).port;
			const { redirects } = await safeFetch(`http://hop-a.invalid:${port}/redir1`, { ...opts, resolver });
			assert.equal(redirects, 2);
			assert.deepEqual(seen, ["hop-a.invalid", "hop-a.invalid", "hop-a.invalid"]);
		});
		it("a rebinding answer that includes a private address is rejected before any connection", async () => {
			let connected = false;
			const resolver = async () => {
				connected = true;
				return [{ address: "93.184.216.34", family: 4 }, { address: "127.0.0.1", family: 4 }];
			};
			await assert.rejects(safeFetch("http://rebind.invalid/", { ...opts, allowPrivateNetwork: false, resolver }), /resolves to 127\.0\.0\.1/);
			assert.equal(connected, true);
		});
		it("pinnedLookup answers both callback shapes with only vetted addresses", () => {
			const lookupFn = pinnedLookup([{ address: "2001:db8::1", family: 6 }, { address: "1.2.3.4", family: 4 }]);
			lookupFn("x", { all: true }, ((err: Error | null, list: Array<{ address: string; family: number }>) => {
				assert.equal(err, null);
				assert.deepEqual(list.map((a) => a.address), ["2001:db8::1", "1.2.3.4"]);
			}) as never);
			lookupFn("x", {}, ((err: Error | null, address: string, family: number) => {
				assert.equal(err, null);
				assert.equal(address, "1.2.3.4", "prefers IPv4 for the single-address shape");
				assert.equal(family, 4);
			}) as never);
			lookupFn("x", { family: 6 }, ((_err: Error | null, address: string) => assert.equal(address, "2001:db8::1")) as never);
		});
	});
});

describe("helpers", () => {
	it("mimeType strips parameters and lowercases", () => {
		assert.equal(mimeType("Text/HTML; charset=utf-8"), "text/html");
		assert.equal(mimeType(null), "");
	});
	it("createLimiter bounds concurrency and preserves results", async () => {
		const limit = createLimiter(2);
		let active = 0;
		let peak = 0;
		const task = (n: number) => limit(async () => {
			active++;
			peak = Math.max(peak, active);
			await new Promise((r) => setTimeout(r, 10));
			active--;
			return n * 2;
		});
		const results = await Promise.all([1, 2, 3, 4, 5].map(task));
		assert.deepEqual(results, [2, 4, 6, 8, 10]);
		assert.equal(peak, 2);
	});
	it("createLimiter propagates rejections without stalling the queue", async () => {
		const limit = createLimiter(1);
		await assert.rejects(limit(async () => { throw new Error("boom"); }), /boom/);
		assert.equal(await limit(async () => "next"), "next");
	});
});
