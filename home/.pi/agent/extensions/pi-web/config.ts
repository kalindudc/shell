/**
 * pi-web configuration.
 *
 * Optional JSON file at `~/.pi/agent/pi-web.json` (or `$PI_WEB_CONFIG`), with
 * environment variables taking precedence over file values. Everything has a
 * sensible default so the extension works with no configuration at all.
 *
 * Config is re-read on every tool call (it is a tiny file), so edits apply
 * without `/reload`.
 */

import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

export const SEARCH_PROVIDERS = ["auto", "duckduckgo", "exa", "brave", "searxng"] as const;
export type SearchProviderName = (typeof SEARCH_PROVIDERS)[number];

export interface PiWebConfig {
	/** Default search provider. `auto` = brave (if key) → searxng (if url) → duckduckgo → exa (both keyless). */
	provider: SearchProviderName;
	/** Brave Search API key (https://brave.com/search/api/). */
	braveApiKey?: string;
	/** Base URL of a SearXNG instance with the JSON format enabled. */
	searxngUrl?: string;
	/** Allow fetching loopback / private / link-local addresses (default false). */
	allowPrivateNetwork: boolean;
	/** Per-request timeout in milliseconds. */
	timeoutMs: number;
	/** Default max characters of page content returned per URL. */
	maxChars: number;
	/** Hard cap on downloaded response bytes. */
	maxResponseBytes: number;
	/** User-Agent header sent with every request. */
	userAgent: string;
	/** Max concurrent network operations per tool call. */
	concurrency: number;
	/** Path the config was loaded from (for diagnostics). */
	configPath: string;
	/** Whether the config file existed. */
	configFileFound: boolean;
	/** Non-fatal problems found while loading (reported by `/web status`). */
	warnings: string[];
}

export const DEFAULT_USER_AGENT =
	"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36 pi-web/0.1";

export const CONFIG_DEFAULTS = {
	provider: "auto" as SearchProviderName,
	allowPrivateNetwork: false,
	timeoutMs: 20_000,
	maxChars: 30_000,
	maxResponseBytes: 5 * 1024 * 1024,
	userAgent: DEFAULT_USER_AGENT,
	concurrency: 4,
};

export function getConfigPath(env: NodeJS.ProcessEnv = process.env): string {
	if (env.PI_WEB_CONFIG) return env.PI_WEB_CONFIG;
	const agentDir = env.PI_CODING_AGENT_DIR ?? join(homedir(), ".pi", "agent");
	return join(agentDir, "pi-web.json");
}

function asString(value: unknown): string | undefined {
	return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function asPositiveInt(value: unknown, warnings: string[], field: string): number | undefined {
	if (value === undefined) return undefined;
	const n = typeof value === "string" ? Number(value) : value;
	if (typeof n === "number" && Number.isFinite(n) && n > 0) return Math.floor(n);
	warnings.push(`${field}: expected a positive number, got ${JSON.stringify(value)}`);
	return undefined;
}

function asBool(value: unknown, warnings: string[], field: string): boolean | undefined {
	if (value === undefined) return undefined;
	if (typeof value === "boolean") return value;
	if (typeof value === "string") {
		const v = value.trim().toLowerCase();
		if (["1", "true", "yes", "on"].includes(v)) return true;
		if (["0", "false", "no", "off", ""].includes(v)) return false;
	}
	warnings.push(`${field}: expected a boolean, got ${JSON.stringify(value)}`);
	return undefined;
}

function asProvider(value: unknown, warnings: string[], field: string): SearchProviderName | undefined {
	if (value === undefined) return undefined;
	if (typeof value === "string" && (SEARCH_PROVIDERS as readonly string[]).includes(value.trim().toLowerCase())) {
		return value.trim().toLowerCase() as SearchProviderName;
	}
	warnings.push(`${field}: expected one of ${SEARCH_PROVIDERS.join("|")}, got ${JSON.stringify(value)}`);
	return undefined;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): PiWebConfig {
	const warnings: string[] = [];
	const configPath = getConfigPath(env);
	let file: Record<string, unknown> = {};
	let configFileFound = false;

	if (existsSync(configPath)) {
		configFileFound = true;
		try {
			const parsed: unknown = JSON.parse(readFileSync(configPath, "utf8"));
			if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
				file = parsed as Record<string, unknown>;
			} else {
				warnings.push(`${configPath}: expected a JSON object`);
			}
		} catch (err) {
			warnings.push(`${configPath}: ${err instanceof Error ? err.message : String(err)}`);
		}
	}

	const pick = <T>(envValue: T | undefined, fileValue: T | undefined, fallback: T): T =>
		envValue !== undefined ? envValue : fileValue !== undefined ? fileValue : fallback;

	const searxngUrl = pick(asString(env.SEARXNG_URL), asString(file.searxngUrl), undefined);
	if (searxngUrl && !/^https?:\/\//i.test(searxngUrl)) {
		warnings.push(`searxngUrl must start with http:// or https:// (got ${searxngUrl})`);
	}

	return {
		provider: pick(
			asProvider(env.PI_WEB_PROVIDER, warnings, "PI_WEB_PROVIDER"),
			asProvider(file.provider, warnings, "provider"),
			CONFIG_DEFAULTS.provider,
		),
		braveApiKey: pick(asString(env.BRAVE_API_KEY), asString(file.braveApiKey), undefined),
		searxngUrl: searxngUrl?.replace(/\/+$/, ""),
		allowPrivateNetwork: pick(
			asBool(env.PI_WEB_ALLOW_PRIVATE, warnings, "PI_WEB_ALLOW_PRIVATE"),
			asBool(file.allowPrivateNetwork, warnings, "allowPrivateNetwork"),
			CONFIG_DEFAULTS.allowPrivateNetwork,
		),
		timeoutMs: pick(
			asPositiveInt(env.PI_WEB_TIMEOUT_MS, warnings, "PI_WEB_TIMEOUT_MS"),
			asPositiveInt(file.timeoutMs, warnings, "timeoutMs"),
			CONFIG_DEFAULTS.timeoutMs,
		),
		maxChars: pick(
			asPositiveInt(env.PI_WEB_MAX_CHARS, warnings, "PI_WEB_MAX_CHARS"),
			asPositiveInt(file.maxChars, warnings, "maxChars"),
			CONFIG_DEFAULTS.maxChars,
		),
		maxResponseBytes: pick(undefined, asPositiveInt(file.maxResponseBytes, warnings, "maxResponseBytes"), CONFIG_DEFAULTS.maxResponseBytes),
		userAgent: pick(asString(env.PI_WEB_USER_AGENT), asString(file.userAgent), CONFIG_DEFAULTS.userAgent),
		concurrency: Math.min(
			8,
			pick(undefined, asPositiveInt(file.concurrency, warnings, "concurrency"), CONFIG_DEFAULTS.concurrency),
		),
		configPath,
		configFileFound,
		warnings,
	};
}

/** Mask a secret for display: keeps first 4 and last 2 characters. */
export function maskSecret(secret: string | undefined): string {
	if (!secret) return "(not set)";
	if (secret.length <= 8) return "*".repeat(secret.length);
	return `${secret.slice(0, 4)}${"*".repeat(Math.min(12, secret.length - 6))}${secret.slice(-2)}`;
}
