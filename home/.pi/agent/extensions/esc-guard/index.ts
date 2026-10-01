/**
 * esc-guard: require multiple Esc presses to abort a running agent.
 *
 * Stock pi aborts the active run on a single `app.interrupt` (Esc) press.
 * This extension swaps in a CustomEditor subclass that holds Esc while the
 * agent is busy until PI_ESC_ABORT_PRESSES presses arrive, each within
 * PI_ESC_ABORT_WINDOW_MS of the previous one; the final press is passed
 * through to pi's normal interrupt handler.
 *
 * Only Esc delivered to the main editor is affected. Dialogs, selectors and
 * overlays own focus while open, so their single-Esc cancel is unchanged, as
 * is closing editor autocomplete and every idle-time Esc behaviour
 * (double-Esc /tree, bash-mode clear, cancelling `!cmd`).
 *
 * Config (env, read at load; run /reload after changing):
 *   PI_ESC_ABORT_PRESSES    presses required (default 2; 1 disables the guard)
 *   PI_ESC_ABORT_WINDOW_MS  max gap between presses in ms (default 1000)
 */

import { CustomEditor, type ExtensionAPI, type ExtensionContext, keyText } from "@earendil-works/pi-coding-agent";
import { PressCounter, readConfig } from "./press-counter.ts";

type EditorArgs = ConstructorParameters<typeof CustomEditor>;

const STATUS_KEY = "esc-guard";

/** Returns true when the Esc press should be swallowed instead of interrupting. */
type HoldEscape = () => boolean;

class EscGuardEditor extends CustomEditor {
	private readonly kb: EditorArgs[2];
	private readonly holdEscape: HoldEscape;

	constructor(tui: EditorArgs[0], theme: EditorArgs[1], kb: EditorArgs[2], holdEscape: HoldEscape) {
		// Match the default editor, which embeds the working indicator in its top border.
		super(tui, theme, kb, { embedWorkingStatus: true });
		this.kb = kb;
		this.holdEscape = holdEscape;
	}

	handleInput(data: string): void {
		// Autocomplete check mirrors CustomEditor: there Esc closes the popup rather than interrupting.
		if (this.kb.matches(data, "app.interrupt") && !this.isShowingAutocomplete() && this.holdEscape()) return;
		super.handleInput(data);
	}
}

export default function (pi: ExtensionAPI) {
	const { presses, windowMs } = readConfig(process.env);
	if (presses === 1) return;

	const counter = new PressCounter(presses, windowMs);
	let ctx: ExtensionContext | undefined;
	let clearTimer: ReturnType<typeof setTimeout> | undefined;

	const clearHint = () => {
		if (clearTimer) clearTimeout(clearTimer);
		clearTimer = undefined;
		ctx?.ui.setStatus(STATUS_KEY, undefined);
	};

	const disarm = () => {
		counter.reset();
		clearHint();
	};

	const holdEscape: HoldEscape = () => {
		if (!ctx || ctx.isIdle()) {
			disarm();
			return false;
		}
		const remaining = counter.press(Date.now());
		if (remaining === 0) {
			clearHint();
			return false;
		}
		const key = keyText("app.interrupt");
		const hint = remaining === 1 ? `Press ${key} again to abort` : `Press ${key} ${remaining} more times to abort`;
		ctx.ui.setStatus(STATUS_KEY, ctx.ui.theme.fg("warning", hint));
		if (clearTimer) clearTimeout(clearTimer);
		clearTimer = setTimeout(clearHint, windowMs);
		clearTimer.unref?.();
		return true;
	};

	pi.on("session_start", (_event, startCtx) => {
		if (startCtx.mode !== "tui") return;
		ctx = startCtx;
		disarm();
		startCtx.ui.setEditorComponent((tui, theme, kb) => new EscGuardEditor(tui, theme, kb, holdEscape));
	});

	pi.on("agent_end", () => disarm());
	pi.on("session_shutdown", () => disarm());
}
