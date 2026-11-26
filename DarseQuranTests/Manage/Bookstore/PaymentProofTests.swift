import XCTest
@testable import DarseQuran

/// Ported from Android's ui/manage/bookstore/PaymentProofTest.kt.
final class PaymentProofTests: XCTestCase {
    func testPdfProofsAreToldApartByTheirName() {
        XCTAssertTrue(isPdfProof("/api/files/orders/o1/proof.pdf"))
        XCTAssertTrue(isPdfProof("https://files.example.test/uploads/PROOF.PDF"))
        XCTAssertTrue(isPdfProof("/api/files/orders/o1/proof.pdf?token=abc"))
        XCTAssertFalse(isPdfProof("/api/files/orders/o1/proof.jpg"))
        XCTAssertFalse(isPdfProof("/api/files/orders/o1/pdf-proof.png"))
    }
}
