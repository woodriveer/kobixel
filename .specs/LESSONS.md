# Lessons

Hand-maintained fallback (no Python interpreter available in this environment to run `scripts/lessons.py`). Entries follow the same rules the script would enforce: grounded in a real `validation.md` signal, one terse general sentence per lesson, `candidate` until corroborated across 2 distinct features, `source` mandatory. Accounting here is best-effort until a code-execution tool is available to migrate this into `.specs/lessons.json`.

---

## Candidate

### L-001

- **Status**: candidate (1/2 features)
- **Signal**: `surviving_mutant`
- **Feature**: prompt-context-audit-i18n
- **Source**: `tools/gemini-web-edit/edit.mjs:57` (mutation `&&` → `||`), `tools/gemini-web-edit/edit.test.mjs:7-16`
- **Lesson**: When a function branches on "both of N optional inputs present," write a test for the case where exactly one is present, not just the all-present and all-absent extremes.

### L-002

- **Status**: candidate (1/2 features)
- **Signal**: `spec_precision_gap`
- **Feature**: prompt-context-audit-i18n
- **Source**: spec.md AC3 of "P1: edit.mjs prompt reflects actual image dimensions" ("without `--width` OR without `--height`") vs. its own narrower "Independent Test" clause (only both-present / both-absent)
- **Lesson**: When an AC uses "without X or without Y" phrasing, write the AC's own Independent Test to cover the mixed case explicitly, not just the two all-or-nothing extremes, so implementation tests inherit full coverage.

### L-003

- **Status**: candidate (1/2 features)
- **Signal**: `gate_fail`
- **Feature**: prompt-context-audit-i18n
- **Source**: `tasks.md` Gate Check Commands table, `CLAUDE.md:25,55` — `node --test tools/gemini-web-edit`
- **Lesson**: Before documenting a `node --test <directory>` gate command, verify it actually runs on Windows Node — directory-style test-runner arguments can fail there even on trivial, unrelated directories; cite the test file path or an explicit glob instead.

### L-004

- **Status**: candidate (1/2 features)
- **Signal**: `surviving_mutant`
- **Feature**: npm-global-install
- **Source**: `tools/kobixel-gemini-web/edit.mjs:220` (mutation: reverted `realpathSync` fix in the direct-execution guard), `tools/kobixel-gemini-web/edit.test.mjs` (4/4 still pass against the mutant)
- **Lesson**: A module's direct-execution guard (an `import.meta.url`/`process.argv[1]` entry-point check) is invisible to unit tests that only import the module's exported functions — declare it explicitly as an uncovered layer in the Test Coverage Matrix rather than assuming the module's existing suite exercises it, and prefer a stubbed-argv unit test over relying solely on manual verification when the guard's logic is non-trivial (e.g. symlink resolution).

---

*(Self-check: `validation.md` for prompt-context-audit-i18n had signal — one surviving mutant, one spec-precision gap, and one gate-command failure — so lessons were recorded rather than silently skipped. `validation.md` for npm-global-install had one surviving mutant (entry-guard fix, `node --test` blind to it) — recorded as L-004 rather than silently skipped.)*
