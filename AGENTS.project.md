# Tonight Project Guide for Agents

## Product intent

Tonight is a personal movie recommendation app. Its defining product rule is that recommendations come from the user's own imported movie library. TMDB enriches that library with metadata and artwork; it never decides what the user owns and must not become the library source of truth.

Success for the current milestone means the established library remains reliable while Tonight produces explainable, responsive recommendations from resolved movies the user owns and can separately rank Apple’s current U.S. $4.99 purchase collection without treating deals as owned movies.

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
- Local, explainable recommendation selection with controlled randomness
- Human mood profiles, optional tuning choices, rotating recommendation lanes, and recent-session cooldown
- Persisted recommendation responses and movie-level watched/liked/disliked taste signals
- A medium WidgetKit widget showing the top persisted Tonight recommendation
- A disposable, cached Apple $4.99 Deals catalog with TMDB enrichment, ownership badges, and taste-based ranking
- Functional Tonight, Library, Deals, History, and Settings screens

Explicitly out of scope:

- AI/LLM integration
- Free-form mood interpretation, collaborative filtering, or cloud-trained personalization
- TMDB discovery outside imported titles and the explicit current Apple Deals enrichment context
- Streaming availability, accounts, CloudKit/iCloud, social features, reviews, trailers, external ratings, and purchase/rental links outside the explicit Apple $4.99 deal link

## Architecture snapshot

- `TonightApp` owns the root SwiftData model container for `Movie` and `RecommendationEvent`.
- `AppRootView` uses `NavigationSplitView` on regular width and a native `TabView` adaptation on compact width.
- The regular-width sidebar visibility is a display-only `AppStorage` preference and must restore its last visible or hidden state after relaunch.
- SwiftData `Movie` records represent both enriched and unresolved personal-library entries.
- `RecommendationEngine` combines a human mood profile with runtime, watch state, era, language, quality evidence, cast/director familiarity, local response history, and controlled randomness from a credible shortlist.
- Each recommendation set contains a Best Fit plus two rotating lanes such as Hidden Gem, Short & Sharp, Comfort Rewatch, Different Decade, Deep Cut, or Wildcard.
- `RecommendationEvent` records each generated pick, its selected mood, and the user’s accepted, rejected, not-tonight, or watched response.
- The `TonightWidgetExtension` reads a compact App Group snapshot published by the app; it never opens SwiftData or receives the TMDB credential.
- `MovieImportParser`, `MovieTitleNormalizer`, `LibraryDuplicateDetector`, `MovieMatcher`, and `LibrarySort` are deterministic logic boundaries.
- `TMDBClient` owns URLSession requests and maps dedicated TMDB DTOs into rich local movie values.
- `TMDBMatchResolver` combines deterministic search-result matching with a narrow alternative-title confirmation from the selected movie-details response.
- `AppleMovieDealsProvider` is the only boundary that knows Apple’s public collection URL and page structure; it emits normalized deal records and verifies the collection/link price context.
- `MovieDealsRepository` loads the disposable cache, reuses existing library/cached metadata, and performs bounded TMDB enrichment outside views.
- `DealsViewModel` loads cached results immediately, enforces a six-hour refresh lifetime, and preserves cached results with a visible warning when refresh fails.
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
- Normal Tonight recommendations must select only resolved, non-disliked records already present in the local library.
- Deal recommendations are the sole exception: their candidate pool is the current Apple $4.99 catalog, while the personal library and recommendation history remain the taste source.
- Deal refreshes must never insert, update, or delete personal-library records.
- Apple deals without a confident TMDB match remain visible; one failed enrichment must not prevent the remaining catalog from loading.
- An In Library badge may use exact TMDB identity or a unique normalized title/year fallback, but must not guess when ownership is ambiguous.
- Mood profiles must describe a viewing feeling rather than act as exact genre filters; runtime, era, quality, familiarity, and watch state contribute alongside genre.
- Under Two Hours and Unwatched Only are hard tuning filters; Something Older and More Adventurous are ranking and lane preferences.
- Best Fit balances explicit taste, mood, watch state, quality evidence, and recency; the other two lanes must truthfully match their displayed perspective.
- Refreshing should avoid movies from the five most recent recommendation sessions when the eligible library is large enough.
- Not Tonight is a temporary, decaying penalty; Not Interested remains a user-controlled exclusion.
- A recommendation set should reduce repeated genres, directors, principal cast, and decades when credible alternatives exist.
- Recommendation responses and watched/liked/disliked taste signals must persist locally and remain user-controlled.
- Choosing a recommendation for tonight must immediately mark that movie watched while preserving the accepted response in History.
- The widget must show the top eligible pick from the latest successfully saved recommendation set, promote an alternate after watched or rejected movies are removed, and degrade to a useful empty state when no snapshot is available.

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
- Share only display-ready recommendation snapshots with the widget through `group.com.donnoel.Tonight`; the app’s SwiftData store remains authoritative.
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
- Recommendation selection: resolved-only eligibility, distinct picks, human mood scoring, tuning filters, rotating lanes, diversity, disliked exclusion, fixed-seed reproducibility, five-session cooldown, and decaying Not Tonight behavior
- Recommendation persistence: generated events with mood, responses, and watched/liked/disliked signals survive relaunch
- Widget snapshot persistence: binary property-list round trip, pick removal, empty state, artwork fallback, and app-to-widget refresh
- Apple deal parsing: expected collection identity, verified $4.99 purchase links, order, duplicate IDs, changed markup, and valid empty catalogs using local fixtures rather than the live site
- Deals behavior: disposable cache round-trip, cached fallback, missing-credential preservation, bounded TMDB handoff, In Library detection, and recommendation candidate ranking

## Build and run notes

- Project: `Tonight.xcodeproj`
- Scheme: `Tonight`
- Widget target: `TonightWidgetExtension` (`systemMedium` only)
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
- Exercise every mood and tuning option against a varied resolved library, confirm rotating lanes remain truthful, refresh repeatedly to verify cooldown/diversity, record each response type, and verify History and relaunch persistence.
- Open Deals on iPad and iPhone, verify the live or cached catalog, poster enrichment, All/Not in Library/Recommended filters, manual refresh, Apple link behavior, and graceful offline/format-change messaging.
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
