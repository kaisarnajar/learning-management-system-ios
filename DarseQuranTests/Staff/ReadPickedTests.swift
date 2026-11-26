import UIKit
import XCTest
@testable import DarseQuran

/// Reading a picked file for an upload field, within the website's limits. Ported from Android's ReadPickedTest.kt
/// (temporary files stand in for the document provider; Android's sampleSizeFor has no iOS counterpart, as ImageIO
/// makes the smaller image itself).
final class ReadPickedTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("picked-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func put(_ name: String, _ data: Data) -> URL {
        let url = dir.appendingPathComponent(name)
        try? data.write(to: url)
        return url
    }

    private func png(_ width: Int, _ height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func testAFileWithinTheLimitIsRead() async {
        let outcome = await readPicked(fileAt: put("cover.png", png(20, 20)), limit: .cover)
        XCTAssertEqual("cover.png", outcome.file?.name)
        XCTAssertEqual("image/png", outcome.file?.mime)
    }

    func testAFileOverTheLimitIsRefusedFromItsReportedSize() async {
        let outcome = await readPicked(fileAt: put("big.pdf", Data(count: 3 * 1024 * 1024)), limit: UploadLimit.cover.with(mimeTypes: []))
        XCTAssertEqual("This file is 3.0 MB; the limit here is 2.0 MB.", outcome.reason)
    }

    func testAFileOverTheLimitIsRefusedEvenWhenItsSizeIsUnknown() async {
        let outcome = await readPicked(data: Data(count: 3 * 1024 * 1024), name: "big.pdf", mime: "application/pdf", limit: UploadLimit.cover.with(mimeTypes: []))
        XCTAssertNotNil(outcome.reason)
    }

    func testATypeTheWebsiteRefusesIsRefusedHere() async {
        let outcome = await readPicked(fileAt: put("notes.pdf", Data(count: 10)), limit: .image)
        XCTAssertEqual("This type of file can't be used here; choose a JPEG, PNG, WebP or GIF file.", outcome.reason)
    }

    func testAHugePhotoIsShrunkInsteadOfDecodedAtFullSize() throws {
        let jpeg = try XCTUnwrap(jpegFromImageData(png(4000, 3000), maxSide: 1600))
        let decoded = try XCTUnwrap(UIImage(data: jpeg))
        XCTAssertEqual(1600, max(decoded.size.width * decoded.scale, decoded.size.height * decoded.scale))
    }

    func testAPhotoWithoutANameIsNamedAfterItsType() async {
        let outcome = await readPicked(data: png(4, 4), name: nil, mime: "image/png", limit: .image)
        XCTAssertEqual("upload.png", outcome.file?.name)
    }
}
