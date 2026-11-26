import SwiftUI

struct BookstoreScreen: View {
    var body: some View { StubScreen(title: "Bookstore") }
}

struct BookScreen: View {
    let id: String
    var body: some View { StubScreen(title: "Book") }
}

struct CheckoutScreen: View {
    var body: some View { StubScreen(title: "Checkout") }
}

struct OrdersScreen: View {
    var body: some View { StubScreen(title: "My orders") }
}

struct OrderScreen: View {
    let id: String
    var body: some View { StubScreen(title: "Order") }
}
