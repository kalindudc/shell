# Bare harness quick start

Use a headless lead for unattended work. It wakes on messages while you are away. Use an interactive lead only for an attended session: it reads the inbox when you run `inbox` or `wait`. Both modes use the same local broker and require Python 3.9 or later on a trusted Unix host.

Members use the human's normal harness configuration, including extensions, MCP servers, skills, plugins, and settings. Add flags only to run headless or grant access the fleet needs, such as an extra directory, writable root, or permission allowlist. Do not disable configured tools unless the human asks. Native subagents and other available spawning or messaging tools can be used alongside `fleet.py`; the same fleet protocol applies.

## Prepare the fleet from a normal terminal

Run setup from the directory the lead should work in, or pass its absolute path to `init --cwd`. Set aside the fleet directory and any worktree roots before starting. The broker approves member working directories under the lead's working directory or under `broker.cwd_roots`.

```sh
SKILL=/Users/me/.agents/skills/dispatch
FLEET=/Users/me/fleets/ci-refactor
PYTHON=$(python3 -c 'import sys; print(sys.executable)')
mkdir -p "$FLEET/watch" "$FLEET/worktrees"
cd /Users/me/code/lead-checkout
```

Save this worked example as `$FLEET/fleet.json` before `init`. Replace all example paths, including the Python path in the Claude Code allowlist, with actual absolute paths. Pick `pi`, `claude`, or `codex` under `defaults.harness` for an interactive lead's default worker.

```json
{
  "defaults": {"harness": "codex"},
  "adapters": {
    "pi": {
      "extra_args": [],
      "interactive_extra_args": []
    },
    "claude": {
      "extra_args": ["--permission-prompts", "none", "--add-dir", "/Users/me/.agents/skills/dispatch", "/Users/me/fleets/ci-refactor", "--allowedTools", "Read", "Bash(/usr/bin/python3 /Users/me/.agents/skills/dispatch/scripts/fleet.py *)"],
      "interactive_extra_args": ["--add-dir", "/Users/me/.agents/skills/dispatch", "/Users/me/fleets/ci-refactor"]
    },
    "codex": {
      "extra_args": ["--add-dir", "/Users/me/fleets/ci-refactor"],
      "interactive_extra_args": ["--add-dir", "/Users/me/fleets/ci-refactor"]
    }
  },
  "broker": {
    "cwd_roots": ["/Users/me/fleets/ci-refactor/worktrees"],
    "wake_checks": ["/usr/bin/python3 /Users/me/.agents/skills/dispatch/scripts/pr-sentinel.py check /Users/me/fleets/ci-refactor/watch/prs.json /Users/me/fleets/ci-refactor/watch/snapshot.json"]
  },
  "notify": {
    "command": ["/usr/bin/osascript", "-e", "on run argv\n  display notification (item 2 of argv) with title (item 1 of argv)\nend run", "{title}", "{body}"],
    "on_lead_final": true
  }
}
```

Create `RULES.md` and `LEAD.md` from the [fleet templates](fleet-files.md). Add the goal and the skill's absolute path to `lead-prompt.md`. A headless lead is also prompted to write both files from the templates if either is missing. `spawn` refuses until `RULES.md` exists. Keep the configuration, runtime, and approved check programs trusted; the broker is not a security boundary against someone who can tamper with same-user files.

## Start the lead

Use one of these commands from the normal terminal you prepared above. The harness is explicit for a headless lead. Use that harness's installed model selection if you omit `--model`.

```sh
# Pi
"$PYTHON" "$SKILL/scripts/fleet.py" --fleet "$FLEET" init --lead lead --harness pi --prompt-file "$FLEET/lead-prompt.md"
# Claude Code
"$PYTHON" "$SKILL/scripts/fleet.py" --fleet "$FLEET" init --lead lead --harness claude --prompt-file "$FLEET/lead-prompt.md"
# Codex
"$PYTHON" "$SKILL/scripts/fleet.py" --fleet "$FLEET" init --lead lead --harness codex --prompt-file "$FLEET/lead-prompt.md"
```

For an interactive lead, run `"$PYTHON" "$SKILL/scripts/fleet.py" --fleet "$FLEET" init --lead lead` instead. Open the harness in the same working directory with `FLEET` and `FLEET_MEMBER=lead` in its environment, or use `--fleet "$FLEET" --as lead` on fleet commands. With Claude Code, open it with `--add-dir "$SKILL" "$FLEET"`; with Codex workspace-write, add `--add-dir "$FLEET"` if the fleet is outside the checkout. An interactive parent's `spawn` needs `--harness` or `defaults.harness` (and can use `defaults.model`).

`init` starts one broker. On an initialized fleet, the human runs `"$PYTHON" "$SKILL/scripts/fleet.py" --fleet "$FLEET" up` from a normal terminal if the broker is down. It uses that terminal's environment plus `FLEET` and `FLEET_MEMBER` for launches. A worker gets its own harness sandbox, not its parent's. `down` stops the broker, not active turns or timers. Pause or archive members first if you want those processes stopped too.

The broker uses atomic JSON requests and responses with a 30-second wait. An exit 2 timeout does not prove nothing happened; inspect status before retrying. Look for the supervisor PID, heartbeat and queue length in `status`. Treat a dead broker as an outage for automatic headless coverage even if timers still run. `BROKER-DEAD` flags pending command requests; `DELIVERY-STALLED` flags idle headless recipients with unread inbox messages even when the command queue is empty. While the broker is down, `tell` queues messages for `up`, and `spawn` and `resume` exit 2 rather than launching headless turns directly. `pause NAME --tree` cancels all descendant wakes and stops their turns before pausing the parent, then verifies that the subtree is stopped. Plain `pause` affects only the named agent.

## Harness permissions and sessions

- **Pi (1.5.0):** `pi --list-models` lists model IDs. Use `--skill PATH` to load this skill explicitly if Pi does not discover it. Headless launches use `-p --mode json`, with a known `--session-id` and `--session` to resume; the adapter reads the last successful assistant text. Built-in Bash runs fleet commands. Its `timeout` is optional and in seconds, but a wrapper may still impose a limit.
- **Claude Code (2.1.326):** Include **both** `--add-dir` paths: the skill and the fleet directory. Headless leads were denied reads of the skill outside their cwd, and worktree members were denied reads of fleet briefs. When using `--permission-prompts none`, explicitly allow the fleet commands, permitted reads and the project's actual test commands instead of expecting a prompt. Preserve any reviewed `--settings` auth and sandbox options in `interactive_extra_args`, without print-only permission flags. The CLI uses `--model ID` or aliases such as `haiku`; `/model` lists interactive choices. Headless `-p --output-format json --session-id UUID` reads its prompt on stdin, and `--resume UUID` reuses the session. The adapter reads the JSON `result`. Bash's timeout is in milliseconds; use short wait slices rather than assuming a host limit.
- **Codex (0.170.0):** The broker smoke passed with `-s workspace-write -a never` on lead and worker. `--add-dir "$FLEET"` lets members write requests and replies when their cwd is a different worktree. No network grant or sandbox bypass was needed for a worker's `tell`. Use `codex debug models --bundled` for model IDs and `--model ID` to select one. Headless `codex exec --json --skip-git-repo-check -` captures the session ID and final text from JSON events and resumes with `codex exec resume`. Place the skill in a normal `.agents/skills` or `$CODEX_HOME/skills` discovery directory, or tell the lead its path.

**Worktree commits require a separate permission decision.** If `RULES.md` authorizes commits, a workspace-write Codex builder needs write access to the main repository's Git directory **and** its linked worktree Git directory. From the worktree, `git rev-parse --path-format=absolute --git-common-dir` and `git rev-parse --absolute-git-dir` name the two paths. Add both to the specific committing adapter's reviewed writable-root configuration. Do not grant this to all agents by default; a patch handoff does not need it. In the Nov. 19 scratch probe, `codex sandbox -c 'sandbox_mode="workspace-write"' -- git add sample` failed on `index.lock`. Granting just the common dir still failed there; granting just the linked dir denied object/ref writes. With both in `sandbox_workspace_write.writable_roots`, `git add sample` and `git update-ref` both exited 0. No additional commit was made.

## Approve in the same session

From a normal human terminal, run `"$PYTHON" "$SKILL/scripts/fleet.py" --fleet "$FLEET" attach lead`. It opens the saved session in its original cwd, queues messages while attached and leaves an already paused agent paused on exit. It refuses to interrupt a running turn unless you pass `--stop`. Attachment requires explicit `interactive_extra_args` if the session launched with customized `extra_args` (even if you later remove them), if the current config customizes `extra_args`, or if the session has no recorded launch profile. Attach uses the current config and the attaching terminal's environment. Bring the same harness config directory and auth; for example, use the same `CODEX_HOME` or `CLAUDE_CONFIG_DIR`. Confirm access to the approved target with a harmless read-only command before you rely on this path. Changing a harness sandbox does not grant project approval.

For a bare fleet, type both explicit yeses into the same interactive or attached approving lead session that executes the gated action. A child lead can accept chartered non-production approvals only in its own human session; production stays with the top lead. `tell`, `inbox`, and `wait` identify a claimed sender, not an authenticated approver. Never execute a gated action on the strength of a relay. The runtime does not authenticate who typed in the terminal. A real Codex session refused `attach lead` with exit 2 and `set adapters.codex.interactive_extra_args` when only `extra_args` was set; it remained idle with its session unchanged.

## Arm a check and test notifications

For the worked example, prepare `watch/prs.json` as a JSON list of `{"repo":"owner/name","number":123}` records and seed `watch/snapshot.json` with `pr-sentinel.py snapshot` using those paths. Run the matched check from the watcher:

```sh
"$PYTHON" "$SKILL/scripts/fleet.py" wake self --id ci --every 600 --check '/usr/bin/python3 /Users/me/.agents/skills/dispatch/scripts/pr-sentinel.py check /Users/me/fleets/ci-refactor/watch/prs.json /Users/me/fleets/ci-refactor/watch/snapshot.json'
```

`--check` always needs a live broker and an exact match in `broker.wake_checks`. A check fires once on exit 0; after handling the change, the member updates the snapshot and re-arms. Exit 0 only on a **change**, never on “still green”. The PR sentinel reports missing, empty or unrecognized check data as unknown, not green. Removing a command revokes future runs immediately; a new grant needs a broker restart from a normal terminal. If the broker is down or a check was revoked, the loop skips the check, records `last_result: policy-blocked` in its wake state, and stays armed unless its deadline expires. Host checks have a 60-second bound. An allowlist checks the command string, not what the script does; keep scripts read-only and outside agent-writable paths. Timer wakes without `--check` need no broker to queue. `unwake NAME --all` cancels every loop; `--id LOOP` cancels one. `wait` defaults to 540 seconds; use a lower `--timeout` when inside a shell tool.

`notify --title T --body B` reads the current configuration, runs directly in the caller's environment and is bounded to 30 seconds. It does not escape a caller's sandbox. `notify.on_lead_final` instead uses the broker's startup configuration and the runner environment with the same bound. Both run `notify.command` in the fleet directory without a shell. Automatic notices cap the title at 80 and body at 180 characters; the full answer remains in `agents/lead/final.md`. Test the route from the actual notifier and confirm you received it. Other than revoking check commands, change broker settings at startup or while the fleet is idle and restart the broker.

## Adapter overrides

`fleet.json` adapter entries shallowly override built-ins; an `extra_args` list replaces that harness's defaults. Pi and Codex have no default extra arguments. Claude Code defaults to `--permission-prompts none` in headless mode and has no extra arguments in interactive mode. For a new adapter supply `start`, `resume`, and optionally `interactive` as argument arrays, plus a `final` JSON event selector (`match` with dotted keys, and `path` for the text). Use a `session` selector or `known_session: true`, and optionally `failure` or `text_blocks: true`. `{extra_args}` and `{model_args}` expand into argv lists; `model_flag` defaults to `--model`. Other template fields are `{session_id}`, `{member_dir}`, `{fleet}`, `{cwd}`, `{model}`, `{python}`, `{script}`, and `{prompt}`. Set `stdin: true` if the headless harness reads the prompt on stdin. Per-turn stdout and stderr are in `agents/NAME/runs/N.log` and `N.stderr`. A launch failure is not evidence that the turn made no changes; read the logs before restarting it.
