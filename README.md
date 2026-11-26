# Darse Quran Academy — iOS

The native iOS app for [Darse Quran Academy](https://darsequranacademy.com). Students and visitors can browse
courses, apply and pay fees, follow their classes (updates, attendance, marks, fees), read the blog, fatwas and
library, order books, and manage their account. Teachers, admins and developers also get their staff area. It talks
to the website's `/api/v1` API.

It is a port of the [Android app](../learning-management-system-android) and looks and works the same: same screens,
colours, fonts, spacing, wording and flows. The design is written up in the Android repo's `docs/DESIGN.md`; how a
screen is ported is in [docs/PORTING.md](docs/PORTING.md).

## What is in the app

- **Home** — greeting, verse or hadith of the day, cards for anything that needs attention (complete your profile,
  verify your e-mail, a fee that is due, a payment under review), my courses, announcements, featured courses,
  blog, fatwas and books.
- **Courses** — my courses and the catalogue (search, paging); course page with fees and teacher; apply; the
  course's Updates, Attendance, Marks and Fees tabs.
- **Pay** — enrollment and monthly fees in three steps: amount (with fee-waiver coupons and month), pay (opens a
  UPI app with the amount filled in, or shows the UPI and bank details and QR code to copy or scan), confirm (UTR and
  an optional screenshot from Photos or the camera).
- **Explore** — fatwa (categories, search, ask a question), blog (likes and comments), library, bookstore
  (cart, checkout, orders), announcements, teachers.
- **Account** — notifications, payments and receipts (PDF, opened in Quick Look to view, share or save), fee-waiver
  requests, reviews, book orders, edit profile and photo, change password, light/dark/system appearance, contact,
  about, delete account.
- **Staff** — a Teach tab for teachers and an Admin (or Developer) tab for admins, with the website's admin sections.
- Sign in with e-mail and password or Google; register; forgot password; resend the verification e-mail.

Where iOS differs from Android, it is only where iOS requires it: the system share sheet and Quick Look for
documents, the system photo picker and camera, the Sign in with Google flow, and the UPI hand-off (iOS opens the UPI
app registered for `upi://`; without one, as in the Simulator, the pay step shows the details and QR code instead).

## Stack

| | |
| :--- | :--- |
| Language | Swift 6 (strict concurrency) |
| UI | SwiftUI, iOS 17+, custom components matching the Android app's Material 3 look |
| State | `@Observable` models on the main actor, one `AppContainer` for dependencies |
| Network | `URLSession` + `Codable`, one `APIClient`; access tokens refreshed in one place (`TokenRefresher` actor) |
| Storage | Keychain (one session per server), `UserDefaults` (appearance, chosen server) |
| Images | `RemoteImage` with an in-memory cache over `URLCache` |
| Sign-in | GoogleSignIn (Swift Package), sending the Google ID token to the same endpoint as Android |
| Project | [XcodeGen](https://github.com/yonaskolb/XcodeGen): `project.yml` is committed, the `.xcodeproj` is generated |

```
DarseQuran/
├── App/             DarseQuranApp, AppContainer
├── Data/            APIClient, SessionStore, Keychain, Environment, Remote/ (API + models), Repo/, Staff/
├── Resources/       fonts (Source Serif 4, Poppins, Amiri), asset catalog
└── UI/
    ├── Theme/       colours, type, shapes, icons (light and dark)
    ├── Common/      shared components, formatting, paging, files and links
    ├── Nav/         routes, tabs, link router
    └── Home/ Courses/ Pay/ Explore/ Bookstore/ Account/ Auth/ Teach/ Manage/
DarseQuranTests/     XCTest, with URLProtocol stubs (Support/StubServer.swift) for the API
```

## Building

You need Xcode (with the iOS Simulator runtime) and XcodeGen (`brew install xcodegen`).

```bash
xcodegen generate             # makes DarseQuran.xcodeproj from project.yml
open DarseQuran.xcodeproj
```

Or from the command line (generates the project, builds, and prints only problems):

```bash
scripts/build.sh
DEST='platform=iOS Simulator,name=iPhone 17' scripts/build.sh test
```

Optional settings go in `Config/Local.xcconfig` (not committed; copy `Config/Local.example.xcconfig`):

```
// The staging website the debug build talks to (default: the current Vercel staging deployment).
STAGING_BASE_URL_OVERRIDE = https:/$()/staging.example.com
// Google Sign-In. Without them the "Continue with Google" button is hidden.
GOOGLE_IOS_CLIENT_ID = 1234567890-ios.apps.googleusercontent.com
GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.1234567890-ios
GOOGLE_SERVER_CLIENT_ID = 1234567890-web.apps.googleusercontent.com
```

(`//` starts a comment in an xcconfig, hence `https:/$()/`.) The server client ID is the Web client ID Android uses
as `GOOGLE_WEB_CLIENT_ID`, so the ID token is issued for the audience the website checks.

### Which server a build talks to

There are two builds, which can be installed side by side:

| Build | Server | App name (bundle id) | Used for |
|---|---|---|---|
| Debug | staging, or production after switching | DQA (debug) (`com.darsequran.academy.debug`) | development; never shared |
| Release | production only | Darse Quran Academy (`com.darsequran.academy`) | the published app |

The debug build starts on staging. Switch servers in **Account → Server** (or tap the STAGING strip); you stay signed
in separately on each. The release build has no switch and doesn't even contain the staging URL.

Test on **staging**: never test against production. While on staging, the app shows an orange STAGING strip at the
top.

Staging's demo seed (`ALLOW_DEMO_SEED` on the website) gives you students, courses, payments and content to try the
app with. To try paying, set a UPI ID in the website's admin payment settings; for checkout, books need stock.

For checking screens without typing, debug builds read optional launch variables:

```bash
SIMCTL_CHILD_DQA_EMAIL=… SIMCTL_CHILD_DQA_PASSWORD=… xcrun simctl launch booted com.darsequran.academy.debug  # sign in
SIMCTL_CHILD_DQA_SIGN_OUT=1 xcrun simctl launch booted com.darsequran.academy.debug                         # sign out
SIMCTL_CHILD_DQA_GALLERY=1 xcrun simctl launch booted com.darsequran.academy.debug                          # design gallery
SIMCTL_CHILD_DQA_OPEN=/admin/finance xcrun simctl launch booted com.darsequran.academy.debug               # open a website path
```

Links open the app through the custom scheme `darsequran://` with the website's paths, e.g.
`darsequran://blog/<id>` or `darsequran://profile/payments` (universal links can come later).

### Release builds

Release builds need an Apple Developer account for signing; nothing for signing is committed (`*.p12`,
provisioning profiles and `GoogleService-Info.plist` are git-ignored). Archive the **DarseQuran** scheme (Release) from
Xcode once signing is set up.
