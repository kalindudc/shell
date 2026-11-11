// Deterministic UI audit of a rendered page. It measures; it does not judge.
//
// Run it in the page, with any tool that evaluates a script there:
//   - Playwright or Puppeteer: await page.evaluate(fs.readFileSync("audit-page.js", "utf8"))
//   - a browser's devtools console: paste the file
//   - a harness that gives scripts a `browser` object with getPage("main"), such
//     as bb's browser automation (catalog/hosts/bb/README.md): pass the file as the script.
// It audits the page as it is now: navigate, resize and open the state you want
// first. To audit only part of the page (an embedded surface inside a host app),
// set options in the page before running it:
//
//   window.__uxAuditOptions = { root: "[data-app-root]" }
//
// Options: root (CSS selector, default body), minFont (px, default 11),
// minTarget (px, default 24, WCAG 2.2 SC 2.5.8), maxLineCh (default 100),
// maxBlockWords (default 12: a text block outside content whose longest
// segment between separators such as "·" is longer than this is listed),
// content (selector of text people or agents wrote, default "[data-content]";
// it and code are left out of the text-load counts), messages (selector of
// errors, empty states and status messages, default "[role=alert],
// [role=status], [data-empty], [data-error]"; counted but never flagged),
// limit (offenders listed per check, default 12).
//
// It returns JSON text: the viewport, a summary of counts, and the worst
// offenders of each check with a selector path and a text sample. Counts cover
// the whole rendered root, not only the first screen; the summary also gives
// first-screen counts. Contrast over images or gradients is reported as
// unknown, not as a pass. SVG text is measured by its fill over the shapes drawn
// before it. Text of disabled controls is counted apart (WCAG
// calls it incidental). Small targets that meet SC 2.5.8's spacing exception
// are counted apart. Hidden content (display none, closed <details>,
// content-visibility) is skipped. A count is a candidate list for a reviewer to
// confirm, never a conformance score. Text load counts words per block (the
// nearest box that is not inline) and flags long blocks and instructions
// ("click", "to see", "move with") written by the interface itself. Layout
// defects list text wider than its box, text drawn outside its card, text over
// text, sticky bars over content, and in diagrams (SVGs of 48 px or more) labels
// wider than their shape, connector ends that touch no shape or meet one at a
// corner (atCorner: touching, but read as loosely attached), and shapes cut by
// the frame. Text in a floating layer (dialog, menu, popover, tooltip, fixed)
// is not counted as overlapping the page under it. Run it again in each state an action
// opens (armed confirmations, expanded rows, a focused map): defects often
// appear only there.

function uxAudit(given) {
  const opts = Object.assign({ root: "body", minFont: 11, minTarget: 24, maxLineCh: 100, maxBlockWords: 12, content: "[data-content]", messages: "[role=alert], [role=status], [data-empty], [data-error]", limit: 12 }, window.__uxAuditOptions || {}, given || {});
  const root = document.querySelector(opts.root) || document.body;
  const vw = window.innerWidth;
  const vh = window.innerHeight;

  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = 1;
  const ctx = canvas.getContext("2d", { willReadFrequently: true });
  // Any CSS colour (rgb, oklch, color-mix results, named) to [r, g, b, a 0-1].
  const rgba = (css) => {
    if (!css || css === "transparent") return [0, 0, 0, 0];
    ctx.clearRect(0, 0, 1, 1);
    ctx.fillStyle = "#000";
    ctx.fillStyle = css;
    ctx.fillRect(0, 0, 1, 1);
    const d = ctx.getImageData(0, 0, 1, 1).data;
    return [d[0], d[1], d[2], d[3] / 255];
  };
  const over = (top, bottom) => {
    const a = top[3];
    return [top[0] * a + bottom[0] * (1 - a), top[1] * a + bottom[1] * (1 - a), top[2] * a + bottom[2] * (1 - a), 1];
  };
  const lum = ([r, g, b]) => {
    const f = (v) => {
      v /= 255;
      return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
    };
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
  };
  const ratio = (a, b) => {
    const [x, y] = [lum(a), lum(b)].sort((m, n) => n - m);
    return (x + 0.05) / (y + 0.05);
  };

  const pathOf = (el) => {
    const parts = [];
    for (let e = el; e && e !== document.body && parts.length < 5; e = e.parentElement) {
      let part = e.tagName.toLowerCase();
      const data = [...e.attributes].find((a) => a.name.startsWith("data-") && a.name !== "data-state");
      if (e.id) part += `#${e.id}`;
      else if (data) part += `[${data.name}${data.value ? `="${data.value.slice(0, 24)}"` : ""}]`;
      else if (e.classList.length) part += `.${[...e.classList].slice(0, 2).join(".")}`;
      parts.unshift(part);
    }
    return parts.join(" > ");
  };
  const sample = (el) => ((el instanceof SVGElement ? el.textContent : el.innerText) || el.getAttribute("aria-label") || el.value || "").replace(/\s+/g, " ").trim().slice(0, 60);
  const visible = (el) => {
    if (el.checkVisibility && !el.checkVisibility({ checkOpacity: true, checkVisibilityCSS: true })) return false;
    const s = getComputedStyle(el);
    if (s.display === "none" || s.visibility === "hidden" || Number(s.opacity) === 0) return false;
    // Content of a closed <details> is not shown, but some engines still give it a box.
    const closed = el.closest("details:not([open])");
    if (closed && !el.closest("summary")?.parentElement?.isSameNode(closed)) return false;
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0;
  };
  const inFold = (el) => {
    const r = el.getBoundingClientRect();
    return r.top < vh && r.bottom > 0;
  };
  // WCAG treats text of inactive controls as incidental: measured, but not counted as a failure.
  const inactive = (el) => Boolean(el.closest(":disabled, [aria-disabled='true']"));

  // Effective background: blend translucent layers up the tree; images and gradients make it unknown.
  const bgCache = new Map();
  const background = (el) => {
    if (!el || el === document.documentElement.parentElement) return { color: [255, 255, 255, 1], known: true };
    if (bgCache.has(el)) return bgCache.get(el);
    const s = getComputedStyle(el);
    const parent = el.parentElement ? background(el.parentElement) : { color: rgba(getComputedStyle(document.documentElement).backgroundColor || "#fff")[3] ? rgba(getComputedStyle(document.documentElement).backgroundColor) : [255, 255, 255, 1], known: true };
    let out;
    if (s.backgroundImage && s.backgroundImage !== "none") out = { color: parent.color, known: false };
    else {
      const own = rgba(s.backgroundColor);
      out = own[3] === 0 ? parent : { color: over(own, parent.color), known: parent.known };
    }
    bgCache.set(el, out);
    return out;
  };

  // Behind SVG text: the last solid shape drawn before it that covers its centre, else the SVG's HTML background.
  const svgBackground = (el) => {
    const svg = el.ownerSVGElement || el.closest("svg");
    const base = background(svg && svg.parentElement);
    const tr = el.getBoundingClientRect();
    const cx = tr.left + tr.width / 2, cy = tr.top + tr.height / 2;
    const shapes = [...(svg ? svg.querySelectorAll("rect, circle, ellipse, polygon, path") : [])].filter((sh) => sh.compareDocumentPosition(el) & Node.DOCUMENT_POSITION_FOLLOWING);
    let colour = base.color, known = base.known;
    for (const sh of shapes) {
      const q = sh.getBoundingClientRect();
      if (cx < q.left || cx > q.right || cy < q.top || cy > q.bottom || q.width < 4 || q.height < 4) continue;
      const c = getComputedStyle(sh);
      if (c.display === "none" || c.visibility === "hidden") continue;
      if (/^url/.test(c.fill)) { known = false; continue; }
      const f = rgba(c.fill === "none" ? "transparent" : c.fill);
      const a = f[3] * Number(c.fillOpacity) * Number(c.opacity);
      if (a > 0) colour = over([f[0], f[1], f[2], a], colour);
    }
    return { color: colour, known };
  };

  const textEls = [];
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, { acceptNode: (n) => (n.nodeValue.trim() ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT) });
  const seen = new Set();
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    const el = n.parentElement;
    if (el && !seen.has(el) && visible(el)) {
      seen.add(el);
      textEls.push(el);
    }
  }

  // Text load: words per text block (the nearest non-inline box), outside what people or agents wrote.
  const inContent = (el) => Boolean(opts.content && el.closest(opts.content)) || Boolean(el.closest("pre, code, kbd, samp"));
  const blockOf = (el) => {
    for (let e = el; e && e !== root.parentElement; e = e.parentElement) {
      const d = getComputedStyle(e).display;
      if (d !== "inline" && d !== "contents") return e;
    }
    return root;
  };
  const textBlocks = new Map();
  const wordWalker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, { acceptNode: (n) => (n.nodeValue.trim() ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT) });
  for (let n = wordWalker.nextNode(); n; n = wordWalker.nextNode()) {
    const el = n.parentElement;
    if (!el || !seen.has(el)) continue;
    const block = blockOf(el);
    const entry = textBlocks.get(block) || { text: "", content: inContent(el) };
    entry.text += " " + n.nodeValue;
    entry.content = entry.content && inContent(el);
    textBlocks.set(block, entry);
  }
  const wordsOf = (text) => (text.match(/[\p{L}\p{N}][\p{L}\p{N}'’.-]*/gu) || []).length;
  const instruction = /\b(click|tap|press|hover|drag|scroll|select a|choose a|move with|use the|to see|you can|here you)\b/i;
  let words = 0;
  let wordsOutsideContent = 0;
  let firstScreenWords = 0;
  let firstScreenWordsOutsideContent = 0;
  const longBlocks = [];
  const instructions = [];
  for (const [block, entry] of textBlocks) {
    const n = wordsOf(entry.text);
    const fold = inFold(block);
    const text = entry.text.replace(/\s+/g, " ").trim();
    words += n;
    if (fold) firstScreenWords += n;
    if (entry.content) continue;
    wordsOutsideContent += n;
    if (fold) firstScreenWordsOutsideContent += n;
    // Errors, empty states and status messages may need sentences; they are counted but not flagged.
    if (block.closest(opts.messages)) continue;
    // A fact line ("Working · 3 of 8 done · oldest 2 d") is several short facts, so the longest segment decides.
    const longest = Math.max(...text.split(/\s[·•|—–]\s|;\s/).map(wordsOf));
    const item = { path: pathOf(block), words: n, longestSegment: longest, text: text.slice(0, 120), firstScreen: fold };
    if (longest > opts.maxBlockWords) longBlocks.push(item);
    if (n >= 4 && instruction.test(text)) instructions.push(item);
  }

  const contrast = [];
  const unknownContrast = [];
  let inactiveLowContrast = 0;
  const smallText = [];
  const longLines = [];
  const fontSizes = new Map();
  const textColours = new Map();
  const weights = new Map();
  for (const el of textEls) {
    const s = getComputedStyle(el);
    const size = parseFloat(s.fontSize);
    const weight = Number(s.fontWeight) || 400;
    fontSizes.set(size, (fontSizes.get(size) || 0) + 1);
    weights.set(weight, (weights.get(weight) || 0) + 1);
    // SVG text is painted by its fill, over the shapes drawn before it, not by `color` over HTML backgrounds.
    const svgText = el instanceof SVGElement;
    const bg = svgText ? svgBackground(el) : background(el);
    let fg = rgba(svgText ? (/^(none|url)/.test(s.fill) ? "transparent" : s.fill) : s.color);
    if (svgText && fg[3] === 0) bg.known = false;
    let alpha = fg[3] * (svgText ? Number(s.fillOpacity) : 1);
    for (let e = el; e && e !== document.documentElement; e = e.parentElement) alpha *= Number(getComputedStyle(e).opacity);
    fg = over([fg[0], fg[1], fg[2], alpha], bg.color);
    textColours.set(fg.slice(0, 3).join(","), (textColours.get(fg.slice(0, 3).join(",")) || 0) + 1);
    const large = size >= 24 || (size >= 18.66 && weight >= 700);
    const need = large ? 3 : 4.5;
    const r = ratio(fg, bg.color);
    const item = { path: pathOf(el), text: sample(el), ratio: Math.round(r * 100) / 100, need, size, firstScreen: inFold(el) };
    if (!bg.known) unknownContrast.push(item);
    else if (r < need && inactive(el)) inactiveLowContrast += 1;
    else if (r < need) contrast.push(item);
    if (size < opts.minFont) smallText.push({ path: pathOf(el), text: sample(el), size });
    if (s.display === "block" || s.display === "list-item" || el.tagName === "P") {
      const ch = el.getBoundingClientRect().width / (size * 0.5);
      if (ch > opts.maxLineCh && (el.innerText || "").length > opts.maxLineCh) longLines.push({ path: pathOf(el), text: sample(el), approxCh: Math.round(ch) });
    }
  }

  const interactive = [...root.querySelectorAll("a[href], button, input, select, textarea, summary, [role=button], [role=tab], [role=link], [role=checkbox], [role=menuitem], [tabindex]:not([tabindex='-1'])")].filter(visible);
  const smallTargets = [];
  let smallTargetsSpaced = 0;
  const unnamed = [];
  const centres = interactive.map((el) => {
    const r = el.getBoundingClientRect();
    return [r.left + r.width / 2, r.top + r.height / 2];
  });
  interactive.forEach((el, i) => {
    const r = el.getBoundingClientRect();
    const inlineLink = el.tagName === "A" && getComputedStyle(el).display === "inline";
    if (!inlineLink && (r.width < opts.minTarget || r.height < opts.minTarget)) {
      // SC 2.5.8 spacing exception: a 24 px circle on this target's centre touches no other target's centre circle.
      const [x, y] = centres[i];
      const crowded = centres.some(([cx, cy], j) => j !== i && !interactive[j].contains(el) && !el.contains(interactive[j]) && Math.hypot(cx - x, cy - y) < opts.minTarget);
      if (crowded) smallTargets.push({ path: pathOf(el), text: sample(el), w: Math.round(r.width), h: Math.round(r.height), firstScreen: inFold(el) });
      else smallTargetsSpaced += 1;
    }
    const name = (el.getAttribute("aria-label") || el.getAttribute("aria-labelledby") || el.getAttribute("title") || el.innerText || el.value || el.getAttribute("placeholder") || el.querySelector("img[alt], svg title")?.textContent || "").trim();
    const labelled = el.id && document.querySelector(`label[for="${CSS.escape(el.id)}"]`);
    if (!name && !labelled) unnamed.push({ path: pathOf(el) });
  });

  const truncated = [];
  const overflowX = [];
  for (const el of root.querySelectorAll("*")) {
    if (!visible(el)) continue;
    const s = getComputedStyle(el);
    if (s.textOverflow === "ellipsis" && el.scrollWidth > el.clientWidth + 1) truncated.push({ path: pathOf(el), text: sample(el), hasTitle: Boolean(el.title || el.closest("[title]")) });
    const r = el.getBoundingClientRect();
    if (r.right > vw + 1 && s.position !== "fixed" && el.closest("[style*='overflow'], .overflow-x-auto, .overflow-auto") === null) overflowX.push({ path: pathOf(el), right: Math.round(r.right) });
  }

  // Layout defects: text that spills from its box or card, text drawn over text, sticky bars over content,
  // and in diagrams, labels wider than their shape, connector ends that touch no shape, shapes cut by the frame.
  const clipTo = (el, r) => {
    const o = { left: r.left, right: r.right, top: r.top, bottom: r.bottom };
    for (let e = el; e && e !== document.documentElement; e = e.parentElement) {
      const c = getComputedStyle(e);
      if (c.overflowX !== "visible" || c.overflowY !== "visible" || (c.webkitLineClamp && c.webkitLineClamp !== "none")) {
        const q = e.getBoundingClientRect();
        o.left = Math.max(o.left, q.left); o.right = Math.min(o.right, q.right); o.top = Math.max(o.top, q.top); o.bottom = Math.min(o.bottom, q.bottom);
      }
    }
    return { ...o, width: Math.max(0, o.right - o.left), height: Math.max(0, o.bottom - o.top) };
  };
  const inkOf = (el) => { const range = document.createRange(); range.selectNodeContents(el); return clipTo(el, range.getBoundingClientRect()); };
  const clips = (from, to) => { for (let e = from; e && e !== to; e = e.parentElement) { const c = getComputedStyle(e); if (c.overflowX !== "visible" || c.overflowY !== "visible") return true; } return false; };
  const boxed = (e) => { const c = getComputedStyle(e); return parseFloat(c.borderTopWidth) > 0 || parseFloat(c.borderLeftWidth) > 0 || !/^(rgba\(0, 0, 0, 0\)|transparent)$/.test(c.backgroundColor) || c.boxShadow !== "none"; };
  const blockText = textEls.filter((el) => !el.closest("svg") && getComputedStyle(el).display !== "inline");
  const textSpill = [];
  const textOutsideBox = [];
  for (const el of blockText) {
    const s = getComputedStyle(el);
    if (s.overflowX === "visible" && s.textOverflow !== "ellipsis" && el.clientWidth > 0 && el.scrollWidth > el.clientWidth + 2) textSpill.push({ path: pathOf(el), text: sample(el), over: el.scrollWidth - el.clientWidth });
    let card = null;
    for (let e = el.parentElement; e && e !== root.parentElement; e = e.parentElement) if (boxed(e)) { card = e; break; }
    if (!card || clips(el, card)) continue;
    const ink = inkOf(el), cr = card.getBoundingClientRect();
    const out = Math.max(cr.left - ink.left, ink.right - cr.right, cr.top - ink.top, ink.bottom - cr.bottom);
    if (ink.width > 0 && out > 1.5) textOutsideBox.push({ path: pathOf(el), box: pathOf(card), text: sample(el), over: Math.round(out) });
  }
  const inks = blockText.map((el) => ({ el, r: inkOf(el) })).filter((x) => x.r.width > 0 && x.r.height > 0 && x.r.top < vh && x.r.bottom > 0);
  // Text in a floating layer (a dialog, menu, popover, tooltip or fixed overlay) covers the page on purpose.
  const layerOf = (el) => {
    for (let e = el; e && e !== document.documentElement; e = e.parentElement) {
      if (e.matches("dialog, [role=dialog], [role=alertdialog], [role=menu], [role=listbox][popover], [role=tooltip], [popover]") || getComputedStyle(e).position === "fixed") return e;
    }
    return null;
  };
  const overlappingText = [];
  for (let i = 0; i < inks.length && overlappingText.length < opts.limit; i++) {
    for (let j = i + 1; j < inks.length; j++) {
      const a = inks[i], b = inks[j];
      if (a.el.contains(b.el) || b.el.contains(a.el)) continue;
      if (layerOf(a.el) !== layerOf(b.el)) continue;
      const ix = Math.min(a.r.right, b.r.right) - Math.max(a.r.left, b.r.left), iy = Math.min(a.r.bottom, b.r.bottom) - Math.max(a.r.top, b.r.top);
      if (ix > 3 && iy > 3) { overlappingText.push({ path: pathOf(a.el), text: sample(a.el), other: sample(b.el) }); break; }
    }
  }
  const coveredBySticky = [];
  for (const bar of root.querySelectorAll("*")) {
    const c = getComputedStyle(bar);
    if ((c.position !== "sticky" && c.position !== "fixed") || !visible(bar)) continue;
    const br = bar.getBoundingClientRect();
    if (br.height < 8) continue;
    for (const x of inks) {
      if (bar.contains(x.el) || x.el.contains(bar)) continue;
      const ix = Math.min(x.r.right, br.right) - Math.max(x.r.left, br.left), iy = Math.min(x.r.bottom, br.bottom) - Math.max(x.r.top, br.top);
      if (ix <= 3 || iy <= 3) continue;
      const hit = document.elementFromPoint(Math.max(x.r.left, br.left) + 2, Math.max(x.r.top, br.top) + 2);
      if (hit && bar.contains(hit)) coveredBySticky.push({ path: pathOf(x.el), text: sample(x.el), bar: pathOf(bar) });
    }
  }
  // Diagrams: SVGs at least 48 px each way, so icons are left out.
  const svgLabelOverflow = [];
  const looseConnectors = [];
  const clippedShapes = [];
  const shapeSel = "rect, circle, ellipse, polygon";
  for (const svg of root.querySelectorAll("svg")) {
    const sr = svg.getBoundingClientRect();
    if (sr.width < 48 || sr.height < 48 || !visible(svg)) continue;
    for (const t of svg.querySelectorAll("text")) {
      const shape = t.parentElement && t.parentElement.tagName === "g" && [...t.parentElement.children].find((c) => c.matches(shapeSel) && c.getBoundingClientRect().width > 8);
      if (!shape) continue;
      const tb = t.getBoundingClientRect(), bb = shape.getBoundingClientRect();
      // Only a label that starts inside its shape belongs in it; a label beside a bar (a Gantt lane) is not an overflow.
      const startsInside = tb.left >= bb.left - 1 && tb.left < bb.right && tb.top + tb.height / 2 > bb.top && tb.top + tb.height / 2 < bb.bottom;
      if (startsInside && (tb.right > bb.right + 1 || tb.left < bb.left - 1)) svgLabelOverflow.push({ path: pathOf(t), text: (t.textContent || "").trim().slice(0, 60), over: Math.round(Math.max(tb.right - bb.right, bb.left - tb.left)) });
    }
    const host = svg.parentElement || svg;
    const shapes = [...svg.querySelectorAll(shapeSel), ...host.querySelectorAll(":scope > :not(svg)")].map((e) => e.getBoundingClientRect()).filter((q) => Math.max(q.width, q.height) > 6 && Math.min(q.width, q.height) >= 2 && q.width < sr.width * 0.95);
    // A diagram has node groups (a shape with a label) or positioned HTML nodes beside it; charts and icons do not.
    const nodeGroups = [...svg.querySelectorAll("g")].filter((g) => g.querySelector(`:scope > :is(${shapeSel})`) && g.querySelector(":scope > text"));
    const htmlNodes = [...host.children].filter((c) => c !== svg && getComputedStyle(c).position === "absolute");
    if (shapes.length >= 2 && (nodeGroups.length >= 2 || htmlNodes.length >= 2)) {
      for (const e of svg.querySelectorAll("path, line, polyline")) {
        if (getComputedStyle(e).fill !== "none" && e.tagName === "path") continue;
        const len = e.getTotalLength ? e.getTotalLength() : 0;
        const ctm = e.getScreenCTM();
        if (!len || !ctm) continue;
        const ends = [["start", 0], ["end", len]].map(([end, at]) => {
          const p = new DOMPoint(e.getPointAtLength(at).x, e.getPointAtLength(at).y).matrixTransform(ctm);
          const gap = Math.min(...shapes.map((q) => Math.hypot(Math.max(q.left - p.x, 0, p.x - q.right), Math.max(q.top - p.y, 0, p.y - q.bottom))));
          const corner = shapes.some((q) => Math.min(Math.abs(p.x - q.left), Math.abs(p.x - q.right)) < 3 && Math.min(Math.abs(p.y - q.top), Math.abs(p.y - q.bottom)) < 3);
          return { end, gap: Math.round(gap * 10) / 10, atCorner: corner };
        });
        // A line that touches no shape at either end is a grid or axis line, not a connector.
        if (ends.every((x) => x.gap > 1.5 && !x.atCorner)) continue;
        for (const x of ends) if (x.gap > 1.5 || x.atCorner) looseConnectors.push({ path: pathOf(e), ...x });
      }
    }
    const frame = clipTo(svg, sr);
    for (const shape of svg.querySelectorAll(shapeSel)) {
      const q = shape.getBoundingClientRect();
      if (q.width < 6 || q.height < 6 || q.width >= sr.width * 0.95) continue;
      const cut = q.left < frame.left - 1 || q.right > frame.right + 1 || q.top < frame.top - 1 || q.bottom > frame.bottom + 1;
      const gone = q.right <= frame.left || q.left >= frame.right || q.bottom <= frame.top || q.top >= frame.bottom;
      if (cut && !gone) clippedShapes.push({ path: pathOf(shape), label: (shape.parentElement?.textContent || "").trim().slice(0, 40) });
    }
  }

  // The first screen: the blocks that share it, found by descending through wrappers taller than 60% of the viewport.
  const firstScreen = [];
  const blocks = (el, depth) => {
    for (const child of el.children) {
      if (!visible(child)) continue;
      const r = child.getBoundingClientRect();
      if (r.top >= vh || r.bottom <= 0) continue;
      const shown = Math.min(r.bottom, vh) - Math.max(r.top, 0);
      if (depth < 12 && child.children.length > 0 && shown > vh * 0.6) blocks(child, depth + 1);
      else firstScreen.push({ path: pathOf(child), left: Math.round(r.left), top: Math.round(r.top), width: Math.round(r.width), height: Math.round(shown), text: sample(child) });
    }
  };
  blocks(root, 0);
  const inkInFold = textEls.filter((el) => {
    const r = el.getBoundingClientRect();
    return r.top < vh && r.bottom > 0;
  }).length;

  const spacing = new Map();
  for (const el of [...root.querySelectorAll("*")].slice(0, 4000)) {
    const s = getComputedStyle(el);
    for (const v of [s.paddingTop, s.paddingLeft, s.marginTop, s.marginBottom, s.rowGap, s.columnGap]) {
      const n = parseFloat(v);
      if (n > 0) spacing.set(n, (spacing.get(n) || 0) + 1);
    }
  }
  // Hairlines (1 px) and sub-pixel values from rem or zoom are not off the scale.
  const offScale = [...spacing.keys()].filter((n) => n > 1 && Number.isInteger(n) && n % 2 !== 0);

  const imagesWithoutAlt = [...root.querySelectorAll("img:not([alt])")].filter(visible).map((el) => ({ path: pathOf(el) }));
  const top = (list, key) => list.sort((a, b) => (key ? a[key] - b[key] : 0)).slice(0, opts.limit);

  return {
    url: location.href,
    viewport: { width: vw, height: vh },
    root: opts.root,
    summary: {
      textElements: textEls.length,
      textElementsInFirstScreen: inkInFold,
      interactive: interactive.length,
      words,
      wordsOutsideContent,
      firstScreenWords,
      firstScreenWordsOutsideContent,
      longTextBlocks: longBlocks.length,
      longTextBlocksInFirstScreen: longBlocks.filter((b) => b.firstScreen).length,
      instructionalText: instructions.length,
      contrastFailures: contrast.length,
      contrastFailuresInFirstScreen: contrast.filter((c) => c.firstScreen).length,
      contrastUnknown: unknownContrast.length,
      inactiveLowContrast,
      smallText: smallText.length,
      smallTargets: smallTargets.length,
      smallTargetsInFirstScreen: smallTargets.filter((t) => t.firstScreen).length,
      smallTargetsPassingBySpacing: smallTargetsSpaced,
      unnamedControls: unnamed.length,
      truncatedText: truncated.length,
      truncatedWithoutTitle: truncated.filter((t) => !t.hasTitle).length,
      longLines: longLines.length,
      horizontalOverflow: overflowX.length || (document.documentElement.scrollWidth > vw + 1 ? 1 : 0),
      textSpill: textSpill.length,
      textOutsideBox: textOutsideBox.length,
      overlappingText: overlappingText.length,
      coveredBySticky: coveredBySticky.length,
      svgLabelOverflow: svgLabelOverflow.length,
      looseConnectors: looseConnectors.length,
      clippedShapes: clippedShapes.length,
      distinctFontSizes: fontSizes.size,
      distinctFontWeights: weights.size,
      distinctTextColours: textColours.size,
      distinctSpacingValues: spacing.size,
      offScaleSpacingValues: offScale.length,
      imagesWithoutAlt: imagesWithoutAlt.length,
    },
    fontSizes: [...fontSizes.entries()].sort((a, b) => a[0] - b[0]).map(([size, count]) => ({ size, count })),
    firstScreen: firstScreen.sort((a, b) => a.top - b.top).slice(0, 20),
    longTextBlocks: longBlocks.sort((a, b) => Number(b.firstScreen) - Number(a.firstScreen) || b.words - a.words).slice(0, opts.limit),
    instructionalText: instructions.slice(0, opts.limit),
    contrast: top(contrast, "ratio"),
    contrastUnknown: unknownContrast.slice(0, opts.limit),
    smallText: top(smallText, "size"),
    smallTargets: top(smallTargets, "h"),
    unnamedControls: unnamed.slice(0, opts.limit),
    truncated: truncated.slice(0, opts.limit),
    longLines: longLines.sort((a, b) => b.approxCh - a.approxCh).slice(0, opts.limit),
    horizontalOverflow: overflowX.slice(0, opts.limit),
    textSpill: textSpill.slice(0, opts.limit),
    textOutsideBox: textOutsideBox.slice(0, opts.limit),
    overlappingText,
    coveredBySticky: coveredBySticky.slice(0, opts.limit),
    svgLabelOverflow: svgLabelOverflow.slice(0, opts.limit),
    looseConnectors: looseConnectors.slice(0, opts.limit),
    clippedShapes: clippedShapes.slice(0, opts.limit),
    offScaleSpacing: offScale.sort((a, b) => a - b).slice(0, 20),
    imagesWithoutAlt: imagesWithoutAlt.slice(0, opts.limit),
  };
}

// The file's value: in a page, the report; in a harness with a `browser` object and no page of its own, a promise of it.
typeof document === "undefined" && typeof browser !== "undefined"
  ? browser.getPage("main").then((page) => page.evaluate(uxAudit)).then((report) => JSON.stringify(report, null, 1))
  : JSON.stringify(uxAudit(), null, 1);
