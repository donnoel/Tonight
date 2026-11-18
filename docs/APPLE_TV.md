# Tonight on Apple TV

The `TonightTV` target is a native tvOS app sharing Tonight’s existing local models, recommendation engines, and private CloudKit sync. It uses poster grids, a compact row of up to three movie picks, native focusable cards, and separate Movies / TV Shows collections. Minimum deployment is tvOS 18.

Tonight uses three large portrait posters with stronger rounded movie titles and a 22-point title gap; lane/year captions and the redundant “Your movie night” heading are removed. A fixed-width left cinema rail replaces the top navigation bar: move focus vertically through Tonight, Library, Deals, History, and Settings, then right into the page. Above the posters, a compact Now Showing marquee sits alongside spaced, unboxed collection, Mood, and refresh controls. Mood and tuning share one sheet. Select a card to open its details, recommendation rationale, Choose action, and other response options. Poster focus outlines hug the artwork. Movie details use a TV-specific poster/text composition, compact primary actions, and a More menu for secondary actions; additional credits and ratings remain below the overview.

## Library setup

Use the same iCloud account as the iPhone or iPad containing the current library. Both collections fetch automatically at launch and foreground entry. **Get Libraries from iCloud**, shown on empty collections and in Settings, explicitly retries both collections and reports each sync status and local count separately.

This downloads existing CloudKit library records, including matched metadata, artwork references, personal movie state, TV ownership, episode progress, and TV viewing history. It does not open iCloud Drive text files. Add titles on iPhone or iPad; there is no manual title import on Apple TV in this milestone.

An empty fetch does not replace a populated library. Existing account isolation, independent field revisions, durable outboxes, membership tombstones, and local backups remain in use. See [movie sync](LIBRARY_SYNC.md) and [TV sync](TV_SYNC.md). [Apple documents tvOS storage as purgeable](https://developer.apple.com/library/archive/documentation/General/Conceptual/AppleTV_PG/iCloudStorage.html); the private iCloud collection is important for restoring the TV’s local copy. Keep the original imported libraries on the iPhone and iPad.

## Shared television theme

`TonightTV/AppleTVTheme.swift` owns the adaptive cinema palette, page margins, panels, page header, fixed rail, and focus styles. The focused rail item magnifies to 118%, adjacent items to 106%, and the selected item rests at 112% when focus moves into the page. A separate outline communicates focus; there is no vertical selection bar. Scale animation is scoped to rail labels, with fixed layout slots and no content shifting. Reduce Motion disables the scale tween. `AppleTVCinemaAtmosphere.swift` supplies one continuous full-screen gradient and the Now Showing marquee. Three broad colors blend through blues, red, pink, orange, and yellow over a one-minute cycle; light direction moves over 28 seconds. The movie view has spaced text controls above the cards; other sections retain their shared page header. Gradient colors adapt to light/dark appearance for text contrast. Don’s design direction is **elegant**: blended color, unhurried motion, and prominent artwork.

On Tonight’s movie page, a native gradient layer interpolates colors and direction independently of SwiftUI model updates. `AppleTVFloatingArtwork.swift` displays each poster in its final explicit 2:3 frame from entry, with unanimated layout and high-priority bitmap requests through the existing memory/disk cache. A native animation changes only layer translation (at most five points horizontally and seven vertically, staggered 32–44-second cycles). It never animates bounds, scale, or layout. Titles and focus targets stay fixed. Loaded artwork is retained when returning from details. This replaces the SwiftUI repeating animation after build 19’s physical review exposed a slow grow/shrink/rebuild cycle. Motion stops offscreen or while inactive and is disabled by Reduce Motion; Increased Contrast strengthens text/background separation. The fixed-height Now Showing marquee replaces rotating slogans; it has no timer or background work. Artwork absent from the cache still requires a download; there is no intentional entrance delay. Physical acceptance is tracked in GitHub #4.

Tonight’s movie header leaves 50 points between its row and the poster row, with eight additional points below the header content. Movie captions are centered beneath their posters. TV movie Library, TV-show Library, and Deals grids reserve consistent title and status space so cards stay the same size within each grid/filter, including short titles and entries without status badges. Deals cards omit the TMDB match-status message; the year uses TMDB metadata when available, falling back to Apple’s paginated catalog release date. Missing years are left blank rather than guessed. The optional Apple year remains cache-only, and older disposable catalogs refresh to collect it; ownership and match confidence do not change.

TV Library and Deals have explicit, readable action rows. Movie and TV History use spaced panels/cards, and Settings uses scrollable sections rather than dense full-width native form rows. iPhone/iPad keep their established presentation. Artwork crop policy, performance qualification, and deeper navigation features remain owned by their separate issues. The theme work is tracked by [#4](https://github.com/donnoel/Tonight/issues/4); physical visual acceptance is recorded there.

## Controls

- Tonight: use the collection control to select Movies or TV Shows. Use **Mood** to choose a mood and tune movie filters, and the refresh arrow for **Find My Picks** / **More Ideas**. Select a movie card for its details and response controls. Movie **Choose** records the selection and marks it watched, matching iOS behavior. It does not start playback.
- Library: search, shuffle, filter, sort, and open movie or TV details. Movie watch changes and TV viewing-state changes use the same sync path as iOS.
- TV sessions: select a time and mood, plan an owned episode session, record the first episode or full session afterward, or continue from an explicit saved position. Planning alone does not mark episodes watched.
- Deals: the separate current Apple U.S. $4.99 candidate pool, including existing ownership detection, cache fallback, and local taste ranking. Only the explicit deal page can open Apple’s purchase destination.
- History: movie choices and watched actions are device-local except synced movie watch state; TV viewing history syncs. Recommendation cards and mood/tuning preferences stay device-local.

The fixed left rail switches sections when focus rests on a button, without requiring a click. A short cancellable delay skips intermediate page loads during a quick vertical swipe. The rail never expands or shifts content during focus changes. Back from a root page returns focus to its navigation button; detail destinations keep native Back. Library search opens only after selecting Search, so entering Library does not capture focus in the TV keyboard. Native tvOS controls and card focus effects handle selection. Artwork is decorative to VoiceOver; titles and actions have semantic labels. Detail text can receive focus for remote scrolling.

On the movie-picks page, Up from any poster focuses the last-used upper-right control (Mood initially). Down from the controls returns to the same poster, or the first current poster after the set changes. The route uses stable recommendation IDs and does not select a movie or generate new picks. Modal collection/tuning controls retain native navigation. The experimental 01/02/03 caption labels are removed.

Movie details initially focus Choose for a pending pick, the watched-state action for a library movie, or the available store/More action in other contexts. Down from the onscreen Back button routes directly to that primary action; Up from Choose/watch/store routes back to Back. Native navigation between More and the primary action, scrolling, and the remote Back button remain available. These are focus routes only; entering details never chooses or marks a movie watched.

## Section switching

The rail owns focus and magnification independently of the content area. Moving its highlight does not invalidate the whole page. Each visited section retains its root page, navigation container, data state, and loaded artwork for the app session; sections are created on first use. Hidden pages are disabled, excluded from accessibility, and receive an inactive scene phase so decorative motion stops. Leaving a detail destination resets that section’s navigation stack to preserve the established return-to-root behavior.

Tonight retains its loaded recommendation state across ordinary section changes. A library-save notification invalidates hidden state (dropping potentially deleted model references), then reloads it on activation. Visible edits continue to reload immediately. Deals checks freshness on activation and retains its loaded catalog and ranking; expired catalogs still refresh normally. iPhone/iPad retain their existing loading paths.

This removes concrete repeated work found in the source; it is not a measured latency claim. The physical Time Profiler attempt on November 18 ended after about one second with Device disconnected, so physical responsiveness and a reliable instrumented comparison remain tracked in [#6](https://github.com/donnoel/Tonight/issues/6).

## TMDB credential

Receiving and recommending already matched iCloud records needs no TMDB credential. Matching and fresh Deals enrichment need a TMDB Read Access Token entered into the secure field in Settings. The value remains in this Apple TV’s device-only Keychain. It is never hard-coded, synced, displayed after saving, or stored in source/configuration.

## Top Shelf and performance

`TonightTopShelf` reads the display-only snapshot from the tvOS App Group’s `Library/Caches` directory. It displays up to **five** real owned movie suggestions under Tonight’s Picks (Weekend Picks on a weekend): current eligible pending picks first, then distinct unwatched alternatives selected locally with the same mood/tuning and recommendation engine. The app’s main three-poster layout and iOS widget remain unchanged. Supplemental shelf suggestions do not record a watch, response, or browsing exposure merely by being prepared.

Each poster uses `tonight://movie/<local-movie-UUID>`. The app validates the route, switches to Movies/Tonight, resets that page’s old navigation stack, and opens that exact library movie in a full-screen detail view. A current pending pick reuses its event; another eligible unwatched movie gets a temporary response context, persisted only after an explicit Choose/other response. Choose retains existing watched/history semantics, and Back closes to Tonight. Watched/disliked/unresolved stale items open normal library details without a fresh Choose offer; removed items show a plain unavailable message. The legacy `tonight://picks` route still opens Tonight.

The extension never opens SwiftData, obtains the TMDB key, invents recommendations, records a watch, or starts playback. tvOS owns Home-screen display and refresh timing. With no snapshot it falls back to continuous panoramic brand artwork. The small and large TV app icons use a continuous full-width cinema background with the existing separate Tonight text overlay; there is no blank black half. See [artwork sources](../TonightTV/Branding/README.md).

tvOS uses cache directories for local library files, backup markers, artwork, and disposable Deals data. iOS keeps its existing Application Support locations and file protection. A first installation records that no prior SwiftData store exists rather than failing while enumerating a nonexistent directory. Existing-store backups still copy the store and journals before opening.

TV artwork is cached as visible views request it, rather than bulk-prefetching the complete library after every CloudKit pass. Common TV artwork decode limits are smaller, the background uses a single gradient, and the physical Debug target uses Swift optimization. No before/after frame-time trace was captured; smoothness requires physical acceptance.

## Build and delivery

`project.yml` owns the target and shared version/build values; regenerate with `xcodegen generate`. The bundle identifier is `com.donnoel.Tonight`, using the existing team, iCloud container, and private zones. Local development signing and App Store production CloudKit qualification remain separate.

Read the current [fixed local target guide](/Users/donnoel/Development/DevSystem/notes/APPLE-LOCAL-TARGETS.md) before validation. There is no Apple TV simulator in the fixed local target set. Compile generically, then use the paired physical Apple TV for remote and visual acceptance. Do not create a substitute simulator.

```sh
bash scripts/local-check.sh xcodebuild -project Tonight.xcodeproj -scheme TonightTV \
  -destination 'generic/platform=tvOS' CODE_SIGNING_ALLOWED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES build
python3 /Users/donnoel/Development/DevSystem/scripts/apple-local.py run iphone -- \
  xcodebuild -project Tonight.xcodeproj -scheme Tonight \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES test
```

Physical installation/launch, commits, pushes, and distribution require authorization. Retain the signed artifact used for acceptance; a new changed device build increments the build number.

## Work tracking and owner review

[GitHub Issues](https://github.com/donnoel/Tonight/issues) owns all outstanding work. Documentation records behavior and evidence rather than maintaining a second backlog.

The November 15 sprint ended with 1.1 (11) on Living Room. Don confirmed working iCloud libraries and Library Back, preferred the compact three-pick layout, and supplied a Home-screen photo showing three Weekend Picks. Further app changes stopped at the owner's request.

| Follow-up | Owning issue |
| --- | --- |
| Consistent theme, headings, typography, and spacing across all TV pages | [#4](https://github.com/donnoel/Tonight/issues/4) |
| Faces/heads in artwork and visually level cards during focus changes | [#5](https://github.com/donnoel/Tonight/issues/5) |
| Physical-device navigation and scrolling performance | [#6](https://github.com/donnoel/Tonight/issues/6) |
| Relaunch, offline behavior, and cross-device acceptance | [#7](https://github.com/donnoel/Tonight/issues/7) |
| Opening the particular movie selected on Top Shelf | [#8](https://github.com/donnoel/Tonight/issues/8) |
| Optional weekend movie-night plan proposal | [#9](https://github.com/donnoel/Tonight/issues/9) |

Existing [TV-show card polish #1](https://github.com/donnoel/Tonight/issues/1), [public-release exploration #2](https://github.com/donnoel/Tonight/issues/2), and [Recently Added browsing #3](https://github.com/donnoel/Tonight/issues/3) remain tracked in their original issues. Consult GitHub for current state and priorities.
