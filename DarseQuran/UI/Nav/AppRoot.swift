import SwiftUI
import UIKit

/// The app's root: the staging strip, the tabs and their stacks, the bottom bar (Android's AppRoot).
///
/// A new server, role or user starts a fresh navigation: nothing from the previous one carries over (after a student
/// signs out, the tab stacks would otherwise bring back the previous student's screens and data).
struct AppRoot: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        let shell = Shell.of(container.session?.user.role)
        VStack(spacing: 0) {
            if container.environment != .production {
                EnvironmentStrip(env: container.environment)
            }
            AppContent(shell: shell)
                .id("\(container.environment.key)-\(shell.rawValue)-\(container.session?.user.id ?? "guest")")
        }
        .background(Scheme.background)
        .overlay { ToastOverlay() }
        .task { await container.loadConfig() }
    }
}

private struct AppContent: View {
    @Environment(AppContainer.self) private var container
    @State private var nav: Navigator
    @Environment(\.scenePhase) private var phase

    init(shell: Shell) { _nav = State(initialValue: Navigator(shell: shell)) }

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(nav.shell.tabs, id: \.self) { tab in
                TabStack(tab: tab)
                    .opacity(nav.tab == tab ? 1 : 0)
                    .allowsHitTesting(nav.tab == tab)
                    .accessibilityHidden(nav.tab != tab)
                    .safeAreaPadding(.bottom, nav.tab == tab && nav.showsTabBar ? BottomBar.height : 0)
            }
            if nav.showsTabBar {
                BottomBar().transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: nav.showsTabBar)
        .environment(nav)
        .environment(\.openLink) { href in nav.openLink(href) }
        .onAppear {
            let app = container // lives as long as the app
            nav.isSignedIn = { app.session != nil }
            nav.toast = { app.toaster.show($0) }
            #if DEBUG
            // Debug builds: SIMCTL_CHILD_DQA_OPEN=/admin/students opens a website path on launch (for screen checks).
            if let path = ProcessInfo.processInfo.environment["DQA_OPEN"], !path.isEmpty {
                Task { try? await Task.sleep(for: .seconds(1.5)); nav.openHref(path) }
            }
            #endif
        }
        // As the website's /auth/continue: a Google sign-in with an incomplete profile goes on to the profile form.
        .onChange(of: container.googleWelcomePending, initial: true) { _, pending in
            if pending { container.googleWelcomePending = false; nav.push(.editProfile) }
        }
        .onChange(of: phase) { _, new in if new == .active { container.refreshUserIfStale() } }
        // Light status bar text over a dark hero; on staging the amber strip sits there instead (always light).
        .onChange(of: nav.heroUnderStatusBar || container.environment != .production, initial: true) { _, light in
            StatusBar.light = light
        }
        .onOpenURL { url in
            guard let path = pathForIncomingURL(url) else { return }
            if !nav.openHref(path) { nav.toast("This page isn't in the app yet.") }
        }
    }
}

/// One tab's stack of screens.
private struct TabStack: View {
    let tab: AppTab
    @Environment(Navigator.self) private var nav

    var body: some View {
        NavigationStack(path: nav.path(tab)) {
            TabRoot(tab: tab)
                .navigationDestination(for: Route.self) { route in
                    RouteView(route: route)
                        .toolbar(.hidden, for: .navigationBar)
                }
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

/// The first screen of each tab.
private struct TabRoot: View {
    let tab: AppTab
    @Environment(Navigator.self) private var nav

    var body: some View {
        switch tab {
        case .home: HomeScreen()
        case .courses: CoursesScreen()
        case .explore: ExploreScreen()
        case .account: AccountScreen()
        case .staff:
            if nav.shell.adminPanel { AdminDashboardScreen() } else { TeachHomeScreen() }
        }
    }
}

/// Every screen that opens on top of a tab.
struct RouteView: View {
    let route: Route

    var body: some View {
        Group {
            switch route {
            case .course(let id): CourseDetailScreen(courseId: id)
            case .learn(let courseId, let title): LearnScreen(courseId: courseId, title: title)
            case .pay(let courseId, let type, let title): PayScreen(courseId: courseId, type: type, title: title)
            case .teacher(let id): TeacherScreen(id: id)
            case .teachers: TeachersScreen()
            case .blog: BlogListScreen()
            case .blogPost(let id): BlogPostScreen(id: id)
            case .fatwa: FatwaListScreen()
            case .fatwaDetail(let id): FatwaDetailScreen(id: id)
            case .askFatwa: AskFatwaScreen()
            case .library: LibraryListScreen()
            case .libraryItem(let id): LibraryItemScreen(id: id)
            case .announcements: AnnouncementsScreen()
            case .announcement(let id): AnnouncementScreen(id: id)
            case .bookstore: BookstoreScreen()
            case .book(let id): BookScreen(id: id)
            case .cart: CartScreen()
            case .checkout: CheckoutScreen()
            case .orders: OrdersScreen()
            case .order(let id): OrderScreen(id: id)
            case .signIn: SignInScreen()
            case .register: RegisterScreen()
            case .forgotPassword: ForgotPasswordScreen()
            case .notifications: NotificationsScreen()
            case .editProfile: EditProfileScreen()
            case .payments: PaymentsScreen()
            case .waivers: WaiversScreen()
            case .reviews: ReviewsScreen()
            case .changePassword: ChangePasswordScreen()
            case .deleteAccount: DeleteAccountScreen()
            case .contact: ContactScreen()
            case .about: AboutScreen()
            case .server:
                if AppEnvironment.isDebugBuild { ServerScreen() } else { EmptyView() }
            case .manage(let r): ManageDestination(route: r)
            }
        }
        .background(Scheme.background.ignoresSafeArea())
    }
}

/// Material 3's NavigationBar: white, 80pt, a pill indicator behind the selected icon, labels under the icons.
struct BottomBar: View {
    static let height: CGFloat = 80
    @Environment(Navigator.self) private var nav

    var body: some View {
        HStack(spacing: 0) {
            ForEach(nav.shell.tabs, id: \.self) { tab in
                let item = TabItem.of(tab, shell: nav.shell)
                let selected = nav.tab == tab
                Button { nav.switchTab(tab) } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Capsule().fill(selected ? Scheme.secondaryContainer : .clear).frame(width: 64, height: 32)
                            (selected ? item.selectedIcon : item.icon).image
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(selected ? Scheme.onSecondaryContainer : Scheme.onSurfaceVariant)
                        }
                        Text(item.label)
                            .textStyle(Typo.labelMedium)
                            .foregroundStyle(selected ? Scheme.secondary : Scheme.onSurfaceVariant)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: Self.height)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.label)
                .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Self.height)
        .background(Scheme.surfaceContainerLowest.ignoresSafeArea(edges: .bottom))
    }
}

struct TabItem {
    let label: String
    let icon: Icon
    let selectedIcon: Icon

    static func of(_ tab: AppTab, shell: Shell) -> TabItem {
        switch tab {
        case .home: TabItem(label: "Home", icon: .home, selectedIcon: .homeFilled)
        case .courses: TabItem(label: "Courses", icon: .courses, selectedIcon: .coursesFilled)
        case .explore: TabItem(label: "Explore", icon: .explore, selectedIcon: .exploreFilled)
        case .account: TabItem(label: "Account", icon: .account, selectedIcon: .accountFilled)
        case .staff:
            shell == .teacher
                ? TabItem(label: "Teach", icon: .teach, selectedIcon: .teachFilled)
                : TabItem(label: shell.staffLabel, icon: .dashboard, selectedIcon: .dashboardFilled)
        }
    }
}

/// A thin band above everything while the debug build is on staging, so test data is never mistaken for real.
/// Tapping it opens the Server screen.
struct EnvironmentStrip: View {
    let env: AppEnvironment
    @Environment(AppContainer.self) private var container
    @State private var showServer = false

    var body: some View {
        Button { showServer = true } label: {
            HStack(spacing: 6) {
                Icon.server.image.font(.system(size: 10, weight: .semibold))
                Text("\(env.label.uppercased()) · \(env.host)").textStyle(Typo.labelSmall).lineLimit(1).truncationMode(.tail)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 3)
            .frame(maxWidth: .infinity)
            .background(Brand.stagingAmber.ignoresSafeArea(edges: .top))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Connected to \(env.label) server. Opens server settings.")
        .sheet(isPresented: $showServer) {
            NavigationStack { ServerScreen(onClose: { showServer = false }) }
                .environment(container)
        }
    }
}

// Keeps the edge swipe back working while the system navigation bar is hidden (the app draws its own top bars).
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
