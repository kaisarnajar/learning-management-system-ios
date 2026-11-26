import Foundation

/*
 * The website's sanitiser (services/rich-text.ts) keeps only `color` and `text-align` styles and a fixed list of tags,
 * so formatting written as CSS on <span>s (`<span style="font-weight: bold; font-style: italic;">`) would be lost
 * when saved. Before sending, [toWebsiteHtml] rewrites those styles as the tags the sanitiser keeps (strong, em, u,
 * s, h2), the same tags the website's own editor produces. Ported from Android's ui/manage/content/WebsiteHtml.kt.
 *
 * iOS: the editor (RichTextField, a content-editable web view) writes strikethrough as <strike>, a tag the sanitiser
 * drops, so it is rewritten as <s> too.
 */

private let htmlToken = try! NSRegularExpression(pattern: "<[^>]*>|[^<]+")
private let htmlStyleAttr = try! NSRegularExpression(pattern: #"style\s*=\s*"([^"]*)""#, options: .caseInsensitive)
private let htmlAllowedColor = try! NSRegularExpression(pattern: #"^(#[0-9a-fA-F]{3,8}|rgb\(\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}\s*\)|[a-z]{3,20})$"#)
private let htmlHeadingMark = "<strong data-heading>"
private let htmlHeadingParagraph = try! NSRegularExpression(
    pattern: #"<p([^>]*)>\s*"# + NSRegularExpression.escapedPattern(for: htmlHeadingMark) + #"((?:(?!</?(?:p|strong)[\s>]).)*)</strong>\s*</p>"#,
    options: .dotMatchesLineSeparators
)
private let htmlStrike = try! NSRegularExpression(pattern: #"<(/?)strike(\s[^>]*)?>"#, options: .caseInsensitive)
private let htmlTag = try! NSRegularExpression(pattern: "<[^>]*>")

private func matches(_ regex: NSRegularExpression, _ text: String) -> [NSTextCheckingResult] {
    regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
}

private func group(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String {
    guard let range = Range(match.range(at: index), in: text) else { return "" }
    return String(text[range])
}

/// Editor HTML → HTML whose formatting survives the website's sanitiser.
func toWebsiteHtml(_ editorHtml: String) -> String {
    var out = ""
    var closers: [String] = []
    for match in matches(htmlToken, editorHtml) {
        let t = group(match, 0, in: editorHtml)
        let lower = t.lowercased()
        if lower.hasPrefix("<span") {
            let (open, close) = spanReplacement(t)
            out += open
            closers.append(close)
        } else if lower.hasPrefix("</span") {
            out += closers.popLast() ?? ""
        } else {
            out += t
        }
    }
    // A paragraph that is all heading becomes an <h2> (keeping its alignment); other heading runs stay bold.
    let html = htmlHeadingParagraph.stringByReplacingMatches(
        in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "<h2$1>$2</h2>"
    )
    let strong = html.replacingOccurrences(of: htmlHeadingMark, with: "<strong>")
    return htmlStrike.stringByReplacingMatches(in: strong, range: NSRange(strong.startIndex..., in: strong), withTemplate: "<$1s>")
}

/// The opening and closing markup that replace one `<span style="…">`.
private func spanReplacement(_ tag: String) -> (String, String) {
    let styleText = matches(htmlStyleAttr, tag).first.map { group($0, 1, in: tag) } ?? ""
    var styles: [String: String] = [:]
    for decl in styleText.split(separator: ";") {
        let parts = decl.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { continue }
        styles[parts[0].trimmingCharacters(in: .whitespaces).lowercased()] = parts[1].trimmingCharacters(in: .whitespaces)
    }
    var wrappers: [String] = []
    let heading = styles["font-size"].map(isHeadingSize) == true
    let bold = styles["font-weight"].map { w -> Bool in
        let v = w.lowercased()
        return v == "bold" || v == "bolder" || (Int(v) ?? 0) >= 600
    } == true
    if heading { wrappers.append("strong data-heading") } else if bold { wrappers.append("strong") }
    if let style = styles["font-style"]?.lowercased(), style == "italic" || style == "oblique" { wrappers.append("em") }
    let decoration = (styles["text-decoration"]?.lowercased() ?? "") + " " + (styles["text-decoration-line"]?.lowercased() ?? "")
    if decoration.contains("underline") { wrappers.append("u") }
    if decoration.contains("line-through") { wrappers.append("s") }
    let color = styles["color"].flatMap { c in matches(htmlAllowedColor, c).isEmpty ? nil : c }

    var open = ""
    var close = ""
    if let color { open += "<span style=\"color: \(color)\">" }
    for w in wrappers { open += "<\(w)>" }
    for w in wrappers.reversed() { close += "</\(w.components(separatedBy: " ")[0])>" }
    if color != nil { close += "</span>" }
    return (open, close)
}

/// The toolbar's heading is 22pt (body text 15): anything from 1.2em / 18px up counts as a heading.
private func isHeadingSize(_ value: String) -> Bool {
    guard let numberMatch = value.firstMatch(of: /[\d.]+/), let number = Float(numberMatch.0) else { return false }
    let unit = value.lowercased().replacing(/[\d.\s]/, with: "")
    switch unit {
    case "em", "rem": return number >= 1.2
    case "%": return number >= 120
    default: return number >= 18
    }
}

/// [html] without its tags, with &nbsp; as a space.
private func visibleText(_ html: String) -> String {
    htmlTag.stringByReplacingMatches(in: html, range: NSRange(html.startIndex..., in: html), withTemplate: "")
        .replacingOccurrences(of: "&nbsp;", with: " ")
}

/// True when rich text has no visible words (the editor writes `<p></p>` for an empty document).
func isBlankHtml(_ html: String) -> Bool { visibleText(html).trimmed.isEmpty }

/// Why a fatwa answer can't be published yet, or nil. Counts the visible text, not the formatting tags.
func answerProblem(_ answerHtml: String) -> String? {
    if isBlankHtml(answerHtml) { return "Write the answer first." }
    if visibleText(answerHtml).trimmed.count < 20 { return "The answer must be at least 20 characters." }
    return nil
}
