# Porting a screen from Android

The iOS app mirrors the Android app (`../learning-management-system-android`) screen by screen: same layout, colours,
fonts, spacing, wording and behaviour. Android is the source of truth; never change it. When Android's code and its
`docs/DESIGN.md` disagree, follow the code and note it in your report.

## Where things go

The folders mirror Android's packages:

| Android | iOS |
|---|---|
| `data/` (Network, SessionStore, ApiCall) | `DarseQuran/Data/` |
| `data/remote/` (AcademyApi, Models) | `DarseQuran/Data/Remote/` |
| `data/repo/` | `DarseQuran/Data/Repo/` |
| `data/staff/<section>/` | `DarseQuran/Data/Staff/<Section>/` |
| `ui/theme/`, `ui/common/`, `ui/nav/` | `DarseQuran/UI/Theme/`, `UI/Common/`, `UI/Nav/` |
| `ui/<area>/` | `DarseQuran/UI/<Area>/` |
| `app/src/test/.../ui/<area>/*Test.kt` | `DarseQuranTests/<Area>/*Tests.swift` |

Each screen already exists as a stub with a fixed name and initializer (see `UI/Nav/AppRoot.swift`, `RouteView`). Replace
the stub's body; keep its name and parameters.

## The building blocks (read them before writing a screen)

- **Theme** (`UI/Theme`): `Scheme.*` (Material colour roles, light and dark), `Brand.*` (gold, hero green, status tones,
  `cta`/`onCta`), `Typo.*` (Material type scale: `.textStyle(Typo.titleLarge)`; `Text.styled(_)` inside concatenation),
  `Radius` (12 card, 8 input/button, 16 sheet, 6 text field), `Spacing` (20 screen, 16 card), `Icon` (Material icon →
  SF Symbol; add a case there if you need one).
- **Components** (`UI/Common/Components.swift`): `BackTopBar`, `TabTopBar`, `IconButton` (always pass a VoiceOver
  label), `SectionHeader` (uppercase, last word gold), `GoldRule`, `Overline`, `AppCard` (hairline + soft shadow;
  `onClick:` makes it a button), `HeroBox` (green gradient + pattern), `StatusChip` + `statusLabel(_:kind:)` +
  `orderStatusTone` + `courseStatusTone`, `MessageState` / `EmptyState` / `ErrorState`, `SkeletonList`,
  `SkeletonBlock`, `LoadContent`, `ArabicText`, `PriceLine`, `PrimaryButton` (gold CTA, 52pt), `SecondaryButton`
  (outlined), `TextButton`, `CtaButton` (pill), `Banner`, `HairlineDivider`.
- **Inputs** (`UI/Common/Inputs.swift`): `OutlinedField` (Material outlined text field: label, error, supporting text,
  secure, multi-line via `lines:`), `ChoicePill`, `FilterChip`, `ChipRow`, `Dropdown`, `SearchField`, `SwitchRow`,
  `RadioRow`, `CheckboxRow`.
- **Screens** (`UI/Common/Scaffold.swift`): `DetailScaffold(title) { … }` (back top bar; Back pops the tab's stack),
  `ScreenColumn` (scrolling column, 20pt padding), `StickyBottomBar`, `.confirmDialog(...)`.
- **State** (`UI/Common/UiState.swift`): `Load<T>`, `Loader<T>` (LoaderViewModel), `Submitter` (SubmitViewModel),
  `PagedListModel<T>` + `PagedListBody` (PagedViewModel + PagedListBody), `.reloadOnReturn { }` (ReloadOnReturn),
  `WithModel` (builds a screen's `@Observable` model from the container once).
- **Images and text**: `RemoteImage(path:)`, `Avatar`, `LogoPlaceholder`, `HtmlText(html:serif:)`, `plainText(_)`.
- **Files and links** (`UI/Common/Files.swift`): `openWeb`, `openOutside`, `downloadAndOpen(client, path:, fileName:)`
  (QuickLook), `share([...])`, `DocumentPreview.open(url)`, `Toaster` (`toaster.show("…")`, Android's Toast/Snackbar).
- **Formatting** (`UI/Common/Format.swift`): `rupees`, `formatInr`, `formatDate`, `formatCalendarDate`,
  `formatDateTime`, `relativeTime`, `feeFrequencySuffix`, `titleCase`, `announcementCategory`, `countOf`,
  `YearMonth`, `feePeriod`, `monthlyFeeLabel`, `monthlyFeeDue`, `courseFeeText`, `linkTarget`.
- **Pay pieces** (`UI/Pay/PaymentProof.swift`, `UpiQr.swift`): `PayWithUpiButton`, `PaymentDetailsCard`,
  `PaymentDetailsError`, `PaymentConfirmFields`, `CopyRow`, `ProofImagePicker` + `ScreenshotPicker`, `QrCode`,
  `upiPaymentUri` and friends. Fee payment and book checkout both use them.
- **Data**: `AppContainer` (`@Environment(AppContainer.self)`): `repo` (AcademyRepository), `auth`, `cart`
  (CartStore), `session`, `config` (AppConfig, may be nil until loaded), `client` (APIClient, for staff APIs and
  downloads), `toaster`, `appearance`, `environment`, `switchEnvironment`. All repository calls return
  `ApiResult<T>` (`Result<T, ApiError>`; `.value`, `.error?.message`).
- **Navigation** (`@Environment(Navigator.self) var nav`): `nav.push(.course(id: …))`, `nav.pop()`,
  `nav.switchTab(.courses)`, `nav.signedIn(.cart)` (sign-in first when needed), `nav.replace(upTo:with:)`,
  `nav.openHref("/blog/x")`, `nav.openLink(href)`, `nav.shell` (student / teacher / admin / developer).
  Links inside `HtmlText` already go through `nav.openLink`.

## Conventions

- **Same words.** Copy every string from the Android screen: titles, labels, empty states, errors, button text.
- **View models**: Android's `ViewModel` + `StateFlow` becomes a `@MainActor @Observable final class` built with
  `WithModel`. Keep the same state fields and the same rules (the "newest load wins", "one request at a time", …).
- ***Rules.kt** files are pure logic: port them 1:1 as free functions or enums in the same folder, and port their
  `*RulesTest.kt` / `*Test.kt` files to XCTest in `DarseQuranTests/<Area>/`. Port the ViewModel tests too where
  they test logic (use `StubServer` from `DarseQuranTests/Support` to answer API calls; see
  `DarseQuranTests/Data/NetworkAuthTests.swift`).
- **Look**: no stock iOS lists, navigation bars, or forms where Android differs. Use the components above. Detail
  screens hide the tab bar automatically.
- **Accessibility**: VoiceOver labels on every icon-only button; Dynamic Type comes from `Typo` (don't hard-code
  `.font(.system(...))` for text); Arabic and Urdu text right to left (`ArabicText`).
- **Concurrency**: Swift 6 strict concurrency is on. No `DispatchQueue`; use `Task` / `async`.
- **Don't edit shared files** (`UI/Common`, `UI/Theme`, `UI/Nav`, `Data/` except your own `Data/Staff/<Section>`,
  `project.yml`) unless the guide for your task says so. If you need a shared helper, put it in a new file in your
  own folder. If something shared is wrong, say so in your report.

## Building and checking

```bash
scripts/build.sh                                         # generate the project and build
DEST='platform=iOS Simulator,name=<device>' scripts/build.sh test   # unit tests
```

To look at a screen, build for your simulator, then:

```bash
xcrun simctl install <device> build/dd/Build/Products/Debug-iphonesimulator/DarseQuran.app
SIMCTL_CHILD_DQA_EMAIL=… SIMCTL_CHILD_DQA_PASSWORD=… xcrun simctl launch <device> com.darsequran.academy.debug
xcrun simctl ui <device> appearance dark     # or light
xcrun simctl io <device> screenshot /path/to/shot.png
```

The debug build talks to staging. Demo accounts (one admin, teachers, students) and their passwords are in the
website repo's git-ignored `.seed-credentials.local.json`; read them from there when launching, and never print,
commit or copy them anywhere else. Never point the app at production.

Compare with the Android screenshots in `../learning-management-system-android/docs/screenshots/` and with the Android
code's layout (paddings, sizes, colours) before calling a screen done.
