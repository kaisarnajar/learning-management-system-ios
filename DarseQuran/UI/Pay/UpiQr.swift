import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/*
 * The UPI QR code of the website's PaymentDetailsPanel: the same upi://pay link (services/upi.ts), drawn with the same
 * quiet zone and colours as its `qrcode` call (margin 2, #1c1917 on white, error correction M). Android's UpiQr.kt.
 */

/// The payee name the website falls back to when the academy has not set one.
private let defaultPayee = "Darse Quran Academy"
private let payeeMax = 50
private let noteMax = 80
private let refMax = 35
private let qrMargin = 2

/// `upi://pay` for the academy's UPI ID only, as the website's buildUpiVpaUrlFromSettings.
func upiVpaUri(_ settings: PaymentSettings) -> String {
    upiUri([("pa", settings.upiId ?? ""), ("pn", upiPayee(settings)), ("cu", "INR")])
}

/// `upi://pay` with the amount, as the website's buildUpiPaymentUrlFromSettings. Without a [paymentRef] the transaction
/// reference is `FEE-<amount in paise>`, as the website's panel sends it.
func upiPaymentUri(_ settings: PaymentSettings, amountPaise: Int, note: String, paymentRef: String? = nil) -> String {
    upiUri([
        ("pa", settings.upiId ?? ""),
        ("pn", upiPayee(settings)),
        ("am", upiAmount(amountPaise)),
        ("cu", "INR"),
        ("tn", String(note.prefix(noteMax))),
        ("tr", String((paymentRef ?? "FEE-\(amountPaise)").prefix(refMax))),
    ])
}

/// The link the QR code holds: with the amount when one is due, else just the UPI ID (as the website decides).
func upiQrUri(_ settings: PaymentSettings, amountPaise: Int?, note: String?, paymentRef: String? = nil) -> String {
    if let amountPaise, amountPaise > 0 { return upiPaymentUri(settings, amountPaise: amountPaise, note: note ?? "", paymentRef: paymentRef) }
    return upiVpaUri(settings)
}

/// The payee name shown in the UPI app: the academy's, trimmed, else the website's default.
func upiPayee(_ settings: PaymentSettings) -> String {
    String((settings.upiPayeeName?.trimmed.nilIfBlank ?? defaultPayee).prefix(payeeMax))
}

/// "349.00" from 34900 paise (Locale.ROOT formatting: a dot, two decimals).
func upiAmount(_ paise: Int) -> String {
    String(format: "%d.%02d", paise / 100, paise % 100)
}

/// Form-encodes like the browser's URLSearchParams (and Java's URLEncoder), so the QR holds the same text as the
/// website's: letters, digits and `*-._` stay; a space becomes "+"; everything else is %XX in UTF-8.
func formEncode(_ value: String) -> String {
    var out = ""
    for byte in value.utf8 {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "*"), UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"):
            out.append(Character(UnicodeScalar(byte)))
        case UInt8(ascii: " "):
            out.append("+")
        default:
            out += String(format: "%%%02X", byte)
        }
    }
    return out
}

private func upiUri(_ params: [(String, String)]) -> String {
    "upi://pay?" + params.map { "\($0.0)=\(formEncode($0.1))" }.joined(separator: "&")
}

/// The opener link for a UPI app (Android builds it with Uri.Builder): payee, amount and a note of at most 60 characters.
func upiLaunchUri(_ settings: PaymentSettings, amountPaise: Int, note: String) -> URL? {
    guard let vpa = settings.upiId?.trimmed.nilIfBlank else { return nil }
    var c = URLComponents()
    c.scheme = "upi"
    c.host = "pay"
    c.queryItems = [
        URLQueryItem(name: "pa", value: vpa),
        URLQueryItem(name: "pn", value: upiPayee(settings)), // the same name as the QR code
        URLQueryItem(name: "am", value: upiAmount(amountPaise)),
        URLQueryItem(name: "cu", value: "INR"),
        URLQueryItem(name: "tn", value: String(note.prefix(60))),
    ]
    // URLQueryItem leaves "+" as it is, which UPI apps read as a space; Uri.Builder sends it as %2B.
    c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
    return c.url
}

/// The QR code's modules for [text] (true = dark), with the website's quiet zone of 2 modules.
func qrMatrix(_ text: String) -> [[Bool]]? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"
    guard let image = filter.outputImage else { return nil }
    let extent = image.extent.integral
    let width = Int(extent.width), height = Int(extent.height)
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = CIContext(options: [.useSoftwareRenderer: true])
    context.render(image, toBitmap: &pixels, rowBytes: width * 4, bounds: extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
    var dark = [[Bool]](repeating: [Bool](repeating: false, count: width), count: height)
    var minX = width, minY = height, maxX = -1, maxY = -1
    for y in 0..<height {
        for x in 0..<width where pixels[(y * width + x) * 4] < 128 {
            dark[y][x] = true
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= minX, maxY >= minY else { return nil }
    // Core Image adds its own border; crop to the code and add the website's margin instead.
    let size = maxX - minX + 1
    var out = [[Bool]](repeating: [Bool](repeating: false, count: size + qrMargin * 2), count: size + qrMargin * 2)
    for y in 0..<size { for x in 0..<size { out[y + qrMargin][x + qrMargin] = dark[minY + y][minX + x] } }
    return out
}

/// The last QR code built, so a screen that redraws doesn't build it again each time (Android: remember(text)).
@MainActor
private enum QrCache {
    private static var last: (text: String, matrix: [[Bool]])?

    static func matrix(_ text: String) -> [[Bool]] {
        if let last, last.text == text { return last.matrix }
        let matrix = qrMatrix(text) ?? []
        last = (text, matrix)
        return matrix
    }
}

/// Draws [text] as a QR code, dark modules on white whatever the theme, so every UPI app can scan it.
struct QrCode: View {
    let text: String
    let description: String
    var size: CGFloat = 220

    var body: some View {
        let matrix = QrCache.matrix(text)
        Canvas { context, canvasSize in
            guard !matrix.isEmpty else { return }
            let cell = canvasSize.width / CGFloat(matrix.count)
            var path = Path()
            for (y, row) in matrix.enumerated() {
                for (x, on) in row.enumerated() where on {
                    // Overlap neighbours by half a point so no hairline seams show.
                    path.addRect(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell + 0.5, height: cell + 0.5))
                }
            }
            context.fill(path, with: .color(Color(hex: 0x1C1917)))
        }
        .frame(width: size, height: size)
        .background(Color.white)
        .accessibilityElement()
        .accessibilityLabel(description)
        .accessibilityAddTraits(.isImage)
    }
}
