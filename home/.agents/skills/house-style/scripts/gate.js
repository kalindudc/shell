// The house gate: run it whole, as one expression, in the page as it will be published (a
// browser tool's evaluate, Puppeteer's page.evaluate of this file's text, or the devtools
// console). It answers with a list of what the page lacks or gets wrong, each saying what to do;
// an empty list passes. It checks the parts every page has (SKILL.md, Every Page Has Its Parts),
// the measure, the sizes and the writing's guard. It presses ? and Escape to test the Keys list,
// so run it on a page nobody is reading. Run it at 320, 390, 768 and 1400px, in both themes.
//
// Its method is adapted from gate.js in Joel Gerber's web-design skill (github.com/Jitsusama/
// core.nix, modules/theme/web/skill), MIT License, Copyright (c) 2024 Joel Gerber; the parts it
// looks for are this house's own.
(async () => {
  const missing = [];
  const page = document;
  const root = page.documentElement;
  const main = page.querySelector("main");
  const overview = main?.classList.contains("overview") === true;
  const project = main?.classList.contains("project") === true;
  const shown = (element) => element?.isConnected === true && element.checkVisibility();
  const meta = (selector) => page.querySelector(selector)?.getAttribute("content")?.trim() ?? "";
  const loads = async (address, drawing) => {
    try {
      const answer = await fetch(address, { cache: "no-store" });
      const text = await answer.text();
      return answer.ok && (drawing ? text.includes("<svg") : text.trim() !== "" && !text.includes("<html"));
    } catch {
      return false;
    }
  };
  const named = (element) => {
    const walker = page.createTreeWalker(element, NodeFilter.SHOW_TEXT);
    const words = [];
    while (walker.nextNode()) {
      if (walker.currentNode.parentElement.closest('[aria-hidden="true"]') === null) words.push(walker.currentNode.textContent.trim());
    }
    return words.filter((word) => word !== "").join(" ").replace(/ ([,.;:!?])/gu, "$1");
  };

  // The head: what names the page in a tab, a shared link and a reader.
  if (page.characterSet !== "UTF-8") missing.push('<meta charset="utf-8"> first in the head');
  if (!root.lang) missing.push('a lang on <html>, such as lang="en"');
  if (page.title.trim() === "") missing.push("a <title>: the page's pithy title");
  const icon = page.querySelector('link[rel~="icon"]');
  if (icon === null || !new URL(icon.href).pathname.endsWith(".svg")) missing.push('a favicon of the site\'s mark: <link rel="icon" href="favicon.svg">');
  else if (!(await loads(icon.href, true))) missing.push(`a favicon that loads: ${icon.href} doesn't answer with an SVG`);
  for (const [selector, part] of [
    ['meta[name="description"]', '<meta name="description">, the lede'],
    ['meta[property="og:title"]', '<meta property="og:title">, for a shared link'],
    ['meta[property="og:description"]', '<meta property="og:description">, for a shared link'],
    ['meta[property="og:type"]', '<meta property="og:type" content="website">'],
    ['meta[name="theme-color"]', '<meta name="theme-color">, the ground round the page'],
  ]) if (meta(selector) === "") missing.push(part);

  // The header and the memo head: the seal, the route, the Keys button and the switch in the
  // header; one title and the brief in the head; and a skip link first.
  if (main === null) missing.push('a <main class="page"> holding the page');
  const bar = page.querySelector("header.topbar");
  if (bar === null) missing.push('the header: <header class="topbar"> before <main>, holding the seal, the route, the Keys button and the switch');
  const route = page.querySelector('.topbar nav.route[aria-label="Parts"]');
  const parts = [...page.querySelectorAll("main .part[id]")];
  if (route === null) missing.push('the route in the header: <nav class="route" aria-label="Parts"><ol> with a link to each part');
  else for (const part of parts) if (route.querySelector(`a[href="#${part.id}"]`) === null) missing.push(`a stop on the route for the part "${part.id}"`);
  const titles = [...page.querySelectorAll("h1")].filter(shown).length;
  if (titles !== 1) missing.push(`one <h1>, the page's title: it has ${titles}`);
  if (page.querySelector(".topbar .home svg.mark.seal .edge") === null) missing.push("the site's seal in the header's home link: draw it with scripts/mark.py");
  if (page.querySelector('.topbar [role="radiogroup"][aria-label="Theme"]') === null) missing.push('the theme switch in the header: role="radiogroup" aria-label="Theme", with Light, Match System and Dark');
  const briefed = [...page.querySelectorAll(".masthead .brief > div")].length >= 2;
  if (project && !overview) missing.push('the project form on the status page\'s desk: <main class="page overview project">');
  if (project && !briefed && page.querySelectorAll("main .headline > .card").length < 2) missing.push('the brief or the headline: a project page opens on <dl class="brief"> or a .headline of two to three cards (built, moved, left)');
  else if (!project && !briefed) missing.push('the brief under the lede: <dl class="brief"> with the two to five facts a reader needs first (status, what is asked, owner, updated)');
  const first = page.querySelector("a[href], button, input, select, textarea, [tabindex]:not([tabindex='-1'])");
  const skipsTo = first?.getAttribute("href")?.startsWith("#") ? first.getAttribute("href") : "";
  if (skipsTo.length < 2 || page.getElementById(decodeURIComponent(skipsTo.slice(1))) === null) missing.push("a skip link, the first thing focus reaches, to the page's main part");

  // Controls the page draws: no system menu, and nothing in the header that comes and goes.
  const native = [...page.querySelectorAll("select")].find(shown);
  if (native) missing.push(`a system dropdown ("${(native.getAttribute("aria-label") || native.name || native.id).slice(0, 30)}"): load kit/site.js, which draws every <select> as the page's own`);
  if (page.querySelector(".topbar .live, .topbar [data-live], .topbar [aria-live]") !== null) missing.push("live status in the header: put it in the page beside what it describes, so the header keeps its shape");
  // Every number a project page draws from data names its source and when it was true.
  const unsourced = [...page.querySelectorAll("main .fact")].find((fact) => shown(fact) && !(fact.dataset.tip ?? "").trim());
  if (unsourced) missing.push(`a number without its source ("${named(unsourced).slice(0, 30)}"): give each .fact a data-tip with its source and as-of time`);
  // A group whose every item is done starts folded, so what still needs work stays in view.
  const doneOpen = [...page.querySelectorAll("details.group[open]")].find((group) => { const states = [...group.querySelectorAll(".rows .state")]; return states.length > 0 && states.every((state) => state.classList.contains("good")); });
  if (doneOpen) missing.push(`a group that is all done but open ("${named(doneOpen.querySelector("summary")).slice(0, 30)}"): fold it by leaving out open`);

  // The Keys list opens on ? and Escape closes it, with focus back where it was.
  const keysHeading = () => [...page.querySelectorAll("dialog h2, dialog h3")].find((heading) => named(heading) === "Keys");
  const within = (holds) => new Promise((answer) => {
    const until = performance.now() + 2000;
    const look = () => (holds() || performance.now() >= until ? answer(holds()) : requestAnimationFrame(look));
    look();
  });
  const press = (key, code) => (page.activeElement ?? page.body).dispatchEvent(new KeyboardEvent("keydown", { key, code, shiftKey: key === "?", bubbles: true, cancelable: true, composed: true }));
  const start = page.activeElement;
  first?.focus();
  const before = page.activeElement;
  press("?", "Slash");
  if (await within(() => shown(keysHeading()))) {
    const dialog = keysHeading().closest("dialog");
    if (dialog?.matches(":modal") && typeof dialog.requestClose === "function") dialog.requestClose();
    else if (dialog?.open) dialog.close();
    if (!(await within(() => !shown(keysHeading())))) missing.push("Escape didn't close the Keys list");
    else if (page.activeElement !== before) missing.push("focus didn't come back after the Keys list closed");
  } else {
    missing.push('a Keys list: <dialog class="keys" id="keys"> headed Keys, that ? opens (kit/site.js)');
  }
  if (start === page.body) page.activeElement?.blur();
  if (page.querySelector(".topbar [data-open-keys]") === null) missing.push('the Keys button in the header: <button class="iconbtn" data-open-keys aria-label="Keys"><kbd>?</kbd></button>');
  if (page.querySelector("#keys [data-keys-toggle]") === null) missing.push('a "Character shortcuts" toggle in the Keys list: <input type="checkbox" data-keys-toggle> (WCAG 2.1.4)');

  // The twin for agents.
  const twin = page.querySelector('link[rel="alternate"][type="text/markdown"]');
  if (twin === null || !(await loads(twin.href, false))) missing.push('a Markdown twin that loads: <link rel="alternate" type="text/markdown" href="index.md">');
  if (!(await loads(new URL("/llms.txt", location.href).href, false))) missing.push("an llms.txt at the site's root, saying what it holds and where");

  // The foot and its byline.
  const by = page.querySelector("footer .by");
  if (by === null || by.textContent.trim() !== "by Kalindu De Costa") missing.push('the foot\'s byline: <span class="by">by Kalindu De Costa</span>');

  // Each part explains with a figure, or says on its section why it has none.
  const pictures = "svg[role='img'], [role='img'], table, figure img[alt]:not([alt=''])";
  const said = (element) => element?.closest("[data-figure]")?.dataset.figure?.trim() ?? "";
  for (const heading of [...page.querySelectorAll("main h2")].filter((h) => h.closest("dialog, aside, .plate") === null)) {
    const part = heading.closest("section") ?? heading.parentElement;
    if (part.querySelector(pictures) === null && said(part) === "") missing.push(`a figure for "${named(heading)}", or data-figure="why" on its section`);
  }
  if (!overview && main !== null && main.querySelector("svg[role='img']") === null && said(main) === "") missing.push('a drawing: a page to read with no SVG role="img" has lost its imagery');

  // A drawing's labels never fall under 12px on screen.
  const onScreen = (label) => {
    const scale = label.getScreenCTM();
    const size = Number.parseFloat(getComputedStyle(label).fontSize);
    return scale === null ? size : size * Math.hypot(scale.a, scale.b);
  };
  for (const picture of [...page.querySelectorAll("svg[role='img']")].filter(shown)) {
    const sizes = [...picture.querySelectorAll("text")].filter(shown).map(onScreen);
    const smallest = Math.min(...sizes);
    if (sizes.length > 0 && smallest < 11.5) {
      const what = picture.querySelector("title")?.textContent.trim().slice(0, 60) || "a drawing";
      missing.push(`labels drawn at ${smallest.toFixed(1)}px in "${what}": draw a narrow twin, or set its labels as HTML`);
    }
  }

  // No serif text in the page under 15px, and prose holds the measure: 45 to 80 characters a line.
  if (main !== null) {
    const probe = page.createElement("span");
    probe.style.fontFamily = "var(--mono)";
    main.append(probe);
    const mono = getComputedStyle(probe).fontFamily;
    probe.remove();
    const isMono = (element) => getComputedStyle(element).fontFamily === mono || element.closest("code, kbd, samp, pre, .mono, svg, sup, sub, .sr") !== null;
    let small = null;
    const parents = new Set();
    const texts = page.createTreeWalker(main, NodeFilter.SHOW_TEXT);
    for (let text = texts.nextNode(); text !== null; text = texts.nextNode()) if (text.textContent.trim() !== "" && text.parentElement) parents.add(text.parentElement);
    for (const element of parents) {
      if (!shown(element) || isMono(element)) continue;
      const size = Number.parseFloat(getComputedStyle(element).fontSize);
      if (size < 14.5 && (small === null || size < small.size)) small = { element, size };
    }
    if (small !== null) missing.push(`serif text at ${small.size.toFixed(1)}px ("${small.element.textContent.trim().slice(0, 40)}"): set it at --step-small or larger`);
    const lines = (block) => {
      const counts = new Map();
      const range = page.createRange();
      const walker = page.createTreeWalker(block, NodeFilter.SHOW_TEXT);
      for (let text = walker.nextNode(); text !== null; text = walker.nextNode()) {
        for (let at = 0; at < text.length; at += 1) {
          range.setStart(text, at);
          range.setEnd(text, at + 1);
          const box = range.getClientRects()[0];
          if (box) counts.set(Math.round(box.top), (counts.get(Math.round(box.top)) ?? 0) + 1);
        }
      }
      return [...counts.values()];
    };
    // Only blocks of running text count: a block whose children all flow inline, so its lines are
    // lines of one paragraph, not cells of a row set side by side.
    const running = (block) => getComputedStyle(block).display === "block" && [...block.querySelectorAll("*")].every((child) => getComputedStyle(child).display.startsWith("inline") || getComputedStyle(child).display === "none");
    const blocks = [...main.querySelectorAll("p, li, figcaption, .lede")].filter((block) => shown(block) && !isMono(block) && running(block) && block.closest("table, dialog, nav, .plate header") === null && block.textContent.trim().length >= 160);
    const wide = innerWidth >= 1024;
    for (const block of blocks) {
      const counts = lines(block);
      if (counts.length < 2) continue;
      const longest = Math.max(...counts);
      const widest = Math.max(...counts.slice(0, -1));
      if (longest > 84) missing.push(`a line of ${longest} characters ("${block.textContent.trim().slice(0, 40)}"): hold prose to the measure`);
      else if (wide && widest < 40) missing.push(`lines of ${widest} characters at most ("${block.textContent.trim().slice(0, 40)}"): a column too narrow for sentences`);
    }
  }

  // Nothing wider than the screen. On a phone (or one emulated with isMobile) an overflowing page
  // widens the layout viewport instead of scrolling, so innerWidth alone hides it; screen.width
  // does not move. A desktop's screen.width says nothing about the window, so it counts only there.
  const room = (matchMedia("(hover: none)").matches ? Math.min(innerWidth, screen.width) : innerWidth) + 1;
  if (page.documentElement.scrollWidth > room) {
    const culprit = [...main.querySelectorAll("*")].find((element) => {
      const box = element.getBoundingClientRect();
      if (box.width === 0 || box.right <= room) return false;
      for (let up = element.parentElement; up && up !== main; up = up.parentElement) if (getComputedStyle(up).overflowX !== "visible") return false;
      return true;
    });
    missing.push(`a page ${page.documentElement.scrollWidth}px wide on a ${room - 1}px screen${culprit ? `, from <${culprit.localName}> ("${culprit.textContent.trim().slice(0, 40)}")` : ""}: let it wrap, or scroll inside its own box`);
  }

  // Text on the ground: the wash darkens the paper under the memo head, so every text colour in its
  // reach must still pass against the darkest paper it can make (4.5:1, or 3:1 for large text).
  // A fresh probe for each colour: the kit's reduced-motion rule gives every element a 1ms
  // transition, so a reused probe would still report the colour before.
  const rgb = (css) => {
    const probe = page.createElement("i");
    probe.style.color = css;
    page.body.append(probe);
    const value = getComputedStyle(probe).color;
    probe.remove();
    const parts = value.match(/-?[\d.]+/g).map(Number);
    return value.startsWith("color(srgb") ? parts.slice(0, 3).map((x) => x * 255) : value.startsWith("rgb") ? parts.slice(0, 3) : null;
  };
  const lum = ([r, g, b]) => [r, g, b].map((x) => { x /= 255; return x <= 0.03928 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4; }).reduce((sum, x, i) => sum + x * [0.2126, 0.7152, 0.0722][i], 0);
  const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };
  const paper = rgb("var(--paper)");
  const washed = rgb("color-mix(in srgb, var(--wash) var(--wash-hue), color-mix(in srgb, var(--tint) var(--wash-tint), var(--paper)))");
  if (paper === null || washed === null) missing.push("the ground's colours could not be read as sRGB, so text on the wash went unmeasured");
  const reach = parseFloat(getComputedStyle(page.documentElement).getPropertyValue("--wash-reach")) || 0;
  const onGround = (element) => { for (let el = element; el && el !== page.body; el = el.parentElement) { const bg = getComputedStyle(el).backgroundColor; if (!/rgba\(0, 0, 0, 0\)|transparent/.test(bg)) return false; } return true; };
  const seen = new Set();
  const texts = page.createTreeWalker(page.body, NodeFilter.SHOW_TEXT);
  for (let text = texts.nextNode(); text !== null && washed !== null && paper !== null; text = texts.nextNode()) {
    const element = text.parentElement;
    if (!text.textContent.trim() || seen.has(element) || element.closest("script, style, .topbar, dialog, [popover]")) continue;
    seen.add(element);
    const box = element.getBoundingClientRect();
    if (box.width === 0 || box.top + scrollY > reach || !onGround(element)) continue;
    const style = getComputedStyle(element);
    const size = parseFloat(style.fontSize);
    const large = size >= 24 || (size >= 18.66 && Number(style.fontWeight) >= 700);
    const ink = rgb(style.color);
    if (ink === null) continue;
    const measured = ratio(ink, washed);
    if (measured < (large ? 3 : 4.5)) { missing.push(`text on the wash at ${measured.toFixed(2)}:1 ("${text.textContent.trim().slice(0, 30)}" in <${element.localName}>, ${ratio(ink, paper).toFixed(2)}:1 on plain paper): use a stronger colour or lower --wash-hue`); break; }
  }

  // Category chips (the pastel category set): each word must read on its own pastel fill, 4.5:1.
  for (const chip of page.querySelectorAll(".cat")) {
    if (!shown(chip) || !chip.textContent.trim()) continue;
    const style = getComputedStyle(chip);
    const ink = rgb(style.color), fill = rgb(style.backgroundColor);
    if (ink === null || fill === null || /rgba\(0, 0, 0, 0\)|transparent/.test(style.backgroundColor)) { missing.push(`a category chip ("${chip.textContent.trim().slice(0, 30)}") without a pastel fill: give it a class from .cat.c1 to .cat.c7`); break; }
    const measured = ratio(ink, fill);
    if (measured < 4.5) { missing.push(`a category chip at ${measured.toFixed(2)}:1 ("${chip.textContent.trim().slice(0, 30)}"): use its --cat-N-ink on its --cat-N-soft`); break; }
  }

  // The kit, not a stranger's: fonts from the site, and no colour typed into the markup.
  const away = performance.getEntriesByType("resource").map((entry) => new URL(entry.name).host).filter((host) => host !== location.host);
  if (away.length > 0) missing.push(`requests that leave the site, to ${[...new Set(away)].join(", ")}: serve fonts and scripts from the site`);
  const typed = [...page.querySelectorAll("[style]")].find((element) => /#[0-9a-f]{3,8}\b|rgba?\(|hsla?\(/i.test(element.getAttribute("style")));
  if (typed) missing.push(`a colour typed into a style attribute on <${typed.localName}>: name a token, such as var(--aqua)`);

  // The writing's guard: nothing private an agent's work left behind.
  const prose = [];
  const walker = page.createTreeWalker(page.body, NodeFilter.SHOW_TEXT);
  for (let text = walker.nextNode(); text !== null; text = walker.nextNode()) {
    if (text.parentElement.closest("code, kbd, pre, samp, script, style, template, [data-said-by]") === null) prose.push(text.textContent);
  }
  const words = `${page.title} ${meta('meta[name="description"]')} ${prose.join(" ")}`;
  for (const [trace, what] of [["/Users/", "a path on a machine"], ["~/.", "a path on a machine"], ["thr_", "a thread id"], ["localhost", "a local address"], ["TODO", "a TODO"], ["lorem ipsum", "placeholder text"]]) {
    if (words.toLowerCase().includes(trace.toLowerCase())) missing.push(`nothing private or unfinished: the page shows ${what} ("${trace}")`);
  }
  return missing;
})()
