import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { isDeepStrictEqual, parseArgs } from "node:util";

const { values } = parseArgs({ options: {
  session: { type: "string" }, host: { type: "string" },
  audit: { type: "string" }, output: { type: "string" }, compare: { type: "string" },
} });
if (!values.session || !values.host) throw new Error("Usage: node run.mjs --session <browser-session> --host <host-id> [--audit <path>] [--output <path>] [--compare <before.json>]");
const directory = dirname(fileURLToPath(import.meta.url));
const audit = readFileSync(values.audit || join(directory, "../audit-page.js"), "utf8");
const cases = [
  ...["paint", "layout-paint", "strict", "content", "clip", "hidden", "auto", "x-clip"].map((clip) => ({
    name: `clipping: ${clip}`, file: `clipping.html?clip=${clip}`,
    expected: { horizontalOverflow: 0, horizontalOverflowListed: 0, overlappingText: 0 },
  })),
  { name: "clipping: y-clip", file: "clipping.html?clip=y-clip", expected: { horizontalOverflow: 1, horizontalOverflowListed: 1, overlappingText: 1 } },
  { name: "clipping: y-hidden", file: "clipping.html?clip=y-hidden", expected: { horizontalOverflow: 0, horizontalOverflowListed: 0, overlappingText: 0 } },
  { name: "clipping: y-hidden-spill", file: "clipping.html?clip=y-hidden-spill", expected: { horizontalOverflow: 1, horizontalOverflowListed: 0, overlappingText: 0, textSpill: 1 } },
  { name: "genuinely offscreen", file: "offscreen.html", expected: { horizontalOverflow: 2, horizontalOverflowListed: 2 } },
  { name: "plain offscreen baseline", file: "offscreen.html?plain=true", unchanged: true, expected: { horizontalOverflow: 2, horizontalOverflowListed: 2 } },
  ...["down", "inline", "zoom", "nested", "mixed", "individual"].map((mode) => ({
    name: `size: ${mode}`, file: `scaling.html?mode=${mode}`,
    expected: { smallText: 1, smallTargets: 2, smallTargetsPassingBySpacing: 0 }, expectedSize: 7.7,
  })),
  { name: "size: up", file: "scaling.html?mode=up", expected: { smallText: 0, smallTargets: 0, smallTargetsPassingBySpacing: 0 } },
  { name: "size: SVG down", file: "svg-scaling.html", expected: { smallText: 1 }, expectedSize: 7.7 },
  { name: "unscaled baseline", file: "baseline.html", unchanged: true, expected: { smallText: 1, horizontalOverflow: 0, overlappingText: 0 } },
];
const scriptFor = (batch) => `const page = await browser.getPage("main");
await page.setViewport({ width: 800, height: 600 });
const results = [];
for (const test of ${JSON.stringify(batch)}) {
  await page.goto(${JSON.stringify(pathToFileURL(join(directory, "fixtures/")).href)} + test.file);
  const report = JSON.parse(await page.evaluate(${JSON.stringify(audit)}));
  const actual = { ...report.summary, horizontalOverflowListed: report.horizontalOverflow.length };
  const failures = Object.entries(test.expected).filter(([key, value]) => actual[key] !== value).map(([key, value]) => key + ": expected " + value + ", got " + actual[key]);
  if (test.expectedSize !== undefined && !report.smallText.some((item) => Math.abs(item.size - test.expectedSize) < 0.05)) failures.push("expected a rendered font size of " + test.expectedSize);
  results.push({ name: test.name, expected: test.expected, actual, sizes: report.smallText.map((item) => item.size), failures, report });
}
results;`;
const temporary = mkdtempSync(join(tmpdir(), "ux-audit-test-"));
try {
  const scriptPath = join(temporary, "run.js");
  const results = [];
  for (let start = 0; start < cases.length; start += 4) {
    writeFileSync(scriptPath, scriptFor(cases.slice(start, start + 4)));
    const response = JSON.parse(execFileSync("bb", ["browser-automation", "run", values.session, "--script-host", values.host, "--script-file", scriptPath, "--timeout-ms", "120000", "--json"], { encoding: "utf8", maxBuffer: 1024 * 1024, timeout: 125000 }));
    if (response.ok === false) throw new Error(JSON.stringify(response.error));
    if (response.exitCode !== 0) throw new Error(response.text);
    const batch = JSON.parse(response.text);
    if (!Array.isArray(batch)) throw new Error("Expected an array of fixture results");
    results.push(...batch);
  }
  if (values.compare) {
    const before = JSON.parse(readFileSync(values.compare, "utf8"));
    for (const test of results) {
      const original = before.find((item) => item.name === test.name);
      if (!original) throw new Error(`Missing original result for ${test.name}`);
      for (const keys of [Object.keys, (report) => Object.keys(report.summary)]) {
        if (!isDeepStrictEqual(keys(test.report), keys(original.report))) test.failures.push("audit output keys changed");
      }
      if (cases.find((item) => item.name === test.name).unchanged && !isDeepStrictEqual(test.report, original.report)) test.failures.push("baseline report changed");
    }
  }
  if (values.output) writeFileSync(resolve(values.output), JSON.stringify(results, null, 2) + "\n");
  for (const test of results) {
    const counts = Object.keys(test.expected).map((key) => `${key}=${test.actual[key]}`).join(", ");
    console.log(`${test.failures.length ? "FAIL" : "PASS"} ${test.name}: ${counts}${test.sizes.length ? `; sizes=${test.sizes.join(",")}` : ""}`);
    for (const failure of test.failures) console.log(`  ${failure}`);
  }
  const failed = results.filter((test) => test.failures.length).length;
  console.log(`${results.length - failed} passed, ${failed} failed`);
  process.exitCode = failed ? 1 : 0;
} finally {
  rmSync(temporary, { recursive: true });
}
