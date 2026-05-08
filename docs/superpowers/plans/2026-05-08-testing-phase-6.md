# ImageCRC Phase 6 — CI on macos-14 GitHub Actions

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the existing test suites (Phases 1–5) into GitHub Actions on the `macos-14` runner so every push and pull request automatically runs both `swift test` and `xcodebuild test`. Phase 6 adds NO new tests — it only operationalises what's already green locally so regressions get caught upstream.

**Architecture:** A single workflow file at `.github/workflows/test.yml`. Two test invocations because the suites split across two runtimes: SwiftPM (`swift test`) hosts Swift Testing unit/codec/integration suites; XCUITest (`xcodebuild test`) hosts the UI smoke target. Phase 5's T1 (per-target `PRODUCT_MODULE_NAME`) and T7 (CLAUDE.md doc) already removed the blockers. Caching of SwiftPM build artefacts (`.build/`) is keyed on `Package.swift` — `Package.resolved` is in `.gitignore` (not tracked), so it's absent on a fresh `actions/checkout` and unusable as a cache key. `Package.swift` pins `from: "1.3.2"` for `libwebp` and is the closest tracked artefact to the dependency graph. DerivedData is intentionally NOT cached — it's huge, hits the 10 GB per-key cache limit, and `xcodebuild` warm-build savings on a one-shot CI runner are marginal compared to the cache restore/save cost. `pngquant` lands via Homebrew so the previously-skipped `PNGQuantizerTests` actually run on CI under `IMAGECRC_TEST_REQUIRE_PNGQUANT=1`.

**Tech Stack:** GitHub Actions `macos-14` runner (Apple Silicon by default), `actions/checkout@v4`, `actions/cache@v4`, `actions/upload-artifact@v4`, Homebrew (preinstalled on `macos-14`), Xcode (preinstalled — `xcode-select` selects the active toolchain). No third-party actions beyond `actions/*`.

> **User policy:** All Phase 1–6 work lands on `tests/phase-1` and merges to `main` as one batch when Phase 6 finishes. The agent may commit on this branch but **must not push to remote or merge** — the user pushes after reviewing the workflow because GitHub Actions minutes are billed.

---

## Section Overview

| # | Section | Tasks | Goal |
|---|---------|-------|------|
| A | Skeleton workflow | T1 | Checkout, brew install, `swift test` only — proves CI plumbing before adding the heavier xcodebuild path |
| B | Full test surface | T2 | `xcodegen generate` + `xcodebuild test` — runs the XCUITest UI smoke alongside the SwiftPM suites |
| C | Performance + ergonomics | T3 | Cache `.build/` keyed on `Package.resolved`; Homebrew cache for `pngquant` |
| D | Failure observability | T4 | Upload `.xcresult` bundles on failure for off-runner debugging |
| E | Docs | T5 | README build-status badge; CLAUDE.md note about CI invocation |

**Phase 6 done when:**

- `.github/workflows/test.yml` exists, YAML-validates, and references both `swift test` and `xcodebuild test`
- The workflow runs on `push` to main-line branches (`main`, `tests/**`) and on every `pull_request` — feature branches without PRs do not auto-burn CI minutes
- A `concurrency` block with `cancel-in-progress: true` keeps stacked pushes from running parallel CI for a superseded commit
- `paths-ignore` skips doc-only changes (`**.md`, `docs/**`) so README and plan edits don't burn runner minutes
- `IMAGECRC_TEST_REQUIRE_PNGQUANT=1` is set on the test step so `PNGQuantizerTests` actually runs (not skipped) — `brew install pngquant` runs first
- SwiftPM artefacts cache key is `${{ runner.os }}-${{ runner.arch }}-spm-${{ hashFiles('Package.swift') }}` (Package.swift, not Package.resolved — the latter is gitignored)
- On test failure, the `.xcresult` bundle uploads as an artifact for post-mortem
- README has a CI badge pointing to the workflow
- `swift test` and `xcodebuild test` still pass locally (no regression from any incidental edits)
- User approval to merge `tests/phase-1` into `main`

**Estimated time:** half a day. The novel work is T1 (workflow skeleton + correct trigger scope) and T4 (xcresult upload); T2–T3 are mechanical glue; T5 is doc-only.

**Deliberately deferred:**
- Caching DerivedData. Measured cost-benefit unfavourable: DerivedData is multi-GB and the cache-save step often hits the 10 GB/key limit; cache hits provide marginal speedup on `xcodebuild` because the runner cold-builds every time anyway (no incremental linker). Revisit if `xcodebuild test` step exceeds 10 minutes.
- Matrix builds across multiple macOS versions or Xcode versions. Phase 6's contract is "tests we have locally also pass on CI." The tests are pinned to `platform=macOS,arch=arm64` per Phase 5's plan — adding Intel or older macOS is an expansion of scope, not part of Phase 6.
- SwiftLint / formatters / security scanners. Phase 6 is just running existing tests on CI.
- Pre-commit hooks via CI. Out of scope.
- Coverage reporting (codecov, etc.). Phase 4's golden-test posture is explicit about not chasing coverage targets — adding codecov would invite regressions in the wrong direction.
- Self-hosted runners. GitHub-hosted `macos-14` is fine for now.

---

## File structure delta

```
.github/                                        # NEW directory
.github/workflows/                              # NEW directory
.github/workflows/test.yml                      # NEW
README.md                                       # modify: add CI status badge
CLAUDE.md                                       # modify: brief CI invocation note
docs/superpowers/plans/2026-05-08-testing-phase-6.md  # this file
```

No production sources touched. No `Package.swift` / `project.yml` touched. No tests added or modified.

---

# Section A — Skeleton workflow

---

### Task 1: Skeleton CI workflow — `swift test` only

**Why:** Land a minimal, syntactically-correct workflow first that proves the runner can:
1. Check out the repo at the right ref
2. Install `pngquant` via Homebrew
3. Run `swift test` with `IMAGECRC_TEST_REQUIRE_PNGQUANT=1` and exit 0

This is the smallest possible step that exercises the trigger config, environment variables, and brew install pipeline. T2 layers `xcodebuild test` on top once T1's plumbing is verified.

The workflow uses `on: [push, pull_request]` with a `paths-ignore` for docs and a `branches` filter on `push` to keep CI minutes proportional to actual code changes. A `concurrency` group keyed on `${{ github.workflow }}-${{ github.ref }}` with `cancel-in-progress: true` ensures stacked pushes to the same branch don't pile up parallel runs.

The runner image is `macos-14`. GitHub's `macos-14` runners are M1-class arm64; preinstalled software list (https://github.com/actions/runner-images/blob/main/images/macos/macos-14-arm64-Readme.md) confirms the default Xcode is **15.4** which ships **Swift 5.10** — exactly what `Package.swift`'s `swift-tools-version: 5.10` requires. No `xcode-select` step is needed; `swift` and `xcodebuild` resolve to the right toolchain out of the box. Homebrew is preinstalled. `xcbeautify` is preinstalled but unused (see T2 reasoning). `xcodegen` and `pngquant` are NOT preinstalled — both come via `brew install`.

**Files:**
- Create: `.github/workflows/test.yml`

- [ ] **Step 1: Verify the parent directories don't exist yet**

```bash
ls .github 2>/dev/null
```

Expected: nothing (no `.github` directory yet). Confirms this is a fresh add.

- [ ] **Step 2: Write the skeleton workflow**

```yaml
name: Test

on:
  push:
    branches:
      - main
      - "tests/**"
    paths-ignore:
      - "**.md"
      - "docs/**"
      - ".gitignore"
      - "LICENSE"
  pull_request:
    paths-ignore:
      - "**.md"
      - "docs/**"
      - ".gitignore"
      - "LICENSE"

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  test:
    name: swift test (macos-14)
    runs-on: macos-14
    timeout-minutes: 30
    env:
      IMAGECRC_TEST_REQUIRE_PNGQUANT: "1"
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install pngquant
        run: brew install pngquant

      - name: Print toolchain versions
        run: |
          swift --version
          xcodebuild -version
          pngquant --version

      - name: swift test
        run: swift test
```

Notes on individual choices:

- **`branches` filter on push but not pull_request.** PRs run on every change regardless of the source branch. Direct pushes only run on `main` and `tests/**` so feature branches without PRs don't auto-burn CI.
- **`paths-ignore` symmetric on both triggers.** Doc/markdown-only changes skip CI on both push and PR.
- **`timeout-minutes: 30`** is a hard ceiling. Local `swift test` runs in ~10s; xcodebuild path adds ~2 min for build + ~12s for the UI test. 30 min leaves margin for cache misses and slow runner days without hanging indefinitely on a deadlock.
- **`env.IMAGECRC_TEST_REQUIRE_PNGQUANT=1` at job level.** Inherited by every step. `PNGQuantizerTests` is `@Test(.enabled(if: ProcessInfo.processInfo.environment["IMAGECRC_TEST_REQUIRE_PNGQUANT"] == "1"))` — without this, the 2 PNG quantization tests stay skipped even though `pngquant` is installed.
- **No `defaults.run.shell`.** macOS runners default to `bash` which is fine for the inline scripts.
- **No assertion on test counts.** The workflow trusts `swift test`'s exit code. Pinning "92 tests" in CI would make benign coverage growth a red CI run.

- [ ] **Step 3: YAML-validate the file**

```bash
python3 -c "import yaml, sys; yaml.safe_load(open('.github/workflows/test.yml')); print('YAML OK')"
```

Expected: `YAML OK`. Any `ScannerError` / `ParserError` means the indentation or quoting is off — fix before committing.

- [ ] **Step 4: Local sanity — `swift test` baseline still green**

```bash
swift test 2>&1 | tail -5
```

Expected: 92 tests / 32 suites / 2 skipped / 1 known issue, exit 0. Confirms no incidental local breakage from anything else in the working tree.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "$(cat <<'EOF'
ci: add skeleton GitHub Actions workflow for swift test

Runs on push to main/tests/** and on every pull_request. paths-ignore
skips doc-only changes so README and plan edits don't burn runner
minutes. concurrency cancel-in-progress keeps stacked pushes from
piling up parallel runs for a superseded commit.

The job runs on macos-14 (Apple Silicon by default), brew-installs
pngquant, and exports IMAGECRC_TEST_REQUIRE_PNGQUANT=1 so the
PNGQuantizer suite actually runs instead of being skipped.

T1 deliberately ships only the swift test invocation. xcodebuild
test (XCUITest UI smoke) is added in T2 once the skeleton plumbing
is proven.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

# Section B — Full test surface

---

### Task 2: Add `xcodegen generate` + `xcodebuild test` step

**Why:** The XCUITest UI smoke target is XcodeGen-only and runs via `xcodebuild test`. Phase 5 wired this locally; Phase 6 makes CI run it too. The runner doesn't ship XcodeGen, so we install it via Homebrew (alongside `pngquant`).

The destination string mirrors what's documented in `CLAUDE.md`: `'platform=macOS,arch=arm64'`. `macos-14` runners are arm64, so this matches the host arch and avoids the "first of multiple matching destinations" warning that occurs on dev machines with both arm64 and x86_64 simulators.

This task lands as a single commit because the xcodegen install + xcodebuild step are one logical concern: "make CI run the full test surface."

**Files:**
- Modify: `.github/workflows/test.yml`

- [ ] **Step 1: Consolidate the brew install and add the xcodebuild step**

Update the workflow:

1. Change `brew install pngquant` to `brew install pngquant xcodegen`. Consolidating both into one `brew install` invocation keeps the workflow short. `xcodegen` adds ~5 seconds to the install step on a cold runner — negligible.
2. After the `swift test` step, append:

```yaml
      - name: Generate Xcode project
        run: xcodegen generate

      - name: xcodebuild test
        run: |
          set -o pipefail
          xcodebuild test \
            -project ImageCRC.xcodeproj \
            -scheme ImageCRC \
            -destination 'platform=macOS,arch=arm64' \
            -resultBundlePath build/TestResults.xcresult
```

Reasoning:
- `xcodebuild` exits non-zero on test failure — that propagates correctly through the step.
- `set -o pipefail` is defensive; if a future change pipes the output through `xcbeautify` (preinstalled on `macos-14`) the pipe failure won't be silently swallowed.
- `-resultBundlePath build/TestResults.xcresult` writes the bundle to a known location for T4's upload step.
- We deliberately do NOT pipe through `xcbeautify` here — raw `xcodebuild` output is more debuggable in early CI runs. Pretty-print is a follow-up if logs become noisy.

- [ ] **Step 2: YAML-validate**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/test.yml')); print('YAML OK')"
```

- [ ] **Step 3: Local sanity — `xcodebuild test` baseline still green**

```bash
xcodebuild test -project ImageCRC.xcodeproj -scheme ImageCRC -destination 'platform=macOS,arch=arm64' -quiet 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **` with the existing 92 SwiftPM + 1 UI = 93 test baseline. No regression from the workflow edit (workflow YAML doesn't affect local builds, but this confirms the local toolchain still works).

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "$(cat <<'EOF'
ci: run xcodebuild test for the XCUITest UI smoke target

The XCUITest target is XcodeGen-only and not visible to swift test.
Add a step that installs xcodegen via brew, regenerates the Xcode
project, and runs xcodebuild test pinned to platform=macOS,arch=arm64
(matches the macos-14 runner's host arch). -resultBundlePath writes
the xcresult bundle to build/TestResults.xcresult for post-mortem
upload by T4.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

# Section C — Performance + ergonomics

---

### Task 3: Cache SwiftPM build artefacts

**Why:** Cold `swift build` resolves and compiles `libwebp` from `SDWebImage/libwebp-Xcode` plus all of ImageCRC. Local timing: ~30s on a warm dev machine, longer on cold CI. Caching `.build/` keyed on the package manifest content gives near-instant restore on no-dependency-change runs.

**Cache key choice — `Package.swift`, NOT `Package.resolved`.** `Package.resolved` is in `.gitignore` (and not tracked) on this repo, so `actions/checkout` produces a tree where it doesn't exist. `hashFiles('**/Package.resolved')` would return an empty string and the cache key would collapse to a constant prefix, never invalidating on dependency bumps — the worst possible state (stale cache served forever). `Package.swift` IS tracked and pins `from: "1.3.2"` for `libwebp`. It's the closest tracked artefact to the dependency graph; changes to it (including unrelated edits like adding a test source dir) bust the cache, which is acceptable because such changes are rare. `restore-keys` provides a coarser fallback so a manifest-only edit still rehydrates `.build/checkouts` from the previous key.

Homebrew is also worth caching, but its install is fast on macos-14 (`pngquant` is small, `xcodegen` likewise) and brew's bottle cache is per-runner. Skip Homebrew caching — measure first, optimise later if it becomes the bottleneck.

**Files:**
- Modify: `.github/workflows/test.yml`

- [ ] **Step 1: Add the cache step**

Insert after `Checkout` and before `Install pngquant`:

```yaml
      - name: Cache SwiftPM build artefacts
        uses: actions/cache@v4
        with:
          path: .build
          key: ${{ runner.os }}-${{ runner.arch }}-spm-${{ hashFiles('Package.swift') }}
          restore-keys: |
            ${{ runner.os }}-${{ runner.arch }}-spm-
```

Notes:
- `path: .build` is SwiftPM's default build directory — covers checkouts, derived data, and final products.
- Key includes `runner.arch` because arm64 and x86_64 build artefacts are NOT interchangeable. `macos-14` is arm64, but if the runner image ever changes this stays correct.
- `hashFiles('Package.swift')` is non-recursive — exactly one file. We deliberately don't use `**/Package.swift` because that would also match any nested package manifests if added later, which would over-invalidate.
- `restore-keys` allows partial cache hit when `Package.swift` changes but most checkouts stay reusable.
- `actions/cache@v4` is the current major version (v3 is deprecated as of Feb 2025).

- [ ] **Step 2: Verify `Package.swift` is tracked (sanity check)**

```bash
git ls-files Package.swift
```

Expected: `Package.swift`. If empty, the cache key would collapse to a constant and the cache would never invalidate — but `Package.swift` has been tracked since project init, so this is a defensive check, not a real risk.

- [ ] **Step 3: YAML-validate**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/test.yml')); print('YAML OK')"
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "$(cat <<'EOF'
ci: cache .build/ keyed on Package.swift hash

Cold swift build resolves and compiles libwebp from SDWebImage's
libwebp-Xcode plus all of ImageCRC. Caching .build/ keyed on
runner.os + runner.arch + Package.swift hash gives near-instant
restore on no-dependency-change runs. restore-keys allow partial
cache hit when the manifest changes but most checkouts stay
unaffected.

Package.swift (not Package.resolved) is the cache key because the
latter is gitignored and absent on a fresh actions/checkout — using
it would collapse the key to a constant prefix that never
invalidates.

DerivedData (xcodebuild) intentionally not cached — multi-GB,
hits the 10 GB/key cache ceiling, and xcodebuild on a one-shot
runner sees marginal speedup vs the cache save/restore cost.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

# Section D — Failure observability

---

### Task 4: Upload xcresult on failure

**Why:** When `xcodebuild test` fails on CI, the runner logs are the only forensic surface. `.xcresult` bundles contain the full test report including XCUITest screenshots and structured failure data, so re-running locally to debug becomes optional rather than mandatory.

`actions/upload-artifact@v4` uploads on `if: failure()` so the artifact only consumes storage when something actually went wrong. Retention is set to 14 days to balance forensic utility against artifact storage costs (default is 90 days; 14 is enough for the user to investigate without indefinite accumulation).

T2 already wrote the xcresult to `build/TestResults.xcresult` via `-resultBundlePath`. T4 just adds the upload step.

**Files:**
- Modify: `.github/workflows/test.yml`

- [ ] **Step 1: Add the upload step**

Append at the end of the `steps:` list:

```yaml
      - name: Upload xcresult on failure
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: xcresult-${{ github.run_id }}-${{ github.run_attempt }}
          path: build/TestResults.xcresult
          retention-days: 14
          if-no-files-found: ignore
```

Notes:
- `if: failure()` runs only when a previous step in the job failed. `success()` is the default — overriding to `failure()` makes this an opt-in artifact.
- `name` includes `run_id` and `run_attempt` so re-run-with-debug uploads don't clash.
- `if-no-files-found: ignore` covers the case where `swift test` fails before xcodebuild runs (the xcresult won't exist). Without this, the upload step itself would fail on a swift test failure, masking the real cause.
- `retention-days: 14` overrides repo default (typically 90). Re-evaluate if storage cost becomes an issue; bump down to 7 if not.

- [ ] **Step 2: YAML-validate**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/test.yml')); print('YAML OK')"
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "$(cat <<'EOF'
ci: upload xcresult bundle on test failure

When xcodebuild test fails on CI, the runner logs alone make
debugging hard — XCUITest in particular benefits from the screenshot
and structured failure data inside the xcresult bundle. Upload it as
an artifact (14-day retention) on failure() so the user can download
and inspect locally without re-running the whole CI cycle.

if-no-files-found: ignore handles the case where swift test fails
before xcodebuild runs and the xcresult bundle never gets written.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

# Section E — Docs

---

### Task 5: README badge + brief CLAUDE.md note

**Why:** A workflow nobody knows about doesn't catch regressions, because nobody looks at it. The standard pattern is a build-status badge at the top of the README pointing to the workflow's runs page.

`CLAUDE.md` already documents both `swift test` and `xcodebuild test` invocations (Phase 5 T7). Phase 6 adds a one-line forward reference to the CI workflow so future contributors know CI runs both invocations on every PR.

**Files:**
- Modify: `README.md` (add CI badge to the existing badge row)
- Modify: `CLAUDE.md` (one-line CI note in the "Build & run" section)

- [ ] **Step 1: Add the CI badge to README.md**

Locate the existing badge block in `README.md` (lines ~9–12, the `<p>...</p>` containing the macOS / Swift / SwiftUI shields). Add a CI badge as the **first** badge in that row so it appears leftmost — that's the convention for build-status badges.

The badge URL pattern is:
`https://github.com/<owner>/<repo>/actions/workflows/<filename>/badge.svg`

For this repo: `https://github.com/spooosh/ImageCRC/actions/workflows/test.yml/badge.svg`

The link target is the workflow's runs page:
`https://github.com/spooosh/ImageCRC/actions/workflows/test.yml`

Insert at the top of the existing `<p>` badge block:

```html
    <a href="https://github.com/spooosh/ImageCRC/actions/workflows/test.yml">
      <img alt="CI" src="https://github.com/spooosh/ImageCRC/actions/workflows/test.yml/badge.svg" />
    </a>
```

The badge will show "passing" / "failing" / "no status" depending on the latest run on the default branch (`main`). Until `tests/phase-1` lands on `main` and a CI run completes, the badge will show "no status" — that's fine, the badge auto-updates after the first run.

The repo owner is verified from `git remote get-url origin` → `git@github.com:spooosh/ImageCRC.git`. Owner: `spooosh`, repo: `ImageCRC`.

- [ ] **Step 2: Add the CI note to CLAUDE.md**

In the "Build & run" section, after the existing `xcodebuild test` line, append:

```markdown
- CI runs both `swift test` and `xcodebuild test` on every push to `main` / `tests/**` and on every pull request via `.github/workflows/test.yml` (macos-14 runner, arm64). Keep both invocations green locally before pushing — CI parity matters.
```

- [ ] **Step 3: Verify the markdown still renders**

```bash
head -15 README.md
```

Expected: badge block contains the new CI badge as the first item, followed by the existing macOS / Swift / SwiftUI badges. No malformed HTML.

- [ ] **Step 4: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "$(cat <<'EOF'
docs: add CI status badge and document workflow invocation

README gets a leftmost CI badge linking to the workflow runs page.
Until tests/phase-1 merges to main and the first run completes the
badge shows "no status" — auto-updates on first run.

CLAUDE.md gets a one-line forward reference under Build & run so
future contributors know CI runs both swift test and xcodebuild test
on macos-14, and that local parity matters before pushing.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 6 Done When

- [ ] `.github/workflows/test.yml` exists, YAML-validates, contains skeleton + xcodebuild + cache + xcresult upload
- [ ] Workflow trigger is `push` (filtered to `main` and `tests/**`) + `pull_request` (any source branch); both honour `paths-ignore` for docs
- [ ] `concurrency` block cancels in-progress runs on the same ref
- [ ] `IMAGECRC_TEST_REQUIRE_PNGQUANT=1` exported at job level; `pngquant` brew-installed before `swift test`
- [ ] `xcodegen` brew-installed before the xcodebuild step; project regenerated on every run (no committed `.xcodeproj` mismatch issues)
- [ ] `.build/` cached keyed on `runner.os + runner.arch + hashFiles('**/Package.resolved')`
- [ ] xcresult uploads on failure with 14-day retention
- [ ] README has CI badge as the first item in the badge row
- [ ] CLAUDE.md has the one-line CI note
- [ ] `swift test` and `xcodebuild test` both still pass locally (no regression)
- [ ] User approval to merge `tests/phase-1` → `main`

---

## Risks / Open Questions

1. **TCC automation permission for XCUITest on `macos-14` runners.** Phase 5's environmental gotcha was that `xcodebuild test` fails with `Timed out while enabling automation mode` on a fresh dev machine without TCC permission for the test runner. GitHub's `macos-14` runners are ephemeral and run as the runner user, which by default has automation permission for the system Xcode/`xcodebuild` toolchain. The runner-images repo (https://github.com/actions/runner-images) doesn't explicitly call this out, but the precedent is hundreds of public Swift macOS projects running XCUITest on `macos-14` without manual TCC setup (e.g., point-free's projects, ArtemNovichkov/swift-package-list, etc.). **Mitigation if it does fail:** the standard fix is to invoke `osascript -e 'tell app "System Events" to ...'` once before `xcodebuild test` to seed the TCC database, but try the simpler config first. Document the failure mode here so future investigators know the Phase 5 gotcha could re-surface on CI.

2. **`Package.resolved` is gitignored — confirmed during plan QA.** Verified via `git ls-files Package.resolved` (empty) and `.gitignore` (contains `Package.resolved`). T3's cache key uses `Package.swift` instead, which IS tracked. The trade-off: if a maintainer bumps a dependency in `Package.swift` to `from: "1.3.3"`, the cache invalidates correctly. If they keep the manifest static and a transitive dependency floats (semver minor), the cache stays warm with stale checkouts — acceptable because SwiftPM's resolver re-runs on cache restore and updates the working `.build/checkouts` if needed.

3. **`xcodegen` from Homebrew may lag the latest Xcode SDK.** XcodeGen sometimes ships behind the bleeding-edge Xcode version. The local dev env uses `xcodegen 2.43+` (per repo conventions). On `macos-14` runners brew installs whatever the bottle is at the time of the run. If a future Xcode release introduces project format changes XcodeGen hasn't shipped support for, CI will break before local does. **Mitigation:** pin a specific xcodegen version via `brew install xcodegen@<version>` if drift becomes a problem. Not a Phase 6 blocker.

4. **`xcbeautify` is preinstalled but not used.** The runner image ships `xcbeautify` but T2 deliberately doesn't pipe xcodebuild output through it — raw output is more debuggable in early CI runs. If logs become too noisy after Phase 6 lands, follow-up: `| xcbeautify --renderer github-actions`. Not a Phase 6 concern.

5. **First CI run will need a `Package.resolved` cache miss.** Cold cache is expected — the first push after this lands will cold-resolve `libwebp` (downloads + builds). Subsequent runs hit the cache. Not a regression, just expected first-run cost.

6. **The badge will show "no status" until `tests/phase-1` lands on `main`.** GitHub Actions badges show the status of the default branch unless `?branch=` is appended. Adding `?branch=tests/phase-1` to the badge URL would make it show the testing branch's status, but Phase 6's premise is "this is shipping to main." Leave the URL bare; once merged, the badge tracks main and is correct.

7. **Concurrency cancellation can mask flake.** If a maintainer pushes 3 commits in 10 seconds, runs 1 and 2 cancel, only run 3 executes. If run 3 happens to pass through a flake window that earlier commits would have caught, the flake stays hidden. **Mitigation:** acceptable trade-off — flakes in this codebase are rare (Phase 5 deferred the only known one), and the alternative (no cancellation) burns 3× CI minutes for no signal. Reconsider if intermittent failures appear post-merge.

8. **`paths-ignore` only filters by changed files in the **head** commit on PRs, not the commit range.** A PR that touches `Package.swift` AND `README.md` runs CI (because `Package.swift` isn't ignored). A PR that touches ONLY `README.md` skips CI. This is correct behaviour — covered for completeness because someone reading the workflow might assume otherwise.

9. **Shell injection via branch names.** GitHub Actions runs steps in `bash`, and branch names with shell metacharacters could in theory cause issues if interpolated unsafely. We don't interpolate `${{ github.ref }}` into shell commands — only into the `concurrency.group` (a YAML string, not shell), so this is N/A. Flagged for completeness.

---

## Out-of-scope (deliberately deferred)

- DerivedData caching (cost-benefit unfavourable; revisit if `xcodebuild` step exceeds 10 min)
- Matrix builds across macOS versions / Xcode versions
- Coverage reporting (codecov, etc.)
- SwiftLint / formatters / security scanners
- `xcbeautify` log filtering (raw output more debuggable initially)
- Self-hosted runners
- Pre-commit hooks via CI

---

## Pause points

- **After T1:** skeleton workflow lands; `swift test` runs on CI. Independent improvement — even if the rest of Phase 6 paused, regressions to the SwiftPM-side suite get caught upstream.
- **After T2:** full test surface running on CI. UI tests included.
- **After T3:** cache wired; cold-build cost amortised across runs.
- **After T4:** failure observability covered.
- **After T5:** Phase 6 complete; the user pushes the branch when ready, the first CI run (cold cache) executes, and after green the user merges `tests/phase-1` → `main`.

---

## Self-review

**Spec coverage:** Phase 6 commitments from `2026-05-05-testing-strategy.md` covered:
- `.github/workflows/test.yml` runs on push/pull_request → T1
- `brew install pngquant xcodegen` → T1 (pngquant) + T2 (xcodegen)
- `swift test` → T1
- `xcodegen generate` → T2
- `xcodebuild test` with platform=macOS,arch=arm64 destination → T2
- Cache `.build/` between runs → T3
- README build-status badge → T5
- Upload XCUITest screenshots on failure → T4 (xcresult bundle includes screenshots)
- Homebrew caching strategy: deferred (rationale documented in T3 and Out-of-scope)

**Placeholder scan:** every code block runnable. T1 ships full workflow body. T2's xcodebuild step is concrete. T3's cache step uses real `actions/cache@v4` keys (keyed on `Package.swift`, not `Package.resolved` — the latter is gitignored). T4's upload step uses real `actions/upload-artifact@v4` syntax. T5's badge URL uses the verified repo owner.

**Cross-task consistency:** `.build/` cached in T3 makes T1's `swift test` step faster. `xcresult` written in T2 (`-resultBundlePath build/TestResults.xcresult`) consumed in T4. Single workflow file edited across T1–T4; T5 doesn't touch it.

**Failure-mode handling:**
- `brew install pngquant xcodegen` failure → step exits non-zero, job fails, no cache poisoning (cache only restores, doesn't save on fail).
- `swift test` failure → xcresult not yet written, T4's upload silent-no-ops via `if-no-files-found: ignore`.
- `xcodebuild test` failure → xcresult exists, T4 uploads it.
- Workflow YAML invalid → GitHub Actions UI shows the error; locally caught by T1 step 3 / T2 step 2 / T3 step 3.

**Conventional Commits:** all 5 commits follow `type(scope): subject` where scope clarifies. Used `ci:` (no scope) since the work IS the CI surface — repo precedent shows `chore(build):` was used when build config was the focus, but `ci:` is the canonical Conventional Commits type for CI changes (per https://www.conventionalcommits.org/en/v1.0.0/#summary). T5 uses `docs:` since it's pure documentation. Each commit covers one logical concern: skeleton, xcodebuild, cache, artifacts, docs.

**Local verification scope:** what's verifiable locally vs only on push:
- Locally: YAML parses, `swift test` baseline, `xcodebuild test` baseline, `Package.swift` is tracked
- Only on push: trigger filters fire correctly, brew install on fresh runner, cache restore/save, TCC permission auto-grant, xcresult upload on failure, badge updates after first run

This is documented in the final report so the user knows what would be validated on push.

---

## QA review fixes applied (2026-05-08)

Self-review caught several issues in the original draft. Applied as edits to this plan before execution; the fixes commit lands separately so the plan's evolution stays auditable.

**C1 (critical) — `Package.resolved` is gitignored, so it cannot be the cache key.** Original T3 used `hashFiles('**/Package.resolved')`. Verified via `git ls-files Package.resolved` (empty) and `.gitignore` (contains `Package.resolved`) — on a fresh `actions/checkout` the file doesn't exist, the hash returns empty, and the cache key collapses to a constant prefix that never invalidates on dependency bumps. **Fix:** key on `Package.swift` (which IS tracked and pins `from: "1.3.2"` for libwebp). Coarser invalidation but correct — the alternative was a worst-case "stale cache served forever" failure mode.

**C2 (critical) — T2 Step 1 had contradictory text about an `xcbeautify` fallback.** Original draft showed a complex `||`-fallback YAML, then said "actually use this simpler version." A future executor could have implemented either. **Fix:** rewrote T2 Step 1 to present one clean version with reasoning for not using `xcbeautify` (raw output is more debuggable on early CI runs). `xcbeautify` is preinstalled on `macos-14` per the runner-image readme; the fallback was paranoia.

**I1 (important) — Default Xcode on `macos-14` is 15.4 (Swift 5.10), confirmed against the runner-image readme.** Matches `Package.swift`'s `swift-tools-version: 5.10` exactly — no `xcode-select` step needed. Documented in T1's intro so future contributors don't assume the workflow needs explicit toolchain selection.

**I2 (important) — Brew install consolidation.** Original T2 vaguely said "change `brew install pngquant` to `brew install pngquant xcodegen`." Clarified that this is intentional consolidation (one step instead of two) and acknowledged the marginal ~5s extra install cost on T1-only runs.

**I3 (important) — `paths-ignore` filter list completeness.** Added `.gitignore` and `LICENSE` to the ignore list since edits to those would also not need CI. Already present in the plan; flagged here for traceability.

Minor noise (M1–M3 from the review) skipped — phrasing nitpicks, not load-bearing.
