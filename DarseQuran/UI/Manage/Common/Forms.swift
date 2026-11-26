import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/*
 * Form fields for admin and teacher screens (Android's ui/manage/common/Forms.kt). Values are kept as the strings the
 * website's forms send (dates as YYYY-MM-DD, amounts as typed), so a screen can hand them straight to
 * `formOf { $0.text(...) }`. The rich text editor is in RichTextField.swift.
 */

// MARK: - the form screen

/// What a form screen shows and allows (the rules of [FormScreen], kept apart so they can be tested).
struct FormSaveState: Equatable {
    var saving: Bool
    var canSave: Bool = true
    var loadError: String? = nil
    var hasRetry: Bool = false

    /// Loading the record failed and can be retried: the error and Try again replace the fields and Save.
    var failedToLoad: Bool { loadError != nil && hasRetry }
    /// Both Save buttons (top bar and bottom) can be pressed.
    var saveEnabled: Bool { !saving && canSave }
}

/// A form screen: scrolling fields, an error banner on top, and a Save button at the bottom (and in the top bar).
///
/// An edit form passes [canSave] = false until its record has loaded, so Save can't send the still-empty fields
/// (blanking the record), and [loadError] with [onRetry] when loading failed, which shows the error and a retry
/// instead of the fields and Save.
struct FormScreen<Content: View>: View {
    let title: String
    let saving: Bool
    let onSave: () -> Void
    var saveLabel: String = "Save"
    var error: String? = nil
    var canSave: Bool = true
    var loadError: String? = nil
    var onRetry: (() -> Void)? = nil
    var onBack: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    init(
        _ title: String, saving: Bool, saveLabel: String = "Save", error: String? = nil, canSave: Bool = true,
        loadError: String? = nil, onRetry: (() -> Void)? = nil, onBack: (() -> Void)? = nil,
        onSave: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.saving = saving
        self.onSave = onSave
        self.saveLabel = saveLabel
        self.error = error
        self.canSave = canSave
        self.loadError = loadError
        self.onRetry = onRetry
        self.onBack = onBack
        self.content = content
    }

    var body: some View {
        let state = FormSaveState(saving: saving, canSave: canSave, loadError: loadError, hasRetry: onRetry != nil)
        ManageScaffold(title, onBack: onBack, actions: {
            if !state.failedToLoad { BarTextButton(saveLabel, enabled: state.saveEnabled, action: onSave) }
        }) {
            if state.failedToLoad, let loadError, let onRetry {
                ErrorState(message: loadError, onRetry: onRetry)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Notice(error ?? loadError)
                        content()
                        Color.clear.frame(height: 4)
                        PrimaryButton(saveLabel, enabled: canSave, loading: saving, action: onSave)
                        Color.clear.frame(height: 24)
                    }
                    .padding(Spacing.screen)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }
}

/// A titled group of fields inside a form.
struct FormSection<Content: View>: View {
    let title: String
    var description: String? = nil
    @ViewBuilder var content: () -> Content

    init(_ title: String, description: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.description = description
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).textStyle(Typo.titleMedium).foregroundStyle(Scheme.primary).accessibilityAddTraits(.isHeader)
            if let description { Text(description).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant) }
            content()
        }
    }
}

// MARK: - text

/// The keyboard a form field asks for (Android's KeyboardType).
enum FormKeyboard {
    case text, number, decimal, email, phone, uri

    var uiKeyboard: UIKeyboardType {
        switch self {
        case .text: .default
        case .number: .numberPad
        case .decimal: .decimalPad
        case .email: .emailAddress
        case .phone: .phonePad
        case .uri: .URL
        }
    }
}

/// An outlined text field (Material OutlinedTextField). [maxLength] cuts what is typed or pasted; [isError] draws it
/// in the error colour (with [supporting] as the message).
struct FormTextField: View {
    let label: String
    @Binding var text: String
    var supporting: String? = nil
    var singleLine: Bool = true
    var minLines: Int = 1
    var keyboard: FormKeyboard = .text
    var capitalization: TextInputAutocapitalization? = nil
    var enabled: Bool = true
    var isError: Bool = false
    var maxLength: Int? = nil

    init(
        _ label: String, text: Binding<String>, supporting: String? = nil, singleLine: Bool = true, minLines: Int = 1,
        keyboard: FormKeyboard = .text, capitalization: TextInputAutocapitalization? = nil, enabled: Bool = true,
        isError: Bool = false, maxLength: Int? = nil
    ) {
        self.label = label
        self._text = text
        self.supporting = supporting
        self.singleLine = singleLine
        self.minLines = minLines
        self.keyboard = keyboard
        self.capitalization = capitalization
        self.enabled = enabled
        self.isError = isError
        self.maxLength = maxLength
    }

    var body: some View {
        let limited = Binding(get: { text }, set: { new in text = maxLength.map { String(new.prefix($0)) } ?? new })
        OutlinedField(
            label: label, text: limited,
            error: isError ? (supporting ?? "") : nil,
            supporting: isError ? nil : supporting,
            keyboard: keyboard.uiKeyboard,
            contentType: keyboard == .email ? .emailAddress : nil,
            // Text gets sentence case; numbers, e-mails and links none (Android's default).
            capitalization: capitalization ?? (keyboard == .text ? .sentences : .never),
            autocorrect: keyboard == .text,
            lines: singleLine ? nil : max(1, minLines)...max(minLines, 40),
            enabled: enabled
        )
    }
}

/// Whole numbers only.
struct FormNumberField: View {
    let label: String
    @Binding var text: String
    var supporting: String? = nil

    init(_ label: String, text: Binding<String>, supporting: String? = nil) {
        self.label = label
        self._text = text
        self.supporting = supporting
    }

    var body: some View {
        FormTextField(label, text: Binding(get: { text }, set: { text = digitsOnly($0) }), supporting: supporting, keyboard: .number)
    }
}

/// Rupees, with up to two decimals (what the website's amount inputs take).
struct FormMoneyField: View {
    let label: String
    @Binding var text: String
    var supporting: String? = nil

    init(_ label: String, text: Binding<String>, supporting: String? = nil) {
        self.label = label
        self._text = text
        self.supporting = supporting
    }

    var body: some View {
        FormTextField(label, text: Binding(get: { text }, set: { if let clean = moneyInput($0) { text = clean } }), supporting: supporting, keyboard: .decimal)
    }
}

/// [value] with only its digits (FormNumberField's filter).
func digitsOnly(_ value: String) -> String { value.filter(\.isASCIIDigitLike) }

/// What a money field keeps of [value]: digits and one dot with at most two decimals, or nil to refuse the edit
/// (FormMoneyField's filter).
func moneyInput(_ value: String) -> String? {
    let clean = value.filter { $0.isASCIIDigitLike || $0 == "." }
    let dots = clean.filter { $0 == "." }.count
    let decimals = clean.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
    return dots <= 1 && decimals <= 2 ? clean : nil
}

private extension Character {
    /// 0–9 (Kotlin's isDigit, for the digits a keyboard types).
    var isASCIIDigitLike: Bool { isNumber && isASCII }
}

/// Paise → the text a money field shows ("1250" or "1250.5"; "" for nil).
func paiseToRupeesText(_ paise: Int?) -> String {
    guard let paise else { return "" }
    let sign = paise < 0 ? "-" : ""
    let p = abs(paise)
    let rupees = p / 100, cents = p % 100
    if cents == 0 { return "\(sign)\(rupees)" }
    var fraction = String(format: "%02d", cents)
    if fraction.hasSuffix("0") { fraction.removeLast() }
    return "\(sign)\(rupees).\(fraction)"
}

// MARK: - choices

/// On/off with an explanation, sent as a checkbox ("on" or absent). The whole row toggles.
struct FormSwitch: View {
    let label: String
    let checked: Bool
    let onChange: (Bool) -> Void
    var description: String? = nil

    init(_ label: String, checked: Bool, description: String? = nil, onChange: @escaping (Bool) -> Void) {
        self.label = label
        self.checked = checked
        self.description = description
        self.onChange = onChange
    }

    var body: some View {
        Button { onChange(!checked) } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(label).textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
                    if let description { Text(description).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                Toggle("", isOn: Binding(get: { checked }, set: { onChange($0) }))
                    .labelsHidden()
                    .tint(Scheme.primary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle(shape: RoundedRectangle(cornerRadius: Radius.input)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityHint(description ?? "")
        .accessibilityValue(checked ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

/// A checkbox row (for confirmations such as "I understand this cannot be undone").
struct FormCheckbox: View {
    let label: String
    let checked: Bool
    let onChange: (Bool) -> Void

    init(_ label: String, checked: Bool, onChange: @escaping (Bool) -> Void) {
        self.label = label
        self.checked = checked
        self.onChange = onChange
    }

    var body: some View {
        CheckboxRow(checked: checked, onToggle: { onChange(!checked) }) {
            Text(label).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface).multilineTextAlignment(.leading)
        }
    }
}

/// Pick one of [options] (value, label). An empty value shows the label in the field; one not among the options
/// shows as it is.
struct FormDropdown: View {
    let label: String
    let options: [(value: String, label: String)]
    let value: String
    let onChange: (String) -> Void
    var placeholder: String = "Choose…"
    var supporting: String? = nil
    var enabled: Bool = true

    init(
        _ label: String, options: [(value: String, label: String)], value: String, placeholder: String = "Choose…",
        supporting: String? = nil, enabled: Bool = true, onChange: @escaping (String) -> Void
    ) {
        self.label = label
        self.options = options
        self.value = value
        self.placeholder = placeholder
        self.supporting = supporting
        self.enabled = enabled
        self.onChange = onChange
    }

    var body: some View {
        let shown = options.first { $0.value == value }?.label ?? (value.trimmed.isEmpty ? "" : value)
        VStack(alignment: .leading, spacing: 4) {
            Dropdown(value: shown, options: options.map(\.label), label: label) { onChange(options[$0].value) }
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.6)
            if let supporting {
                Text(supporting).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - dates

private let isoDateFormat: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.calendar = Calendar(identifier: .gregorian)
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"
    f.isLenient = false
    return f
}()

private let showDateFormat: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.calendar = Calendar(identifier: .gregorian)
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "d MMM yyyy"
    return f
}()

/// A YYYY-MM-DD date as a day (UTC midnight), nil when it isn't one.
func parseIsoDate(_ value: String) -> Date? {
    guard value.count == 10, let date = isoDateFormat.date(from: value) else { return nil }
    return isoDateFormat.string(from: date) == value ? date : nil
}

/// A day as YYYY-MM-DD.
func isoDateString(_ date: Date) -> String { isoDateFormat.string(from: date) }

/// Today at the academy as YYYY-MM-DD (Android's `academyToday().toString()`).
func academyTodayIso(now: Date = Date()) -> String {
    let d = academyToday(now: now)
    return String(format: "%04d-%02d-%02d", d.year ?? 1970, d.month ?? 1, d.day ?? 1)
}

/// A date as YYYY-MM-DD ("" when not set). Accepts full ISO timestamps from the API too.
func dateOnly(_ value: String?) -> String {
    guard let value else { return "" }
    let day = String(value.prefix(10))
    return parseIsoDate(day) != nil ? day : ""
}

/// Pick a date; [value] and the result are YYYY-MM-DD. [clearable] adds a ✕ that empties it.
struct FormDateField: View {
    let label: String
    let value: String
    let onChange: (String) -> Void
    var supporting: String? = nil
    var clearable: Bool = false
    @State private var open = false

    init(_ label: String, value: String, supporting: String? = nil, clearable: Bool = false, onChange: @escaping (String) -> Void) {
        self.label = label
        self.value = value
        self.supporting = supporting
        self.clearable = clearable
        self.onChange = onChange
    }

    var body: some View {
        let date = parseIsoDate(value)
        OutlinedBox(label: label, value: date.map { showDateFormat.string(from: $0) } ?? "", supporting: supporting) {
            if clearable, date != nil {
                IconButton(.close, label: "Clear", tint: Scheme.onSurfaceVariant, size: 18) { onChange("") }
            } else {
                Icon.calendar.image.font(.system(size: 18)).foregroundStyle(Scheme.onSurfaceVariant).frame(width: 48, height: 48)
                    .accessibilityHidden(true)
            }
        } onTap: {
            open = true
        }
        .materialDialog(isPresented: $open) {
            DatePickerDialogBody(initial: date ?? parseIsoDate(academyTodayIso()) ?? Date(), onPick: onChange) { open = false }
        }
    }
}

/// Material's DatePickerDialog: a calendar, Cancel and OK.
private struct DatePickerDialogBody: View {
    let onPick: (String) -> Void
    let onDismiss: () -> Void
    @State private var selection: Date

    init(initial: Date, onPick: @escaping (String) -> Void, onDismiss: @escaping () -> Void) {
        self.onPick = onPick
        self.onDismiss = onDismiss
        _selection = State(initialValue: initial)
    }

    var body: some View {
        DatePicker("", selection: $selection, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(Scheme.primary)
            .environment(\.timeZone, TimeZone(identifier: "UTC")!)
            .environment(\.locale, Locale(identifier: "en_GB"))
        DialogButtons(dismissLabel: "Cancel", confirmLabel: "OK", onDismiss: onDismiss) {
            onPick(isoDateString(selection))
            onDismiss()
        }
    }
}

/// A read-only outlined field that does something when tapped (a date, a picker): the label floats on the outline
/// once there is a value, like OutlinedField; [trailing] sits at the end.
struct OutlinedBox<Trailing: View>: View {
    let label: String
    let value: String
    var supporting: String? = nil
    var error: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Radius.xs).strokeBorder(error != nil ? Scheme.error : Scheme.outline, lineWidth: 1)
                HStack(spacing: 0) {
                    Button(action: onTap) {
                        Text(value.isEmpty ? label : value)
                            .textStyle(Typo.bodyLarge)
                            .foregroundStyle(value.isEmpty ? Scheme.onSurfaceVariant : Scheme.onSurface)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .padding(.leading, 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label)
                    .accessibilityValue(value)
                    trailing().padding(.trailing, 4)
                }
                if !value.isEmpty {
                    Text(label).textStyle(Typo.bodySmall).foregroundStyle(error != nil ? Scheme.error : Scheme.onSurfaceVariant)
                        .padding(.horizontal, 4).background(Scheme.background).offset(x: 12, y: -8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 56)
            if let message = error ?? supporting {
                Text(message).textStyle(Typo.bodySmall).foregroundStyle(error != nil ? Scheme.error : Scheme.onSurfaceVariant).padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - files

/// Material's OutlinedButton (pill, 40pt, outline border, primary label).
struct PillOutlinedButton: View {
    let text: String
    var enabled: Bool = true
    var icon: Icon? = nil
    let action: () -> Void

    init(_ text: String, icon: Icon? = nil, enabled: Bool = true, action: @escaping () -> Void) {
        self.text = text
        self.icon = icon
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { icon.image.font(.system(size: 16, weight: .medium)) }
                Text(text).textStyle(Typo.labelLarge)
            }
            .foregroundStyle(enabled ? Scheme.primary : Scheme.onSurface.opacity(0.38))
            .padding(.horizontal, icon == nil ? 24 : 16)
            .frame(minHeight: 40)
            .overlay(Capsule().strokeBorder(enabled ? Scheme.outline : Scheme.onSurface.opacity(0.12), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(shape: Capsule()))
        .disabled(!enabled)
    }
}

/// An image: shows the picked one, else the current one from the server ([currentUrl]); "Choose" opens the photo
/// picker, "Undo" drops the pick, and "Remove" (with [onRemoveCurrent]) asks to remove the saved image. A picked
/// photo is checked against [limit] (HEIC becomes JPEG); one that can't be used is explained in a toast.
struct FormImageField: View {
    let label: String
    let currentUrl: String?
    let picked: PickedFile?
    let onPick: (PickedFile?) -> Void
    var supporting: String? = nil
    var onRemoveCurrent: (() -> Void)? = nil
    var limit: UploadLimit = .cover
    @Environment(Toaster.self) private var toaster
    @State private var choosing = false
    @State private var item: PhotosPickerItem?

    init(
        _ label: String, currentUrl: String?, picked: PickedFile?, supporting: String? = nil, onRemoveCurrent: (() -> Void)? = nil,
        limit: UploadLimit = .cover, onPick: @escaping (PickedFile?) -> Void
    ) {
        self.label = label
        self.currentUrl = currentUrl
        self.picked = picked
        self.supporting = supporting
        self.onRemoveCurrent = onRemoveCurrent
        self.limit = limit
        self.onPick = onPick
    }

    var body: some View {
        let hasCurrent = !(currentUrl?.trimmed.isEmpty ?? true)
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            Text(label).textStyle(Typo.labelLarge).foregroundStyle(Scheme.onSurfaceVariant)
            Button { choosing = true } label: {
                ZStack {
                    Scheme.surfaceContainer
                    if let picked, let image = UIImage(data: picked.bytes) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else if hasCurrent {
                        RemoteImage(path: currentUrl)
                    } else {
                        VStack(spacing: 4) {
                            Icon.image.image.font(.system(size: 22)).foregroundStyle(Scheme.onSurfaceVariant)
                            Text("Tap to choose an image").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Brand.outlineSoft, lineWidth: 1))
                .contentShape(shape)
            }
            .buttonStyle(CardPressStyle())
            .accessibilityLabel(label)
            HStack(spacing: 8) {
                PillOutlinedButton(picked != nil || hasCurrent ? "Change" : "Choose") { choosing = true }
                if picked != nil {
                    TextButton("Undo") { onPick(nil) }
                } else if hasCurrent, let onRemoveCurrent {
                    TextButton("Remove", color: Scheme.error, action: onRemoveCurrent)
                }
            }
            if let supporting { Text(supporting).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant) }
        }
        .photosPicker(isPresented: $choosing, selection: $item, matching: .images)
        .onChange(of: item) { _, new in
            guard let new else { return }
            item = nil
            Task { await load(new) }
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        let type = item.supportedContentTypes.first
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            showRejected(toaster, .rejected("This file couldn't be read."))
            return
        }
        let mime = type?.preferredMIMEType ?? "image/jpeg"
        let outcome = await readPicked(data: data, name: nil, mime: mime, limit: limit)
        if let file = outcome.file { onPick(file) } else { showRejected(toaster, outcome) }
    }
}

/// A document (PDF, etc.) from the phone's files. [currentName] describes what is saved already. [mimeTypes] are
/// the types the picker offers (e.g. ["application/pdf"]).
struct FormFileField: View {
    let label: String
    let mimeTypes: [String]
    let picked: PickedFile?
    let onPick: (PickedFile?) -> Void
    var currentName: String? = nil
    var supporting: String? = nil
    var limit: UploadLimit = .attachment
    @Environment(Toaster.self) private var toaster
    @State private var choosing = false

    init(
        _ label: String, mimeTypes: [String], picked: PickedFile?, currentName: String? = nil, supporting: String? = nil,
        limit: UploadLimit = .attachment, onPick: @escaping (PickedFile?) -> Void
    ) {
        self.label = label
        self.mimeTypes = mimeTypes
        self.picked = picked
        self.currentName = currentName
        self.supporting = supporting
        self.limit = limit
        self.onPick = onPick
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.input, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            Text(label).textStyle(Typo.labelLarge).foregroundStyle(Scheme.onSurfaceVariant)
            HStack(spacing: 0) {
                Button { choosing = true } label: {
                    HStack(spacing: 10) {
                        Icon.attachment.image.font(.system(size: 18, weight: .medium)).foregroundStyle(Scheme.primary)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(picked?.name ?? currentName ?? "Choose a file").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
                                .multilineTextAlignment(.leading)
                            if let picked {
                                Text(String(format: "%.1f KB, will be uploaded", locale: Locale(identifier: "en_US_POSIX"), Double(picked.bytes.count) / 1024.0))
                                    .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if picked != nil { IconButton(.close, label: "Remove", size: 18) { onPick(nil) } }
            }
            .padding(14)
            .frame(minHeight: 48)
            .overlay(shape.strokeBorder(Brand.outlineSoft, lineWidth: 1))
            .contentShape(shape)
            if let supporting { Text(supporting).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant) }
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: contentTypes) { result in
            guard case .success(let url) = result else { return }
            Task {
                let outcome = await readPicked(fileAt: url, limit: limit)
                if let file = outcome.file { onPick(file) } else { showRejected(toaster, outcome) }
            }
        }
    }

    private var contentTypes: [UTType] {
        let types = mimeTypes.compactMap { mime -> UTType? in
            if mime == "*/*" { return .item }
            if mime.hasSuffix("/*") { return UTType(String(mime.dropLast(2))) ?? (mime.hasPrefix("image") ? .image : nil) }
            return UTType(mimeType: mime)
        }
        return types.isEmpty ? [.item] : types
    }
}

// MARK: - form state

/// A form's chosen files and removal marks (Android's FormFiles ViewModel). Keep it in the screen's model so the
/// picks live as long as the screen:
///
///     let files = FormFiles()           // picked: [PickedFile], single: PickedFile?, removed: Set<String>
@MainActor
@Observable
final class FormFiles {
    var picked: [PickedFile] = []
    var single: PickedFile? = nil
    var removed: Set<String> = []
}

/// Starts a form over once it has been sent: the form sits inside `.id(reset.generation)` and the success callback
/// calls [reset], so its fields (view @State) begin again (Android's FormReset).
@MainActor
@Observable
final class FormReset {
    private(set) var generation = 0
    func reset() { generation += 1 }
}

/// Tells the admin why a chosen file wasn't taken (too big, wrong type, unreadable).
@MainActor
func showRejected(_ toaster: Toaster, _ outcome: PickOutcome) {
    if let reason = outcome.reason { toaster.show(reason, long: true) }
}

// MARK: - homepage slots

/// Whether an item may be shown on the homepage: one already featured stays; a new one only while a slot is free.
func canFeature(currentlyFeatured: Bool, used: Int, max: Int) -> Bool { currentlyFeatured || used < max }

/// The "Show on homepage" description the website's forms use.
func featuredDescription(canFeature: Bool, used: Int, max: Int, section: String, pageName: String, noun: String, condition: String = "when published") -> String {
    canFeature
        ? "Featured in the \(section) section \(condition) (up to \(max); \(min(used, max))/\(max) slots used). All published \(noun) still appear on the \(pageName)."
        : "There are already \(max) featured \(noun). Remove one from the homepage to feature this one."
}

/// "Show on homepage", within the homepage's [max] slots ([used] taken; [currentlyFeatured] = this item holds one).
/// Turning it off is always allowed; turning it on only while [canFeature].
struct FeaturedSwitch: View {
    let featured: Bool
    let onChange: (Bool) -> Void
    let currentlyFeatured: Bool
    let used: Int
    let max: Int
    let section: String
    let pageName: String
    let noun: String
    var condition: String = "when published"

    init(
        featured: Bool, currentlyFeatured: Bool, used: Int, max: Int, section: String, pageName: String, noun: String,
        condition: String = "when published", onChange: @escaping (Bool) -> Void
    ) {
        self.featured = featured
        self.currentlyFeatured = currentlyFeatured
        self.used = used
        self.max = max
        self.section = section
        self.pageName = pageName
        self.noun = noun
        self.condition = condition
        self.onChange = onChange
    }

    /// Whether a tap that sets the switch to [newValue] goes through.
    static func accepts(_ newValue: Bool, allowed: Bool) -> Bool { allowed || !newValue }

    var body: some View {
        let allowed = canFeature(currentlyFeatured: currentlyFeatured, used: used, max: max)
        FormSwitch(
            "Show on homepage", checked: featured && allowed,
            description: featuredDescription(canFeature: allowed, used: used, max: max, section: section, pageName: pageName, noun: noun, condition: condition)
        ) { new in
            if Self.accepts(new, allowed: allowed) { onChange(new) }
        }
    }
}

/// [options] with "Other" at the end (where a value can be typed), whether or not the server's list has it.
func withOther(_ options: [String]) -> [String] {
    options.contains { $0.caseInsensitiveCompare("Other") == .orderedSame } ? options : options + ["Other"]
}
