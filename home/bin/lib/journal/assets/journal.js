// The Morning Edge: a tile names itself when it is pointed at, and the weather's
// buttons pick tiles out of the map; pressing the same button again shows every tile.
(() => {
  const tip = document.getElementById("tip");
  for (const tile of document.querySelectorAll(".tiles a")) {
    const say = () => { if (tip) tip.textContent = tile.dataset.t; };
    tile.addEventListener("mouseenter", say);
  }
  const map = document.getElementById("backlog-map");
  const shown = document.getElementById("shown");
  if (!map) return;
  const buttons = [...document.querySelectorAll("button[data-filter]")];
  // The bar's segments answer a pointer too; the legend's buttons are the same choices for every reader.
  const segments = [...document.querySelectorAll(".stackbar [data-filter]")];
  const calm = () => matchMedia("(prefers-reduced-motion: reduce)").matches;
  for (const segment of segments) {
    segment.addEventListener("click", () => buttons.find((button) => button.dataset.filter === segment.dataset.filter)?.click());
  }
  for (const button of buttons) {
    button.addEventListener("click", () => {
      let filter = button.dataset.filter;
      if (filter === "all" || map.dataset.filter === filter) filter = "";
      map.dataset.filter = filter;
      for (const other of buttons) other.setAttribute("aria-pressed", String(filter !== "" && other.dataset.filter === filter));
      for (const segment of segments) segment.classList.toggle("on", filter !== "" && segment.dataset.filter === filter);
      if (shown) shown.textContent = filter ? `showing ${button.textContent.trim().replace(/^\d+\s*/, "")}; press it again for all` : "";
      if (filter) map.scrollIntoView({ behavior: calm() ? "auto" : "smooth", block: "start" });
    });
  }
})();
