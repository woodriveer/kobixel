# npm-global-install Validation

**Date**: 2026-09-20
**Spec**: `.specs/features/npm-global-install/spec.md`
**Diff range**: `459cfb0..50a8c91` (244eb38, 72f3a92, e238eb2, 29e5129, 50a8c91)
**Verifier**: independent sub-agent (author ≠ verifier)

---

## Task Completion

| Task | Status  | Notes |
| ---- | ------- | ----- |
| T1: bin field + symlink-safe guard | ✅ Done | `tools/kobixel-gemini-web/package.json:7-9`, `tools/kobixel-gemini-web/edit.mjs:220` |
| T2: `call`-safe wrapper + failure hint | ✅ Done | `kobixel.lua:134,142,146-153` |
| T3: README.md reorder/update | ✅ Done | `README.md:67-108,153-184` |
| T4: README.pt-BR.md mirror | ✅ Done | `README.pt-BR.md:65-106,151-182` |
| T5: Changelog/version/rebuild | ✅ Done | `CHANGELOG.md:10-49`, `package.json:5`, `kobixel-0.2.2.aseprite-extension` |

All tasks marked done in tasks.md; none blocked or partial.

---

## Spec-Anchored Acceptance Criteria

### P1: OS-independent default command

| Criterion (WHEN X THEN Y) | Spec-defined outcome | `file:line` + assertion expression | Result |
| --- | --- | --- | --- |
| NPMCLI-01: `npm install -g .` registers a global `kobixel-gemini-web` executable that invokes `edit.mjs` through Node | `package.json` has `bin` mapping the command name to `edit.mjs` | `tools/kobixel-gemini-web/package.json:7-9` - `"bin": { "kobixel-gemini-web": "./edit.mjs" }`. Independently re-verified: copied the package to a scratch dir, ran `npm install -g .` with the real system npm (`C:\Program Files\nodejs\npm.cmd`), confirmed a Junction was created at `...\npm\node_modules\kobixel-gemini-web` pointing at the scratch copy and a `.cmd` shim invoking `node "...\edit.mjs" %*`; invoking that shim printed `Missing required --in`, exit 1 - `main()` genuinely ran through the junction. Uninstalled afterward (`npm uninstall -g kobixel-gemini-web`, confirmed removed). | ✅ PASS |
| NPMCLI-02: default "External command" is `kobixel-gemini-web --in "{input}" --out "{output}" --prompt "{prompt}" --width "{width}" --height "{height}"`, no absolute path, no OS-specific syntax | Exact string match, no `C:\...`, no shell operators | `kobixel.lua:13` - `command = 'kobixel-gemini-web --in "{input}" --out "{output}" --prompt "{prompt}" --width "{width}" --height "{height}"'`. Byte-identical to the string README.md:168 and README.pt-BR.md:166 show, and to what the rebuilt `.aseprite-extension` ships (extracted and diffed: `kobixel-0.2.2.aseprite-extension` → `kobixel.lua:13` matches). | ✅ PASS |
| NPMCLI-03 (revised): non-zero exit appends a hint naming the fix, worded as a suggestion not a diagnosis | Hint text: "...If kobixel-gemini-web is not installed yet, run: npm install -g . inside tools/kobixel-gemini-web" appended to the log on any non-zero exit, both OSes | `kobixel.lua:142` (Windows, `if errorlevel 1 echo [kobixel] The command failed. If kobixel-gemini-web is not installed yet, run: npm install -g . inside tools/kobixel-gemini-web >> "<logPath>"`) and `kobixel.lua:152` (POSIX, `if [ "$kobixel_exit" -ne 0 ]; then echo "[kobixel] The command failed. ..." >> "<logPath>"; fi`). Empirically reproduced both branches in scratch `.bat`/`.sh` wrappers byte-matching the Lua-generated text: missing-binary case → native "not recognized"/"command not found" line + hint line, done=1; real-failure case → real error + hint, done=1; success case → real output only, **no** hint, done=0 (matches the edge case "success SHALL NOT append the hint"). | ✅ PASS |
| NPMCLI-04: on missing output file, existing failure dialog shows the log (including the hint) | Reuse of existing `onFailure`/log-tail-into-`app.alert` path, no new UI | `kobixel.lua:523-533` (`onFailure` reads `logPath` via `readFile` and passes it into `app.alert{...}`) - unchanged by this diff (confirmed via `git diff` scoping: no lines in this range touch `onFailure`). Since the hint is appended to the same `logPath` the existing mechanism already reads, this is correctly a "no new code needed" reuse, consistent with the task's own "Reuses" note. Not independently re-executed end-to-end inside Aseprite (no way to drive Aseprite's UI headlessly); traced by code inspection only. | ✅ PASS (traced, not live-UI-executed - documented project constraint, see Test Coverage Matrix) |
| NPMCLI-08: symlink-crossing invocation still recognizes direct execution and runs `main()` | Guard compares the real (symlink-resolved) path on both sides | `tools/kobixel-gemini-web/edit.mjs:220` - `if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) { main(); }`. Independently re-verified end-to-end (see NPMCLI-01 evidence): running through the npm-created junction printed `Missing required --in` and exited 1, proving `main()` ran. Also re-ran the pre-existing regression case directly: `node tools/kobixel-gemini-web/edit.mjs` (no symlink involved) → `Missing required --in`, exit 1 - unchanged from before the fix. | ✅ PASS |
| NPMCLI-09: `.bat`/`.cmd` External command target gets `call` so control returns and `donePath` is still written regardless of exit status | Windows wrapper prefixes the command line with `call` | `kobixel.lua:134` - `f:write('call ' .. cmd .. ' > "' .. logPath .. '" 2>&1\r\n')`. Empirically reproduced the exact pre/post behavior with two throwaway `.bat` wrappers invoking a child `.bat` that exits 1: **without** `call`, the child's output was captured but the wrapper's next lines (`echo AFTER_CHILD_RAN`, writing the done file) never executed - no done file appeared at all, confirming the discovery note's claim; **with** `call`, both `AFTER_CHILD_RAN` and the done file (containing `1`) were produced correctly. Also confirmed the no-regression edge case: `call whoami.exe` vs bare `whoami.exe` produced identical output and exit code (0) - `call` is a genuine no-op for a plain `.exe`. | ✅ PASS |

**P1 Independent Test** (from spec): could not be run literally end-to-end through the Aseprite dialog (no headless Aseprite driver available to this Verifier), but every mechanical step it implies was independently reproduced out-of-process: global install → global bin resolves and runs `main()` (✅), uninstalled state → wrapper produces the hint within the same wrapper run, not a 3-minute timeout, because `call` lets the wrapper reach the `echo %ERRORLEVEL% > donePath` line immediately after the failed call (✅ demonstrated via the `call` mutation check above). The literal in-Aseprite click-through remains a manual step per this repo's documented convention (CLAUDE.md: no automated Lua test runner).

### P2: Documented, ordered installation

| Criterion (WHEN X THEN Y) | Spec-defined outcome | `file:line` + assertion expression | Result |
| --- | --- | --- | --- |
| NPMCLI-05: README (EN + pt-BR) present npm install step before "Installation" | Heading order: CLI install section before extension "Installation" section | `README.md` heading order (`grep -n "^## "`): `## Install the CLI first` at line 67, `## Installation` at line 109 (67 < 109). `README.pt-BR.md`: `## Instale o CLI primeiro` at line 65, `## Instalação` at line 107 (65 < 107). | ✅ PASS |
| NPMCLI-06: README states `npm install` then `npm install -g .` in order | Both commands present, in that order | `README.md:70-73` - fenced block: `cd tools/kobixel-gemini-web` / `npm install` / `npm install -g .` (in that order). `README.pt-BR.md:68-71` - identical order. | ✅ PASS |
| NPMCLI-07: direct `node "path/to/edit.mjs" ...` form still documented as an alternative | Present, framed as opt-out, not the primary/default | `README.md:171-176` - "If you'd rather not install the CLI globally... point the field at the script directly instead:" followed by `node "C:\path\to\tools\kobixel-gemini-web\edit.mjs" ...`. `README.pt-BR.md:169-174` mirrors this. Confirmed via `grep -n 'C:\\\\path\\\\to' README.md` that this is the *only* remaining occurrence of the old absolute-path form, and it sits under the opt-out framing, not under "Default". | ✅ PASS |

**P2 Independent Test**: Read both READMEs top-to-bottom in heading order; the CLI install step (line 67 / 65) is reached before "Installation" (line 109 / 107) in both files. ✅ PASS

**Status**: ✅ All 9 ACs covered, 0 gaps, 0 spec-precision gaps (P1-AC4 traced by inspection rather than live UI run - noted above as a scoped limitation, not a gap, consistent with this repo's documented lack of a Lua test runner).

---

## Discrimination Sensor

Real worktree baseline captured before any sensor work (`git status --porcelain`); confirmed identical after cleanup (see below). A temporary git worktree (`git worktree add <scratch> HEAD`, later `git worktree remove --force`) was used for the `edit.mjs` mutation; independent scratch `.bat`/`.sh` files (never inside the repo) were used for the `kobixel.lua` wrapper-generation logic, since that code only ever produces *generated* wrapper scripts, not something importable/runnable in isolation from the repo tree itself.

| # | File:line (real code) | Mutation | Test run | Result |
| - | --- | --- | --- | --- |
| 1 | `tools/kobixel-gemini-web/edit.mjs:220` | Reverted the fix: `pathToFileURL(realpathSync(process.argv[1]))` → `pathToFileURL(process.argv[1])` (the pre-fix guard) | `node --test edit.test.mjs` in the scratch worktree | ❌ **Survived** - 4/4 still pass. Expected and already flagged: `edit.test.mjs` covers only `buildPixelArtInstructions`, never the entry guard (Test Coverage Matrix explicitly says "no new unit test added"). This is a genuine, pre-existing, by-design gap in automated coverage - not something this feature was supposed to close. |
| 1b | (same mutation, manual check) | Same reverted guard | Copied the mutated file into a scratch dir with `package.json`+`node_modules`, ran real `npm install -g .`, invoked the resulting global shim | ✅ **Killed** by the project's documented manual-verification method: the shim ran and exited 0 with **zero output** - exactly reproducing the bug the discovery note describes. Confirms the fix is load-bearing and the manual verification path in tasks.md's Done-when is the only thing standing between this regression and shipping. Cleaned up (`npm uninstall -g kobixel-gemini-web`, confirmed shim removed). |
| 2 | `kobixel.lua:134` | Reverted the fix: dropped the `call ` prefix (pre-fix bare invocation) | Reproduced with two scratch `.bat` files outside the repo: a wrapper invoking a child `.bat` (exit 1) bare vs. with `call`, followed by an `echo AFTER` line and writing a done file | ✅ **Killed** (manual/empirical, no automated Lua runner exists per CLAUDE.md): bare invocation → child's output captured, but `AFTER_CHILD_RAN` never printed and the done file never created (control never returned) - exactly the "polls to `MAX_WAIT_SECONDS`" bug the discovery note describes. With `call` restored → both the follow-up line and the done file (value `1`) appeared correctly. |
| 3 | `kobixel.lua:142` | Removed the `if errorlevel 1 echo ...` hint line entirely | Reproduced with a scratch `.bat` matching the real wrapper's generated text, command exiting 1 | ✅ **Killed** (manual/empirical): without the hint line, the log contained only the native failure text with no `[kobixel] The command failed...` suggestion appended; with the line present (real code), the hint appears after the native error, matching the edge case "native error first, hint appended, not deduplicated". |

**Sensor depth**: lightweight (3 targeted mutations + 1 supplementary manual check on the highest-risk new code: the guard fix and the two wrapper-generation fixes)
**Result**: 3/4 killed via the project's actual verification method (manual, since no automated gate exists for `kobixel.lua` or the guard); **1 survives the automated `node --test` suite** - an honest, pre-existing, by-design coverage gap already called out in tasks.md's Test Coverage Matrix, not a regression introduced by this feature.

**Isolation check**: `git status --porcelain` before sensor work and after `git worktree remove --force` + scratch-dir cleanup are identical (only the four pre-existing untracked dirs `.agents/`, `.claude/`, `.cursor/`, `.windsurf/` - unrelated to this feature and present before this session started). Real tree was never mutated.

---

## Code Quality

| Principle | Status |
| --- | --- |
| No features beyond what was asked | ✅ - diff is exactly the bin field, the guard fix, the wrapper fix, docs reorder, and release bookkeeping; nothing extra |
| No abstractions for single-use code | ✅ - hint text is inlined at both wrapper call sites, no premature helper extracted |
| No unnecessary "flexibility" added | ✅ |
| Only touched files required for task | ✅ - `git diff --stat` shows exactly: spec/tasks docs, CHANGELOG, both READMEs, `kobixel.lua`, root `package.json`, `edit.mjs`, `tools/.../package.json`, and the rebuilt `.aseprite-extension` binary (old one removed, new one added) |
| Didn't "improve" unrelated code | ✅ - `onFailure`/polling logic, `buildPixelArtInstructions`, Chrome-automation logic all untouched, as the Out-of-Scope table requires |
| Matches existing patterns/style | ✅ - new `f:write(...)` lines follow the exact style of surrounding lines (comment-then-write, `\r\n` on Windows, `\n` on POSIX) |
| Would senior engineer approve? | ✅ - the two mid-implementation discoveries (symlink guard, `call`) are exactly the kind of thing a careful reviewer would have caught anyway; both are minimal, well-commented fixes with a clear causal chain back to a concrete failure mode |
| Tests map to acceptance criteria and are non-shallow | ⚠️ N/A by design - no unit tests were added or expected (Test Coverage Matrix says "none" for every touched layer); spot-checked `edit.test.mjs`'s 4 existing tests remain about `buildPixelArtInstructions`, untouched and unaffected |
| Spec-anchored outcome check | ✅ - see AC table above; every precise outcome in the spec (exact command string, exact hint wording, exact guard expression) was checked against the literal file content |
| Per-layer Coverage Expectation met | ✅ - matches the Test Coverage Matrix's own declared expectation of "none / manual" for every layer this feature touches; this Verifier additionally went beyond "manual eyeballing" by running real npm installs and real `.bat`/`.sh` executions to empirically confirm the manual claims in tasks.md rather than trusting them at face value |
| Every test in scope maps to a spec AC or Done-when criterion | ✅ - `node --test edit.test.mjs` (unaffected regression check) is the only automated command in scope; the manual empirical checks performed here map 1:1 to tasks.md's own "Manually confirmed" Done-when bullets for T1 and T2 |
| Documented project quality/testing guidelines followed | ✅ - `CLAUDE.md` ("no automated Lua test runner...verify manually") and the Test Coverage Matrix in tasks.md, both followed; cited the test file directly (`edit.test.mjs`), not the directory, per CLAUDE.md's own documented Windows/Node 22 gotcha |

---

## Edge Cases

- [x] `npm install -g .` failure (permissions, old Node) - out of scope by spec design, no custom handling exists or is claimed; verified no custom error-wrapping code was added around npm invocation itself (there is none - npm is never invoked by the extension's own code, only documented as a manual step)
- [x] Re-running `npm install -g .` overwrites cleanly - native npm behavior, not custom logic; not separately re-tested (would be testing npm itself, out of this feature's surface)
- [x] Native "command not found" text and the fallback hint both appear, native first, not deduplicated - confirmed in sensor mutation #3's baseline run (case1_missing.bat log): native "não é reconhecido..." line followed by the `[kobixel]` hint line, in that order
- [x] `edit.mjs` invoked directly (no symlink) still recognizes direct execution post-fix - confirmed (`node tools/kobixel-gemini-web/edit.mjs` → `Missing required --in`, exit 1)
- [x] Existing `.exe`-based custom "External command" unaffected by added `call` - confirmed empirically (`call whoami.exe` vs bare `whoami.exe`: identical output, both exit 0)
- [x] Success path (exit 0) does not append the hint - confirmed empirically in the `case3_success`/`posix_success` mutation-baseline runs: log contains only the real command's own output, no `[kobixel]` line

---

## Gate Check

- **Gate command**: Manual verification per task's `Done when` (no automated build/test gate applies to this feature's layers, per the Test Coverage Matrix) + `node --test tools/kobixel-gemini-web/edit.test.mjs` as the one unaffected regression check
- **Result**: `node --test tools/kobixel-gemini-web/edit.test.mjs` → 4 passed, 0 failed, 0 skipped (re-run independently by this Verifier, matches T1's Done-when claim of "4/4, no change in count")
- **Test count before feature**: 4 (untouched by this feature - `edit.test.mjs` was not modified in this diff)
- **Test count after feature**: 4
- **Delta**: 0 (expected - this feature adds no automated tests, by design, per the Test Coverage Matrix)
- **Skipped tests**: none
- **Failures**: none
- **Additional gates independently re-run by this Verifier** (all manual, as documented): `npm install -g .` from a scratch copy exits 0 and produces a working global shim; the shim runs `main()` through the created Junction; `kobixel.lua`'s `DEFAULTS.command` matches the README and the rebuilt extension binary; CHANGELOG heading `## [0.2.2]` has no collision with `0.2.1/0.2.0/0.1.1/0.1.0`; root `package.json` version (`0.2.2`) matches; `package.json` has no BOM (first bytes `7b 0a`)

---

## Fix Plans (if issues found)

No fix tasks required — 0 gaps found against the spec's acceptance criteria. One pre-existing, by-design coverage limitation is worth recording (not a fix task, since the matrix already declares it and closing it would be new scope):

### Note 1: `edit.mjs`'s entry guard has no automated regression test

- **Observation**: Reverting the `realpathSync` fix leaves `node --test edit.test.mjs` green (4/4) - the automated suite cannot detect a regression in the entry guard. Only the documented manual procedure (`npm install -g .` + run the shim) catches it, as this Verifier confirmed directly.
- **Priority**: Informational / not a blocker - `tasks.md`'s own Test Coverage Matrix already declares "no new unit test added (guard has no dedicated test in this repo)" for this exact line, so this is a known, accepted, pre-existing gap, not something introduced or hidden by this feature.
- **Optional future task** (not required for this feature to pass): a small unit test could stub `process.argv[1]` to a symlinked temp file and assert the guard's boolean expression evaluates `true` post-fix / `false` pre-fix, without needing a real global npm install. Left as a suggestion, not a gap, since the spec's Out-of-Scope table treats `edit.mjs`'s own logic changes narrowly and the matrix explicitly accepts manual verification here.

---

## Requirement Traceability Update

| Requirement | Previous Status | New Status |
| --- | --- | --- |
| NPMCLI-01 | Implementing | ✅ Verified |
| NPMCLI-02 | Pending | ✅ Verified |
| NPMCLI-03 | Pending | ✅ Verified |
| NPMCLI-04 | Pending | ✅ Verified |
| NPMCLI-05 | Pending | ✅ Verified |
| NPMCLI-06 | Pending | ✅ Verified |
| NPMCLI-07 | Pending | ✅ Verified |
| NPMCLI-08 | Implementing | ✅ Verified |
| NPMCLI-09 | Pending | ✅ Verified |

---

## Summary

**Overall**: ✅ Ready

**Spec-anchored check**: 9/9 ACs matched spec outcome, 0 spec-precision gaps (one AC - NPMCLI-04 - traced by code inspection rather than a live Aseprite UI run, which is a documented, pre-existing constraint of this repo, not a gap)

**Sensor**: 3/4 mutations killed by the project's actual (manual) verification method; 1 survives the automated `node --test` suite by design (no test targets the entry guard) - this is an honest, already-flagged limitation, not a regression

**Gate**: `node --test tools/kobixel-gemini-web/edit.test.mjs` - 4 passed, 0 failed (unchanged count); all manual gates re-run independently and passed

**What works**:
- The `bin` field + `realpathSync` fix genuinely make `npm install -g .` produce a working global command - independently reproduced end-to-end (install → run through the created Junction → `main()` executes)
- The `call` fix genuinely prevents the "silent 3-minute timeout" bug for `.bat`/`.cmd` targets - independently reproduced the before/after behavior with scratch wrapper scripts
- The failure hint fires only on non-zero exit, on both Windows and POSIX branches, worded as a suggestion, appended after any native error text - all independently reproduced
- `DEFAULTS.command`, both READMEs, and the rebuilt `.aseprite-extension` are all mutually consistent
- CHANGELOG/version/BOM bookkeeping is correct and collision-free

**Issues found**: None blocking. One informational note: the entry-guard fix (NPMCLI-08) has no automated regression test and relies entirely on manual verification - already declared as accepted in tasks.md's Test Coverage Matrix, so not treated as a gap.

**Next steps**: None required. Feature is verified PASS; no fix→re-verify iteration needed.
