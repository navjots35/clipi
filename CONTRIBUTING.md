# Contributing to clipi

Thanks for your interest in contributing. clipi is small on purpose — the goal is a fast, opinionated, keyboard-first clipboard manager, not a Swiss-army-knife app — so the bar for new behavior is "does this make the keyboard flow tighter?"

## Branch model

- **`main`** — production. Protected. Only release-ready code, only merged via PR.
- **`develop`** — integration. **All PRs target this branch.** When `develop` is stable, a release PR brings it into `main`.
- **Topic branches** — your changes live here, branched off `develop`, named like `fix/settings-close-recursion` or `feat/sparkle-updater`.

## Getting set up

Requirements: macOS 13+, Xcode 15+ (for the Swift 6 toolchain that ships with it).

```sh
git clone https://github.com/navjots35/clipi.git
cd clipi
git checkout develop
./scripts/build.sh        # ad-hoc signed dev build at build/clipi.app
open build/clipi.app
```

Grant Accessibility on first launch, then ⌥⌘V should summon the panel.

## Making a change

1. Branch from `develop`: `git switch -c fix/whatever develop`
2. Make your change. Try to keep PRs single-purpose — easier to review, easier to revert.
3. Run `./scripts/build.sh` and smoke-test the affected flow.
4. Commit with a descriptive message — first line is the subject (≤72 chars), body is the *why*.
5. Push and open a PR against `develop`. CI will build on macOS 14 + macOS-latest under both `-Onone` and `-O` to catch optimization-only regressions.

## Code conventions

- **Swift style** — match the existing files. We follow the standard Swift API design guidelines plus a few project-specific habits documented in the source via `// MARK:` headers and inline comments where the *why* is non-obvious.
- **Comments** — for the *why*, not the *what*. If a method needs a comment to explain what it does, the method name is wrong.
- **No new third-party dependencies** without discussion — clipi is intentionally vendor-free (no SPM packages so far) and we'd rather a 50-line implementation than a 50-MB framework. If you genuinely need one, open an issue first.
- **Error handling** — fail open for capture (a missing pasteboard type → skip that copy, don't crash). Fail closed for security (any ambiguity about whether something is a password → don't capture).

## What kinds of changes are most welcome

- Bug fixes (with a clear reproduction)
- Performance improvements with a measurement
- Privacy / security hardening — additional secure-field detection, password manager bundle IDs, etc.
- Accessibility improvements
- Documentation, README polish
- New per-app rule defaults that catch more sensitive contexts

## What's likely to get pushback

- Major UI changes that move clipi away from the design language documented in `Clipi.html`
- Features that pull clipi into "do everything" territory (snippet expansion, cloud sync, AI integrations) — not because they're bad ideas, but because they'd be better as a separate app or fork
- Adding telemetry / analytics of any kind
- Changes that introduce a third-party SPM dependency without an issue discussion first

## Reporting bugs

Use the [bug report template](https://github.com/navjots35/clipi/issues/new?template=bug_report.yml). The more specific the repro, the faster the fix.

If you find a security issue (something that could capture data clipi shouldn't), please email rather than filing a public issue — see the SECURITY.md (TODO) once it exists, or just include "security:" in your bug-report subject line.

## License

By contributing, you agree your code will be released under the same MIT license as the rest of the project.
