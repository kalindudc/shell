// Capture the resolved design tokens (CSS custom properties) of a rendered page.
//
// Run it in the page like scripts/audit-page.js (page.evaluate of the file's
// text, a devtools console, or a harness with a `browser` object). Open the
// real product first, in the theme the person runs, so the tokens are theirs.
//
// Options, set in the page before running it:
//   window.__uxTokenOptions = { skip: "^--(app-private-|chart-)", variant: "dark" }
// skip: a regex (source text) of variable names to leave out, added to the
//   default list of Tailwind's own namespaces. Leave out private variables of
//   other components so the output stays small; host entries in catalog/hosts
//   give their list.
// variant: the name to record for this capture (default "live"). To capture
//   another theme without changing the person's settings, inject its CSS into
//   the page and set its class first.
//
// The output is JSON text: colour tokens as hex (with alpha when not opaque),
// and fonts and radii as written. A variable whose value is not a colour, a
// font or a radius is left out.

function uxTokens(given) {
  const opts = Object.assign({ skip: null, variant: "live" }, window.__uxTokenOptions || {}, given || {});
  // Tailwind's own theme namespaces: its palette and scales, not the product's tokens.
  const tailwind = /^--(tw-|color-|font-weight|text-|leading|tracking|container|shadow|blur|drop|perspective|animate|ease|default|spacing|inset|aspect)/;
  const extra = opts.skip ? new RegExp(opts.skip) : null;
  const names = new Set();
  const walk = (rules) => {
    for (const rule of rules) {
      if (rule.cssRules) walk(rule.cssRules);
      if (rule.style) for (const name of rule.style) if (name.startsWith("--") && !tailwind.test(name) && !(extra && extra.test(name))) names.add(name);
    }
  };
  for (const sheet of document.styleSheets) {
    try {
      walk(sheet.cssRules);
    } catch {
      // A cross-origin sheet cannot be read; its variables are left out.
    }
  }

  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = 1;
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  const hex = (css) => {
    ctx.clearRect(0, 0, 1, 1);
    ctx.fillStyle = css;
    ctx.fillRect(0, 0, 1, 1);
    const d = ctx.getImageData(0, 0, 1, 1).data;
    const rgb = "#" + [d[0], d[1], d[2]].map((v) => v.toString(16).padStart(2, "0")).join("");
    return d[3] === 255 ? rgb : rgb + d[3].toString(16).padStart(2, "0");
  };

  // A colour token resolves through color-mix and var() only when used, so resolve it on a probe. A value that is
  // not a colour makes the probe inherit its holder's sentinel colour, which marks it as not a colour.
  const holder = document.createElement("div");
  holder.style.color = "rgb(1, 2, 3)";
  const probe = document.createElement("div");
  holder.appendChild(probe);
  document.body.appendChild(holder);
  const tokens = {};
  for (const name of names) {
    const raw = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    if (!raw) continue;
    if (/^--(radius|font)/.test(name)) {
      tokens[name] = raw.slice(0, 120);
      continue;
    }
    probe.style.color = `var(${name})`;
    const resolved = getComputedStyle(probe).color;
    if (resolved && resolved !== "rgb(1, 2, 3)") tokens[name.slice(2)] = hex(resolved);
  }
  holder.remove();
  return {
    variant: opts.variant,
    htmlClass: document.documentElement.className,
    bodyFont: getComputedStyle(document.body).fontFamily.slice(0, 120),
    bodySize: getComputedStyle(document.body).fontSize,
    tokens,
  };
}

typeof document === "undefined" && typeof browser !== "undefined"
  ? browser.getPage("main").then((page) => page.evaluate(uxTokens)).then((out) => JSON.stringify(out))
  : JSON.stringify(uxTokens());
