# npm Global Install for kobixel-gemini-web Specification

## Problem Statement

The Aseprite extension's default "External command" currently ships with a
placeholder absolute path (`C:\path\to\tools\kobixel-gemini-web\edit.mjs`)
that every user must manually edit to match wherever they cloned the repo,
and the syntax differs by OS. When `kobixel-gemini-web`/`node` isn't
reachable, the user gets whatever cryptic native shell error the OS
produces, with no pointer back to the fix. This blocks the Linux/macOS
validation pass and adds unnecessary friction for every new Windows user
too.

## Goals

- [ ] The default "External command" is a single, OS-independent string
      (no absolute path, no OS-specific syntax) that works unmodified on
      Windows, macOS, and Linux once the CLI is installed.
- [ ] Installing `kobixel-gemini-web` is documented as an explicit step,
      performed via npm, and ordered before installing the Aseprite
      extension.
- [ ] If `kobixel-gemini-web` is not installed when the extension tries to
      run it, the user sees a log line that names the problem and gives the
      exact fix command, surfaced through the existing failure dialog
      (no multi-minute wait).

## Out of Scope

| Feature | Reason |
| --- | --- |
| Publishing `kobixel-gemini-web` to the npm registry | No publish/versioning pipeline exists; would require its own scoping (package name availability, release process, semver discipline independent of the extension's own versioning). Local `npm install -g .` from the cloned repo covers the ask. |
| A bundled installer/wizard UI inside the Aseprite dialog | Aseprite's Lua API has no package-manager integration; would mean shelling out to npm from `kobixel.lua` itself, which is a much bigger change than the ask. |
| Changing `edit.mjs`'s `--in/--out/--prompt/--width/--height` argument contract, or any of its Chrome-automation logic | Unaffected by this feature - only how the command is *invoked* changes. **Narrowed during implementation**: the direct-execution entry guard (see NPMCLI-08) turned out to be in scope - see the discovery note below. |
| Supporting yarn/pnpm as documented alternatives | The repo already standardizes on npm (`package-lock.json` is committed); adding more package managers multiplies docs/testing surface for no requested benefit. |

**Discovery note (during T1 implementation):** `npm install -g .` on a local
path installs by symlinking the package directory rather than copying it.
The generated bin shim then invokes `node "<symlink-path>/edit.mjs"`.
`edit.mjs`'s existing entry guard (`import.meta.url === pathToFileURL(process.argv[1]).href`)
compares a symlink-resolved URL against an unresolved path string, which
never match when the invocation crosses a symlink - the guard silently
evaluates false, `main()` never runs, and the process exits 0 with no
output at all (confirmed by instrumenting the installed copy directly).
Without a fix, P1 AC1 cannot be satisfied: the global bin would resolve but
do nothing. This is the minimum change needed to make the rest of the
feature work, not a scope expansion into `edit.mjs`'s own behavior - see
NPMCLI-08.

**Discovery note #2 (during T2 implementation):** `kobixel.lua`'s Windows
wrapper invoked the External command bare (no `call`). This works for a
plain `.exe` but is a documented cmd.exe trap for a `.bat`/`.cmd` target
(exactly what an npm-installed global bin's shim is): control transfers
into the called script and **never returns** to the wrapper, so the lines
after it - including writing `donePath` - silently never run. Every run
would poll until `MAX_WAIT_SECONDS` regardless of success or failure. Fixed
by prefixing with `call`, which is a documented no-op for a plain `.exe`.
This surfaced a second, related discovery: `call` also collapses cmd.exe's
distinct "command not found" errorlevel (`9009`) down to a generic `1`,
indistinguishable from the CLI's own failure codes - so NPMCLI-03 (below)
had to be narrowed from "detect not-found specifically" to "hint on any
failure," see the updated AC3 and its assumption row.

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --- | --- | --- | --- |
| Install source | Local path install (`npm install -g .` run inside a clone of `tools/kobixel-gemini-web`), not a published registry package | Matches the user's own instruction text (`npm install -g ...`) and the repo's existing "clone, then `npm install`" flow; avoids opening the registry-publish scope | y (matches user's literal request) |
| How the "not installed" error reaches the user | A shell-level fallback baked into the default command template itself (`kobixel-gemini-web ... \|\| echo "..."`), not a code change in `edit.mjs` | `edit.mjs` never runs if the global shim doesn't exist — the failure happens at shell-resolution time, before any JS executes, so only the invoking shell can react to it. `\|\|` is valid in both cmd.exe (via the `.bat` wrapper) and POSIX `sh` (via the `.sh` wrapper), keeping the default a single OS-agnostic string | n (not asked - lowest-risk mechanism given the constraint) |
| Direct `node "path/to/edit.mjs" ...` invocation | Kept, documented as an alternative for contributors/CI who don't want a global install | Removing it would take away a working escape hatch for people actively editing `edit.mjs` | n (not asked - conservative, avoids breaking documented behavior) |
| PATH resolution of the global npm bin dir | Rely on npm's standard behavior; document the known GUI-launcher PATH gap (already flagged in CLAUDE.md for `node` itself) using the same "use an absolute path" guidance, now pointed at the `kobixel-gemini-web` shim | Consistent with the project's existing documented workaround for the identical class of problem | n (not asked - extends an existing, already-accepted pattern) |
| Entry-guard symlink fix (NPMCLI-08) | Resolve `process.argv[1]` with `fs.realpathSync()` before comparing to `import.meta.url`, so the comparison is symlink-safe | Minimal, one-line fix; matches the exact resolution Node's ESM loader already applies to `import.meta.url`, so the two sides become comparable again. Does not touch the CLI's argument contract or automation logic | y (user approved fixing it after the discovery was surfaced) |
| Wrapper `call` fix (NPMCLI-09) | Prefix the Windows wrapper's invocation of the External command with `call` | Without it, a `.bat`/`.cmd` target (any npm global bin on Windows) never returns control to the wrapper, so `donePath` never gets written and every run silently polls to the 3-minute timeout. `call` is a documented no-op for `.exe` targets, so this is safe for every existing "External command" users may already have configured, not just the new default | y (user approved fixing it after the discovery was surfaced) |
| Failure-hint precision (revises NPMCLI-03) | Append the install hint on **any** non-zero exit from the External command, worded as a suggestion ("if X isn't installed yet, run...") rather than a diagnosis of "not found" specifically | `call` collapses cmd.exe's specific "not found" errorlevel (9009) to a generic 1, indistinguishable from the CLI's own failure codes - so Windows can no longer detect "not found" precisely. POSIX `sh` could still use exit code 127 precisely (unaffected by this `call` issue), but the two OSes were kept symmetric rather than giving Windows and Linux/macOS users different message logic for the same scenario | n (not asked - judgment call favoring symmetry and honesty over false precision; flagged here for visibility) |

**Open questions:** none - all resolved or logged above.

---

## User Stories

### P1: OS-independent default command ⭐ MVP

**User Story**: As a Kobixel user on any OS, I want the extension's default
"External command" to work without editing a path, so that installing the
CLI is the only setup step left.

**Why P1**: This is the actual ask - removes the absolute-path/OS-branching
problem the last two turns identified.

**Acceptance Criteria**:

1. WHEN a user runs `npm install -g .` from `tools/kobixel-gemini-web` THEN the system SHALL register a global executable named `kobixel-gemini-web` that invokes `edit.mjs` through Node.
2. The system SHALL ship the Aseprite extension's default "External command" as `kobixel-gemini-web --in "{input}" --out "{output}" --prompt "{prompt}" --width "{width}" --height "{height}"`, containing no absolute path and no OS-specific syntax.
3. IF the external command exits with a non-zero status THEN the system SHALL append a log line suggesting `kobixel-gemini-web` may not be installed and naming the fix (`npm install -g .` from `tools/kobixel-gemini-web`) - worded as a hint, not a diagnosis, since a non-zero exit can also mean the CLI ran and failed on its own (e.g. Chrome's debug port not open). **Revised from the original "IF not found" wording** - see the Assumptions row "Failure-hint precision".
4. WHEN the external command finishes without producing the expected output file THEN the existing Kobixel failure dialog SHALL display the log content (including the hint line from AC3) - reusing already-implemented behavior, not new UI.
5. WHEN `edit.mjs` is invoked through a path that crosses a symlink (e.g. via the global bin shim `npm install -g .` creates) THEN the system SHALL still recognize direct execution and run `main()` - the entry guard SHALL compare the real (symlink-resolved) path on both sides.
6. WHEN the External command resolves to a `.bat` or `.cmd` file (as any npm global bin does on Windows) THEN the Windows wrapper SHALL invoke it with `call` so control returns to the wrapper and `donePath` is still written, regardless of the command's own exit status.

**Independent Test**: Fresh clone, `cd tools/kobixel-gemini-web && npm install && npm install -g .`, install the `.aseprite-extension`, leave "External command" at its default, run a generation - it works without editing the field. Then uninstall the global link (`npm uninstall -g kobixel-gemini-web`) and run again - the failure dialog shows the install instruction within one poll tick, not after the 3-minute timeout.

---

### P2: Documented, ordered installation

**User Story**: As a new user reading the README, I want the CLI install
step ordered before the extension install step, so I don't hit a broken
default command on first try.

**Why P2**: Directly requested ("deixando claro que o usuário precisa
instalar o kobixel-gemini-web antes de adicionar a extensão").

**Acceptance Criteria**:

1. THE README (English and pt-BR) SHALL present the `kobixel-gemini-web` npm install step before the "Installation" section that builds/installs the `.aseprite-extension`.
2. THE README SHALL state the two commands in order: `npm install` (dependencies) then `npm install -g .` (global link).
3. WHERE a user prefers not to install globally, THE README SHALL still document the direct `node "path/to/edit.mjs" ...` form as an alternative.

**Independent Test**: A reader following the README top-to-bottom never reaches the extension's dialog before having run the npm install step.

---

## Edge Cases

- IF `npm install -g .` fails (e.g. permissions, Node too old) THEN the system SHALL surface npm's own native error - no custom handling (out of scope; Node/npm's own error is the contract here).
- WHEN a user re-runs `npm install -g .` after already having it installed THEN npm SHALL overwrite the existing global link cleanly (native npm behavior, not custom logic).
- WHEN the fallback log line fires AND the shell also printed its own native "command not found" text THEN both SHALL appear in the log, native error first - not deduplicated (acceptable per Assumptions).
- IF `edit.mjs` is invoked directly (not through the global bin) via a plain absolute path with no symlink in it THEN the entry guard SHALL still recognize direct execution exactly as before (the `realpathSync` fix must not regress the already-documented `node "path/to/edit.mjs" ...` alternative).
- IF a user's own custom "External command" (not the shipped default) already resolves to a plain `.exe` THEN adding `call` in front of it SHALL NOT change its behavior (documented cmd.exe no-op) - existing user configurations must not regress.
- WHEN the external command succeeds (exit 0) THEN the failure hint SHALL NOT be appended to the log - only a non-zero exit triggers it.

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| --- | --- | --- | --- |
| NPMCLI-01 | P1 | Implement | Implementing (T1 done, pending feature-level Verifier) |
| NPMCLI-02 | P1 | Implement | Pending |
| NPMCLI-03 | P1 | Implement | Pending |
| NPMCLI-04 | P1 | Implement | Pending |
| NPMCLI-05 | P2 | Implement | Pending |
| NPMCLI-06 | P2 | Implement | Pending |
| NPMCLI-07 | P2 | Implement | Pending |
| NPMCLI-08 | P1 | Implement | Implementing (T1 done, pending feature-level Verifier) |
| NPMCLI-09 | P1 | Implement | Pending |

**ID format:** `NPMCLI-[NUMBER]`

**Status values:** Pending → Implementing → Verified

**Coverage:** 9 total, 9 mapped to tasks (see tasks.md), 0 unmapped

---

## Success Criteria

- [ ] Default "External command" needs zero edits on a machine that has already run `npm install -g .`.
- [ ] Uninstalled state produces a clear, actionable failure message inside the existing Kobixel alert, appearing within one poll tick (not the 3-minute timeout).
- [ ] README installation order matches the real dependency order (CLI before extension).
