import GoogleSignIn
import SwiftUI

@main
struct DarseQuranApp: App {
    @State private var container: AppContainer
    private let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init() {
        // Unit tests run inside the app: give them a container that touches neither the Keychain nor the network.
        if !testing { forgetSessionsFromAnEarlierInstall(KeychainStore(), defaults: .standard) }
        _container = State(initialValue: testing ? AppContainer(secureStore: MemoryStore(), defaults: UserDefaults(suiteName: "tests") ?? .standard) : AppContainer())
        Self.styleSystemControls()
    }

    var body: some Scene {
        WindowGroup {
            root
                .environment(container)
                .environment(container.toaster)
                .environment(container.cart)
                .preferredColorScheme(container.appearance.colorScheme)
                .tint(Scheme.primary)
                .onOpenURL { url in _ = GIDSignIn.sharedInstance.handle(url) }
        }
    }

    @ViewBuilder private var root: some View {
        // Unit tests build their own screens: the app's own (and its requests to the server) stay out of the way.
        if testing { Color.clear } else { appRoot }
    }

    @ViewBuilder private var appRoot: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["DQA_GALLERY"] == "1" { DesignGallery() } else { AppRoot() }
        #else
        AppRoot()
        #endif
    }

    /// Fonts for the few system controls the app keeps (alerts, menus, segmented pickers).
    private static func styleSystemControls() {
        let label = UIFont(name: FontName.sansMedium, size: 13) ?? .systemFont(ofSize: 13)
        UISegmentedControl.appearance().setTitleTextAttributes([.font: label], for: .normal)
        UIRefreshControl.appearance().tintColor = UIColor(Scheme.primary)
    }
}
