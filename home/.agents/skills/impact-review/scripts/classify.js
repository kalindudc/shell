// @options: {"max_output_tokens": 3000, "timeout_ms": 3600000}
// impact-review: classify evidence shards with the rubric's classifier. Edit P, then pass this whole file as a codemode script.
// Reads <dir>/shards/*.jsonl, writes <dir>/results/<shard>.jsonl. Resumable: finished shards are skipped.
// Run from disk with overrides (see SKILL.md "Running templates"), or paste and edit DEFAULTS.
const DEFAULTS = {
  dir: "/Users/YOU/.agents/tmp/impact-review/<start>_<end>/self", // run dir containing shards/
  questions: "/Users/YOU/.agents/tmp/impact-review/<start>_<end>/self/questions.json", // from: impact.py resolve --out
  subject: "Full Name", // as people know them
  s: "First", // must match the --label / s used by collectors
  role: "Staff Engineer, Team",
  mode: "self", // "self" | "peer" (peer adds peer_only questions)
  concurrency: 4, // pi allows at most 4 concurrent classify calls per script
  retries: 3,
};
const P = { ...DEFAULTS, ...(typeof P_OVERRIDE === "undefined" ? {} : P_OVERRIDE) };

async function sh(command) {
  const r = await tools.bash({ command, timeout: 120 });
  if (r.truncated) throw new Error(`output truncated for: ${command} (use smaller shards: shard --size 50)`);
  return r;
}

const Q = JSON.parse((await sh(`cat ${JSON.stringify(P.questions)}`)).output);
if (!Q.sources) throw new Error(`${P.questions} has no sources: pass the file written by \`impact.py resolve --out\``);
const model = await models.getModelOfType("classifier", Q.model.provider, Q.model.id);
if (!model) throw new Error(`classifier ${Q.model.provider}/${Q.model.id} not available; check models.getAvailableOfType("classifier")`);

function fill(str, source) {
  return str
    .replaceAll("{SOURCE}", source)
    .replaceAll("{SUBJECT}", P.subject)
    .replaceAll("{ROLE}", P.role)
    .replaceAll("{S}", P.s);
}

function questionsFor(item) {
  const src = Q.sources[item.source] || "An item";
  const ctx = fill(Q.context, src);
  const out = {};
  for (const [k, q] of Object.entries(Q.questions)) {
    if (q.peer_only && P.mode !== "peer") continue;
    const crit = q.criteria === "@strength" ? Q.strength : q.criteria;
    const criteria = Array.isArray(crit)
      ? crit.map((c) => fill(c, src))
      : Object.fromEntries(Object.entries(crit).map(([ck, cv]) => [ck, fill(cv, src)]));
    out[k] = { type: q.type, instructions: `${ctx} ${fill(q.instructions, src)}`, criteria };
  }
  return out;
}

function compact(id, answers) {
  const row = { id, p: {} };
  for (const [k, a] of Object.entries(answers)) {
    if (a.type === "bool") row.p[k] = +a.probability.toFixed(3);
    else if (a.type === "choice") {
      row[k] = a.choice;
      row[`${k}_p`] = +(a.probabilities[a.choice] ?? a.confidence).toFixed(3);
    } else if (a.type === "score") row.p[k] = +a.score.toFixed(3);
  }
  return row;
}

async function classifyOne(item) {
  const state = { source: item.source, title: item.title, date: item.date, workstream: item.workstream, text: item.text };
  let last = "";
  for (let i = 0; i <= P.retries; i++) {
    const r = await models.classify(model, { state, questions: questionsFor(item) });
    if (r.stopReason === "stop") return compact(item.id, r.answers);
    last = r.errorMessage || r.stopReason;
    await sh(`sleep ${5 * (i + 1)}`);
  }
  return { id: item.id, error: last };
}

await sh(`mkdir -p ${JSON.stringify(P.dir + "/results")}`);
const ls = await sh(`ls ${JSON.stringify(P.dir + "/shards")}/*.jsonl`);
if (ls.exit_code !== 0) throw new Error(`no shards under ${P.dir}/shards: ${ls.output}`);
const shards = ls.output.trim().split("\n").filter(Boolean);
const readJsonl = async (p) => (await sh(`cat ${JSON.stringify(p)}`)).output.split("\n").filter((l) => l.trim()).map((l) => JSON.parse(l));
const exists = async (p) => (await tools.bash({ command: `test -s ${JSON.stringify(p)} && echo yes || echo no`, timeout: 10 })).output.trim() === "yes";
const t0 = Date.now();
const stats = { shards: shards.length, skipped: 0, items: 0, errors: 0 };
for (const shard of shards) {
  const out = `${P.dir}/results/${shard.split("/").pop()}`;
  const hasOut = await exists(out);
  const hasErr = await exists(`${out}.errors`);
  if (hasOut && !hasErr) {
    stats.skipped++;
    continue;
  }
  const prior = hasOut ? await readJsonl(out) : [];
  const done = new Set(prior.map((r) => r.id));
  const items = (await readJsonl(shard)).filter((it) => !done.has(it.id));
  const rows = [...prior];
  for (let i = 0; i < items.length; i += P.concurrency) {
    rows.push(...(await Promise.all(items.slice(i, i + P.concurrency).map(classifyOne))));
  }
  const ok = rows.filter((r) => !r.error);
  const bad = rows.filter((r) => r.error);
  stats.items += ok.length - prior.length;
  stats.errors += bad.length;
  await tools.write({ path: out, content: ok.map((r) => JSON.stringify(r)).join("\n") + "\n" });
  if (bad.length) await tools.write({ path: `${out}.errors`, content: bad.map((r) => JSON.stringify(r)).join("\n") + "\n" });
  else if (hasErr) await sh(`rm -f ${JSON.stringify(out + ".errors")}`);
}
stats.seconds = Math.round((Date.now() - t0) / 1000);
return stats;
