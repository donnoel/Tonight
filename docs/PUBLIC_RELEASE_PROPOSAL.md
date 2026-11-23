# Tonight public release proposal

November 23, 2026 · [GitHub #2](https://github.com/donnoel/Tonight/issues/2)

**Decision: hold public distribution.** Prepare a free, ad-free iPhone and iPad release centered on importing an owned library, matching movies or TV shows, and getting a first pick. Keep the iPhone/iPad widget in scope if it passes release checks. Defer public tvOS distribution, Deals, and external Apple TV movie lookup until their data sources, rights, and device coverage are ready. Existing private builds can continue to use their current features.

## Metadata and rights

Confirm in writing that the intended distribution, regions, metadata, and artwork are covered. TMDB's developer API is free for attributed noncommercial use. If the project becomes commercial, obtain the applicable license and quote before proceeding. Use the approved TMDB logo and required notice in About or Credits, and verify font, prominence, and attribution requirements in the final design. Confirm cache lifetime and artwork redistribution rights, including any widget surfaces. [TMDB FAQ and attribution](https://developer.themoviedb.org/docs/faq) · [Apple App Review Guidelines §5.2](https://developer.apple.com/app-store/review/guidelines/#intellectual-property)

| Approach | Implication |
| --- | --- |
| Current device-local TMDB token | Keeps personal credentials in Keychain. Suitable for private use, but requires customers and reviewers to obtain and paste their own key. |
| Shared credential in the public app | A packaged credential is extractable. Abuse, rate limits, and revocation would affect the whole installation base. |
| Licensed lookup service | Keeps the service credential server-side and lets customers match without a TMDB account. Adds availability, operating costs, and privacy obligations. |

Choose the licensed lookup service if the rights and budget are approved. Expose only bounded search and details operations. Allowlisted parameters, rate limits, request throttling, and revocable client access protect the upstream quota. Cache only licensed responses with vendor-approved expiration. Separate operational aggregates from queries, disable raw title and token logging, and document any edge-provider IP retention. Back off on rate limits and preserve unresolved rows through outages so users can retry. Test rotation and revocation without requiring an app update. Serve artwork from the approved CDN unless the license requires another arrangement.

Use a metadata-client abstraction to preserve the private build's Keychain path. Retain existing matches, imported titles, timestamps, and history on upgrade. Public builds should prefer the new service without uploading, migrating, or revealing anyone's old credential. Explicit user removal can clear a stored legacy key.

## First run and review

Start with a simple choice to import movies or TV shows. Show a short format example and offer paste or text-file import where supported. Show the review, duplicate, ambiguous, and unresolved states, then produce a recommendation after the first eligible result. A user without iCloud can still use the local library. If offline or interrupted, retain completed imports and allow matching to resume.

Remove personal 39-show shortcuts and copy from the public flow. Audit user-facing defaults and Release bundle resources, including prepared lists, sample assets, and debug tools. Keep season ownership an explicit input. Defer a consumer demo library. Give App Review a small rights-cleared sample text file and instructions to import, match, and choose using a release build with the service enabled. Use a clean test account with no personal data to demonstrate widget and sync behavior. If review requires a separate demo mode, agree on the approach with Apple first. [App Review information](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review)

## Privacy and distribution

| Data flow | Current behavior and release review |
| --- | --- |
| Local app and iOS App Group | Movie titles, match metadata, viewing preferences and history, TV ownership and progress, pending changes, backups, and a display-only widget snapshot are stored locally. Define retention, user-controlled cleanup, and shared-cache behavior. |
| Private CloudKit | Movies, TV ownership, viewing state, and queued updates sync through the user's private database. Verify account isolation, offline catch-up, migrations, deletion, and production entitlements on independent accounts. |
| TMDB and artwork | Matching sends individual title and identity queries and fetches metadata and artwork. Current credentials are device-local. For the public service, verify the vendor and host's processing, logs, retention, and disclosure obligations. |
| Apple storefront | Private Deals copies a U.S. web collection into a disposable cache and opens Apple URLs. Private tvOS movie details can query public Apple listings for exact matches. Exclude each from the proposed launch until permitted data access, locale and price handling, and app-review treatment are confirmed. |

The source tree currently has no `PrivacyInfo.xcprivacy`. Audit the app and widget binaries for required-reason APIs, starting with `UserDefaults`/`AppStorage` and file-metadata access. Declare only reasons that fit actual use and inspect the aggregate Xcode privacy report for the archive. Audit the tvOS app and Top Shelf bundled targets before their separate release. Use the data-flow inventory to draft privacy policy and disclosures, with special attention to vendor and service logging and whether any information is retained or linked. [Required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) · [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)

Deals is a U.S. storefront parser. The private build already handles stale catalogs and retrieval failures, but that does not establish the right to use the source for a distributed app, coverage for other currencies, or stable markup. To reconsider, obtain permission or a documented feed, validate price, region, refresh timestamps and safe stale behavior, and verify any applicable external purchase-link rules. [Apple App Review Guidelines §§3.1 and 5.2](https://developer.apple.com/app-store/review/guidelines/)

## Cost and release sequence

- Apple lists the standard Developer Program at US$99 annually. A small metered worker has a published US$5/month paid-plan baseline as an example. With 100 beta users, two monthly imports each, and 50 uncached inputs per import, plan for about 10,000 searches and up to 10,000 details calls per month before gains from caching. Licensing, storage, monitoring, and support are separate. Budget requires a vendor quote and a measured pilot. [Apple enrollment](https://developer.apple.com/help/account/membership/program-enrollment) · [Example compute pricing](https://developers.cloudflare.com/workers/platform/pricing/)
- Confirm rights and budgets first. Then implement the bounded metadata service and verify its usage and privacy controls.
- Build public first-run flows, remove personal defaults, and qualify empty, offline, interrupted-import, no-iCloud, and accessibility paths on iPhone and iPad.
- Review privacy manifests, service data flows, disclosures, support and privacy URLs, and age rating, regions, pricing, screenshots, description, and reviewer notes.
- After authorization, qualify production signing and the additive CloudKit schema. Run TestFlight clean-install and upgrade passes with independent iCloud accounts before any public submission. [CloudKit production schema](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema)

Those four steps are candidate follow-up issues if Don approves the public-release direction. This proposal completes the exploration. Licensing, paid services, production changes, TestFlight, and App Store submission are later decisions.
