/**
 * Node module-resolution hook for tests.
 *
 * pi provides `@earendil-works/pi-*` and `typebox` to extensions at runtime
 * (via jiti aliases). Plain `node --test` cannot resolve them, so this hook
 * maps those specifiers to the pi runtime installed at ~/.pi/pkg/pi-<version>
 * (override with PI_PKG_DIR). Register with:
 *
 *   node --import ./test/_pi-resolve.mjs --test 'test/*.test.ts'
 */

import { existsSync, readdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { register } from "node:module";
import { pathToFileURL } from "node:url";

function findPiPkgDir() {
	if (process.env.PI_PKG_DIR) return process.env.PI_PKG_DIR;
	const root = join(homedir(), ".pi", "pkg");
	if (!existsSync(root)) return null;
	const versions = readdirSync(root)
		.filter((d) => d.startsWith("pi-"))
		.sort((a, b) => b.localeCompare(a, undefined, { numeric: true }));
	return versions.length ? join(root, versions[0]) : null;
}

const pkgDir = findPiPkgDir();
if (!pkgDir) {
	throw new Error("pi runtime not found: set PI_PKG_DIR to a pi-coding-agent package directory");
}

const map = {
	"@earendil-works/pi-coding-agent": join(pkgDir, "dist", "index.js"),
	"@earendil-works/pi-ai": join(pkgDir, "node_modules", "@earendil-works", "pi-ai", "dist", "index.js"),
	"@earendil-works/pi-tui": join(pkgDir, "node_modules", "@earendil-works", "pi-tui", "dist", "index.js"),
	typebox: join(pkgDir, "node_modules", "typebox", "build", "index.mjs"),
};

const hookSource = `
	const map = ${JSON.stringify(Object.fromEntries(Object.entries(map).map(([k, v]) => [k, pathToFileURL(v).href])))};
	export async function resolve(specifier, context, next) {
		if (map[specifier]) return { url: map[specifier], shortCircuit: true };
		return next(specifier, context);
	}
`;
register(`data:text/javascript,${encodeURIComponent(hookSource)}`, pathToFileURL(import.meta.filename ?? process.cwd()));
