// @options: {"max_output_tokens": 3000, "timeout_ms": 7200000}
// impact-review: collect Slack threads for one or more subjects through a shared per-cycle cache.
//   1. Pages each channel's history once per cycle into <cache_dir>/<cid>.parents.json (all parents, unfiltered).
//   2. Asks `impact.py slack-plan` which threads matter for these subjects (participants come from reply_users;
//      with firsthand_only, only threads the reviewer is also in, plus DMs) and fetches only the uncached ones.
//   3. Runs `impact.py slack-build` to (re)write <subject dir>/<cid>.jsonl items for every subject.
// Every thread is fetched at most once per cycle, across the self run and all peer runs. Batch peers in ONE call
// (subjects: [...]) so shared channels are paged once. Resumable: rate limits back off until budget_minutes is
// spent, then it returns {limited:true} with whatever is cached already built into items. Re-run the same call.
// Call slack_who_am_i once in the session first. Uses the direct Web API transport (format:"json"); hosted Slack
// search is usually rate limited (429). Run from disk with overrides (see SKILL.md "Running templates").
// Spread the org rubric's Slack config into the overrides: { ...rubric.slack, cache_dir, channels, ... }.
const DEFAULTS = {
  // Per-cycle cache shared by all runs. Sensitive (raw text + user ids): same handling as raw/.
  cache_dir: null, // e.g. "/Users/YOU/.agents/tmp/impact-review/<start>_<end>/_slack_cache"
  // C/G/D ids only (user ids are rejected by read_thread). name is used as the workstream label.
  channels: [], // e.g. [{ id: "C0123456789", name: "#team" }]
  oldest: null, // buffered collection start = window start - 30 days
  latest: null, // exclusive bound: day after the window end
  // Org rubric slack.*: workspace subdomain for permalinks and the codemode tool names that read Slack.
  workspace: null,
  read_channel_tool: null,
  read_thread_tool: null,
  // One entry per subject; dir = <run>/raw/slack. Labels (s) must match classify.js P.s for that subject.
  subjects: null, // e.g. [{ uid: "U0123456789", s: "Jane", dir: "/Users/YOU/.../peer-jane-doe/raw/slack" }]
  // Single-subject shorthand (self mode): used when subjects is null.
  dir: null,
  subject_uid: null,
  s: "First",
  reviewer_uid: null, // peer mode: YOUR user id; marks firsthand items and labels your lines
  reviewer_label: "REVIEWER",
  firsthand_only: false, // peer batches: true = only threads the reviewer took part in, plus DMs
  budget_minutes: 100, // stop cleanly before the codemode timeout; re-run to continue
  flush_every: 20,
  max_threads_per_channel: 600,
  impact: "~/.agents/skills/impact-review/scripts/impact.py",
};
const P = { ...DEFAULTS, ...(typeof P_OVERRIDE === "undefined" ? {} : P_OVERRIDE) };
const subjects = P.subjects || [{ uid: P.subject_uid, s: P.s, dir: P.dir }];
const missing = ["cache_dir", "oldest", "latest", "workspace", "read_channel_tool", "read_thread_tool"].filter((k) => !P[k]);
if (!P.channels?.length) missing.push("channels");
if (subjects.some((x) => !x.uid || !x.s || !x.dir)) missing.push("subjects [{uid, s, dir}] (or dir + subject_uid + s)");
if (missing.length) throw new Error(`missing config: ${missing.join(", ")} (spread ...rubric.slack)`);
const readChannel = tools[P.read_channel_tool];
const readThread = tools[P.read_thread_tool];
if (typeof readChannel !== "function" || typeof readThread !== "function") {
  throw new Error(`unknown Slack tool: ${P.read_channel_tool} or ${P.read_thread_tool} (check rubric slack.*)`);
}

const ts = (d) => String(Date.parse(`${d}T00:00:00Z`) / 1000);
const q = JSON.stringify;
const t0 = Date.now();
const left = () => P.budget_minutes * 60000 - (Date.now() - t0);
async function sh(command, timeout = 120) {
  return tools.bash({ command, timeout });
}

// Parse first, then inspect only the error field. Regex-testing the raw body false-positives on messages that
// mention "rate limit" (common in infra channels) and stalls forever. Transient transport errors (network_error,
// timeouts, 5xx) are retried too: a single network_error used to kill a multi-hour run.
// Returns null only when the time budget is spent; the caller saves progress and stops (re-run to resume).
const RETRYABLE = /rate.?limit|ratelimited|429|network_error|timed? ?out|ECONNRESET|internal_error|service_unavailable|\b50[234]\b/i;
async function api(fn, args) {
  for (let i = 0; ; i++) {
    let t;
    try {
      t = (await fn({ ...args, format: "json" })).content?.[0]?.text || "";
    } catch (e) {
      t = String(e?.message || e);
    }
    let j = null;
    try {
      j = JSON.parse(t);
    } catch {}
    if (j?.ok) return j;
    const err = j ? String(j.error) : t.slice(0, 300);
    if (!RETRYABLE.test(err)) throw new Error(`${err} for ${q(args)}`);
    const wait = Math.min(20 * (i + 1), 120);
    if (left() < (wait + 60) * 1000) return null;
    await sh(`sleep ${wait}`, wait + 30);
  }
}

const slim = (m) => ({
  ts: m.ts, user: m.user, text: m.text, subtype: m.subtype, bot_id: m.bot_id,
  reply_count: m.reply_count, reply_users: m.reply_users, reply_users_count: m.reply_users_count,
});
const impact = (args) => sh(`python3 ${P.impact} ${args}`);
const uids = subjects.map((x) => x.uid).join(",");
const planArgs = (cid) =>
  `slack-plan --cache ${q(P.cache_dir)} --cid ${cid} --oldest ${P.oldest} --latest ${P.latest} --subjects ${uids}` +
  (P.reviewer_uid ? ` --reviewer ${P.reviewer_uid}` : "") + (P.firsthand_only ? " --firsthand-only" : "") +
  ` --max ${P.max_threads_per_channel}`;
async function plan(cid) {
  const r = await impact(planArgs(cid));
  if (r.exit_code !== 0) throw new Error(`slack-plan failed for ${cid}: ${r.output.slice(-500)}`);
  return JSON.parse(r.output.trim().split("\n").pop());
}

await sh(`mkdir -p ${q(P.cache_dir)} ${subjects.map((x) => q(x.dir)).join(" ")}`);
const summary = [];
let limited = false;
for (const ch of P.channels) {
  if (limited) break;
  const cid = ch.id || ch;
  const cname = ch.name || cid;
  let pl = await plan(cid);

  // 1. page history once per cycle (all parents, so later subjects reuse it)
  if (pl.parents === null) {
    const parents = [];
    let cursor;
    do {
      const j = await api(readChannel, {
        channel_id: cid, oldest: ts(P.oldest), latest: ts(P.latest), limit: 100, ...(cursor ? { cursor } : {}),
      });
      if (!j) {
        limited = true;
        break;
      }
      parents.push(...(j.messages || []).map(slim));
      cursor = j.has_more ? j.response_metadata?.next_cursor : null;
    } while (cursor);
    if (limited) {
      summary.push({ cid, cname, limited: "while paging history; re-run to resume" });
      break;
    }
    await tools.write({ path: `${P.cache_dir}/${cid}.parents.json`, content: q({ oldest: P.oldest, latest: P.latest, parents }) });
    pl = await plan(cid);
  }

  // 2. fetch only the relevant, uncached threads
  let part = +(await sh(`ls ${q(P.cache_dir)}/${cid}.threads.*.jsonl 2>/dev/null | wc -l`)).output.trim() || 0;
  let buf = [];
  let fetched = 0;
  const flush = async () => {
    if (!buf.length) return;
    await tools.write({
      path: `${P.cache_dir}/${cid}.threads.${String(part++).padStart(3, "0")}.jsonl`,
      content: buf.map((x) => q(x)).join("\n") + "\n",
    });
    buf = [];
  };
  for (const pts of pl.need) {
    const j = await api(readThread, { channel_id: cid, message_ts: pts, ts: pts, limit: 200 });
    if (!j) {
      limited = true;
      break;
    }
    buf.push({ ts: pts, messages: (j.messages || []).map(slim) });
    if (++fetched % P.flush_every === 0) await flush();
  }
  await flush();
  summary.push({
    cid, cname, parents: pl.parents, relevant: pl.relevant, fetched, pending: pl.need.length - fetched,
    ...(pl.truncated ? { truncated: pl.truncated } : {}), ...(limited ? { limited: "while reading threads; re-run to resume" } : {}),
  });
}

// 3. build per-subject items from everything cached so far (also after a limited run)
const stamp = `${Date.now()}`;
await tools.write({ path: `${P.cache_dir}/.channels.${stamp}.json`, content: q(P.channels.map((c) => (c.id ? c : { id: c }))) });
await tools.write({ path: `${P.cache_dir}/.subjects.${stamp}.json`, content: q(subjects) });
const b = await impact(
  `slack-build --cache ${q(P.cache_dir)} --channels ${q(`${P.cache_dir}/.channels.${stamp}.json`)} ` +
    `--subjects ${q(`${P.cache_dir}/.subjects.${stamp}.json`)} --workspace ${q(P.workspace)}` +
    (P.reviewer_uid ? ` --reviewer ${P.reviewer_uid} --reviewer-label ${q(P.reviewer_label)}` : "") +
    (P.firsthand_only ? " --firsthand-only" : ""),
);
await sh(`rm -f ${q(`${P.cache_dir}/.channels.${stamp}.json`)} ${q(`${P.cache_dir}/.subjects.${stamp}.json`)}`);
if (b.exit_code !== 0) throw new Error(`slack-build failed: ${b.output.slice(-500)}`);
return {
  limited, minutes: +((Date.now() - t0) / 60000).toFixed(1),
  channels: summary.filter((x) => x.fetched || x.pending || x.limited || x.truncated),
  untouched: summary.filter((x) => !(x.fetched || x.pending || x.limited || x.truncated)).length,
  items: JSON.parse(b.output.trim().split("\n").pop() || "{}"),
};
