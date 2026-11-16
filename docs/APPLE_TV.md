# Tonight on Apple TV

The `TonightTV` target is a native tvOS app sharing Tonight’s existing local models, recommendation engines, and private CloudKit sync. It uses poster grids, a compact row of up to three movie picks, native focusable cards, and separate Movies / TV Shows collections. Minimum deployment is tvOS 18.

## Library setup

Use the same iCloud account as the iPhone or iPad containing the current library. Both collections fetch automatically at launch and foreground entry. **Get Libraries from iCloud**, shown on empty collections and in Settings, explicitly retries both collections and reports each sync status and local count separately.

This downloads existing CloudKit library records, including matched metadata, artwork references, personal movie state, TV ownership, episode progress, and TV viewing history. It does not open iCloud Drive text files. Add titles on iPhone or iPad; there is no manual title import on Apple TV in this milestone.

An empty fetch does not replace a populated library. Existing account isolation, independent field revisions, durable outboxes, membership tombstones, and local backups remain in use. See [movie sync](LIBRARY_SYNC.md) and [TV sync](TV_SYNC.md). [Apple documents tvOS storage as purgeable](https://developer.apple.com/library/archive/documentation/General/Conceptual/AppleTV_PG/iCloudStorage.html); the private iCloud collection is important for restoring the TV’s local copy. Keep the original imported libraries on the iPhone and iPad.

## Controls

- Tonight: select Movies or TV Shows. Pick a mood, tune the movie filters, and use **Find My Picks** / **More Ideas**. Movie **Choose** records the selection and marks it watched, matching iOS behavior. It does not start playback.
- Library: search, shuffle, filter, sort, and open movie or TV details. Movie watch changes and TV viewing-state changes use the same sync path as iOS.
- TV sessions: select a time and mood, plan an owned episode session, record the first episode or full session afterward, or continue from an explicit saved position. Planning alone does not mark episodes watched.
- Deals: the separate current Apple U.S. $4.99 candidate pool, including existing ownership detection, cache fallback, and local taste ranking. Only the explicit deal page can open Apple’s purchase destination.
- History: movie choices and watched actions are device-local except synced movie watch state; TV viewing history syncs. Recommendation cards and mood/tuning preferences stay device-local.

The fixed top navigation switches sections when focus rests on a button, without requiring a click. A short cancellable delay skips intermediate page loads during a quick swipe. Back from a root page returns focus to its navigation button; detail destinations keep native Back. Library search opens only after selecting Search, so entering Library does not capture focus in the TV keyboard. Native tvOS controls and card focus effects handle selection. Artwork is decorative to VoiceOver; titles and actions have semantic labels. Detail text can receive focus for remote scrolling.

## TMDB credential

Receiving and recommending already matched iCloud records needs no TMDB credential. Matching and fresh Deals enrichment need a TMDB Read Access Token entered into the secure field in Settings. The value remains in this Apple TV’s device-only Keychain. It is never hard-coded, synced, displayed after saving, or stored in source/configuration.

## Top Shelf and performance

`TonightTopShelf` reads the same display-only snapshot format as the iOS widget, in the tvOS App Group’s `Library/Caches` directory. It displays up to three actual saved movie picks under Tonight’s Picks (Weekend Picks on a weekend). Select a poster to open the current movie picks in Tonight. The extension never opens SwiftData, obtains the TMDB key, invents recommendations, records a watch, or starts playback. tvOS owns display and refresh timing. With no snapshot, it falls back to continuous panoramic brand artwork. See [artwork source and final generation prompt](../TonightTV/Branding/README.md).

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
