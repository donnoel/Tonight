# TV library and viewing-history sync

TV uses the existing private `iCloud.com.donnoel.Tonight` container, a separate `TonightTVLibraryV1` record zone, and `TVLibraryItemV1` payload records. Movie records, the movie SwiftData schema, the movie sync engine, and the widget remain separate.

## Synced and local state

Shows, TMDB identity, metadata/artwork references, owned seasons, viewing styles, previously-seen state, favorites, paused recommendations, episode position, and explicitly logged viewing sessions sync. Session plans, recommendation cards/rotation, mood/time filters, and iPad/iPhone layout choices stay local. Artwork is retrieved from its synced public references through the existing cache. TMDB credentials remain in each device's Keychain and are never present in sync records.

## Migration and persistence

Before enabling sync, the original `Library/Application Support/Tonight/tv-library.json` is preserved beside it as `tv-library.json.pre-sync-backup`. The existing per-save `.backup` also remains in use. The TV document stores data, outbound records, account binding, and CKSyncEngine state together in one atomic file. Local saves commit their outbound revisions at the same time as the visible change, including offline edits and history undo.

Initial collections merge by TMDB show identity. Each device retains its own local show UUIDs; cloud identities and history relationships use stable keys. Initial season restrictions are intersected rather than widened, while later explicit ownership edits use their own revisions. Empty cloud results never clear a populated local collection.

Metadata, ownership, viewing style, familiarity, favorite/pause choices, episode position, and membership have separate revisions. Metadata enrichment cannot reset a watch position. Episode metadata combines completed downloads, while owned seasons remain the eligibility boundary. A monotonic local revision clock incorporates downloaded revisions before stamping the next edit.

Each logged viewing session has a stable UUID and its own cloud record, so sessions from both devices combine without duplicating the same event. Undo retains a history tombstone and publishes the restored episode position. Show removals retain membership tombstones; a later explicit reimport can restore a show. Unambiguous unresolved-to-resolved links retain redirects, while known remake ambiguity stays separate.

## Delivery, account safety, and recovery

CKSyncEngine schedules automatic work. The app also requests fetch/send/fetch passes at launch, foreground entry, after local changes, on remote notifications, and from **Settings → iCloud TV Library → Sync TV Now**. Background timing is controlled by iOS; both devices must use the same iCloud account. Settings reports pending edits, last successful sync, and actionable failures.

Uploads acknowledge only the exact record sent, preserving newer edits made during an upload. Conflict records merge and requeue. A changed iCloud account cannot receive the existing account's TV library. Unexpected hard deletions, an unsupported payload, or a missing established zone pause sync with local data retained. Normal retry never deletes or recreates established cloud data. Individual payloads are limited below CloudKit's record-size ceiling; an oversized show remains local with a visible sync error.

Keep current files, pending edits, and the pre-sync backup before attempting recovery. Do not overwrite live files or delete the zone as a routine retry. Development-device qualification does not deploy or verify a production CloudKit schema.

## Validation

`TVSyncTests` covers initial union and permanent backup, preserved local identity, metadata/progress conflicts, ownership restrictions and explicit changes, history union and undo, remote progress, stale planned sessions, deletion/reimport, upload acknowledgement races, relaunch/outbox durability, device-local preferences, resolution redirects, remake ambiguity, account binding, unsupported formats, and merge determinism.

### Device qualification — October 24, 2026

- Build **1.0 (54)** passed all **192 unit tests**, with zero build warnings, and was installed and launched on Don’s iPhone and iPad. App, widget, and system Settings version values agree.
- Both physical devices converged to the same 39 cloud show payloads, representing 2,959 cached episodes, with zero pending changes and an **Up to date** status.
- A reversible Cosmos favorite edit propagated from iPhone to iPad; restoring it on iPad propagated back to iPhone. Both devices were then relaunched without the qualification flag. Final snapshots match the original personal settings, local show identities, ownership limits, and empty viewing history.
- Original TV files were exported outside Git before migration, in addition to the permanent on-device pre-sync backups. The three partial-season restrictions remain intact.
- Settings and Movies/TV navigation were inspected on iPhone and iPad simulators with TV cloud traffic explicitly disabled. History merge/undo and progress propagation were validated with isolated fixtures; no synthetic watched sessions were added to the personal library. Live account switching, cloud-zone loss, and production CloudKit schema deployment were not exercised.

The implementation follows Apple's [CKSyncEngine guidance](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5) and [record-size limits](https://developer.apple.com/documentation/cloudkit/ckrecord). The app handles its own conflict resolution, durable persistence, and account isolation.
