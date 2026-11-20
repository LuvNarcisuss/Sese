# Pull-to-refresh verification

## Behavior and scope

All five root data screens now support manual refresh. Scrollable content/detail screens with reloadable data also have a refresh control. A completion message is shown only after the relevant loads finish; failures keep the last available content where possible and offer another pull. Empty lists remain vertically scrollable. The same search/filter/category and unsent text remain selected.

`ContentScrollView` allows a drag that starts on a button, image-card target, avatar, or map pin to cancel that button's touch tracking and become scrolling. The original plain `UIScrollView` could stop dragging after a control began tracking the touch, so holding briefly on a card before pulling would not reach the refresh control. This matches the default behavior documented by [Apple for touchesShouldCancel(in:)](https://developer.apple.com/documentation/uikit/uiscrollview/touchesshouldcancel(in:)).

`PageRefresh` owns the indicator, completion/failure feedback, duplicate-pull guard, and a bounded waiting state. Each page completes it from its existing asynchronous load. Leaving a page ends its visible refresh state. New list loads cancel superseded loads. The final app retains the existing native UIKit architecture and current app identity.

| Route | Reloaded data |
| --- | --- |
| Shorts | Pull down to reload the catalog, reactions and counts and start a new order within the active filter. Prefer unseen clips until the round is exhausted. Swiping up from the last clip starts the next lap. A quick downward flick on later clips goes back. A sole eligible clip keeps playing. |
| Shorts search | The same data, retaining search text and scope. |
| Comments | Stored comment rows and the matching count, retaining the draft. Shorts opens comments at medium height. Swipe up to expand or drag the grabber down to return to medium height. Pull to refresh at medium height. Done closes the sheet. Either author link opens the full-screen profile. Back restores the eligible discussion, its draft and its selected height. The underlying feed ignores pull gestures while a modal is presented. |
| Community videos | Approved member works. |
| Member video | Current work metadata/status and reactions for approved work. No automatic source playback. |
| Districts | Remote district guides and the existing local wallet/unlock/build state. |
| District exploration/place | Locally persisted visit state; these pages do not imply remote synchronization. |
| Cosplay | Editorial catalog, saved state, community posts, and own posts. One refresh waits for the entire group. |
| Catalog detail | Current item metadata and viewer reactions. |
| Cosplay post | Current post metadata/status, photo bytes, or video reaction totals. Pulling does not automatically present a video player. |
| Chats | Inbox and mutual-friend list, retaining Friends/Conversations/Archived scope. |
| Members | Discoverable profiles and follow relationships, retaining search/scope. |
| Conversation | Latest messages and mutual-follow eligibility, preserving the text/photo composer. |
| Chat photo | Attachment bytes. |
| Me/member profile (including a Shorts publisher) | Profile, metrics, relations, authored work, and available collections. Category switches still only rerender the collection region. |
| Wallet | Local balance/history, unfinished-transaction recovery, and StoreKit product prices. Loading ends after recovery and catalog work finish; the existing price timeout remains. |
| Blocked members | The signed-in account's block list. |
| Media credits | Current catalog credits, replacing rather than appending rows. |

Entry, Settings, agreement readers, and compose/edit/build forms do not represent reloadable lists. They retain their existing actions and form state; no decorative refresh action was added to them.

## Reproduction and environment

The original Shorts pull test failed because pulling did not initiate a reload or acknowledge completion: `/private/tmp/SeseRefreshBaseline.xcresult`. After the Shorts repair, the same test passed: `/private/tmp/SeseRefreshShorts.xcresult`.

The initial ordinary-page gesture test also reproduced a failure when a pull started over an image-card button. The shared scroll-view cancellation fix made that same gesture load data on both populated and empty pages. Subsequent test-harness corrections narrowed same-named tab/content buttons and waited for the initial comment count before comparing it.

Final verification uses the current workspace, scheme Sese, Debug Bundle ID `com.sese.citycommunit`, iOS 26.0 on Sese UI Acceptance (iPhone 17 Pro), UDID `0E1EA5DB-DDE2-460C-A8C9-C5E400CF1B96`, with parallel UI testing disabled. The workspace identity changed to the owner-selected Bundle ID during this task; it was preserved. Earlier reproduction artifacts used the prior Debug installation and are historical evidence only.

`UITests/PullRefreshAcceptanceTests.swift` exercises real drag gestures, waits for a new successful completion rather than a previous message, and retains screenshots for each route. Wallet verification uses the local StoreKit configuration, compares the balance before/after, and checks that no purchase was created. It does not certify Apple's sandbox or production catalog.

## Coverage limits

The current acceptance account has no discoverable other member, existing conversation/attachment, authored member video, or cosplay post. Those detail routes have refresh implementations and build/static coverage, but no populated end-to-end verification in this run. Production member records, relationships, messages, and published content were not created to fill these routes. Transport failures and timeouts have explicit completion paths; no device-wide network outage was induced during this run.

## Executed acceptance

In `/private/tmp/SeseRefreshAcceptance.xcresult`, these three cases passed, covering 24 successful manual refreshes:

- `testCosplayChatsAndMembersRefresh`: four Cosplay scopes, catalog detail, four Chats scopes, Members and Following.
- `testDistrictMapAndPlacesRefresh`: city map, district exploration, place detail, and return to the city map.
- `testProfileCollectionsWalletAndSettingsListsRefresh`: five profile category checks, wallet, blocked members, and two successive media-credit loads. The profile checks target content buttons rather than same-named tab items.

The Shorts case in that run exposed the discussion sheet dismissal conflict and is superseded by the later focused runs. `/private/tmp/SeseRefreshSheet.xcresult` passed `testShortsCreatorSearchAndCommentsRefresh`: two Shorts pulls, creator, three consecutive comment pulls, search, and community videos. It also compared video-region frames two seconds apart with the discussion open, confirmed the medium-height sheet, and checked the count remained 24 after each reload. Screenshot inspection then identified overlap between search feedback and filter controls; feedback was moved into its own header row, with a new non-overlap assertion.

The final focused rerun in `/private/tmp/SeseRefreshFinalShorts.xcresult` passed with zero failures (95.120 seconds). It repeated all eight Shorts-related pulls on the latest build, verified that search feedback does not overlap the filter row, retained the search query, repeated the discussion playback/count checks, and returned to the Shorts feed. The exported final search screenshot was visually inspected and confirms the separate feedback row.

Across the three passing ordinary-page cases and the final focused Shorts case, all four acceptance cases have passed, covering 32 route/state refresh checks. This is evidence from the relevant runs, not a claim that the earlier mixed-result bundle was entirely successful. The latest `build-for-testing` succeeded, and `git diff --check` reported no whitespace errors. The final build remains installed on the named acceptance simulator.

## Shorts rotation and continuous paging

On November 18, 2026, three serial UI tests passed on Sese UI Acceptance (iPhone 17 Pro, iOS 26.0.1) with the online catalog. With four eligible Shorts, consecutive pulls showed all four before a repeat. The next pull changed the visible clip. Eight upward swipes completed two full laps, and a pull from a later clip selected a different video. With one eligible film clip, a pull and an upward swipe kept the same clip playing. The existing creator, comments, playback, search and community-video refresh test also passed. Result bundle: `/private/tmp/sese-shorts-loop.ejVUhe/Final.xcresult`.

The resizable Shorts discussion and full-screen author route have static source and syntax checks only. The updated UI regression covers author navigation from both sheet heights.
