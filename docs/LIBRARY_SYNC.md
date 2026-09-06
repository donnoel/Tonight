# Library sync

Tonight uses a private CloudKit database in `iCloud.com.donnoel.Tonight`, with a dedicated `TonightLibraryV1` zone and `LibraryMovieV1` records. This is separate from the earlier SwiftData CloudKit experiment. SwiftData's automatic CloudKit mirroring is explicitly disabled.

## What travels between devices

- Imported titles, TMDB identity, resolution status and notes, movie metadata, and poster/backdrop references.
- Watched/unwatched status and dates; movie ratings and liked/disliked signals.
- Library membership, including confirmed removals.

Recommendation events, counters, selected mood/tuning, navigation preferences, and the TMDB credential remain local. The credential stays in the device Keychain. Artwork references sync; image files download separately into a persistent, replaceable local cache with three concurrent prefetches at most. No TMDB search/details request is necessary just to receive another device's movie.

## Local safety and migration

Before opening the store with the added sync models, the app copies the original store and journals to `Library/Application Support/PreLibrarySyncBackup` in its data container. The location of the source store comes from the actual ModelConfiguration, including its App Group placement. If backup or migration fails, the app attempts to retain access to the original local model schema and disables sync.

Initial seeding also exports `library-before-sync.json` in that directory. It imports the legacy watched-state snapshot once, then stops using the old key-value sync as a writer. Movie and outbox changes commit together in SwiftData; an offline edit survives process termination and relaunch.

Resolved records use TMDB identity. Unresolved records use a stable normalized imported-title/year identity. Initial metadata prefers the more complete matched record. Watch, taste, metadata, and membership each have independent revisions with deterministic conflict ties. Default unwatched imports cannot overwrite explicit watch edits. Initial libraries are combined; an empty cloud response is never treated as a request to clear the device.

An unresolved record can merge into a resolved record only with one unambiguous imported-title/year candidate. A missing year is accepted only if that fallback still identifies a single candidate. Remakes with different known TMDB IDs remain separate. Resolution redirects preserve local movie identity and recommendation relationships, carry later offline personal-state edits forward, and prevent stale unresolved copies from reappearing. Deletions use retained tombstones, while a later explicit reimport may restore a movie.

## Delivery and status

CKSyncEngine handles automatic delivery and retries. The app requests a fetch/send/fetch cycle at launch, foreground entry, Sync Now, and after local edits, and registers for remote notifications. Background timing remains controlled by iOS. Both devices must use the same iCloud account.

Fetched merges immediately queue any resulting uploads. Confirmed records are removed from the pending engine queue before forming bounded batches, preventing stale queue entries from blocking later uploads. Upload acknowledgements do not clear a newer local edit.

Settings reports active work, pending changes, last successful sync, or actionable iCloud failures. A completed local save alone is not reported as successful cloud sync. An unexpected cloud zone deletion or incompatible record format pauses sync. Account binding prevents automatic upload of an existing library to a different iCloud account.

## Verification and recovery

The regression suite covers additive store migration, initial library union, rich metadata preservation, offline metadata/watch conflicts, unwatch, deletion/reimport, unresolved redirects and chains, ambiguous remakes, durable outbox relaunch, idempotent reconciliation, and acknowledged queue entries preceding pending uploads. Existing in-memory tests explicitly disable automatic CloudKit mirroring.

Physical-device migration backups from September 6, 2026 were also retained outside Git in `~/Library/Application Support/Tonight Migration Backups/2026-09-06/`. Both passed SQLite integrity checks and held 960 movies. The baseline iPhone had 135 watched and 808 resolved; iPad had 134 watched and 809 resolved.

For recovery, preserve both the current store and its pending edits before any restore. Do not delete the cloud zone, clear the library, or overwrite the current store as a routine retry. Original backups predate later edits; restoring them must be a deliberate recovery action. A future App Store release must validate the corresponding production CloudKit schema and signing environment separately from development-device qualification.

## September 6, 2026 device qualification

Final build: **1.0 (7)**. App, widget, and generated system Settings version row agree. Both physical devices installed and launched successfully. Warning-as-error simulator tests and signed device builds passed with zero build warnings; all **119 unit tests** passed.

The real iPhone backup was also migrated in an isolated simulator with cloud writes disabled: all 960 movies and 135 watched states remained intact. iPhone and iPad Settings layouts were inspected, including local access without an iCloud account.

After live CloudKit synchronization, independently copied databases from both physical devices passed SQLite integrity checks. Each had **960 movies, 135 watched, 809 resolved, and zero pending uploads**. The complete active synchronization payloads matched for all 960 records, including all movie details, artwork references, watched state, and revisions. The extra retained sync record is a resolution redirect, not a duplicate movie. The iPad artwork cache contained 2,420 downloaded image files during qualification; initial downloads on another device may continue separately from record synchronization.

Offline conflicts, deletion/reimport, and relaunch safety were exercised through isolated tests; no test movie was added to or deleted from the live personal library. Deliberately signing out of iCloud, exhausting account storage, production CloudKit deployment, and prolonged background-delivery timing were not exercised on the user's devices.
