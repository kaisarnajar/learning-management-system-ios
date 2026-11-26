import SwiftUI
import UIKit

/// Decoded images kept in memory, and their bytes on disk through URLCache (Android uses Coil for the same).
actor ImageLoader {
    static let shared = ImageLoader()

    nonisolated(unsafe) private let memory = NSCache<NSURL, UIImage>()
    private var running: [URL: Task<UIImage?, Never>] = [:]
    private let session: URLSession
    /// Fetches a private picture as the signed-in user (set by AppContainer to its APIClient).
    private var authorized: (@Sendable (URL) async throws -> Data)?

    func useAuthorizedFetch(_ fetch: @escaping @Sendable (URL) async throws -> Data) { authorized = fetch }

    /// Private pictures (payment screenshots) need the viewer's token, and must not go into the shared disk cache.
    nonisolated static func isPrivate(_ url: URL) -> Bool { url.path.hasPrefix("/api/files/private/") }

    /// Forgets the pictures in memory (another user signed in: they must not see the last one's private pictures).
    nonisolated func forgetMemory() { memory.removeAllObjects() }

    init() {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 200 << 20, directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("images"))
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
        memory.totalCostLimit = 64 << 20
    }

    nonisolated func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func image(_ url: URL) async -> UIImage? {
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        if let task = running[url] { return await task.value }
        let session = self.session
        let authorized = Self.isPrivate(url) ? self.authorized : nil
        let task = Task<UIImage?, Never> {
            let bytes: Data?
            if let authorized {
                bytes = try? await authorized(url)
            } else if let (data, response) = try? await session.data(from: url),
                      (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true {
                bytes = data
            } else {
                bytes = nil
            }
            guard let bytes, let image = UIImage(data: bytes) else { return nil }
            // Decode now, off the main thread, so scrolling doesn't stutter.
            return image.preparingForDisplay() ?? image
        }
        running[url] = task
        let image = await task.value
        running[url] = nil
        if let image { memory.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4)) }
        return image
    }
}

/// A remote picture (cover, photo) that fades in, with a branded placeholder when there is no picture or it fails
/// (Android's RemoteImage).
struct RemoteImage: View {
    let path: String?
    var contentDescription: String? = nil
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        let url = resolveUrl(path)
        ZStack {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else if url == nil || failed {
                LogoPlaceholder()
            } else {
                Scheme.surfaceContainerHigh
            }
        }
        .clipped()
        .accessibilityElement()
        .accessibilityLabel(contentDescription ?? "")
        .accessibilityHidden(contentDescription == nil)
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = ImageLoader.shared.cached(url) { image = hit; return }
            let loaded = await ImageLoader.shared.image(url)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded; failed = loaded == nil }
        }
    }
}

/// The green gradient with a faint logo, used where a course or post has no picture.
struct LogoPlaceholder: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Brand.hero, Brand.heroDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image("Logo").resizable().scaledToFit().frame(width: 44, height: 44).clipShape(Circle()).opacity(0.5)
        }
    }
}

/// Initials avatar or photo (Android's Avatar). The website's default male/female icons count as "no photo".
struct Avatar: View {
    let name: String?
    let image: String?
    var size: CGFloat = 44

    var body: some View {
        if let url = resolveUrl(image), !url.absoluteString.contains("/assets/") {
            RemoteImage(path: url.absoluteString, contentDescription: name)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(Scheme.primaryContainer)
                Text(initials(name)).textStyle(Typo.titleSmall).foregroundStyle(Scheme.onPrimaryContainer)
            }
            .frame(width: size, height: size)
            .accessibilityLabel(name ?? "")
        }
    }
}

func initials(_ name: String?) -> String {
    let letters = (name ?? "?").trimmed.split(separator: " ").filter { !$0.isEmpty }.prefix(2).map { $0.prefix(1).uppercased() }.joined()
    return letters.isEmpty ? "?" : letters
}
