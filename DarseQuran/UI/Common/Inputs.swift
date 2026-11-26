import SwiftUI

/// Material 3's OutlinedTextField: a 1pt outline (2pt primary when focused), the label inside until there is text or
/// focus, then floating on the outline; supporting or error text below.
struct OutlinedField: View {
    let label: String
    @Binding var text: String
    var placeholder: String? = nil
    var error: String? = nil
    var supporting: String? = nil
    var secure: Bool = false
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var capitalization: TextInputAutocapitalization = .sentences
    var autocorrect: Bool = true
    var lines: ClosedRange<Int>? = nil
    var enabled: Bool = true
    var leading: Icon? = nil
    var submitLabel: SubmitLabel = .next
    var onSubmit: (() -> Void)? = nil

    @FocusState private var focused: Bool
    @State private var revealed = false
    @Environment(\.fieldSurface) private var surface

    private var floating: Bool { focused || !text.isEmpty }
    private var outline: Color {
        if error != nil { return Scheme.error }
        if !enabled { return Scheme.onSurface.opacity(0.12) }
        return focused ? Scheme.primary : Scheme.outline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Radius.xs)
                    .strokeBorder(outline, lineWidth: focused || error != nil ? 2 : 1)
                HStack(alignment: lines == nil ? .center : .top, spacing: 12) {
                    if let leading { leading.image.font(.system(size: 18)).foregroundStyle(Scheme.onSurfaceVariant).padding(.top, lines == nil ? 0 : 2) }
                    ZStack(alignment: lines == nil ? .leading : .topLeading) {
                        if !floating {
                            Text(label).textStyle(Typo.bodyLarge).foregroundStyle(error != nil ? Scheme.error : Scheme.onSurfaceVariant)
                                .allowsHitTesting(false)
                        } else if let placeholder, text.isEmpty {
                            Text(placeholder).textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurfaceVariant).allowsHitTesting(false)
                        }
                        input
                    }
                    if secure {
                        Button { revealed.toggle() } label: {
                            (revealed ? Icon.visibilityOff : Icon.visibility).image.font(.system(size: 18)).foregroundStyle(Scheme.onSurfaceVariant)
                        }
                        .accessibilityLabel(revealed ? "Hide password" : "Show password")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, lines == nil ? 0 : 16)
                .frame(minHeight: 56)
                if floating {
                    Text(label)
                        .textStyle(Typo.bodySmall)
                        .foregroundStyle(error != nil ? Scheme.error : (focused ? Scheme.primary : Scheme.onSurfaceVariant))
                        .padding(.horizontal, 4)
                        .background(surface)
                        .offset(x: 12, y: -8)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .animation(.easeOut(duration: 0.15), value: floating)
            // An empty error marks the field red without a message (Material's isError without supporting text).
            if let message = error ?? supporting, !message.isEmpty {
                Text(message).textStyle(Typo.bodySmall).foregroundStyle(error != nil ? Scheme.error : Scheme.onSurfaceVariant).padding(.horizontal, 16)
            }
        }
        .opacity(enabled ? 1 : 0.6)
        .disabled(!enabled)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var input: some View {
        Group {
            if secure && !revealed {
                SecureField("", text: $text)
            } else if let lines {
                TextField("", text: $text, axis: .vertical).lineLimit(lines)
            } else {
                TextField("", text: $text)
            }
        }
        .textStyle(Typo.bodyLarge)
        .foregroundStyle(Scheme.onSurface)
        .tint(Scheme.primary)
        .keyboardType(keyboard)
        .textContentType(contentType)
        .textInputAutocapitalization(secure ? .never : capitalization)
        .autocorrectionDisabled(secure || !autocorrect)
        .submitLabel(submitLabel)
        .onSubmit { onSubmit?() }
        .focused($focused)
        .accessibilityLabel(label)
        .accessibilityHint(error ?? "")
    }
}

/// A selectable pill (amount, month, year choices).
struct ChoicePill: View {
    let label: String
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.input)
        Button(action: onClick) {
            Text(label)
                .textStyle(Typo.labelLarge)
                .foregroundStyle(selected ? Scheme.onPrimaryContainer : Scheme.onSurface)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(selected ? Scheme.primaryContainer : Scheme.surfaceContainerLowest, in: shape)
                .overlay(shape.strokeBorder(selected ? Scheme.primary : Brand.outlineSoft, lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(PressableStyle(shape: shape))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Material's FilterChip as Android uses it (no leading icon): outlined, filled with the secondary container when selected.
struct FilterChip: View {
    let label: String
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.input)
        Button(action: onClick) {
            Text(label).textStyle(Typo.labelLarge).lineLimit(1)
            .foregroundStyle(selected ? Scheme.onSecondaryContainer : Scheme.onSurfaceVariant)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(selected ? Scheme.secondaryContainer : Color.clear, in: shape)
            .overlay(shape.strokeBorder(selected ? Color.clear : Scheme.outlineVariant, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle(shape: shape))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A row of filter chips that scrolls sideways.
struct ChipRow: View {
    let options: [(id: String?, label: String)]
    let selected: String?
    let onSelect: (String?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    FilterChip(label: option.label, selected: option.id == selected) { onSelect(option.id) }
                }
            }
        }
    }
}

/// A read-only outlined field that opens a menu of [options] (Android's ExposedDropdownMenu).
struct Dropdown: View {
    @Environment(\.fieldSurface) private var surface
    let value: String
    let options: [String]
    var label: String? = nil
    var error: String? = nil
    let onSelect: (Int) -> Void

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button(option) { onSelect(index) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: Radius.xs).strokeBorder(error != nil ? Scheme.error : Scheme.outline, lineWidth: 1)
                    HStack {
                        Text(value.isEmpty ? (label ?? "") : value)
                            .textStyle(Typo.bodyLarge)
                            .foregroundStyle(value.isEmpty ? Scheme.onSurfaceVariant : Scheme.onSurface)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(Scheme.onSurfaceVariant)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    if let label, !value.isEmpty {
                        Text(label).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                            .padding(.horizontal, 4).background(surface).offset(x: 12, y: -8)
                    }
                }
                if let error { Text(error).textStyle(Typo.bodySmall).foregroundStyle(Scheme.error).padding(.horizontal, 16) }
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel(label ?? "")
        .accessibilityValue(value)
    }
}

/// A rounded search box that searches on Return and clears with the ✕ (Android's SearchField).
struct SearchField: View {
    let initial: String
    let placeholder: String
    let onSearch: (String) -> Void
    @State private var text: String
    @FocusState private var focused: Bool

    init(initial: String, placeholder: String, onSearch: @escaping (String) -> Void) {
        self.initial = initial
        self.placeholder = placeholder
        self.onSearch = onSearch
        _text = State(initialValue: initial)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.sheet)
        HStack(spacing: 12) {
            Icon.search.image.font(.system(size: 18)).foregroundStyle(Scheme.onSurfaceVariant)
            ZStack(alignment: .leading) {
                if text.isEmpty { Text(placeholder).textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurfaceVariant).lineLimit(1) }
                TextField("", text: $text)
                    .textStyle(Typo.bodyLarge)
                    .foregroundStyle(Scheme.onSurface)
                    .tint(Scheme.primary)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .onSubmit { onSearch(text.trimmed) }
                    .accessibilityLabel(placeholder)
            }
            if !text.isEmpty {
                Button { text = ""; onSearch("") } label: {
                    Icon.close.image.font(.system(size: 15, weight: .medium)).foregroundStyle(Scheme.onSurfaceVariant).frame(width: 32, height: 32)
                }
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .overlay(shape.strokeBorder(focused ? Scheme.primary : Scheme.outline, lineWidth: focused ? 2 : 1))
        .contentShape(shape)
        .onTapGesture { focused = true }
    }
}

/// A switch row (Material Switch, primary when on).
struct SwitchRow: View {
    let label: String
    var supporting: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
                if let supporting { Text(supporting).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant) }
            }
        }
        .toggleStyle(MaterialSwitchStyle())
    }
}

/// Material 3's Switch: a 52×32 track, primary when on with a large thumb, outlined with a small thumb when off.
struct MaterialSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 12) {
                configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? Scheme.primary : Scheme.surfaceContainerHighest)
                        .overlay(Capsule().strokeBorder(configuration.isOn ? Color.clear : Scheme.outline, lineWidth: 2))
                        .frame(width: 52, height: 32)
                    Circle()
                        .fill(configuration.isOn ? Scheme.onPrimary : Scheme.outline)
                        .frame(width: configuration.isOn ? 24 : 16, height: configuration.isOn ? 24 : 16)
                        .overlay {
                            if configuration.isOn {
                                Icon.check.image.font(.system(size: 11, weight: .bold)).foregroundStyle(Scheme.onPrimaryContainer)
                            }
                        }
                        .padding(.horizontal, configuration.isOn ? 4 : 8)
                }
                .animation(.easeOut(duration: 0.15), value: configuration.isOn)
                .opacity(enabled ? 1 : 0.38)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// A radio button row.
struct RadioRow: View {
    let label: String
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().strokeBorder(selected ? Scheme.primary : Scheme.onSurfaceVariant, lineWidth: 2).frame(width: 20, height: 20)
                    if selected { Circle().fill(Scheme.primary).frame(width: 10, height: 10) }
                }
                .frame(width: 40, height: 40)
                Text(label).textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}

/// A checkbox row.
struct CheckboxRow<Label: View>: View {
    let checked: Bool
    let onToggle: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 2).strokeBorder(checked ? Scheme.primary : Scheme.onSurfaceVariant, lineWidth: 2)
                        .background(checked ? Scheme.primary : .clear, in: RoundedRectangle(cornerRadius: 2))
                        .frame(width: 18, height: 18)
                    if checked { Icon.check.image.font(.system(size: 12, weight: .bold)).foregroundStyle(Scheme.onPrimary) }
                }
                .frame(width: 40, height: 40)
                label()
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? [.isSelected, .isButton] : .isButton)
    }
}

/// The colour behind a text field (its floating label is drawn on it): the screen's background, or the card's.
struct FieldSurfaceKey: EnvironmentKey {
    static let defaultValue: Color = Scheme.background
}

extension EnvironmentValues {
    var fieldSurface: Color {
        get { self[FieldSurfaceKey.self] }
        set { self[FieldSurfaceKey.self] = newValue }
    }
}
