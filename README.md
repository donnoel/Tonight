# Tonight

Tonight is an iPad-first personal movie recommendation app built with SwiftUI and SwiftData. The imported library is the source of truth for movies the user owns; TMDB is used only to enrich those entries with metadata and artwork.

The Tonight screen now produces a **Best Match**, **Wildcard**, and **Forgotten One** from resolved movies in that library. A genre mood can guide the result, immediate refreshes rotate away from recent picks, and watched/liked/disliked choices improve later recommendations. Generated picks and responses are saved locally and appear in History.

The library syncs through the same private iCloud account on iPad and iPhone. Titles, matched details, artwork references, watched/unwatched state, and movie taste are merged through CloudKit. Each device keeps its local library and a durable queue of offline changes. Artwork downloads into a persistent local cache. Settings shows sync status and **Sync Now**. Recommendation history, mood/layout settings, and the TMDB credential remain device-local.

Ambiguous titles and special editions remain visible as **Needs Match**. Select one of those movies and use **Find TMDB Match** on its detail screen to associate the correct artwork and metadata directly, or use **Match Movies** from the Library toolbar to retry safe matches in a batch before reviewing the remainder. Automatic matching recognizes common canonical-title variations, collector-edition suffixes, and uniquely confirmed TMDB alternative titles while keeping genuine remake ambiguity for confirmation. A confirmed match enriches the existing local record without replacing personal history.

Library search matches titles, years, genres, directors, and cast. **Library Options** can show all, unwatched, or watched movies and sort by title, release year, date added, runtime, rating, or last watched in either direction. Shuffle remains a one-tap toolbar action. These choices only change the grid presentation and never modify the stored collection.

On iPad, Tonight remembers whether the sidebar was visible or hidden and restores that choice on the next launch.

## Tonight's Pick widget

The medium **Tonight's Pick** widget presents one clear recommendation from the latest successfully saved set; tapping it opens the Tonight screen. The shared snapshot retains alternates so marking the displayed movie watched or not interested can promote the next eligible pick immediately.

The widget reads only a display-ready binary property-list snapshot in the `group.com.donnoel.Tonight` App Group. It does not access SwiftData, make TMDB API requests, or receive the TMDB credential. Poster data is downloaded by the main app and copied into that local snapshot when available.

## Apple $4.99 movie deals

**Deals** shows Apple’s current U.S. **Buy for $4.99** movie collection without adding those titles to the personal Library. The adaptive grid includes the verified deal price, TMDB artwork and metadata when available, and an **In Library** badge for movies Tonight already knows you own. Filters show all deals, titles not already in the Library, or deals ranked with the same local taste signals used by Tonight’s recommendation engine.

The catalog is read from Apple’s public, unauthenticated Apple TV collection page. Apple does not document this collection as a catalog API, so `AppleMovieDealsProvider` contains the page URL and minimal parsing assumptions in one replaceable boundary. Only U.S. movie links carrying the collection’s $4.99 purchase-price context are accepted. The app opens Apple’s page for any transaction; Tonight never processes a purchase.

Deal results and temporary TMDB matches are cached locally for six hours. A cached catalog appears immediately and remains usable with its last refresh time if Apple or TMDB is temporarily unavailable. The cache is disposable and is never coupled to SwiftData Library records. Unmatched Apple titles remain visible rather than disappearing.

## Requirements

- Xcode 26 or later
- iOS 18 or later
- A TMDB API Read Access Token for live import

## Configure TMDB

1. Build and run Tonight.
2. Open **Settings** in the app.
3. Under **TMDB**, paste the TMDB **API Read Access Token** and choose **Save Credential**.

Tonight stores the token as a generic-password item in the device Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. It is never written to the Xcode project, Info.plist, UserDefaults, logs, or Git, and it does not sync or migrate to another device. The app and local library remain usable without a token; attempting a live import directs the user to Settings.

After configuration, Settings keeps the credential controls collapsed. Choose **Update Credential** to reveal the secure token field again.

## Generate and build

```sh
xcodegen generate
xcodebuild -project Tonight.xcodeproj -scheme Tonight -destination 'generic/platform=iOS Simulator' build
```

Run tests on an installed simulator:

```sh
xcodebuild -project Tonight.xcodeproj -scheme Tonight \
  -destination 'platform=iOS Simulator,name=Local CI iPhone,OS=26.4' test
```

Debug builds also accept `-TonightSeedPreviewLibrary`, `-TonightSeedUnresolvedLibrary`, and `-TonightOpenDeals` as explicit launch arguments. The first two insert local fixtures only when requested; the third opens Deals directly for layout and retrieval smokes without changing normal app launches.

## Architecture

- `Models/`: SwiftData `Movie` and persisted `RecommendationEvent`
- `Recommendation/`: deterministic, explainable local scoring and three-pick selection
- `Deals/`: isolated Apple collection retrieval/parsing, disposable caching, bounded TMDB enrichment, ownership matching, and Deals screen state
- `Import/`: parsing, collector-suffix search cleanup, normalization, duplicate detection, progress state, and reliable per-title persistence
- `Library/`: unresolved matching coordination and deterministic presentation ordering
- `Sync/`: private CloudKit library synchronization, atomic local outbox, field-level merges, migration backups, and persistent artwork caching
- `TMDB/`: Bearer-authenticated URLSession client, DTOs, match scoring, rich model mapping, and centralized artwork URLs
- `Views/`: adaptive app shell, poster Library and Deals grids, persisted/reused detail, import/review/progress, unresolved-match queue, History, and Settings

TMDB requests use `GET /3/search/movie` and `GET /3/movie/{id}?append_to_response=credits,alternative_titles`. The details response supplies runtime, genres, ratings, language, artwork paths, director, primary cast, and the alternative titles used for narrow fallback confirmation without redundant requests.

General TMDB discovery outside the Deals enrichment context, streaming availability, accounts, whole-library cloud sync, AI/LLM interpretation, and advanced collaborative filtering remain intentionally deferred.
