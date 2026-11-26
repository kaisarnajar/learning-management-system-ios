import SwiftUI
import UIKit

/// Opens a link found in academy content; set by the app's navigation (academy pages open in the app, the rest
/// outside). Android's LocalOpenLink.
struct OpenLinkKey: EnvironmentKey {
    static let defaultValue: @MainActor (String) -> Void = { href in
        switch linkTarget(href) {
        case .inApp(let path): openWeb(path)
        case .outside(let url): openOutside(url)
        }
    }
}

extension EnvironmentValues {
    var openLink: @MainActor (String) -> Void {
        get { self[OpenLinkKey.self] }
        set { self[OpenLinkKey.self] = newValue }
    }
}

/// Sanitised server HTML (blog bodies, fatwa answers) as native text with tappable links (Android's HtmlText).
/// Parsed once per text. Inline images, which text can't show, are left out rather than drawn as an empty box.
struct HtmlText: View {
    let html: String
    var serif: Bool = false
    @Environment(\.openLink) private var openLink
    @State private var rendered: AttributedString?

    var body: some View {
        Group {
            if let rendered {
                Text(rendered)
                    .lineSpacing(serif ? 7 : 6)
                    .tint(Scheme.primary)
                    .foregroundStyle(Scheme.onSurface)
                    .textSelection(.enabled)
            } else {
                Text(plainText(html)).textStyle(serif ? Typo.serifBody : Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            openLink(url.absoluteString)
            return .handled
        })
        .task(id: html) { rendered = renderHtml(html, serif: serif) }
    }
}

/// Server HTML as styled text in the app's fonts: bold and italic kept, links kept (relative ones made absolute on the
/// academy's server, which the link router then keeps in the app), images dropped.
@MainActor
func renderHtml(_ html: String, serif: Bool, size: CGFloat = 16) -> AttributedString? {
    var source = html.replacingOccurrences(of: "<img[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
    source = source.replacingOccurrences(of: "href=\"/", with: "href=\"\(CurrentEnvironment.baseUrl)/")
    source = source.replacingOccurrences(of: "href='/", with: "href='\(CurrentEnvironment.baseUrl)/")
    let wrapped = "<meta charset=\"utf-8\"><div>\(source)</div>"
    guard let data = wrapped.data(using: .utf8),
          let parsed = try? NSMutableAttributedString(
              data: data,
              options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
              documentAttributes: nil
          ) else { return nil }
    let full = NSRange(location: 0, length: parsed.length)
    let scaled = UIFontMetrics(forTextStyle: .body).scaledValue(for: size)
    parsed.enumerateAttribute(.font, in: full) { value, range, _ in
        let traits = (value as? UIFont)?.fontDescriptor.symbolicTraits ?? []
        let bold = traits.contains(.traitBold)
        let italic = traits.contains(.traitItalic)
        let sourceSize = (value as? UIFont)?.pointSize ?? 12
        // Headings come in larger than 12pt (the HTML default); keep their relative size.
        let factor = max(1, sourceSize / 12)
        let name: String = switch (serif, bold, italic) {
        case (true, _, true): FontName.serifItalic
        case (true, true, false): FontName.serifSemiBold
        case (true, false, false): FontName.serifRegular
        case (false, true, _): FontName.sansSemiBold
        case (false, false, _): FontName.sansRegular
        }
        parsed.addAttribute(.font, value: UIFont(name: name, size: scaled * factor) ?? UIFont.systemFont(ofSize: scaled * factor), range: range)
    }
    parsed.removeAttribute(.foregroundColor, range: full)
    parsed.removeAttribute(.paragraphStyle, range: full)
    // Trailing newlines from closing paragraphs.
    while parsed.string.hasSuffix("\n") { parsed.deleteCharacters(in: NSRange(location: parsed.length - 1, length: 1)) }
    return try? AttributedString(parsed, including: \.uiKit)
}

/// Plain text from HTML, for previews in cards.
func plainText(_ html: String?) -> String {
    guard let html, !html.isEmpty else { return "" }
    var text = html.replacingOccurrences(of: "<br\\s*/?>|</p>|</div>|</li>|</h[1-6]>", with: " ", options: [.regularExpression, .caseInsensitive])
    text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&rsquo;": "’", "&lsquo;": "‘", "&rdquo;": "”", "&ldquo;": "“", "&hellip;": "…", "&mdash;": "—", "&ndash;": "–"]
    for (entity, char) in entities { text = text.replacingOccurrences(of: entity, with: char) }
    text = text.replacingOccurrences(of: "&#(\\d+);", with: "", options: .regularExpression)
    return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmed
}
