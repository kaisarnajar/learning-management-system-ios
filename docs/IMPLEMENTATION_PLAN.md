# Implementation plan for the 2026-11-26 code review

Each row is one small commit on `dev`, in the order they were made. Every commit builds and passes the unit tests.
The findings are described in [CODE_REVIEW.md](CODE_REVIEW.md).

| # | Issues | Severity | Affected | Change | Depends on | Commit message |
|---|---|---|---|---|---|---|
| 1 | — | — | docs | The review findings and this plan | — | `docs: code review findings and implementation plan` |
| 2 | H1 | High | Admin payment and book-order screenshots | `APIClient.authorizedData`; `ImageLoader` fetches `/api/files/private/` through it, outside the disk cache; memory cleared on user change | — | `fix(images): private payment screenshots load with the signed-in token` |
| 3 | H2 | High | Home, course page, Learn, Courses tab, admin lists | `ReloadOnReturn` tracks visibility | — | `fix(common): a covered screen reloads when it is shown again, not when the app comes back` |
| 4 | M1 | Medium | Every API answer | `@Default` takes the default only for null or missing values; tests | — | `fix(data): a value of the wrong type is reported, not replaced by a default` |
| 5 | M2, L21 | Medium, Low | Downloads, all requests | `url(_:)` throws instead of force-unwrapping; the refused answer is dropped before a retry | — | `fix(network): a bad file path fails the download instead of crashing the app` |
| 6 | M3, L27 | Medium, Low | App start, unit tests | Clear stored sessions on the first launch after install; the test host shows no app screens; tests | — | `fix(app): a fresh install starts signed out, and unit tests don't start the app's screens` |
| 7 | M4 | Medium | Pay | `PaySavedState` persisted per course and fee type, cleared after submitting; test | — | `fix(pay): the chosen waiver, month and year survive iOS ending the app during payment` |
| 8 | L10 | Low | Contact, review, waiver, sign-up, checkout, admin forms | `jsLength` and `jsPrefix(_:)`; counters and caps use them; tests | — | `fix(forms): lengths are counted as the website counts them` |
| 9 | M5 | Medium | Every filtered text field, grade marks, comments | `Binding.shown` and `.correctsRefusedEdits` | 8 | `fix(forms): a field never shows text its filter refused` |
| 10 | M6 | Medium | Edit profile photo | Toast when a chosen photo can't be read | — | `fix(account): a photo that can't be read says so` |
| 11 | M7, L16 | Medium, Low | Admin book orders | The card isn't a button; the actions are flow-row items | 8 | `fix(admin): book order actions reachable with VoiceOver and wrapping like Android` |
| 12 | L1 | Low | Session observers | Observers with an owner are dropped once the owner is gone; test | — | `fix(data): screens stop listening to the session when they close` |
| 13 | L2, L3 | Low | Pay | `+` encoded in the UPI link; QR code cached; test | — | `fix(pay): a plus in the UPI note survives, and the QR code is built once` |
| 14 | L4, L5 | Low | Home | Badge uses `Typo.labelSmall`; Home uses Account's `ResendState` | — | `refactor(home): the badge follows Dynamic Type and Home shares ResendState` |
| 15 | L8, L9, L11 | Low | Explore, Bookstore, Account | Filled icons as on Android, decorative icons hidden from VoiceOver, no pull-to-refresh on a fatwa | 9 | `fix(parity): Explore and bookstore icons as on Android, decorative icons hidden from VoiceOver` |
| 16 | L13 | Low | Fee waivers | Coupon font | 8 | `fix(account): the waiver coupon is 16pt monospaced and scales` |
| 17 | L14 | Low | Server (debug) | Trim `/`, one session, total timeout | — | `fix(server): the server check reuses one session and trims the address` |
| 18 | L17 | Low | Admin finance, coupons | No literal "null" | — | `fix(admin): no "null" for a missing order number or name` |
| 19 | L19, L22, L23, L28, L30 | Low | App shell | Refresh on cold launch; edge-swipe delegate on the tab stacks only; Android's wording; bars and Dynamic Type; the strip pushes Server | — | `fix(nav): app shell matches Android and leaves system navigation controllers alone` |
| 20 | L20 | Low | Checkout | Cart restore runs to the end | — | `fix(cart): books left out of an order are put back even if checkout closes` |
| 21 | L24 | Low | Article links | Toast when no app opens a link | — | `fix(links): mail and phone links say when no app can open them` |
| 22 | L25 | Low | Register | Terms and Privacy as VoiceOver actions | 8 | `fix(auth): VoiceOver can open the terms and privacy links on Register` |
| 23 | L29 | Low | Home | Saved home read off the main thread | — | `perf(home): the saved home screen is read off the main thread` |
| 24 | L26 | Low | Build, CI | Commit `Package.resolved`, add it to the CI cache key | — | `chore: pin Swift package versions with Package.resolved` |

## No change, with the reason

These are explained in [CODE_REVIEW.md](CODE_REVIEW.md): L6 and L7 (Pay), L12 (Explore hub), L15 (book-order alerts),
L18 (audit log filters) and L31 (tests that already exist).

## Verification

After each commit:

```bash
DEST='platform=iOS Simulator,name=iPhone 18 Pro' scripts/build.sh test
```

At the end, the changed screens were checked on the Simulator against staging:
- Explore icons.
- Pay: the QR code, and the reference field's filter.
- A smoke run of 31 screens, for the stricter JSON decoding.

The Android app needed no changes.
