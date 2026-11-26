# Code review: the iOS app compared with Android (2026-11-26)

The iOS app was reviewed in full against the Android app (`../learning-management-system-android`, branch `dev` at
`ba5a278`), which is the reference for behaviour, wording and look. Both apps were run side by side on the iOS
Simulator (iPhone 18 Pro, iOS 27.2) and the Android Emulator (API 37) against staging.

How it was done:

- Five areas were compared file by file, both sides read in full:
  1. data layer, auth and app shell
  2. Home, Courses and Pay
  3. Explore, Bookstore and Account
  4. staff area part 1: money, bookstore admin, students, dashboard
  5. staff area part 2: Teach, course admin, content, people, shared forms
- Every finding was checked against the code on both sides before it was accepted.
- Shared screens were compared on the two simulators: Explore, the course catalogue, Home and Pay. A smoke run then
  opened 31 screens on staging with the fixed build (every admin section, the student's own pages and the bookstore).

**Overall.** The port is close. Endpoints, parameters, JSON fields, wording, layout, spacing, colours, validation, the
"one request at a time" and "newest load wins" rules, and navigation targets all match. Every Android unit test has an
iOS counterpart. The findings below are what didn't match, plus bugs found in the iOS code itself.

There were no Critical findings.

| Severity | Found | Fixed | No change (reason given) |
|---|---|---|---|
| Critical | 0 | 0 | 0 |
| High | 2 | 2 | 0 |
| Medium | 7 | 7 | 0 |
| Low | 31 | 25 | 6 |
| **Total** | **40** | **34** | **6** |

The plan, with a commit for each fix, is in [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md).

## High

**H1. Private payment screenshots never load.**
- **Where:** `UI/Common/Images.swift`, used by the payment and book-order screenshot views in `UI/Manage/Money/MoneyCommon.swift` and `UI/Manage/Bookstore/BookOrdersAdmin.swift`.
- **Problem:** `ImageLoader` fetched every picture with a plain `URLSession`, without the Bearer token. Payment screenshots live under `/api/files/private/...`, and the website refuses those with a 401 unless a viewer is signed in. So admins saw the placeholder instead of the proof.
- **Android:** Coil uses the app's authorized OkHttp client (`AcademyApp.kt`, `Network.kt`).
- **Fix:** private pictures are now fetched through `APIClient` (token for the academy host only, one refresh on a 401). They stay out of the shared disk cache, and the in-memory copies are dropped when the user changes.

**H2. Screens under another screen reload at the wrong time.**
- **Where:** `UI/Common/UiState.swift` (`ReloadOnReturn`), used by Home, the course page, Learn, the Courses tab and admin lists.
- **Problem:** a screen covered by Pay still saw the app come back from the UPI app. It reloaded while hidden and cleared its "away" flag. When Pay was popped it then didn't reload, so the course page, Learn's Fees tab and Home kept offering "Pay the enrollment fee" after the payment was sent. Every hidden tab also reloaded on every return to the app.
- **Android:** a covered destination stays CREATED; it reloads only when shown again.
- **Fix:** `ReloadOnReturn` tracks whether it is visible. A hidden screen keeps "away" set and reloads when it appears.

## Medium

**M1. Wrong-typed JSON was silently replaced by defaults.**
- **Where:** `Data/Remote/Defaults.swift`.
- **Problem:** `@Default` used `try?`, so a value of the wrong type became its default. A price sent as text showed as "Free", and one malformed course emptied a whole list.
- **Android:** `coerceInputValues` only replaces null; other mismatches fail and are reported.
- **Fix:** only null or missing values take the default. Wrong types now fail with the app's usual "The server's answer wasn't what this app expects" message. Tests were added.

**M2. A server file path could crash the app.**
- **Where:** `Data/APIClient.swift` `url(_:)` (`URLComponents(string:)!`, `components.url!`).
- **Problem:** a download path with spaces or Urdu letters crashed the app.
- **Fix:** `url(_:)` falls back to percent-encoding, then throws `URLError(.badURL)`, which the caller already turns into "Couldn't download the file".

**M3. The sign-in survived deleting and reinstalling the app.**
- **Where:** `Data/Keychain.swift`, `App/DarseQuranApp.swift`.
- **Problem:** Keychain items outlive the app.
- **Android:** uninstalling wipes the app's data, and backup is off.
- **Fix:** a first launch after install clears the stored sessions for every server. The flag that marks the install lives in UserDefaults, which an uninstall removes. A test was added.

**M4. Pay screen choices were lost if iOS ended the app during the UPI hand-off.**
- **Where:** `UI/Pay/PayScreen.swift` (`PaySavedState`).
- **Problem:** the state only lived in memory, so the "same waiver, month and year after coming back" rule only held in a unit test.
- **Fix:** the choices are written to UserDefaults per course and fee type. Opening the same payment again brings them back, and they are forgotten once the payment is submitted. A test was added.

**M5. Filtered text fields showed text that wouldn't be saved.**
- **Where:**
  - `UI/Common/Inputs.swift` (`OutlinedField`), and every field built on it: `FormTextField` length caps, `FormNumberField`, `FormMoneyField`, the pay reference, the checkout PIN and phone, the Verse & Hadith Arabic text.
  - `UI/Manage/Courses/CourseGrades.swift` (the marks field).
  - `UI/Explore/ExploreScreens.swift` (the comment field).
- **Problem:** when a binding refused an edit (a third decimal, a letter in a number, past the length cap), the stored value didn't change, so SwiftUI kept showing the refused text. Save then sent something different from what was on screen.
- **Android:** Compose always redraws from the stored value.
- **Fix:** a shared `Binding.shown(_:)` and `.correctsRefusedEdits` pair puts the field back to the stored text. Checked in the Simulator: typing `AB-12/3` into the reference field shows `AB123`.

**M6. A photo that couldn't be read failed silently.**
- **Where:** `UI/Account/AccountWidgets.swift`.
- **Problem:** choosing an unreadable photo did nothing.
- **Android:** it shows "That photo couldn't be read. Try another one."
- **Fix:** the same toast. A cancelled camera still stays silent.

**M7. VoiceOver couldn't reach the order buttons on a book-order card.**
- **Where:** `UI/Manage/Bookstore/BookOrdersAdmin.swift`.
- **Problem:** Approve, Decline, Ship, Refund and Void sat inside the card's own `Button`, which VoiceOver reads as one element.
- **Fix:** the card is no longer a button. A tap anywhere else, or the VoiceOver action "Open order", opens the order.

## Low

| ID | Finding | Where | Resolution |
|---|---|---|---|
| L1 | Session observers were never removed. Every course page or blog post opened added one for the life of the app. | `Data/SessionStore.swift`; Home, Courses, Blog models | Fixed: an observer with an owner is dropped once the owner is gone. Test added. |
| L2 | A `+` in the UPI app link wasn't encoded, so UPI apps read it as a space. | `UI/Pay/UpiQr.swift` | Fixed: sent as `%2B`, as Android's `Uri.Builder` does. Test added. |
| L3 | The QR code was rebuilt, with a new `CIContext`, on every render. | `UI/Pay/UpiQr.swift` | Fixed: the last code is cached by its text. |
| L4 | The unread badge had a hard-coded font size and didn't follow Dynamic Type. | `UI/Home/HomeScreen.swift` | Fixed: `Typo.labelSmall`. |
| L5 | Home had its own copy of `ResendState`. | `UI/Home/HomeModel.swift` | Fixed: Home uses Account's `ResendState`, as on Android. |
| L6 | "Attach payment screenshot" asks "Choose from photos" or "Take a photo" first; Android opens the picker. | `UI/Pay/PaymentProof.swift` | No change: the camera is a deliberate iOS addition (README, "Where iOS differs"). |
| L7 | `@State private var proof = ProofImagePicker()` runs its initializer on every parent update. | `UI/Pay/PayScreen.swift` | No change: SwiftUI keeps the first instance, the initializer does no work, and moving it would change working code for no gain. |
| L8 | Icons didn't match Android: Explore hub tiles weren't filled; Bookstore was a bag rather than a storefront; Teachers wasn't "Groups"; "Question sent" wasn't "QuestionAnswer"; Shipped wasn't "LocalShipping"; the order card wasn't a filled bag. | `UI/Explore`, `UI/Bookstore`, `UI/Theme/Icons.swift` | Fixed. |
| L9 | Decorative icons were read aloud by VoiceOver. | Explore hub, fatwa answer, announcement location, order card, profile complete | Fixed: `accessibilityHidden(true)`. |
| L10 | Length limits counted characters, where Android and the website count UTF-16 units. Text with emoji passed on iOS and was then refused by the server. | Contact, review, waiver, sign-up, checkout and admin forms | Fixed: `jsLength` and `jsPrefix(_:)`. Tests added. |
| L11 | Fatwa detail had pull-to-refresh; Android doesn't. | `UI/Explore/ExploreScreens.swift` | Fixed: removed. |
| L12 | Explore hub titles shrink to fit; Android wraps them, breaking "Announcement/s" mid-word. | `UI/Explore/ExploreScreens.swift` | No change: same function and layout, and iOS avoids the broken word. |
| L13 | The waiver coupon used a hard-coded 17pt system font. | `UI/Account/WaiverScreens.swift` | Fixed: 16pt monospaced bold (`.callout`) that scales. |
| L14 | The Server screen's ping didn't trim a trailing `/`, leaked one `URLSession` per ping, and had no total timeout. | `UI/Account/ServerScreen.swift` | Fixed. |
| L15 | Book-order confirmations use the system alert, not the Material dialog. | `UI/Manage/Bookstore/BookOrdersAdmin.swift` | No change: every confirmation in the iOS app (`confirmDialog`) is the system alert, so this one is consistent. |
| L16 | Order action buttons sat in one row and couldn't wrap one at a time. | `UI/Manage/Bookstore/BookOrdersAdmin.swift` | Fixed: each button is its own flow-row item, as with Android's `FlowRow`. |
| L17 | The literal text "null" appeared for a missing order number (bookstore finance) and a missing name ("For" on a coupon). Android has the same bug. | `UI/Manage/Money` | Fixed on iOS. Android is left as is: this task doesn't change the Android app. |
| L18 | Setting an entity id in the audit log keeps the entity chip and actor search; Android starts the list over. | `UI/Manage/People/AuditLog.swift` | No change: keeping the admin's filters loses nothing. Recorded here as a deliberate difference. |
| L19 | The role and profile refresh didn't run on a cold launch. | `UI/Nav/AppRoot.swift` | Fixed: `onChange(of: phase, initial: true)`, like Android's `onStart`. |
| L20 | Cancelling the caller could stop the cart restore after an order and drop the left-out books. | `Data/Repo/CartStore.swift` | Fixed: it runs to the end, like Android's `NonCancellable`. |
| L21 | A download retried after a 401 left its first temporary file behind. | `Data/APIClient.swift` | Fixed. |
| L22 | A category override of `UINavigationController.viewDidLoad` changed every navigation controller, including the camera, Quick Look and the share sheet. | `UI/Nav/AppRoot.swift` | Fixed: a small representable sets the edge-swipe delegate on the tab stacks only. |
| L23 | A `darsequran://` link to a path with no screen said "This page isn't in the app yet." | `UI/Nav/AppRoot.swift` | Fixed wording: "This section opens on the website for now.", as on Android. The scheme stays (README). |
| L24 | `mailto:` and `tel:` links in articles gave no feedback when no app could open them. | `UI/Nav/Navigator.swift`, `UI/Common/Files.swift` | Fixed: "No app on this phone can open this link." |
| L25 | On Register, VoiceOver couldn't open the Terms and Privacy links on their own. | `UI/Auth/AuthScreens.swift` | Fixed: both are offered as VoiceOver actions. |
| L26 | GoogleSignIn and its dependencies weren't pinned (no committed `Package.resolved`). | `.gitignore`, CI | Fixed: `Package.resolved` is committed and is part of the CI cache key. |
| L27 | Unit tests ran the real app screens in the test host, which called staging. | `App/DarseQuranApp.swift` | Fixed: the test host shows an empty view. |
| L28 | Top bars and the bottom bar had fixed heights, so large text sizes clipped. | `UI/Common/Components.swift`, `UI/Nav/AppRoot.swift` | Fixed: top bars grow; tab labels stop growing at `xxLarge`. |
| L29 | The saved home screen was read from disk on the main thread at cold start. | `Data/Repo/AcademyRepository.swift` | Fixed: read off the main thread. |
| L30 | The staging strip opened the Server screen as a sheet, with a 10pt icon. | `UI/Nav/AppRoot.swift` | Fixed: it pushes the Server screen, as Android does, with a 14pt icon. |
| L31 | Reported as missing tests: CartSession, SplitTitle, LoadMore, ReloadOnReturn. | `DarseQuranTests` | No change: the first three already exist (`CartStoreTests`, `StatusLabelTests`, `PagedListModelTests`). ReloadOnReturn is a Compose UI test on Android; on iOS it was checked in the Simulator. |

## Found during implementation

- Caching the QR code in view state first left the code blank, because Canvas read the state outside `body`. This was
  caught in the Simulator before it was committed and replaced by the per-text cache in L3.
- Typing several characters in one injected burst straight after a refused one can drop the burst in the Simulator.
  Typing at human speed and pasting both work. Left as is and noted here.

## What could not be checked

- **H1 on a real screenshot.** Staging had no payment with a screenshot during the test, so the fix is covered by the
  code path and the build, not by an image on screen.
- **Signed-in Android screens.** The website's seed credentials could not be read in this session. Android was compared
  as a guest; iOS used the staging session already on the Simulator.
- **The Register consent row.** Whether a tap on a link also ticks the box needs a signed-out device. The VoiceOver
  part (L25) is fixed.
