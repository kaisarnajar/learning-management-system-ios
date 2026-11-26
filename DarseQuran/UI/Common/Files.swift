import Foundation
import QuickLook
import SafariServices
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Presents system screens (in-app browser, document preview, share sheet) over whatever is on screen.
@MainActor
enum Presenter {
    static var top: UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    static func present(_ controller: UIViewController) {
        top?.present(controller, animated: true)
    }
}

/// Opens a web page in the in-app browser (Android's Custom Tab).
@MainActor
func openWeb(_ url: String?) {
    guard let target = resolveUrl(url), target.scheme == "http" || target.scheme == "https" else { return }
    let safari = SFSafariViewController(url: target)
    safari.preferredControlTintColor = UIColor(Scheme.primary)
    Presenter.present(safari)
}

/// Schemes of outside links that are handed to another app on the phone (mail, dialler, messages, WhatsApp).
private let phoneSchemes: Set<String> = ["mailto", "tel", "sms", "smsto", "whatsapp"]

/// How an outside link is opened: a web page in the browser, a phone link in its app, anything else not at all.
enum OutsideOpen: Equatable {
    case web(String)
    case phoneApp(String)
    /// `javascript:`, `file:` and other schemes content must not be able to trigger.
    case ignored
}

func outsideOpen(_ url: String) -> OutsideOpen {
    let scheme = url.contains(":") ? String(url[..<url.firstIndex(of: ":")!]).lowercased() : ""
    if scheme == "http" || scheme == "https" { return .web(url) }
    if phoneSchemes.contains(scheme) { return .phoneApp(url) }
    return .ignored
}

/// Opens a link that leads outside the academy: web pages in the in-app browser, mailto:/tel: and the like in the app
/// that handles them.
@MainActor
func openOutside(_ url: String, toast: Toaster? = nil) {
    switch outsideOpen(url) {
    case .web(let web): openWeb(web)
    case .phoneApp(let uri):
        guard let target = URL(string: uri) else { return }
        UIApplication.shared.open(target) { opened in
            if !opened { Task { @MainActor in toast?.show("No app on this phone can open this link.") } }
        }
    case .ignored: break
    }
}

/// The type to open a downloaded file as: the server's, unless it only says "some bytes" (storage often does), in
/// which case the file name's extension decides.
func mimeFor(fileName: String, contentType: String?) -> String {
    let declared = contentType?.components(separatedBy: ";").first?.trimmed.lowercased()
    if let declared, !declared.isEmpty, declared != "application/octet-stream", declared != "binary/octet-stream" { return declared }
    let ext = (fileName as NSString).pathExtension.lowercased()
    return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
}

/// Shows a downloaded document in QuickLook (preview, share, save to Files), as Android opens it in the viewer app.
@MainActor
final class DocumentPreview: NSObject, QLPreviewControllerDataSource {
    private static var current: DocumentPreview?
    private let file: URL

    private init(file: URL) { self.file = file }

    static func open(_ file: URL) {
        let preview = DocumentPreview(file: file)
        current = preview
        let controller = QLPreviewController()
        controller.dataSource = preview
        Presenter.present(controller)
    }

    nonisolated func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
    nonisolated func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        MainActor.assumeIsolated { file as NSURL }
    }
}

/// Shares a file or text with the system share sheet.
@MainActor
func share(_ items: [Any]) {
    let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
    if let pop = controller.popoverPresentationController, let view = Presenter.top?.view {
        pop.sourceView = view
        pop.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
    }
    Presenter.present(controller)
}

extension APIClient {
    /// Downloads a file the API protects (course attachments under /api/files/…, receipts) with the signed-in session,
    /// following the redirect to the short-lived storage URL, into the document cache. Returns the file.
    func download(_ path: String, fileName: String, query: [String: String?] = [:]) async throws -> URL {
        let (temp, response) = try await downloadToFile(path, query: query)
        var name = fileName
        if (name as NSString).pathExtension.isEmpty {
            let mime = mimeFor(fileName: name, contentType: response.value(forHTTPHeaderField: "Content-Type"))
            if let ext = UTType(mimeType: mime)?.preferredFilenameExtension { name += "." + ext }
        }
        let file = DocumentCache.file(named: name)
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: temp, to: file)
        return file
    }
}

/// Downloads a protected file and opens it. Returns a message to show when it fails.
@MainActor
func downloadAndOpen(_ client: APIClient, path: String, fileName: String) async -> String? {
    guard resolveUrl(path) != nil else { return "This file is not available." }
    do {
        let file = try await client.download(path, fileName: fileName)
        DocumentPreview.open(file)
        return nil
    } catch {
        if apiError(from: error).cancelled { return nil }
        return "Couldn't download the file. Check your connection and try again."
    }
}

// MARK: - toasts

/// Short messages at the bottom of the screen (Android's Toast and Snackbar).
@MainActor
@Observable
final class Toaster {
    private(set) var message: String?
    @ObservationIgnored private var hide: Task<Void, Never>?

    func show(_ text: String, long: Bool = false) {
        message = text
        hide?.cancel()
        hide = Task { [weak self] in
            try? await Task.sleep(for: .seconds(long ? 3.5 : 2.2))
            guard !Task.isCancelled else { return }
            withAnimation { self?.message = nil }
        }
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}

/// The toast overlay, placed once at the root.
struct ToastOverlay: View {
    @Environment(Toaster.self) private var toaster

    var body: some View {
        VStack {
            Spacer()
            if let message = toaster.message {
                Text(message)
                    .textStyle(Typo.bodyMedium)
                    .foregroundStyle(Scheme.inverseOnSurface)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Scheme.inverseSurface, in: RoundedRectangle(cornerRadius: Radius.input))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.easeOut(duration: 0.2), value: toaster.message)
        .allowsHitTesting(false)
    }
}
