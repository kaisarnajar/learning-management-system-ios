import SwiftUI

/// How a server answered the health check.
private enum Health: Equatable {
    case checking
    case up(ms: Int)
    case down(String)
}

/// Debug build only: choose which copy of the website the app talks to. Each server keeps its own sign-in, so switching
/// back returns to the account used there. Both servers are pinged, so a dead one is obvious before switching to it.
struct ServerScreen: View {
    var onClose: (() -> Void)? = nil
    @Environment(AppContainer.self) private var container
    @State private var health: [AppEnvironment: Health] = [:]

    var body: some View {
        DetailScaffold("Server", onBack: onClose) {
            ScreenColumn {
                Banner("This debug build can talk to either copy of the website. You stay signed in separately on each.", tone: .info)
                ForEach(AppEnvironment.available, id: \.self) { env in
                    AppCard(onClick: {
                        if env != container.environment {
                            container.switchEnvironment(env)
                            onClose?()
                        }
                    }) {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle().strokeBorder(env == container.environment ? Scheme.primary : Scheme.onSurfaceVariant, lineWidth: 2).frame(width: 20, height: 20)
                                if env == container.environment { Circle().fill(Scheme.primary).frame(width: 10, height: 10) }
                            }
                            .frame(width: 40, height: 40)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(env.label).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
                                Text(env.host).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                            }
                            Spacer()
                            switch health[env] {
                            case .up(let ms): StatusChip("\(ms) ms", tone: .success)
                            case .down(let reason): StatusChip(reason, tone: .danger)
                            default: StatusChip("Checking", tone: .neutral)
                            }
                        }
                    }
                    .accessibilityAddTraits(env == container.environment ? .isSelected : [])
                }
            }
        }
        .task {
            await withTaskGroup(of: (AppEnvironment, Health).self) { group in
                for env in AppEnvironment.available {
                    health[env] = .checking
                    group.addTask { (env, await ping(env)) }
                }
                for await (env, result) in group { health[env] = result }
            }
        }
    }
}

/// A plain request: the app's own client would send this server's sign-in token to the other one.
private func ping(_ env: AppEnvironment) async -> Health {
    guard let url = URL(string: env.baseUrl + "/api/v1/app-config") else { return .down("No URL") }
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 8
    let started = Date()
    do {
        let (_, response) = try await URLSession(configuration: config).data(from: url)
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (200..<300).contains(status) ? .up(ms: ms) : .down("HTTP \(status)")
    } catch {
        return .down((error as? URLError).map { "\($0.code)".replacingOccurrences(of: "NSURLErrorDomain", with: "") } ?? "Error")
    }
}
