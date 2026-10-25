# Forge Diagnostics: Ranitas visual-envelope session

Date: 2026-10-25. Agent: Claude Code (Opus 5.5), with six Fable subagents
(three for read-only research, three for implementation in isolated
worktrees). Forge: Fedora 44 container, `accel_class=workstation-gpu`, branch
discipline level 0.

The project owner asked for this file so the forge creators can look for
enhancements that fit their architecture. It reports what happened in this
session. It is not a benchmark.

## What the session did

- **Research:** three subagents studied the codebase in parallel: scene and
  light, lily pad physics, and frog depth.
- **Specification:** an OpenSpec change (`openspec/changes/visual-envelope`),
  a research and limits document, and an asset hand-off for image-generation
  agents.
- **Implementation:** three subagents built three branches in parallel
  (`work/pond-atmosphere`, `work/pond-layers`, `work/pond-pads-depth`). I
  merged them into `work/visual-envelope`, resolved the conflicts, wired the
  branches into each other, checked offscreen renders, and folded in the
  owner's answers.
- **Result:** 8 code and doc commits plus merges across 5 pushed `work/*`
  branches. The test suite grew from 25 to 61 tests; `flutter analyze` is
  clean.

## Worked out of the box

- **Git through the enclave mirror.** No remotes, tokens or SSH setup. Pushing
  new branches just worked, and the pre-receive hook gave clear output when it
  refused one (see below).
- **Flutter / Dart toolchain** (`flutter analyze`, `flutter test`, offscreen
  rendering to PNG inside tests). This made a visual check possible without a
  browser.
- **OpenSpec CLI** (`openspec new change`, `instructions`, `validate`).
- **ImageMagick and ffmpeg shims, node + sharp.** `magick montage`/`crop` were
  enough to inspect renders, and sharp produced the emissive masks.
- **Isolated worktrees for subagents.** Three agents edited the same files in
  parallel without interfering. Merge conflicts were small and confined to
  hot spots the briefs had predicted.
- **The kill-by-PID guidance in the global CLAUDE.md.** It was never needed,
  but it was clear.

## Required some figuring out

1. **OpenSpec output rejected by the mirror's YAML validator.**
   - **What happened:** `openspec new change` writes
     `created: 2026-10-25` (an unquoted YAML date). The mirror's pre-receive
     hook validates YAML with Ruby `Psych.safe_load`, which refuses `Date`
     (`Tried to load unspecified class: Date (Psych::DisallowedClass)`). That
     rejected the whole push.
   - **Workaround:** quote the date.
   - **Suggested fix:** pass `permitted_classes: [Date]` in the validator, or
     validate with `yq`, which the startup context already recommends. Two
     forge-endorsed tools currently disagree about what valid YAML is.
2. **Branch-name grammar.** The owner asked for "work branches". The mirror
   expects `work/<order>` (an order id) and warned on `work/visual-envelope`.
   The warning didn't block anything, but there is no documented `work/<slug>`
   form for projects that have no plan ledger. `claude/*` would have matched,
   but that isn't what the owner asked for.
3. **Advisory noise.** Every commit, merge and push printed the same three
   lines ("4 committer identities… could use an integration branch…"). One
   advisory per session, or per change in state, would be enough.
4. **Test feedback is slow for parallel agents.** The suite takes about 2–3
   minutes. Four agents (three implementers plus me) ran it repeatedly. A
   shared, warm Flutter tool cache or a `flutter test --concurrency` hint in the
   forge docs might help.
5. **`node_modules` absent in a fresh checkout.** The art scripts failed with
   `ERR_MODULE_NOT_FOUND` for `sharp` until `npm ci` ran. That is expected for a
   fresh clone, but a startup-context line saying "JS deps not installed; run
   `npm ci`", like the existing `base_state` lines, would save a round trip.
6. **The source tmpfs fills up with parallel worktrees.** `/home/forge/src`
   is a 1.5 GB tmpfs. Six subagent worktrees (100–400 MB each with `build/`
   and `node_modules`) reached **99 % with 25 MB free** while two agents were
   still running. One agent hit `ENOSPC` mid-test, and another moved its
   `build/` and `node_modules` to the scratchpad through symlinks. I freed
   ~870 MB by removing worktrees whose commits were verified on origin. A
   startup-context line with the tmpfs size and a warning threshold, or
   auto-pruning finished worktrees, would prevent this.
7. **Leftover worktrees.** Isolated subagents left
   `.claude/worktrees/agent-*` checkouts behind, which show up as untracked
   `.claude/` in `git status`.

## Did not work

1. **Ruby via its brew shim.**
   - **What happened:** the startup context says `ruby` is ABSENT, but a
     `ruby` brew shim exists. Running `ruby -ryaml -e '…' file` triggered a
     ~60 MB Homebrew install of Ruby 4.0.9 and its dependencies, then failed:
     `/home/linuxbrew/.linuxbrew/bin/ruby: No such file or directory -- timeout (LoadError)`.
   - **Likely cause:** the shim probably passes its own `timeout` wrapper to
     Ruby as the script argument.
   - **Two issues:** the shim bug itself, and the startup context contradicting
     the shim list.
   - **My part:** I reached for Ruby because the pre-receive error came from
     Ruby. I had not yet read the startup context, which tells agents to use
     `yq`.
2. **No image generation.** The project's art came from an image generator.
   This forge's inference endpoint serves only text and embedding models. The
   painted assets were specified in `art/ASSET_REQUESTS.md` for other agents
   instead of being produced. The host reports a usable Radeon GPU (ROCm tier),
   so a local image model looks feasible.
3. **`tellme`.** Every call printed
   `requested dir /opt/cheatsheets lacks INDEX.md` before falling back to the
   image bundle. `tellme lua` is an unknown command, and there is no Lua topic.
4. **Lua is not usable.** The owner mentioned a Lua runtime. Only the
   `lua-libs-5.4.8` shared library is installed (`/usr/lib64/liblua-5.4.so`,
   which no installed package requires). There is no `lua`, `lua5.4` or
   `luajit` on PATH, no brew shim for one, and no mention of one in the startup
   context or `tellme`. An agent cannot discover or call it.
5. **No in-browser check.** The `host-browser` MCP tools (`publish_local`,
   screenshots) were available, but I didn't try them. The visual check used
   offscreen renders from the test suite. This was my choice, not a forge
   failure, and is recorded so nobody reads it as "the browser path was
   verified".
6. **Pillow.** Python has no Pillow, which is consistent with the no-Python
   policy. I fell back to ImageMagick.

## Session analysis: the Python calls

The owner noticed many `python3` executions. I ran about two dozen
`python3 - <<'EOF' … EOF` heredocs. None of them is committed; the repository
contains no Python. They fell into four groups:

| Use | Count (approx.) | Why Python |
| --- | --- | --- |
| **Multi-site source edits** (several replacements in one file, each guarded by `assert old in s`) | ~12 | Atomic all-or-nothing edits in large files (`pond_model.dart` ~1900 lines) that subagents had just changed, without re-reading the whole file first, which the Edit tool requires |
| **Merge-conflict resolution** (regex over `<<<<<<<`/`>>>>>>>` blocks, sometimes keeping both sides) | ~5 | Each hunk needed a hand-written combination; a regex was the quickest exact way to do it |
| **Doc and table rewrites** (decision table rows, renumbered question list, inserted sections) | ~5 | Positional inserts relative to headings |
| **Probing for Pillow** | 1 | Failed; switched to ImageMagick |

**What would have avoided them:**

- **The dedicated Edit tool** covers most single edits. I under-used it.
- **A forge-provided structured-edit command** would cover the rest: for
  example, `forge-edit FILE --replace OLD NEW … --assert-once`, plus
  `--resolve-conflict ours|theirs|both`. It would do batched, atomic,
  asserted replacements and conflict-hunk handling with an exit code.
- **A Lua interpreter on PATH** would also work, if exposed with a couple of
  helpers, e.g. `forge-lua -e 'replace(file, old, new)'` with the standard
  library plus `lfs`/`lpeg`. Lua is small, embeddable and already half-present
  as `lua-libs`. If it were on PATH and listed in the "Tooling actually present
  here" section of the startup context, agents would reach for it instead of
  the forbidden `python3`.

Today the forbidden tool is the most discoverable scripting runtime, and the
policy only covers *committed* automation. Ad-hoc agent use drifts to it
because nothing better is advertised.

## Nice to have (fits the existing architecture)

1. **A Lua (or other blessed scripting) runtime exposed on PATH and in the
   startup context's tool list.** Ship it with small wrappers for the
   operations agents keep improvising: batched asserted replace, YAML/JSON
   get/set (already covered by `yq`/`jq`), conflict-hunk resolution, and
   frontmatter edits.
2. **One YAML truth.** Make the mirror's pre-receive validator agree with `yq`
   and with what common generators emit (dates, anchors).
3. **Fix the `ruby` shim.** Either fix the `timeout` argument handling or
   remove the shim to match "ruby ABSENT".
4. **`work/<slug>` in the branch grammar** for projects without a plan ledger,
   or a documented mapping from free-form names to `work/<order>`.
5. **An image-generation endpoint** next to the Ollama text models, given the
   usable GPU, with an asset-hand-off convention such as
   `art/ASSET_REQUESTS.md`, so art requests can be fulfilled in the same
   enclave.
6. **Quieter advisories:** print once per session or on change.
7. **Auto-cleanup or a `git worktree prune` hint** for subagent worktrees left
   under `.claude/worktrees/`.
8. **A Flutter-web screenshot recipe** in `tellme` that uses `publish_local`
   plus the host-browser screenshot tools, so "view it in a browser" is a
   documented one-liner.

## Codex asset completion session — 2026-10-25

### What went well

- The integration branch already contained all six implementation branches.
  The asset request file, optional filename registry, OpenSpec tasks and
  procedural fallbacks made the remaining scope discoverable without asking
  the owner to reconstruct Claude's work.
- Built-in image generation worked without API credentials. Delivered 64
  image assets (60 biome layers/atlases, two replacement frog sheets and two
  depth sheets), retained PNG sources and lossless WebP exports, and recorded
  the prompt set in `art/GENERATION.json`.
- The forge's Flutter wrapper provided a working shared SDK. Static analysis,
  all 89 existing Flutter tests (including the 100-seed soak), nine audio tests,
  and the upgraded all-biome real-asset rendering test passed.
- `publish_local` and the host browser worked for Flutter web. The preview
  route has trusted local TLS; Chromium fetched the optional assets with HTTP
  200, rendered the pond, accepted a pointer press/release, and reported no
  application console errors. Headless mode has no speakers, so this verifies
  audio code and browser execution rather than subjective listening quality.
- Final release validation: 132 image/data contracts passed; the corrected
  assets passed all three renderer smoke tests; the production web build
  contains 181 files totaling 61.16 MiB, with every file below 25 MiB.

### What required figuring out

- `work/visual-envelope` is the integrated implementation;
  `work/visual-envelope-specs` is its older ancestor, not a second unfinished
  feature to merge independently. Git ancestry was more reliable than branch
  names for establishing the scope.
- The `flutter` executable is a host-toolchain wrapper, not a local SDK.
  Initial output can be delayed, while long tests continue normally through
  the returned process session. Polling only the final output avoided
  mistaking toolchain startup or the soak test for a hang.
- Image tools return substantial inline data alongside a default saved path.
  Imagegen's `output_hint` carries the path; browser screenshots carry base64
  in `structuredContent.data`, even though their content block is text.

### What required fixing

- The existing export script doubled every non-sheet texture. Added distinct
  handling for fixed-size leaf atlases, branch strips and numeric cycle maps.
- Generated atlases had uneven row padding. The importer detects occupied
  row bands and repacks cells before scaling, preventing cross-cell bleeding.
  It also enforces binary alpha, black RGB under transparent pixels, the clear
  jump lane, frog palettes, integer enlargement and branch endpoint coverage.
- Initial mid-bank generations copied overhead branches from scenic
  references. Regenerated all twelve using ground-object-only prompts without
  backdrop references. Four foliage generations included lanterns, fungi or
  crystals instead of leaves; regenerated those with leaf-only prompts.
- A Sharp pipeline combining extraction and trimming failed with
  `extract_area: bad extract area`: trim changed the coordinate space. Splitting
  those into separate buffer operations fixed the importer.
- Numeric lookup maps are data, not illustrative images. Exported all 56
  directly from the canonical Dart region table; isolated the remaining stars
  locally instead of globally keying petals, snow and sky dithering. Scenes
  without painted light sources intentionally have empty alpha masks.

### What did not work as a one-step operation

- Asking imagegen for exact grids, dimensions and clean scene decomposition
  was insufficient by itself. Generated art needed inspection, normalization
  and targeted regeneration before it satisfied the runtime contracts.
- Printing an entire imagegen result or screenshot text exposes hundreds of
  thousands of base64 tokens in tool output. The first attempts did this;
  subsequent calls reported only metadata and rendered image data separately.
- A ten-request image batch made other tool replies noticeably less responsive.
  The correction batch used four concurrent requests and concise completion
  notices. No CLI/API fallback or external image credentials were needed.

### Improvements for the next run

- Expose a small documented image-result schema with saved path, dimensions,
  alpha status and thumbnail, and keep base64 out of normal text results.
  Browser screenshots and imagegen should use the same image-content shape.
- Add asset contracts to handoffs as machine-readable data: filename, required
  size, cell layout, scale policy, clear regions and whether the file encodes
  art or numeric data. `npm run check:art` now checks this project's contracts
  for all 132 delivered image/data assets.
- Recommend small bounded image batches, early contact-sheet review, and
  prompts that describe only the objects belonging to a compositing layer.
  A style reference can unintentionally reintroduce its scene geometry.
- Advertise the Flutter wrapper and a `publish_local` → `browser_open` →
  screenshot/console/network recipe in startup tooling guidance. Both worked
  here and address the browser-validation gap documented in the prior session.
