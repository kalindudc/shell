/**
 * Pure multi-press detection, kept free of pi imports so it is unit-testable
 * under plain `node --test`.
 */

export interface EscGuardConfig {
	/** Presses needed (each within `windowMs` of the previous) to trigger. */
	presses: number;
	/** Max gap in ms between consecutive presses before the sequence restarts. */
	windowMs: number;
}

const DEFAULTS: EscGuardConfig = { presses: 2, windowMs: 1000 };

export class PressCounter {
	readonly presses: number;
	readonly windowMs: number;
	private count = 0;
	private lastAt = 0;

	constructor(presses: number, windowMs: number) {
		if (!Number.isInteger(presses) || presses < 1) {
			throw new Error(`esc-guard: presses must be a positive integer, got ${presses}`);
		}
		if (!Number.isFinite(windowMs) || windowMs <= 0) {
			throw new Error(`esc-guard: windowMs must be a positive number, got ${windowMs}`);
		}
		this.presses = presses;
		this.windowMs = windowMs;
	}

	/** Record a press at `now` (ms). Returns presses still needed; 0 means trigger. */
	press(now: number): number {
		if (this.count > 0 && now - this.lastAt > this.windowMs) this.count = 0;
		this.count += 1;
		this.lastAt = now;
		if (this.count >= this.presses) {
			this.count = 0;
			return 0;
		}
		return this.presses - this.count;
	}

	reset(): void {
		this.count = 0;
	}
}

function readPositiveInt(env: Record<string, string | undefined>, name: string, fallback: number): number {
	const raw = env[name];
	if (raw === undefined || raw === "") return fallback;
	const value = Number(raw);
	if (!Number.isInteger(value) || value < 1) {
		throw new Error(`esc-guard: ${name} must be a positive integer, got ${JSON.stringify(raw)}`);
	}
	return value;
}

export function readConfig(env: Record<string, string | undefined>): EscGuardConfig {
	return {
		presses: readPositiveInt(env, "PI_ESC_ABORT_PRESSES", DEFAULTS.presses),
		windowMs: readPositiveInt(env, "PI_ESC_ABORT_WINDOW_MS", DEFAULTS.windowMs),
	};
}
