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
- For a fix, feature, build, or refactor, carry the smallest in-scope local change through investigation, implementation, and relevant non-destructive validation without step-by-step approval. Make routine technical decisions and give progress updates instead of permission requests.
- Commit, push, deploy, message others, add dependencies, make purchases, perform destructive actions or other external writes, or change system/live state only when explicitly requested or approved. Authorization for the named action and target carries through the task; ask again only if the target, scope, or risk materially changes.
- Investigate technical uncertainty before asking. Pause only for a consequential unresolved product, safety, or scope decision, or missing authorization for the actions above. Complete safe preparation before asking once, and preserve mandatory platform confirmations and project-specific release gates.

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
- Keep recommendation scoring local, deterministic, and explainable. Normal Tonight picks remain limited to resolved movies in the user’s own library; the Deals screen may rank only its explicit current Apple $4.99 candidate pool while still learning taste from the personal library. Never substitute fake picks or general TMDB discovery.

## Validation

Start with focused parser, duplicate, or matching tests when those contracts change. For app-wide, model, navigation, or project changes, run a warning-clean build and unit tests, then smoke the relevant iPad and iPhone simulator flows. State clearly when live TMDB verification was skipped because no credential was configured.
