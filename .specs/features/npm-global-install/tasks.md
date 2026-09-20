# npm Global Install for kobixel-gemini-web Tasks

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill: activate it by name
and follow its Execute flow and Critical Rules.

---

**Spec**: `.specs/features/npm-global-install/spec.md`
**Status**: Approved

---

## Test Coverage Matrix

> Generated from codebase - confirm before Execute. Guidelines found: `CLAUDE.md`
> ("There is no automated test suite for the Lua side... To verify a Lua
> change: run `.\release.ps1`, install... and exercise manually"). The
> repo's one automated test file, `tools/kobixel-gemini-web/edit.test.mjs`,
> covers `buildPixelArtInstructions` only - untouched by this feature.

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| --- | --- | --- | --- | --- |
| `tools/kobixel-gemini-web/package.json` (bin field) | none | config-only, build gate only | n/a | manual: `npm install -g .` then confirm `kobixel-gemini-web` resolves on PATH |
| `tools/kobixel-gemini-web/edit.mjs` (entry guard only - `buildPixelArtInstructions` untouched) | existing unit suite must still pass; no new unit test added (guard has no dedicated test in this repo) | regression: existing suite green + manual guard verification (see T1) | `tools/kobixel-gemini-web/edit.test.mjs` | `node --test tools/kobixel-gemini-web/edit.test.mjs` (cite the file directly - a directory argument fails on Windows/Node 22, per CLAUDE.md and lesson L-003) |
| `kobixel.lua` (`DEFAULTS.command`) | none | no Lua test runner exists in this repo (documented project convention) | n/a | manual: install `.aseprite-extension`, run a generation with the bin installed (success path) and with it removed (failure path) |
| `README.md` / `README.pt-BR.md` | none | docs-only | n/a | manual proofread |
| `CHANGELOG.md` / `package.json` (root) / `.aseprite-extension` | none | release bookkeeping | n/a | `.\release.ps1` (or manual zip per README) succeeds, produces the expected filename |

No task in this feature touches `edit.mjs`'s tested logic (`buildPixelArtInstructions`), so `node --test tools/kobixel-gemini-web/edit.test.mjs` is unaffected and not part of this feature's gate - it is unrelated to the change surface.

## Gate Check Commands

| Gate Level | When to Use | Command |
| --- | --- | --- |
| Build | Every task in this feature (no automated test layer applies) | Manual verification per task's `Done when`, as listed in the matrix above |

---

## Execution Plan

### Phase 1: CLI packaging

```
T1 → T2
```

### Phase 2: Docs

```
T3 → T4
```

### Phase 3: Release

```
T5
```

---

## Task Breakdown

### T1: Expose `kobixel-gemini-web` as an npm global bin, symlink-safe

**What**: Add a `bin` field to `tools/kobixel-gemini-web/package.json` so `npm install -g .` registers a global `kobixel-gemini-web` command that runs `edit.mjs`; fix `edit.mjs`'s direct-execution entry guard so it still fires when invoked through the symlink `npm install -g .` creates for a local path.
**Where**: `tools/kobixel-gemini-web/package.json`, `tools/kobixel-gemini-web/edit.mjs`
**Depends on**: None
**Reuses**: `edit.mjs`'s existing `#!/usr/bin/env node` shebang (edit.mjs:1) - no change needed there.
**Requirement**: NPMCLI-01, NPMCLI-08

**Discovery (logged in spec.md):** `npm install -g .` on a local path
symlinks the package rather than copying it. The generated shim invokes
`node "<symlink-path>/edit.mjs"`, and the existing guard
(`import.meta.url === pathToFileURL(process.argv[1]).href`) compares a
symlink-resolved URL against an unresolved path - never equal across a
symlink, so `main()` silently never runs (confirmed by instrumenting the
installed copy: guard evaluated `false`, process exited 0 with zero
output). Fix: resolve `process.argv[1]` with `fs.realpathSync()` before
the comparison, matching the resolution Node's ESM loader already applies
to `import.meta.url`.

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [x] `package.json` has `"bin": { "kobixel-gemini-web": "./edit.mjs" }`
- [x] `edit.mjs`'s closing guard imports `realpathSync` from `node:fs` and compares `import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href`
- [x] `npm install -g .` run from `tools/kobixel-gemini-web` exits 0 (verified with the real system npm at `C:\Program Files\nodejs\npm.cmd` - a `~/bin/npm` shim from an unrelated app shadows it on this machine's PATH; unrelated to this feature, not touched)
- [x] Manually confirmed: running the installed global shim (`kobixel-gemini-web` with no args, both the raw symlinked path and the real `.cmd` shim via `cmd /c`) prints `Missing required --in` and exits 1 - i.e. `main()` actually runs through the symlinked install path
- [x] Regression check: invoking `edit.mjs` directly by a plain path with no symlink (`node tools/kobixel-gemini-web/edit.mjs`) still triggers `main()` exactly as before (`Missing required --in`, exit 1)
- [x] `node --test tools/kobixel-gemini-web/edit.test.mjs` still passes: 4/4 (no change in count)

**Tests**: none (no unit test covers the entry guard itself - `edit.test.mjs` only covers `buildPixelArtInstructions`; this is a manual/gate-level verification per the Test Coverage Matrix)
**Gate**: build

**Commit**: `fix(cli): expose kobixel-gemini-web as a symlink-safe npm global bin`

---

### T2: Default the External command to the global bin, with a `call`-safe failure hint

**What**: Change `DEFAULTS.command` in `kobixel.lua` to the plain OS-independent `kobixel-gemini-web ...` invocation (no shell logic embedded in it), and make the wrapper generator in `runCommandAsync` (a) invoke the Windows command with `call` so control returns when it's a `.bat`/`.cmd`, and (b) append a failure hint to the log on any non-zero exit.
**Where**: `kobixel.lua`
**Depends on**: T1
**Reuses**: existing `donePath`/`onFailure` polling mechanism (kobixel.lua:543-553) - no changes needed there, the hint text just rides the existing log-tail-into-alert path.
**Requirement**: NPMCLI-02, NPMCLI-03, NPMCLI-04, NPMCLI-09

**Discovery (logged in spec.md, two parts):**
1. A `|| echo` embedded directly in `DEFAULTS.command` was the original plan, but testing showed the wrapper's own trailing `> "logPath" 2>&1` (appended after `cmd` by `runCommandAsync`) binds only to the right-hand side of an unparenthesized `||` in cmd.exe - on the *success* path this silently dropped ALL log capture (no log file at all), which would have broken the existing progress dialog for every run, not just the failure case. Moved the hint logic into `runCommandAsync` itself instead, after the wrapper's own redirection is already in place.
2. While testing that, found `kobixel.lua`'s Windows wrapper invoked the External command bare (no `call`) - harmless for a `.exe`, but for a `.bat`/`.cmd` (exactly what npm's global bin shim is) this transfers control permanently and the wrapper's remaining lines (writing `donePath`) never run - every run would silently poll to the 3-minute timeout. Fixed with `call`. This in turn collapses cmd.exe's specific "not found" errorlevel (9009) to a generic 1, so the hint fires on any failure rather than specifically "not installed" (see spec.md's "Failure-hint precision" assumption) - kept symmetric with the POSIX `sh` branch rather than giving Windows and Linux/macOS different precision.

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [ ] `DEFAULTS.command` = `kobixel-gemini-web --in "{input}" --out "{output}" --prompt "{prompt}" --width "{width}" --height "{height}"` (no embedded shell logic)
- [ ] Windows branch of `runCommandAsync` prefixes the command with `call` before its own redirection
- [ ] Windows branch appends `if errorlevel 1 echo [kobixel] The command failed. If kobixel-gemini-web is not installed yet, run: npm install -g . inside tools/kobixel-gemini-web >> "<logPath>"` after the command line
- [ ] POSIX branch captures the exit code and appends the equivalent hint when it's non-zero
- [ ] Manually confirmed (simulated wrapper, three cases): missing binary → native error + hint, `done`=1; real binary failing for an unrelated reason (Chrome debug port closed) → real error + hint (accepted imprecision), `done`=1; success stand-in → real output only, no hint, `done`=0
- [ ] Manually confirmed: a plain `.exe`-based command prefixed with `call` behaves identically to before (no regression for existing user configurations)
- [x] Wrapper simulations reproduce byte-for-byte what `kobixel.lua`'s `f:write(...)` calls generate for this command - real end-to-end verification through the Aseprite dialog itself is deferred to the user's manual pass (per `CLAUDE.md`: no automated Lua test runner exists in this repo; manual exercise in Aseprite is the documented verification method), to be done together with the upcoming Ubuntu/Linux validation session

**Tests**: none
**Gate**: build

**Commit**: `fix(kobixel): call External command safely and hint on failure`

---

### T3: Reorder and update README.md

**What**: Move the `kobixel-gemini-web` npm install step ahead of the extension "Installation" section; update the shown command to the new bin-based default; keep the direct `node "path/to/edit.mjs" ...` form documented as an alternative.
**Where**: `README.md`
**Depends on**: T1, T2
**Reuses**: existing "Requirements" section (added in the prior commit) as the anchor point for the reordering.
**Requirement**: NPMCLI-05, NPMCLI-06, NPMCLI-07

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [x] The `tools/kobixel-gemini-web` npm setup (`npm install` then `npm install -g .`) appears before the "Installation" section that builds/installs the `.aseprite-extension` (new "Install the CLI first" section)
- [x] The command shown in "The CLI" matches T2's new default exactly (`kobixel-gemini-web --in ...`, no path)
- [x] The direct `node "path/to/edit.mjs" ...` form remains documented as an alternative for contributors who don't want a global install
- [x] No leftover reference to the old `node "C:\path\to\..."` default as *the* recommended command (it's now explicitly the opt-out alternative)

**Tests**: none
**Gate**: build

**Commit**: `docs: document npm global install for kobixel-gemini-web`

---

### T4: Mirror README.pt-BR.md

**What**: Apply the same reordering and command update to the Portuguese README.
**Where**: `README.pt-BR.md`
**Depends on**: T3
**Reuses**: T3's English wording as the source of truth for structure/content parity.
**Requirement**: NPMCLI-05, NPMCLI-06, NPMCLI-07 (pt-BR mirror)

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [ ] Same structural changes as T3, in Portuguese
- [ ] Both READMEs present the same install order and the same example command (language aside)

**Tests**: none
**Gate**: build

**Commit**: `docs: mirror npm global install instructions in pt-BR`

---

### T5: Changelog, version bump, and rebuild

**What**: Add a CHANGELOG entry for this feature, bump `package.json`'s version, and rebuild the `.aseprite-extension`.
**Where**: `CHANGELOG.md`, `package.json` (root), `kobixel-X.Y.Z.aseprite-extension`
**Depends on**: T2, T3, T4
**Reuses**: `release.ps1` (already handles the bump + rebuild + old-artifact cleanup).
**Requirement**: N/A (release bookkeeping, not a spec AC)

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [ ] CHANGELOG `[Unreleased]` gets an entry describing the npm-bin default and doc reorder, then is moved into a new version heading as part of this bump (per `CLAUDE.md`)
- [ ] New version number does not collide with any existing CHANGELOG heading (learned from the 0.1.1 collision earlier this session - check the full heading list, not just the latest one, before picking the number)
- [ ] `.\release.ps1` run (or the manual `Compress-Archive` steps in the README) produces the new `.aseprite-extension`, and the old one is removed
- [ ] Root `package.json` `version` matches the new CHANGELOG heading and the artifact filename

**Tests**: none
**Gate**: build

**Commit**: `chore(release): bump to <version>`

---

## Phase Execution Map

```
Phase 1 → Phase 2 → Phase 3

Phase 1:  T1 ------→ T2
Phase 2:  T3 ------→ T4
Phase 3:  T5
```

---

## Task Granularity Check

| Task | Scope | Status |
| --- | --- | --- |
| T1: Expose bin field + symlink-safe guard fix | 2 files, one cohesive deliverable (bin field is inert without the guard fix - discovered mid-implementation, see spec.md discovery note) | ✅ Granular (cohesive, not splittable - the fix exists only to make the bin field's `Done when` achievable) |
| T2: Update default command | 1 file (one field) | ✅ Granular |
| T3: Update README.md | 1 file | ✅ Granular |
| T4: Mirror README.pt-BR.md | 1 file | ✅ Granular |
| T5: Changelog + bump + rebuild | 3 files, one cohesive release action | ✅ Granular (release bookkeeping is conventionally one unit, matches prior commit in this repo's history) |

---

## Diagram-Definition Cross-Check

| Task | Depends On (task body) | Diagram Shows | Status |
| --- | --- | --- | --- |
| T1 | None | None | ✅ Match |
| T2 | T1 | T1 → T2 | ✅ Match |
| T3 | T1, T2 | (Phase 2 follows Phase 1; T3 → T4 within phase) | ✅ Match (cross-phase deps point backward only) |
| T4 | T3 | T3 → T4 | ✅ Match |
| T5 | T2, T3, T4 | Phase 3 follows Phase 2 | ✅ Match (cross-phase deps point backward only) |

---

## Test Co-location Validation

| Task | Code Layer Created/Modified | Matrix Requires | Task Says | Status |
| --- | --- | --- | --- | --- |
| T1 | `package.json` (config) + `edit.mjs` (entry guard only) | none (existing `edit.test.mjs` suite must stay green - regression, not new coverage) | none | ✅ OK |
| T2 | `kobixel.lua` (no test runner exists for this layer, per `CLAUDE.md`) | none | none | ✅ OK |
| T3 | docs | none | none | ✅ OK |
| T4 | docs | none | none | ✅ OK |
| T5 | release bookkeeping | none | none | ✅ OK |

**Note**: this feature adds zero coverage to `edit.mjs`'s tested function (`buildPixelArtInstructions`); `edit.test.mjs`'s existing suite is unaffected and out of scope.
