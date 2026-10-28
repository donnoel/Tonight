# TV rediscovery sessions

Familiar shows default to rediscovery. Consecutive and season-story styles offer up to two adjacent episodes from anywhere within one owned season; standalone style offers up to three individually ranked episodes. These are maximums, not a promise to fill the whole selected time budget. Shows marked new to the user always start at their next unwatched episode in order, even if their usual style is standalone. A longer pilot is never skipped just to find a shorter later episode.

## Selection and explanations

- Only matched, unpaused shows with complete owned-season metadata qualify. Mood, new-to-me, ownership, aired dates, and time budget remain hard boundaries.
- Every recommendation slot rotates. Shows not yet offered in the eligible browsing rotation receive priority, and the previous row is avoided when alternatives exist. A small collection may need to reuse a show; episode offers still rotate.
- Device-local `episodeOffers` stores the last generation in which each show/episode pair was offered. Recently offered episodes and recently logged watches are down-ranked. Offering a session never invents a watch.
- A fixed, local vocabulary detects lightweight themes in episode descriptions. Shared terms can link a session to the latest logged viewing or the selected mood. Explanations identify this as description evidence; they do not invent critical ratings, episode arcs, or knowledge of unlogged viewing.
- Tie-breaking is deterministic for a saved document and generation. No LLM, discovery feed, new service, or TMDB fetch is needed to refresh.

## Continuation and persistence

Continue Watching is separate from recommendation slots. It offers shows with an explicit saved position and creates an ordered plan within the selected time budget. Rediscovery sessions are tagged with an optional `isRediscovery` field: logging them adds normal synced viewing history while leaving that saved position alone. Continue Watching advances it normally. Partial sessions retain their tag, and undo restores the previous position.

`episodeOffers` and `sessionEngineVersion` are additive optional local fields. The first launch on the new engine regenerates suggestions while preserving show identities, ownership, personal choices, actual history, and any legacy active plan. Older active plans without the tag retain their original logging behavior. Existing viewing-style raw values and cloud payload formats remain unchanged. Offer evidence and session plans stay local; actual viewing history continues through the existing TV sync path.

The refresh action is an icon button with a minimum 44-point target, a VoiceOver label and hint, and an accessibility identifier in the upper-right TV header. The old bottom button and sync note were removed. iPad rows retain three portrait/four landscape choices; compact layouts remain a single column.

## Qualification — October 27, 2026

- Version **1.0 (57)**: app, widget, and system Settings version values agree; signed device build is warning-clean.
- **202 unit tests** cover show and episode rotation, cycle boundaries, deterministic selection, consecutive windows, first-time viewing, oversized pilots, theme evidence, watch/offer separation, saved positions, undo, partial sessions, legacy-plan migration, and existing library/sync contracts.
- iPhone and iPad simulator smokes used existing collection metadata with cloud traffic disabled. Four iPad refreshes preserved the collection, actual history, active plan and saved positions; generated plans respected ownership, time and adjacency. Continue Watching opened the existing Death Note continuation at S1 E2.
- Current physical-device TV files were exported outside Git before installation. No synthetic viewing sessions were added to the personal collection.
- Build 57 was installed and launched on Don’s iPhone and iPad. Post-launch exports verified the new engine and offer tracking on both devices, with all 39 shows, three logged sessions, existing saved plans, ownership limits, and personal settings preserved. Hands-on acceptance of the new session choices remains the user's next check.
- Live TMDB enrichment and production CloudKit deployment are outside this change. The episode-description heuristic does not establish narrative independence; the user explicitly marks whether a show is familiar and can continue it in order separately.
