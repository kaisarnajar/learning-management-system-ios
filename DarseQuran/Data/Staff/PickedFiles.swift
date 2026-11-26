import Foundation
import ImageIO
import UniformTypeIdentifiers

/*
 * Files chosen on the phone for upload fields (Android's PickedFile, UploadLimit, PickOutcome and readPicked in
 * data/staff/Staff.kt).
 */

/// A file chosen on the phone, ready to upload.
struct PickedFile: Sendable, Hashable {
    let name: String
    let mime: String
    let bytes: Data

    init(_ name: String, _ mime: String, _ bytes: Data) {
        self.name = name
        self.mime = mime
        self.bytes = bytes
    }

    // Two picks are the same file when their names and bytes are (as on Android, the type doesn't count).
    static func == (a: PickedFile, b: PickedFile) -> Bool { a.name == b.name && a.bytes == b.bytes }
    func hash(into hasher: inout Hasher) { hasher.combine(name); hasher.combine(bytes) }
}

/// What an upload field accepts: the website's limits (its config/constants/file.ts), checked before reading.
struct UploadLimit: Sendable, Equatable {
    var maxBytes: Int64
    var mimeTypes: Set<String> = []
    var typesLabel: String? = nil

    private static let mb: Int64 = 1024 * 1024
    private static let images: Set<String> = ["image/jpeg", "image/png", "image/webp", "image/gif"]

    /// Blog and announcement images.
    static let image = UploadLimit(maxBytes: 5 * mb, mimeTypes: images, typesLabel: "JPEG, PNG, WebP or GIF")
    /// Book and library covers.
    static let cover = UploadLimit(maxBytes: 2 * mb, mimeTypes: images, typesLabel: "JPEG, PNG, WebP or GIF")
    /// Course announcement attachments (the picker already filters the types).
    static let attachment = UploadLimit(maxBytes: 15 * mb)

    /// This limit with other accepted types (Kotlin's `copy(mimeTypes = …)`).
    func with(mimeTypes: Set<String>) -> UploadLimit { var l = self; l.mimeTypes = mimeTypes; return l }
}

/// A file read for upload, or why it can't be used.
enum PickOutcome: Sendable, Equatable {
    case picked(PickedFile)
    case rejected(String)

    var file: PickedFile? { if case .picked(let f) = self { f } else { nil } }
    var reason: String? { if case .rejected(let r) = self { r } else { nil } }
}

/// The MIME type of a file name's extension ("application/octet-stream" when unknown).
func mimeType(forFileName name: String) -> String {
    let ext = (name as NSString).pathExtension
    return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
}

/// Reads a picked document (from the Files picker; [url] may be security-scoped) for an upload field, within [limit]
/// (Android's `Context.readPicked`). Runs off the main thread.
///
/// The size is checked from the file's metadata before reading, and again while reading, so a huge file is refused
/// instead of filling memory. A HEIC/HEIF photo (what iPhone cameras save) is turned into a JPEG, which the website
/// accepts.
func readPicked(fileAt url: URL, limit: UploadLimit) async -> PickOutcome {
    await Task.detached(priority: .userInitiated) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .nameKey])
        let name = values?.name ?? url.lastPathComponent
        let mime = values?.contentType?.preferredMIMEType ?? mimeType(forFileName: name)
        let size = values?.fileSize.map { Int64($0) }
        return readPickedSource(name: name, mime: mime, size: size, limit: limit) { max in
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            if let max { return try? handle.read(upToCount: max) ?? Data() }
            return try? handle.readToEnd() ?? Data()
        }
    }.value
}

/// Reads picked bytes (a photo from the photo library, whose size is only known once loaded) for an upload field,
/// within [limit]. [name] may be nil (the library doesn't always tell); the type then names it ("upload.jpeg").
func readPicked(data: Data, name: String?, mime: String, limit: UploadLimit) async -> PickOutcome {
    await Task.detached(priority: .userInitiated) {
        let fileName = name ?? ("upload." + (mime.components(separatedBy: "/").dropFirst().first ?? "bin"))
        return readPickedSource(name: fileName, mime: mime, size: nil, limit: limit) { max in max.map { data.prefix($0) } ?? data }
    }.value
}

/// The shared rules of both [readPicked]s. `read(max)` returns at most `max` bytes, or all of them for nil (nil when
/// unreadable).
private func readPickedSource(name: String, mime: String, size: Int64?, limit: UploadLimit, read: (Int?) -> Data?) -> PickOutcome {
    let tooBig = { (bytes: Int64) in PickOutcome.rejected("This file is \(megabytes(bytes)); the limit here is \(megabytes(limit.maxBytes)).") }

    if mime == "image/heic" || mime == "image/heif" {
        if !limit.mimeTypes.isEmpty && !limit.mimeTypes.contains("image/jpeg") { return .rejected(typesMessage(limit)) }
        // A photo can be large before conversion; read it whole (the JPEG is checked against the limit).
        guard let source = read(nil), let jpeg = jpegFromImageData(source, maxSide: 2048) else {
            return .rejected("This photo couldn't be converted. Choose a JPEG or PNG.")
        }
        if Int64(jpeg.count) > limit.maxBytes { return tooBig(Int64(jpeg.count)) }
        return .picked(PickedFile(((name as NSString).deletingPathExtension) + ".jpg", "image/jpeg", jpeg))
    }
    if !limit.mimeTypes.isEmpty && !limit.mimeTypes.contains(mime) { return .rejected(typesMessage(limit)) }
    if let size, size > limit.maxBytes { return tooBig(size) }
    guard let bytes = read(Int(limit.maxBytes + 1)) else { return .rejected("This file couldn't be read.") }
    if Int64(bytes.count) > limit.maxBytes { return tooBig(size ?? Int64(bytes.count)) }
    return .picked(PickedFile(name, mime, bytes))
}

private func typesMessage(_ limit: UploadLimit) -> String {
    "This type of file can't be used here" + (limit.typesLabel.map { "; choose a \($0) file." } ?? ".")
}

/// "3.0 MB".
private func megabytes(_ bytes: Int64) -> String {
    String(format: "%.1f MB", locale: Locale(identifier: "en_US_POSIX"), Double(bytes) / (1024.0 * 1024.0))
}

/// An image file's bytes as a JPEG no larger than [maxSide] pixels on its longer side, upright (Android's
/// readImageAsJpeg). ImageIO makes the smaller image straight from the file, without decoding a 50-megapixel photo
/// at full size first.
func jpegFromImageData(_ data: Data, maxSide: Int) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxSide,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    let out = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return out as Data
}
