// House script: the theme switch, the page keys and their list, the header's route and strip,
// checklists that remember, blocks that arrive once, and a helper that hands charts the theme's colours. The page is whole without
// it; the head's inline script has already applied a stored theme and set class="js" on <html>.
// Load it with <script src="kit/site.js" defer></script>.

(() => {
  const root = document.documentElement;
  const store = {
    get: (key) => { try { return localStorage.getItem(key); } catch { return null; } },
    set: (key, value) => { try { localStorage.setItem(key, value); } catch {} },
    del: (key) => { try { localStorage.removeItem(key); } catch {} },
  };
  const calm = () => matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Charts and drawings read colours when they draw, and draw again when the theme changes:
  // house.onTheme(draw) calls draw() now and after every change; house.color("--blue") reads one.
  const listeners = new Set();
  const house = {
    color: (name) => getComputedStyle(root).getPropertyValue(name).trim(),
    onTheme: (draw) => { listeners.add(draw); draw(); return () => listeners.delete(draw); },
    series: () => ["--blue", "--aqua", "--orange", "--purple", "--red", "--green"].map(house.color),
    mermaid: () => ({
      theme: "base",
      themeVariables: {
        fontFamily: house.color("--mono"), fontSize: "13px",
        background: house.color("--paper"), mainBkg: house.color("--card"),
        primaryColor: house.color("--card"), primaryBorderColor: house.color("--ink-soft"), primaryTextColor: house.color("--ink"),
        secondaryColor: house.color("--deep"), tertiaryColor: house.color("--paper"),
        lineColor: house.color("--rule"), textColor: house.color("--ink"),
        clusterBkg: house.color("--deep"), clusterBorder: house.color("--rule"),
        noteBkgColor: house.color("--blue-soft"), noteTextColor: house.color("--ink"), noteBorderColor: house.color("--blue"),
        edgeLabelBackground: house.color("--paper"),
      },
    }),
  };
  window.house = house;
  const themeChanged = () => {
    const meta = document.querySelector('meta[name="theme-color"]:not([media])');
    if (meta) meta.content = house.color("--paper");
    for (const draw of listeners) draw();
  };

  // The switch: Light, Match System and Dark. Match System removes the stored choice.
  const toggle = document.querySelector('.switch[role="radiogroup"]');
  const showTheme = () => {
    if (!toggle) return;
    const choice = root.dataset.theme || "system";
    for (const button of toggle.querySelectorAll("button[data-choice]")) {
      const on = button.dataset.choice === choice;
      button.setAttribute("aria-checked", String(on));
      button.tabIndex = on ? 0 : -1;
    }
  };
  const chooseTheme = (choice) => {
    const apply = () => {
      if (choice === "system") { delete root.dataset.theme; store.del("theme"); }
      else { root.dataset.theme = choice; store.set("theme", choice); }
      showTheme();
      themeChanged();
    };
    if (document.startViewTransition && !calm()) document.startViewTransition(apply); else apply();
  };
  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => { showTheme(); themeChanged(); });
  if (toggle) {
    showTheme();
    toggle.addEventListener("click", (event) => {
      const button = event.target.closest("button[data-choice]");
      if (button) chooseTheme(button.dataset.choice);
    });
    toggle.addEventListener("keydown", (event) => {
      const step = { ArrowLeft: -1, ArrowUp: -1, ArrowRight: 1, ArrowDown: 1 }[event.key];
      if (!step) return;
      event.preventDefault();
      const buttons = [...toggle.querySelectorAll("button[data-choice]")];
      const next = buttons[(buttons.indexOf(document.activeElement) + step + buttons.length) % buttons.length];
      next.focus();
      chooseTheme(next.dataset.choice);
    });
  }
  themeChanged();

  // A sticky header reserves its own height on the content (--header-room, read as each element's
  // scroll margin), so a jump never hides a heading under it and focus in the header never scrolls.
  const bar = document.querySelector(".topbar");
  const pad = () => {
    const sticky = bar && getComputedStyle(bar).position === "sticky";
    root.style.setProperty("--header-room", sticky ? `${Math.ceil(bar.getBoundingClientRect().height) + 16}px` : "0px");
  };
  if (bar) { pad(); addEventListener("resize", pad); new ResizeObserver(pad).observe(bar); }

  // The header. On the route a part you passed is .done, the part you are reading is .current,
  // and the line after it fills by how far into that part you are (--seg). The strip's pieces
  // are built here from the route and the pages: a button naming where you are, a list of every
  // page and part it opens, and a reading line with a tick where each part starts. When the
  // route bar's stops don't fit its row, the header is .tight and shows the strip instead.
  const header = document.querySelector(".topbar");
  const route = header?.querySelector(".route");
  const parts = [...document.querySelectorAll("main .part[id]")];
  const routeStops = route ? [...route.querySelectorAll("li")] : [];
  const stopFor = (part) => routeStops.find((li) => li.querySelector("a")?.getAttribute("href") === `#${part.id}`);
  const nameOf = (part) => stopFor(part)?.textContent.trim() ?? part.querySelector(".label")?.textContent.replace(/^\s*\d+\s*\/?\s*/, "").trim() ?? part.id;
  let here = null, list = null, fill = null;
  const ticks = [];
  if (header && parts.length > 0) {
    here = document.createElement("button");
    here.type = "button";
    here.className = "here";
    here.setAttribute("popovertarget", "site-index");
    here.setAttribute("aria-expanded", "false");
    here.innerHTML = '<span class="sr">Contents: </span><span class="n"></span><span class="t">Contents</span><svg class="chev" viewBox="0 0 12 12" aria-hidden="true"><path d="M3 4.5l3 3 3-3" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    header.querySelector(".home")?.after(here);

    list = document.createElement("div");
    list.id = "site-index";
    list.className = "parts-pop";
    list.setAttribute("popover", "");
    const section = (label, links) => {
      const heading = document.createElement("p");
      heading.className = "label";
      heading.textContent = label;
      const ol = document.createElement("ol");
      for (const link of links) { const li = document.createElement("li"); li.append(link); ol.append(li); }
      list.append(heading, ol);
    };
    const pages = [...(header.querySelector(".pages")?.querySelectorAll("a") ?? [])].map((a) => a.cloneNode(true));
    if (pages.length > 0) section("Pages", pages);
    section("On this page", parts.map((part, i) => {
      const a = document.createElement("a");
      a.href = `#${part.id}`;
      a.innerHTML = `<span class="n">${String(i + 1).padStart(2, "0")}</span><span></span>`;
      a.lastChild.textContent = nameOf(part);
      return a;
    }));
    document.body.append(list);
    list.addEventListener("toggle", (event) => {
      const open = event.newState === "open";
      here.setAttribute("aria-expanded", String(open));
      if (!open) return;
      const box = here.getBoundingClientRect();
      list.style.inset = "auto";
      list.style.position = "fixed";
      list.style.top = `${Math.round(box.bottom + 8)}px`;
      list.style.left = `${Math.round(Math.max(12, Math.min(box.left, innerWidth - list.offsetWidth - 12)))}px`;
      (list.querySelector('a[aria-current="location"]') ?? list.querySelector('a[href^="#"]') ?? list.querySelector("a"))?.focus();
    });
    list.addEventListener("click", (event) => { if (event.target.closest("a")) list.hidePopover(); });

    const line = document.createElement("div");
    line.className = "progress";
    line.setAttribute("aria-hidden", "true");
    fill = document.createElement("span");
    fill.className = "fill";
    line.append(fill);
    for (const _ of parts) { const tick = document.createElement("span"); tick.className = "tick"; line.append(tick); ticks.push(tick); }
    header.append(line);
  }
  const fit = () => {
    if (!header || !route) return;
    header.classList.remove("tight");
    if (getComputedStyle(route).display !== "none" && route.scrollWidth > route.clientWidth + 1) header.classList.add("tight");
  };
  const mark = () => {
    if (parts.length === 0) return;
    const reading = scrollY + innerHeight * 0.3;
    const end = Math.max(0, root.scrollHeight - innerHeight);
    const starts = parts.map((part) => part.getBoundingClientRect().top + scrollY);
    let current = -1;
    starts.forEach((start, i) => { if (start <= reading) current = i; });
    if (end > 0 && scrollY >= end - 2) current = parts.length - 1;
    const next = current + 1 < starts.length ? starts[current + 1] : end + innerHeight * 0.3;
    const into = current < 0 ? 0 : Math.max(0, Math.min(1, (reading - starts[current]) / Math.max(1, next - starts[current])));
    parts.forEach((part, i) => {
      part.classList.toggle("current", i === current);
      const stop = stopFor(part);
      if (!stop) return;
      stop.classList.toggle("done", i < current);
      stop.classList.toggle("current", i === current);
      stop.style.setProperty("--seg", i < current ? "100%" : i === current ? `${(into * 100).toFixed(1)}%` : "0%");
      const link = stop.querySelector("a");
      if (i === current) link.setAttribute("aria-current", "location"); else link.removeAttribute("aria-current");
    });
    if (here) {
      here.querySelector(".n").textContent = current < 0 ? "" : String(current + 1).padStart(2, "0");
      here.querySelector(".t").textContent = current < 0 ? "Contents" : nameOf(parts[current]);
    }
    list?.querySelectorAll('a[href^="#"]').forEach((link, i) => { if (i === current) link.setAttribute("aria-current", "location"); else link.removeAttribute("aria-current"); });
    if (fill) {
      fill.style.width = `${(end === 0 ? 100 : Math.min(100, (scrollY / end) * 100)).toFixed(2)}%`;
      ticks.forEach((tick, i) => {
        tick.style.left = `${(end === 0 ? 0 : Math.max(0, Math.min(100, ((starts[i] - innerHeight * 0.3) / end) * 100))).toFixed(2)}%`;
        tick.classList.toggle("done", i < current);
        tick.classList.toggle("current", i === current);
      });
    }
  };
  if (header) {
    let queued = false;
    addEventListener("scroll", () => { if (!queued) { queued = true; requestAnimationFrame(() => { queued = false; mark(); }); } }, { passive: true });
    addEventListener("resize", () => { fit(); mark(); });
    document.fonts?.ready.then(() => { fit(); mark(); });
    fit();
    mark();
  }

  // The keys: j and k step part to part, g and G go to the top and the last part, ? opens the
  // list. They never fire in a field or with a modifier held, and the Keys list's "Character
  // shortcuts" toggle turns all five off for good (WCAG 2.1.4), leaving the header's ? button;
  // the toggle is <input type="checkbox" data-keys-toggle>.
  const keys = document.getElementById("keys");
  const lettersOn = () => store.get("keys") !== "off";
  const toggleLetters = keys?.querySelector("[data-keys-toggle]");
  if (toggleLetters) {
    toggleLetters.checked = lettersOn();
    toggleLetters.addEventListener("change", () => (toggleLetters.checked ? store.del("keys") : store.set("keys", "off")));
  }
  const stops = () => [...document.querySelectorAll(".masthead, .part")].filter((el) => el.offsetParent !== null);
  const at = () => {
    const line = scrollY + innerHeight * 0.25;
    let index = 0;
    stops().forEach((el, i) => { if (el.getBoundingClientRect().top + scrollY <= line) index = i; });
    return index;
  };
  const go = (index) => {
    const list = stops();
    const target = list[Math.max(0, Math.min(index, list.length - 1))];
    if (!target) return;
    if (!target.hasAttribute("tabindex")) target.tabIndex = -1;
    target.scrollIntoView({ behavior: calm() ? "auto" : "smooth", block: "start" });
    target.focus({ preventScroll: true });
  };
  document.addEventListener("keydown", (event) => {
    if (event.metaKey || event.ctrlKey || event.altKey) return;
    if (event.target.closest?.("input, textarea, select, [contenteditable]")) return;
    if (!lettersOn()) return;
    if (event.key === "?" && keys) {
      event.preventDefault();
      if (keys.open) keys.close(); else keys.showModal();
      return;
    }
    if (keys?.open) return;
    if (!"jkgG".includes(event.key) || event.key.length !== 1) return;
    document.querySelector(".parts-pop:popover-open")?.hidePopover();
    if (event.key === "j") go(at() + 1);
    else if (event.key === "k") go(at() - 1);
    else if (event.key === "g") go(0);
    else if (event.key === "G") go(stops().length - 1);
  });
  keys?.addEventListener("click", (event) => {
    const box = keys.getBoundingClientRect();
    const inside = event.clientX >= box.left && event.clientX <= box.right && event.clientY >= box.top && event.clientY <= box.bottom;
    if (!inside) keys.close();
  });
  document.querySelectorAll("[data-open-keys]").forEach((button) => button.addEventListener("click", () => keys?.showModal()));

  // Checklists remember their ticks: give each box a data-key that is stable across edits.
  for (const box of document.querySelectorAll('.checklist input[type="checkbox"][data-key]')) {
    const key = `check:${location.pathname}:${box.dataset.key}`;
    box.checked = store.get(key) === "1";
    box.addEventListener("change", () => (box.checked ? store.set(key, "1") : store.del(key)));
  }

  // A button with data-copy="id" copies that element's text, and says so for a moment.
  for (const button of document.querySelectorAll("[data-copy]")) {
    button.addEventListener("click", async () => {
      const text = document.getElementById(button.dataset.copy)?.textContent ?? "";
      const label = button.textContent;
      try { await navigator.clipboard.writeText(text); button.textContent = "Copied"; }
      catch { button.textContent = "Select it"; }
      setTimeout(() => { button.textContent = label; }, 1600);
    });
  }

  // Blocks marked .arrives come in once as they scroll into view; with less motion asked for,
  // or without this script, they are simply there.
  if (!calm() && "IntersectionObserver" in window) {
    root.classList.add("motion");
    const seen = new IntersectionObserver((entries) => {
      for (const entry of entries) if (entry.isIntersecting) { entry.target.classList.add("arrived"); seen.unobserve(entry.target); }
    }, { rootMargin: "0px 0px -8% 0px" });
    document.querySelectorAll(".arrives").forEach((el) => {
      if (el.getBoundingClientRect().top < innerHeight) el.classList.add("arrived"); else seen.observe(el);
    });
  }
})();
