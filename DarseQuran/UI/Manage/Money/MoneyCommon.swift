import Observation
import SwiftUI

/*
 * Pieces shared by the money screens (Android's ui/manage/money/MoneyCommon.kt): amounts, list filters kept as one
 * string, the date range bar, summary tiles, a small bar chart, the payment screenshot and the receipt button.
 */

// MARK: - amounts

/// ₹ amount from paise for totals that can pass Int (and be negative); see [formatInr].
func money(_ paise: Int64) -> String { formatInr(paise) }

func money(_ paise: Int) -> String { formatInr(Int64(paise)) }

/// [value] with its first letter in upper case (Kotlin's `replaceFirstChar { it.uppercase() }`).
func moneyCapitalized(_ value: String) -> String { value.prefix(1).uppercased() + value.dropFirst() }

// MARK: - filters

/*
 * A list's filters travel through `PagedListModel.filter` as one string ("tab=income&preset=this_month"): these turn
 * it into the query map the endpoint takes and back.
 */

private let moneyFormAllowed: CharacterSet = {
    var set = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    set.insert(charactersIn: "-._*")
    return set
}()

/// URLEncoder.encode(…, "UTF-8"): form encoding, a space as "+".
private func moneyFormEncode(_ value: String) -> String {
    (value.addingPercentEncoding(withAllowedCharacters: moneyFormAllowed.union(.init(charactersIn: " "))) ?? value)
        .replacingOccurrences(of: " ", with: "+")
}

/// URLDecoder.decode(…, "UTF-8").
private func moneyFormDecode(_ value: String) -> String {
    let spaced = value.replacingOccurrences(of: "+", with: " ")
    return spaced.removingPercentEncoding ?? spaced
}

func moneyDecodeFilters(_ value: String?) -> [String: String] {
    var map: [String: String] = [:]
    for part in (value ?? "").split(separator: "&", omittingEmptySubsequences: false) where part.contains("=") {
        let key = part.prefix { $0 != "=" }
        let rest = part.dropFirst(key.count + 1)
        map[moneyFormDecode(String(key))] = moneyFormDecode(String(rest))
    }
    return map
}

/// The filter string of [map] (blank values left out), nil when nothing is left. Keys are sorted, so the same filters
/// always give the same string.
func moneyEncodeFilters(_ map: [String: String?]) -> String? {
    let text = map.compactMap { key, value -> (String, String)? in
        guard let value, !value.trimmed.isEmpty else { return nil }
        return (key, value)
    }
    .sorted { $0.0 < $1.0 }
    .map { moneyFormEncode($0.0) + "=" + moneyFormEncode($0.1) }
    .joined(separator: "&")
    return text.trimmed.isEmpty ? nil : text
}

/// Returns [current] with [changes] applied (a nil or blank value removes the key).
func moneyWithFilters(_ current: String?, _ changes: [String: String?]) -> String? {
    var map: [String: String?] = moneyDecodeFilters(current).mapValues { Optional($0) }
    for (k, v) in changes { map[k] = .some(v) }
    return moneyEncodeFilters(map)
}

/// Extra data that comes with a list page (summary totals, tab counts), kept in the screen's model beside its list.
/// The list's fetch writes [value]; the screen reads it (Android's ListExtras).
@MainActor
@Observable
final class MoneyListExtras<T> {
    var value: T?
}

// MARK: - date range

private let moneyPresetOptions = [
    FilterOption("this_month", "This month"),
    FilterOption("last_month", "Last month"),
    FilterOption("this_year", "This year"),
    FilterOption("all_time", "All time"),
    FilterOption("custom", "Custom"),
]

/// The finance pages' date filter: preset chips, and From/To dates for a custom range. [range] is what the server
/// resolved; [onChange] gets the new preset/from/to.
struct MoneyDateRangeBar: View {
    let range: FinanceRange?
    let filter: String?
    let onChange: (String?) -> Void

    var body: some View {
        let current = moneyDecodeFilters(filter)
        let preset = current["preset"] ?? range?.preset ?? "this_month"
        VStack(alignment: .leading, spacing: 8) {
            FilterChips(options: moneyPresetOptions, selected: preset) { p in
                if p == "custom" {
                    onChange(moneyWithFilters(filter, ["preset": "custom", "from": current["from"] ?? range?.from, "to": current["to"] ?? range?.to]))
                } else {
                    onChange(moneyWithFilters(filter, ["preset": p, "from": nil, "to": nil]))
                }
            }
            if preset == "custom" {
                HStack(alignment: .top, spacing: 8) {
                    FormDateField("From", value: current["from"] ?? range?.from ?? "", clearable: true) {
                        onChange(moneyWithFilters(filter, ["preset": "custom", "from": $0]))
                    }
                    .frame(maxWidth: .infinity)
                    FormDateField("To", value: current["to"] ?? range?.to ?? "", clearable: true) {
                        onChange(moneyWithFilters(filter, ["preset": "custom", "to": $0]))
                    }
                    .frame(maxWidth: .infinity)
                }
            } else if let from = range?.from, let to = range?.to {
                Text("\(formatCalendarDate(from)) – \(formatCalendarDate(to))")
                    .textStyle(Typo.labelMedium).foregroundStyle(Scheme.onSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A dropdown filter with an "All …" choice (value "").
struct MoneyFilterDropdown: View {
    let label: String
    let allLabel: String
    let options: [(value: String, label: String)]
    let filter: String?
    let key: String
    let onChange: (String?) -> Void

    var body: some View {
        FormDropdown(
            label, options: [(value: "", label: allLabel)] + options, value: moneyDecodeFilters(filter)[key] ?? "", placeholder: allLabel
        ) { onChange(moneyWithFilters(filter, [key: $0])) }
    }
}

// MARK: - summaries

/// A figure on a summary card; [tone] colours the amount (success = income, danger = expense).
struct MoneyFigure: Identifiable {
    let label: String
    let value: String
    var tone: Tone? = nil
    var note: String? = nil
    var id: String { label }

    init(_ label: String, _ value: String, _ tone: Tone? = nil, note: String? = nil) {
        self.label = label
        self.value = value
        self.tone = tone
        self.note = note
    }
}

/// Summary cards, two per row.
struct MoneyFigureGrid: View {
    let figures: [MoneyFigure]

    var body: some View {
        let rows = stride(from: 0, to: figures.count, by: 2).map { Array(figures[$0..<min($0 + 2, figures.count)]) }
        VStack(spacing: 10) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(rows[i]) { MoneyFigureTile(figure: $0).frame(maxWidth: .infinity) }
                    if rows[i].count == 1 { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                }
            }
        }
    }
}

struct MoneyFigureTile: View {
    let figure: MoneyFigure

    var body: some View {
        AppCard(padding: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(figure.label).textStyle(Typo.labelMedium).foregroundStyle(Scheme.onSurfaceVariant).lineLimit(2)
                Spacer().frame(height: 4)
                Text(figure.value).textStyle(Typo.titleLarge).foregroundStyle(moneyToneColor(figure.tone)).lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let note = figure.note {
                    Text(note).textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 88 - 28, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
    }
}

func moneyToneColor(_ tone: Tone?) -> Color {
    switch tone {
    case .success: Brand.success
    case .danger: Brand.danger
    case .warning: Brand.warning
    case .info: Brand.info
    default: Scheme.onSurface
    }
}

/// One bar of [MoneyBarChart].
struct MoneyBar: Identifiable {
    let label: String
    let value: Int64
    let color: Color
    var id: String { label }

    init(_ label: String, _ value: Int64, _ color: Color) {
        self.label = label
        self.value = value
        self.color = color
    }
}

/// Horizontal bars scaled to the largest absolute value, each with its label and amount.
struct MoneyBarChart: View {
    let bars: [MoneyBar]

    var body: some View {
        let largest = bars.map { $0.value.magnitude }.max() ?? 0
        let max = largest > 0 ? largest : 1
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(bars) { bar in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(bar.label).textStyle(Typo.labelMedium).foregroundStyle(Scheme.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                            Text(money(bar.value)).textStyle(Typo.labelMedium.with(name: FontName.sansSemiBold)).foregroundStyle(Scheme.onSurface)
                        }
                        let fraction = Swift.min(1, Swift.max(0, CGFloat(Double(bar.value.magnitude) / Double(max))))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Scheme.surfaceContainerHigh)
                                if fraction > 0 { Capsule().fill(bar.color).frame(width: geo.size.width * fraction) }
                            }
                        }
                        .frame(height: 12)
                        .accessibilityHidden(true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - row helpers

/// Label, a value, on one line inside a card (small); nothing when [value] is blank.
struct MoneyInfoLine: View {
    let label: String
    let value: String?

    init(_ label: String, _ value: String?) {
        self.label = label
        self.value = value
    }

    var body: some View {
        if let value, !value.trimmed.isEmpty {
            HStack(alignment: .top, spacing: 0) {
                Text(label).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).frame(width: 96, alignment: .leading)
                Text(value).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Buttons that wrap onto the next line when they don't fit (Compose's FlowRow).
struct MoneyFlowRow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { y += line + lineSpacing; x = 0; line = 0 }
            x += size.width + spacing
            line = Swift.max(line, size.height)
            widest = Swift.max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: subviews.isEmpty ? 0 : y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { y += line + lineSpacing; x = bounds.minX; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = Swift.max(line, size.height)
        }
    }
}

/// Material's filled Button in the CTA colours (gold, dark text): a 40pt pill, with an optional icon.
struct MoneyCtaButton: View {
    let text: String
    var icon: Icon? = nil
    var enabled: Bool = true
    var fullWidth: Bool = false
    let action: () -> Void

    init(_ text: String, icon: Icon? = nil, enabled: Bool = true, fullWidth: Bool = false, action: @escaping () -> Void) {
        self.text = text
        self.icon = icon
        self.enabled = enabled
        self.fullWidth = fullWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { icon.image.font(.system(size: 16, weight: .medium)) }
                Text(text).textStyle(Typo.labelLarge).lineLimit(1)
            }
            .padding(.leading, icon == nil ? 24 : 16).padding(.trailing, 24)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 40)
        }
        .buttonStyle(FilledStyle(background: Brand.cta, foreground: Brand.onCta, radius: 20))
        .disabled(!enabled)
    }
}

/// Material's OutlinedButton (40pt pill, outline border), with the label in [color] and an optional icon.
struct MoneyOutlinedButton: View {
    let text: String
    var icon: Icon? = nil
    var color: Color = Scheme.primary
    var enabled: Bool = true
    var fullWidth: Bool = false
    let action: () -> Void

    init(_ text: String, icon: Icon? = nil, color: Color = Scheme.primary, enabled: Bool = true, fullWidth: Bool = false, action: @escaping () -> Void) {
        self.text = text
        self.icon = icon
        self.color = color
        self.enabled = enabled
        self.fullWidth = fullWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { icon.image.font(.system(size: 16, weight: .medium)) }
                Text(text).textStyle(Typo.labelLarge).lineLimit(1)
            }
            .foregroundStyle(enabled ? color : Scheme.onSurface.opacity(0.38))
            .padding(.leading, icon == nil ? 24 : 16).padding(.trailing, 24)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 40)
            .overlay(Capsule().strokeBorder(enabled ? Scheme.outline : Scheme.onSurface.opacity(0.12), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(shape: Capsule()))
        .disabled(!enabled)
    }
}

/// The proof a student uploaded: a thumbnail that opens full screen, or a PDF that opens in a viewer.
struct MoneyScreenshotThumb: View {
    let path: String?
    let isPdf: Bool
    @Environment(AppContainer.self) private var app
    @State private var open = false

    var body: some View {
        if let path, !path.trimmed.isEmpty {
            if isPdf {
                MoneyOutlinedButton("Open proof (PDF)", icon: .pdf) {
                    let app = self.app
                    Task {
                        if let error = await downloadAndOpen(app.client, path: path, fileName: "payment-proof.pdf") { app.toaster.show(error, long: true) }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    Button { open = true } label: {
                        RemoteImage(path: path, contentDescription: "Payment screenshot")
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Payment screenshot")
                    Text("Tap to view the screenshot").textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant)
                }
                .fullScreenCover(isPresented: $open) {
                    ZStack(alignment: .topTrailing) {
                        Color.black.ignoresSafeArea()
                        RemoteImage(path: path, contentDescription: "Payment screenshot", contentMode: .fit)
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        IconButton(.close, label: "Close", tint: .white) { open = false }
                    }
                }
            }
        }
    }
}

/// What the website's receipt button does: "View Receipt" when one exists, else "Generate Receipt" (which generates
/// it and opens it).
struct MoneyReceiptButton: View {
    let recordId: String?
    let generatedAt: String?
    let runner: ActionRunner
    var onGenerated: () -> Void = {}
    @Environment(Navigator.self) private var nav

    var body: some View {
        if let recordId {
            if generatedAt != nil {
                MoneyOutlinedButton("View Receipt") { nav.push(.manage(.receipt(recordId: recordId))) }
            } else {
                MoneyOutlinedButton("Generate Receipt", enabled: !runner.busy) {
                    runner.run({ try await $0.service(MoneyAPI.self).generateReceipt(recordId) }, success: "Receipt generated successfully.") { _ in
                        onGenerated()
                        nav.push(.manage(.receipt(recordId: recordId)))
                    }
                }
            }
        } else {
            Text("No payment record").textStyle(Typo.labelSmall).foregroundStyle(Brand.warning)
        }
    }
}

/// The form body of a "void with reason" call.
func moneyReasonForm(_ reason: String) -> FormBody { formOf { $0.text("reason", reason) } }

extension ActionRunner {
    /// Downloads an Excel export and opens it.
    func openMoneyExport(_ name: String, _ params: [String: String]) {
        openFile { try await $0.service(MoneyAPI.self).export(params, fileName: name) }
    }
}

/// Status chip for fee submissions, book orders, waiver requests.
func moneyStatus(_ status: String?, label: String? = nil) -> (String, Tone) {
    let s = (status ?? "").lowercased()
    let tone = orderStatusTone(s)
    let text = label ?? (s == "pending_verification" ? "Pending verification" : titleCase(s.trimmed.isEmpty ? "unknown" : s))
    return (text, tone)
}

// MARK: - student filter

/// The state of the finance lists' "Student" filter: what is typed, the matches, and the picked student's label.
/// Kept in the screen's model, so it survives the list header scrolling away.
@MainActor
@Observable
final class MoneyStudentFilterModel {
    private(set) var query = ""
    private(set) var matches: [StudentRow] = []
    private(set) var selectedLabel: String?
    @ObservationIgnored private let app: AppContainer
    @ObservationIgnored private var job: Task<Void, Never>?

    init(app: AppContainer) { self.app = app }

    /// How a match is listed and shown once picked.
    static func label(_ s: StudentRow) -> String { s.name.map { "\($0) (\(s.email))" } ?? s.email }

    /// The search box changed: look the students up once typing pauses (two letters at least).
    func type(_ value: String) {
        query = value
        job?.cancel()
        let q = value.trimmed
        if q.count < 2 { matches = []; return }
        let app = self.app
        job = Task {
            try? await Task.sleep(for: .milliseconds(350)) // wait for typing to pause
            if Task.isCancelled { return }
            let found = await mainApiCall { try await app.service(StudentsAdminAPI.self).list(page: 1, q: q, sort: nil) }.value?.data ?? []
            if Task.isCancelled { return }
            matches = Array(found.prefix(8))
        }
    }

    /// Picks [student]: the new filter string.
    func pick(_ student: StudentRow, filter: String?) -> String? {
        selectedLabel = Self.label(student)
        job?.cancel()
        query = ""
        matches = []
        return moneyWithFilters(filter, ["studentId": student.id])
    }

    /// Clears the picked student: the new filter string.
    func clear(filter: String?) -> String? {
        selectedLabel = nil
        return moneyWithFilters(filter, ["studentId": nil])
    }
}

/// The finance lists' "Student" filter, as a search: type part of a name or e-mail and pick from the matches. It used
/// to be a menu of every student in the academy, loaded in full each time, which grows without limit.
struct MoneyStudentFilter: View {
    let model: MoneyStudentFilterModel
    let filter: String?
    let onChange: (String?) -> Void

    var body: some View {
        if moneyDecodeFilters(filter)["studentId"] != nil {
            HStack(spacing: 0) {
                Text("Student: \(model.selectedLabel ?? "selected")").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TextButton("Clear") { onChange(model.clear(filter: filter)) }
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                FormTextField(
                    "Student (name or e-mail)", text: Binding(get: { model.query }, set: { model.type($0) }),
                    capitalization: .never
                )
                ForEach(model.matches) { s in
                    Button { onChange(model.pick(s, filter: filter)) } label: {
                        Text(MoneyStudentFilterModel.label(s)).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10).padding(.horizontal, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
