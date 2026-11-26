import UIKit
import XCTest
@testable import DarseQuran

/// Android's ProofPickerTest checks that an attached screenshot survives the activity being recreated (rotation). The
/// iOS app is portrait only and keeps the picker in the screen's model, so nothing is recreated; these check what the
/// picker does with a picked image instead: an upright, bounded JPEG ready to upload, or a notice when it can't be read.
final class ProofPickerTests: XCTestCase {
    private func image(width: Int, height: Int, orientation: UIImage.Orientation = .up) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let drawn = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return UIImage(cgImage: drawn.cgImage!, scale: 1, orientation: orientation)
    }

    private func pixels(_ jpeg: Data?) -> CGSize? {
        guard let jpeg, let decoded = UIImage(data: jpeg)?.cgImage else { return nil }
        return CGSize(width: decoded.width, height: decoded.height)
    }

    @MainActor
    func testAPickedScreenshotIsAttachedAsAJpeg() throws {
        let picker = ProofImagePicker()
        var unreadable = 0
        picker.onUnreadable = { unreadable += 1 }
        picker.set(image(width: 40, height: 30))
        let attached = try XCTUnwrap(picker.image)
        XCTAssertEqual("image/jpeg", attached.mime)
        XCTAssertEqual(CGSize(width: 40, height: 30), pixels(attached.data))
        XCTAssertEqual(0, unreadable)

        picker.set(nil) // a file that isn't an image
        XCTAssertNil(picker.image)
        XCTAssertEqual(1, unreadable)
    }

    func testABigPhotoIsShrunkToTheUploadSize() {
        XCTAssertEqual(CGSize(width: 1600, height: 1200), pixels(jpegForUpload(image(width: 4000, height: 3000))))
        XCTAssertEqual(CGSize(width: 40, height: 30), pixels(jpegForUpload(image(width: 40, height: 30))), "never enlarged")
    }

    func testAPortraitShotIsUploadedUpright() {
        // Stored landscape, shown rotated (as a camera's EXIF orientation does).
        XCTAssertEqual(CGSize(width: 30, height: 40), pixels(jpegForUpload(image(width: 40, height: 30, orientation: .right))))
    }
}
