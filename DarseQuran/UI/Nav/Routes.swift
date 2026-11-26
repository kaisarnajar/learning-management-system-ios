import Foundation

/// The bottom tabs. Everyone gets Home, Courses, Explore and Account; staff get one more before Account.
enum AppTab: Hashable, Sendable {
    case home, courses, explore, staff, account
}

/// Every screen that opens on top of a tab (Android's Routes.kt).
enum Route: Hashable, Sendable {
    // Courses & learning
    case course(id: String)
    case learn(courseId: String, title: String)
    case pay(courseId: String, type: String, title: String)
    case teacher(id: String)
    case teachers

    // Explore
    case blog
    case blogPost(id: String)
    case fatwa
    case fatwaDetail(id: String)
    case askFatwa
    case library
    case libraryItem(id: String)
    case announcements
    case announcement(id: String)

    // Bookstore
    case bookstore
    case book(id: String)
    case cart
    case checkout
    case orders
    case order(id: String)

    // Account
    case signIn
    case register
    case forgotPassword
    case notifications
    case editProfile
    case payments
    case waivers
    case reviews
    case changePassword
    case deleteAccount
    case contact
    case about
    case server

    // Staff (teacher, admin and developer screens; see UI/Manage/ManageRoutes.swift)
    case manage(ManageRoute)
}
