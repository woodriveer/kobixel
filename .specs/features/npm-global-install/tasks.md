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

### T2: Default the External command to the global bin, with an install-hint fallback

**What**: Change `DEFAULTS.command` in `kobixel.lua` to the OS-independent `kobixel-gemini-web ...` invocation, with a `|| echo` fallback that names the fix when the bin isn't installed.
**Where**: `kobixel.lua`
**Depends on**: T1
**Reuses**: existing `donePath`/`onFailure` polling mechanism (kobixel.lua:543-553) - no changes needed there, the fallback text just rides the existing log-tail-into-alert path.
**Requirement**: NPMCLI-02, NPMCLI-03, NPMCLI-04

**Tools**:
- MCP: NONE
- Skill: NONE

**Done when**:
- [ ] `DEFAULTS.command` = `kobixel-gemini-web --in "{input}" --out "{output}" --prompt "{prompt}" --width "{width}" --height "{height}" || echo "[kobixel-gemini-web] Falha ao executar. Instale antes com: cd tools/kobixel-gemini-web && npm install -g ."`
- [ ] Manually confirmed: with the bin installed, a real generation via the Aseprite dialog still works end to end using the untouched default field
- [ ] Manually confirmed: with the bin uninstalled (`npm uninstall -g kobixel-gemini-web`), running a generation shows the install-hint text inside the Kobixel failure alert within one poll tick (`POLL_INTERVAL`), not after the 3-minute timeout
- [ ] `.bat` wrapper (Windows) and `.sh` wrapper (Linux/macOS, per `isWindows()` branch at kobixel.lua:113-133) both accept `||` syntax unmodified - no OS branching added to `DEFAULTS.command` itself

**Tests**: none
**Gate**: build

**Commit**: `feat(kobixel): default external command to global bin with install-hint fallback`

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
- [ ] The `tools/kobixel-gemini-web` npm setup (`npm install` then `npm install -g .`) appears before the "Installation" section that builds/installs the `.aseprite-extension`
- [ ] The "Working example" command shown matches T2's new default exactly
- [ ] The direct `node "path/to/edit.mjs" ...` form remains documented as an alternative for contributors who don't want a global install
- [ ] No leftover reference to the old `node "C:\path\to\..."` default as *the* recommended command

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
