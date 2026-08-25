# Tonight Project Guide for Agents

## Product intent

Tonight is a personal movie recommendation app. Its defining product rule is that recommendations come from the user's own imported movie library. TMDB enriches that library with metadata and artwork; it never decides what the user owns and must not become the library source of truth.

Success for the current milestone means the established library remains reliable while Tonight produces explainable, responsive recommendations from resolved movies the user owns and learns from their local taste and response history.

## Current product phase

Tonight is in its first recommendation milestone, built on the completed local-library foundation.

Current scope:

- Native SwiftUI app for iPad and iPhone, with iPad-first navigation and layout
- Local SwiftData movie library
- Paste, parse, review, and bulk-import workflow
- Bearer-token TMDB search, matching, details, credits, and artwork enrichment
- Duplicate prevention and preserved unresolved/failed entries
- Safe automatic retry and user-confirmed TMDB matching for unresolved entries
- Local Library ordering by title, release year, or an explicitly reshuffled order
- Local, deterministic Best Match, Wildcard, and Forgotten One selection
- Genre mood preference, immediate refresh rotation, and explainable recommendation reasons
- Persisted recommendation responses and movie-level watched/liked/disliked taste signals
- Functional Tonight, Library, History, and Settings screens

Explicitly out of scope:

- AI/LLM integration
- Free-form mood interpretation, advanced collaborative filtering, or cloud-trained personalization
- TMDB discovery outside imported titles
- Streaming availability, accounts, CloudKit/iCloud, social features, reviews, trailers, external ratings, and purchase/rental links

## Architecture snapshot

- `TonightApp` owns the root SwiftData model container for `Movie` and `RecommendationEvent`.
- `AppRootView` uses `NavigationSplitView` on regular width and a native `TabView` adaptation on compact width.
- The regular-width sidebar visibility is a display-only `AppStorage` preference and must restore its last visible or hidden state after relaunch.
- SwiftData `Movie` records represent both enriched and unresolved personal-library entries.
- `RecommendationEngine` ranks eligible resolved movies using local taste, watch state, TMDB quality evidence, library age, and recommendation recency while keeping the three recommendation kinds distinct.
- `RecommendationEvent` records each generated pick and the user’s accepted, rejected, not-tonight, or watched response.
- `MovieImportParser`, `MovieTitleNormalizer`, `LibraryDuplicateDetector`, `MovieMatcher`, and `LibrarySort` are deterministic logic boundaries.
- `TMDBClient` owns URLSession requests and maps dedicated TMDB DTOs into rich local movie values.
- `TMDBMatchResolver` combines deterministic search-result matching with a narrow alternative-title confirmation from the selected movie-details response.
- `ImportViewModel` coordinates review state, per-entry progress, partial failure handling, and SwiftData insertion.
- `UnresolvedMatchViewModel` retries only unambiguous results and coordinates editable, user-confirmed matching into existing movie records.
- Views read already-persisted details and never refetch TMDB merely because a detail screen opens.

## Behavior invariants

- The local imported library is the source of truth for owned movies.
- TMDB is metadata enrichment only.
- Never silently discard an imported title because it is ambiguous, not found, unauthenticated, offline, or failed.
- Do not blindly accept the first search result when meaningful ambiguity remains.
- Automatic matching may treat leading articles, `and`, common number words/digits, and trailing Roman numerals/digits as equivalent title forms.
- When equivalent search results collide, popularity and vote evidence may reject an obscure duplicate, but established remakes must remain ambiguous without a supplied year.
- Alternative titles may resolve a no-match or scored ambiguity only when exactly one of the top relevant candidates confirms the imported title; direct same-title ambiguity must remain unresolved.
- A matched TMDB ID is the strongest duplicate key; normalized title plus year is the pre-resolution fallback.
- Importing the same library twice must not create duplicate movies.
- Failure for one title must not terminate the rest of a bulk import.
- Authentication and rate-limit failures are batch-level failures: stop without creating one failed library record per title.
- Automatic rematching must still reject meaningful ambiguity; manual matching requires an explicit candidate choice and confirmation.
- Resolving a match enriches the existing record in place and preserves personal history fields.
- A missing TMDB credential must not prevent app launch or local library access.
- Never print or show the TMDB credential.
- Stored rich metadata should power library/detail UI without redundant detail requests.
- Library sorting and shuffling change presentation order only; they must not rewrite movie records or personal history.
- Clearing the library requires explicit confirmation.
- Recommendations must select only resolved, non-disliked records already present in the local library.
- Best Match balances explicit taste, watch state, quality evidence, and recency; Wildcard favors a credible change of pace; Forgotten One resurfaces long-waiting, under-recommended titles.
- Refreshing should rotate away from immediately repeated picks when the eligible library is large enough.
- Recommendation responses and watched/liked/disliked taste signals must persist locally and remain user-controlled.

## TMDB boundary

- Authentication uses the TMDB API Read Access Token as a Bearer token.
- The user enters the token in Settings; store it as a generic-password Keychain item with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` accessibility.
- Never place the token in source, project configuration, Info.plist, UserDefaults, logs, or Git. Never reveal the saved value in the UI.
- Keychain access failures must leave the local library usable and produce an actionable user-facing state.
- Supported API work is imported-title search plus full details with credits and alternative titles, using append-to-response where it prevents redundant calls.
- Image URL construction stays centralized and uses context-appropriate poster/backdrop sizes.
- Treat missing credentials, 401/403 responses, transport errors, non-2xx responses, and decoding failures as explicit user-facing states without exposing request secrets.

## Persistence and concurrency rules

- Keep SwiftData access and UI-observed import state on the main actor.
- Keep TMDB request/DTO work outside views and safe to call with async/await.
- Save useful progress during a bulk import so one later failure does not roll back earlier successes.
- Preserve and update personal history fields deliberately: watched state/dates, rating, liked/disliked, recommendation count, and recommendation dates.
- Do not add CloudKit or account assumptions to the model until separately designed.

## UX and accessibility rules

- Prioritize artwork, typography, generous regular-width spacing, and native navigation.
- Use an adaptive poster grid; unresolved entries need a clear non-artwork state.
- Keep A–Z, Z–A, chronological year, and shuffle available from a native, accessible Library toolbar menu.
- Keep configured TMDB settings compact; reveal the secure token field only while adding or explicitly updating the credential.
- Honor the user’s last iPad sidebar visibility instead of forcing the sidebar open on every launch.
- Keep import progress textual as well as visual so status never relies only on color or an icon.
- Use semantic buttons and native controls, useful accessibility labels/hints, Dynamic Type text styles, and sufficiently large tap targets.
- Keep empty, loading, failure, and missing-configuration states plain-language and actionable.
- Preserve dark and light appearance without hard-coded backgrounds that reduce readability.

## Testing priorities

- Import parsing: whitespace, empty lines, duplicate input, year extraction, and basic comma separation
- Duplicate detection: TMDB ID first, normalized title/year fallback
- TMDB matching: exact and canonical-equivalent titles, mainstream/obscure duplicate ranking, remakes/ambiguous titles, supplied-year selection, alternative-title confirmation, and no-match behavior
- Unresolved matching: safe title cleanup, unique exact results, ambiguous-result confirmation, and in-place enrichment
- Library ordering: title directions, known-year chronology with unknown years last, and stable explicit shuffle ranks
- Bulk import: one-item failure does not prevent later entries, and unresolved input is preserved
- Persistence/startup: saved library survives container recreation/relaunch
- UI restoration: regular-width sidebar visible and hidden choices each survive relaunch
- Recommendation selection: resolved-only eligibility, distinct picks, genre preference, disliked exclusion, refresh rotation, and forgotten-title resurfacing
- Recommendation persistence: generated events, responses, and watched/liked/disliked signals survive relaunch

## Build and run notes

- Project: `Tonight.xcodeproj`
- Scheme: `Tonight`
- Platforms: iPadOS and iOS (`TARGETED_DEVICE_FAMILY = 1,2`)
- Deployment target: iOS 18.0
- Toolchain baseline at project creation: Xcode 26.6 / Swift 6.3.3
- The Xcode project is generated from `project.yml`; persistent build or signing changes belong there rather than only in the generated `.xcodeproj`.
- Automatic device signing uses development team `H7LG8SK72M`; the team identifier is not a credential or private key.
- Warning policy: zero warnings caused by Tonight code
- Generic build: `xcodebuild -project Tonight.xcodeproj -scheme Tonight -destination 'generic/platform=iOS Simulator' clean build`
- Tests: `xcodebuild -project Tonight.xcodeproj -scheme Tonight -destination 'platform=iOS Simulator,name=Local CI iPhone,OS=26.4' test`

## Release-level milestone checks

- Launch and navigate on both iPad and iPhone simulators.
- Exercise editor-to-review import with a substantial list.
- Verify the missing-token path without a credential.
- With a Keychain-configured credential, verify an obvious match, rich details/credits, poster/backdrop loading, unresolved preservation, duplicate re-import, and relaunch persistence.
- Verify automatic retry resolves only unambiguous entries and the one-by-one queue supports editing a query, choosing a candidate, skipping, and relaunch persistence.
- Verify Library A–Z, Z–A, year, and repeated shuffle ordering on both regular and compact widths.
- Generate all three recommendation kinds from a varied resolved library, refresh to rotate picks, record each response type, and verify History and relaunch persistence.
- Re-check VoiceOver labels, Dynamic Type, light/dark appearance, and destructive confirmation.

## Output expectations per patch

Provide:

- Summary of change
- Major files modified
- Validation performed and exact result
- Migration or persistence considerations
- Accessibility notes for user-facing work
- Anything skipped or unverified
- Commit message suggestion when useful
