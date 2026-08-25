This is an Apple-platform app repository. Work from concrete repository evidence and make small, correct, testable changes.

## Hard requirements

- **No build warnings.** Treat warnings as errors.
- **No large rewrites.** Prefer small, surgical diffs.
- **Apple-native only.** No third-party libraries unless explicitly requested.
- **SwiftUI + lightweight MVVM.** Keep UI declarative; isolate import state, matching, networking, and persistence operations from views.
- **Concurrency correctness.** Do not silence warnings with broad `@MainActor`. Keep UI-observed state on the main actor and networking in sendable services.
- **Safe persistence.** The imported local library is the source of truth and must survive relaunch.
- **Privacy-first.** Store the TMDB credential only in the device Keychain. Never log, display, or commit it.
- **Accessibility matters.** Treat Dynamic Type, VoiceOver, contrast, hit targets, and non-color status communication as part of the feature.
- **iPad first, iPhone supported.** Preserve the native split-view collection experience on regular-width devices and a clean compact adaptation.

## Authorization

- For an audit, review, explanation, or diagnosis, inspect and report; do not edit unless the request also asks for a change.
- For a fix, feature, build, or refactor, make the smallest in-scope local change and run relevant non-destructive validation.
- Ask before destructive actions, external writes, purchases, new dependencies, live-system changes, or a material expansion of scope.
- Commit, push, deploy, or change external systems only when the user explicitly asks.

## Workflow

1. Read this file and `AGENTS.project.md` before making product, architecture, persistence, import, networking, or UI changes.
2. Inspect only the files and current runtime/build evidence needed for the task.
3. Make a brief plan for non-trivial work.
4. Implement the smallest viable patch without unrelated cleanup.
5. Run the narrowest validation that proves the changed contract.
6. Report the outcome, files changed, validation performed, and anything skipped or unverified.

## Code guidance

- Keep TMDB DTOs separate from persisted app models.
- Keep network requests out of SwiftUI views.
- Prefer pure helpers for parsing, normalization, duplicate detection, and match scoring.
- Use stable identity and lazy containers for the poster library.
- Preserve cancellation as a normal async outcome and make partial bulk-import failure non-fatal.
- Add abstractions only when they reduce real coupling, duplication, or test friction.
- Never add recommendation scoring or fake recommendation behavior as part of foundation work.

## Validation

Start with focused parser, duplicate, or matching tests when those contracts change. For app-wide, model, navigation, or project changes, run a warning-clean build and unit tests, then smoke the relevant iPad and iPhone simulator flows. State clearly when live TMDB verification was skipped because no credential was configured.
