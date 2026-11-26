import SwiftUI

// Stubs: the section port replaces each screen's body (keep its name and initializer). Android: ui/manage/money/CouponsScreens.kt.

struct CouponsScreen: View {
    var body: some View { StubScreen(title: "Fee waivers & coupons") }
}

struct CouponFormScreen: View {
    let route: CouponFormRoute

    var body: some View { StubScreen(title: route.id == nil ? "Create default coupon" : "Edit coupon") }
}

struct WaiverFinanceScreen: View {
    var body: some View { StubScreen(title: "Fee waiver finance") }
}
