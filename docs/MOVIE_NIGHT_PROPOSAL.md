# Owned-library movie-night proposal

November 23, 2026 · [GitHub #9](https://github.com/donnoel/Tonight/issues/9)

**Decision: propose one optional saved plan inside Tonight.** Try an explicit one- or two-movie plan using a runtime budget. Keep the current single Home Screen feature and All Picks during the trial. Use this if Don wants to pick out an evening ahead of time, or keep the existing flow if the extra step has little value.

Open **Plan a Movie Night** from All Picks or Tonight. Choose one movie or a double feature, then set the time available. Show the best eligible suggestion with each runtime, combined runtime, and a short reason the titles work together. Allow the user to accept, change, or clear the plan. If a pair cannot fit, offer an eligible single movie explicitly. If no movie fits, offer a different budget or a return to picks.

Use the existing locally ranked owned library. Candidates must be resolved, non-disliked, have known runtimes, and respect the current explicit mood and unwatched preferences. Apply a deterministic tie-breaker and favor complementary titles within budget. Deals, discovery results, and repeated editions of the same film stay out of pairings. Generate alternatives on demand without advancing Tonight's recommendation exposure history.

Save one plan locally as ordered library IDs, the selected budget, and a creation timestamp. Keep the plan through relaunch and offline use. On reopen, validate each ID against the current library. If a title was removed or becomes ineligible, show what's missing and allow an explicit replacement. A watched title should remain recognized as completed if the plan was still active. Leave cross-device plan sync for a later decision after the trial. The normal Choose and watched flows keep their existing semantics. Saving, replacing, or clearing a plan creates no watch or recommendation response.

If saved planning proves useful, explore an opt-in Top Shelf feature for the first unwatched planned movie. Use the existing still and exact-detail route behavior. Fall back to regular recommendations when the plan is unavailable, finished, or invalid. No automatic schedules, notifications, purchase links, or playback integration are part of this proposal.

## Acceptance for a trial

- A single or double feature fits the chosen budget, uses only eligible owned movies, and handles missing runtimes and sparse pools.
- Identical inputs produce a stable pairing and rationale. Changing the budget or eligibility produces a truthful result.
- Save, relaunch offline, replace, and clear preserve independent watched history and recommendation rotation.
- Removed and completed titles are recognized on reopen without silently changing the plan. The user chooses replacements and controls when an actual watch is recorded.
- Check the interaction with touch, Apple TV remote, VoiceOver, larger iOS text, and Reduce Motion where applicable.

The proposal is ready for a decision. An implementation trial would be separate work.
