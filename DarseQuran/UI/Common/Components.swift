import SwiftUI

// MARK: - bars

/// A detail screen's top bar: back arrow, title, optional actions (Android's BackTopBar).
struct BackTopBar<Actions: View>: View {
    let title: String
    let onBack: () -> Void
    @ViewBuilder var actions: () -> Actions

    init(_ title: String, onBack: @escaping () -> Void, @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }) {
        self.title = title
        self.onBack = onBack
        self.actions = actions
    }

    var body: some View {
        HStack(spacing: 0) {
            IconButton(.back, label: "Back", action: onBack)
            Text(title)
                .textStyle(Typo.titleLarge)
                .foregroundStyle(Scheme.onSurface)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            HStack(spacing: 0) { actions() }.padding(.trailing, 4)
        }
        .frame(height: 64)
        .padding(.leading, 4)
        .background(Scheme.background)
    }
}

/// A tab's top bar: centred title, optional actions (Android's TabTopBar).
struct TabTopBar<Actions: View>: View {
    let title: String
    @ViewBuilder var actions: () -> Actions

    init(_ title: String, @ViewBuilder actions: @escaping () -> Actions = { EmptyView() }) {
        self.title = title
        self.actions = actions
    }

    var body: some View {
        ZStack {
            Text(title).textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface).accessibilityAddTraits(.isHeader)
            HStack { Spacer(); HStack(spacing: 0) { actions() }.padding(.trailing, 4) }
        }
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        .background(Scheme.background)
    }
}

/// A 48pt round icon button with a VoiceOver label (Material IconButton).
struct IconButton: View {
    let icon: Icon
    let label: String
    var tint: Color = Scheme.onSurface
    var size: CGFloat = 22
    let action: () -> Void

    init(_ icon: Icon, label: String, tint: Color = Scheme.onSurface, size: CGFloat = 22, action: @escaping () -> Void) {
        self.icon = icon
        self.label = label
        self.tint = tint
        self.size = size
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            icon.image
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(shape: Circle()))
        .accessibilityLabel(label)
    }
}

/// The ripple Android draws on press, as a light overlay.
struct PressableStyle<S: Shape>: ButtonStyle {
    var shape: S
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(shape.fill(Scheme.onSurface.opacity(configuration.isPressed ? 0.1 : 0)))
            .contentShape(shape)
    }
}

extension PressableStyle where S == Rectangle {
    init() { shape = Rectangle() }
}

// MARK: - structure

/// The website's SplitSectionTitle: uppercase, the last word in gold ("FEATURED **COURSES**"), the rest in the text colour.
func splitTitle(_ title: String) -> (lead: String, accent: String) {
    let words = title.trimmed.uppercased()
    guard let cut = words.lastIndex(of: " "), cut > words.startIndex else { return ("", words) }
    return (String(words[...cut]), String(words[words.index(after: cut)...]))
}

/// Section heading with the last word in gold and an optional "See all" (Android's SectionHeader).
struct SectionHeader: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        let parts = splitTitle(title)
        HStack(alignment: .center) {
            (Text(parts.lead).foregroundStyle(Scheme.onBackground) + Text(parts.accent).foregroundStyle(Brand.gold))
                .styled(Typo.sectionTitle)
                .lineSpacing(Typo.sectionTitle.lineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(title)
            if let action, let onAction {
                Button(action: onAction) {
                    HStack(spacing: 4) {
                        Text(action).textStyle(Typo.labelLarge)
                        Icon.forward.image.font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Scheme.primary)
                    .padding(.horizontal, 12).frame(minHeight: 40)
                }
                .buttonStyle(PressableStyle(shape: Capsule()))
            }
        }
        .padding(.horizontal, Spacing.screen)
        .frame(minHeight: 40)
    }
}

struct GoldRule: View {
    var width: CGFloat = 36
    var body: some View {
        RoundedRectangle(cornerRadius: 2).fill(Brand.goldSoft).frame(width: width, height: 3)
    }
}

struct Overline: View {
    let text: String
    var color: Color = Brand.gold
    var body: some View {
        Text(text.uppercased()).textStyle(Typo.overline).foregroundStyle(color)
    }
}

/// Card: white surface, hairline outline and a soft shadow, like the website's card-elevated (Android's AppCard).
struct AppCard<Content: View>: View {
    var padding: CGFloat = Spacing.card
    var color: Color = Scheme.surfaceContainerLowest
    var onClick: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    init(padding: CGFloat = Spacing.card, color: Color = Scheme.surfaceContainerLowest, onClick: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.color = color
        self.onClick = onClick
        self.content = content
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let card = VStack(alignment: .leading, spacing: 0) { content() }
            .environment(\.fieldSurface, color)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: shape)
            .overlay(shape.strokeBorder(Brand.outlineSoft, lineWidth: 1))
            .clipShape(shape)
            .shadow(color: Brand.cardShadow, radius: 3, x: 0, y: 1.5)
        if let onClick {
            Button(action: onClick) { card }.buttonStyle(CardPressStyle())
        } else {
            card
        }
    }
}

/// A card's press feedback: a faint overlay, kept inside the rounded corners.
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Scheme.onSurface.opacity(configuration.isPressed ? 0.06 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

/// The deep-green hero with a faint geometric pattern, mirroring the website's page heroes (Android's HeroBox).
struct HeroBox<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    LinearGradient(colors: [Brand.hero, Brand.heroDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                    HeroPattern().stroke(Brand.goldSoft, lineWidth: 1.2).opacity(0.07)
                }
                .clipped() // the pattern's last row stays inside the band
            }
    }
}

/// Offset rows of circles, 44pt apart (Android draws them on a Canvas).
struct HeroPattern: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 44
        let radius = step / 2.6
        var y: CGFloat = 0
        var row = 0
        while y < rect.height + step {
            var x: CGFloat = row % 2 == 0 ? 0 : step / 2
            while x < rect.width + step {
                path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                x += step
            }
            y += step * 0.87
            row += 1
        }
        return path
    }
}

// MARK: - status

enum Tone { case success, warning, danger, info, neutral }

extension Tone {
    var colors: (background: Color, foreground: Color) {
        switch self {
        case .success: (Brand.successContainer, Brand.success)
        case .warning: (Brand.warningContainer, Brand.warning)
        case .danger: (Brand.dangerContainer, Brand.danger)
        case .info: (Brand.infoContainer, Brand.info)
        case .neutral: (Scheme.surfaceContainerHigh, Scheme.onSurfaceVariant)
        }
    }
}

struct StatusChip: View {
    let label: String
    let tone: Tone

    init(_ label: String, tone: Tone) {
        self.label = label
        self.tone = tone
    }

    var body: some View {
        Text(label)
            .textStyle(Typo.labelMedium)
            .foregroundStyle(tone.colors.foreground)
            .lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(tone.colors.background, in: Capsule())
    }
}

/// What a status belongs to, where the website words the same status differently.
enum StatusKind { case enrollment, payment, order, waiver, review }

/// Enrollment / payment / order status → label and tone.
func statusLabel(_ status: String, kind: StatusKind = .enrollment) -> (String, Tone) {
    switch status.lowercased() {
    // Enrolments, as the website's enrollments.ts words and colours them
    case "active": return ("Active", .info)
    case "completed": return ("Completed", .success)
    case "pending_approval": return ("Awaiting approval", .warning)
    case "awaiting_enrollment_fee": return ("Awaiting enrollment fee", .warning)
    default: return recordStatusLabel(status, kind)
    }
}

/// Payments, book orders, waivers and reviews.
private func recordStatusLabel(_ status: String, _ kind: StatusKind) -> (String, Tone) {
    switch status.lowercased() {
    case "pending_verification": return ("Pending Verification", .warning)
    case "pending":
        let label = switch kind {
        case .waiver: "Pending Review"
        case .review: "Pending approval"
        default: "Pending"
        }
        return (label, .warning)
    case "approved": return ("Approved", .success)
    case "rejected": return ("Rejected", .danger)
    // A declined fee payment reads "Rejected" on the website; a declined book order "Declined".
    case "declined": return (kind == .order ? "Declined" : "Rejected", .danger)
    case "shipped": return ("Shipped", .info)
    case "refunded": return ("Refunded", .neutral)
    default: return (titleCase(status), .neutral)
    }
}

/// Fee submissions, book orders and waiver requests (any case): waiting is amber, approved green, shipped blue,
/// refused red (StatusTones.kt).
func orderStatusTone(_ status: String?) -> Tone {
    switch (status ?? "").lowercased() {
    case "pending", "pending_verification": .warning
    case "approved": .success
    case "shipped": .info
    case "rejected", "declined": .danger
    default: .neutral // refunded, cancelled, unknown
    }
}

/// Course status, as the website's CourseStatusBadge colours it.
func courseStatusTone(_ status: String) -> Tone {
    switch status {
    case "PUBLISHED": .info
    case "ONGOING": .success
    case "ON_HOLD", "COMING_SOON": .warning
    default: .neutral
    }
}

// MARK: - states

struct LoadingBox: View {
    var height: CGFloat? = nil
    var body: some View {
        ProgressView()
            .tint(Scheme.primary)
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: height == nil ? .infinity : nil)
            .frame(height: height)
    }
}

/// An icon in a soft circle, a title, a message and an optional button: empty and error states (Android's MessageState).
struct MessageState: View {
    let icon: Icon
    let title: String
    var message: String? = nil
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(Scheme.primaryContainer).frame(width: 72, height: 72)
                icon.image.font(.system(size: 30, weight: .regular)).foregroundStyle(Scheme.onPrimaryContainer)
            }
            .accessibilityHidden(true)
            Spacer().frame(height: 16)
            Text(title).textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface).multilineTextAlignment(.center)
            if let message {
                Spacer().frame(height: 6)
                Text(message).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant).multilineTextAlignment(.center)
            }
            if let action, let onAction {
                Spacer().frame(height: 20)
                CtaButton(action, fullWidth: false, action: onAction)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32).padding(.vertical, 48)
    }
}

struct ErrorState: View {
    let message: String
    let onRetry: () -> Void
    var body: some View {
        MessageState(icon: .cloudOff, title: "Couldn't load this", message: message, action: "Try again", onAction: onRetry)
    }
}

struct EmptyState: View {
    let title: String
    var message: String? = nil
    var action: String? = nil
    var onAction: (() -> Void)? = nil
    var body: some View {
        MessageState(icon: .inbox, title: title, message: message, action: action, onAction: onAction)
    }
}

/// Grey rounded blocks that pulse while a list loads (Android's SkeletonList).
struct SkeletonList: View {
    var rows: Int = 5
    var rowHeight: CGFloat = 88
    @State private var dim = false

    var body: some View {
        VStack(spacing: 14) {
            ForEach(0..<rows, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Scheme.surfaceContainerHigh)
                    .frame(height: rowHeight)
            }
        }
        .opacity(dim ? 0.8 : 0.35)
        .padding(Spacing.screen)
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// A rounded grey block for custom skeletons.
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var radius: CGFloat = Radius.card
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Scheme.surfaceContainerHigh).frame(width: width, height: height)
    }
}

/// Renders a [Load] with the standard loading and error states (Android's LoadContent).
struct LoadContent<T, Content: View>: View {
    let state: Load<T>
    let onRetry: () -> Void
    @ViewBuilder var content: (T) -> Content

    var body: some View {
        switch state {
        case .loading: SkeletonList()
        case .failed(let message): ErrorState(message: message, onRetry: onRetry)
        case .ready(let value): content(value)
        }
    }
}

// MARK: - content

/// Arabic text set in Amiri, right to left, centred.
struct ArabicText: View {
    let text: String
    var color: Color = Scheme.onSurface
    var size: CGFloat = 26

    var body: some View {
        let style = Typo.arabic.with(size: size, lineHeight: size * 1.85)
        Text(text)
            .textStyle(style)
            .foregroundStyle(color)
            .multilineTextAlignment(.center)
            .environment(\.layoutDirection, .rightToLeft)
            .frame(maxWidth: .infinity)
    }
}

/// Price with the MRP struck through when it is higher.
struct PriceLine: View {
    let pricePaise: Int
    var mrpPaise: Int? = nil

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 6) {
            Text(rupees(pricePaise)).textStyle(Typo.titleMedium).foregroundStyle(Scheme.primary)
            if let mrp = mrpPaise, mrp > pricePaise {
                Text(rupees(mrp)).textStyle(Typo.bodySmall).strikethrough().foregroundStyle(Scheme.onSurfaceVariant)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The website's primary button: gold with dark text, 52pt tall, full width (Android's PrimaryButton).
struct PrimaryButton: View {
    let text: String
    var enabled: Bool = true
    var loading: Bool = false
    let action: () -> Void

    init(_ text: String, enabled: Bool = true, loading: Bool = false, action: @escaping () -> Void) {
        self.text = text
        self.enabled = enabled
        self.loading = loading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if loading { ProgressView().tint(Brand.onCta) } else { Text(text).textStyle(Typo.labelLarge) }
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(FilledStyle(background: Brand.cta, foreground: Brand.onCta, radius: Radius.input))
        .disabled(!enabled || loading)
        .accessibilityLabel(loading ? "\(text), in progress" : text)
    }
}

/// Material's filled Button (pill), gold with dark text, as MessageState's action.
struct CtaButton: View {
    let text: String
    var fullWidth: Bool = false
    let action: () -> Void

    init(_ text: String, fullWidth: Bool = false, action: @escaping () -> Void) {
        self.text = text
        self.fullWidth = fullWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(text).textStyle(Typo.labelLarge)
                .padding(.horizontal, 24)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 40)
        }
        .buttonStyle(FilledStyle(background: Brand.cta, foreground: Brand.onCta, radius: 20))
    }
}

/// Outlined button, 52pt tall, full width (Android's SecondaryButton).
struct SecondaryButton: View {
    let text: String
    var enabled: Bool = true
    var icon: Icon? = nil
    let action: () -> Void

    init(_ text: String, enabled: Bool = true, icon: Icon? = nil, action: @escaping () -> Void) {
        self.text = text
        self.enabled = enabled
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { icon.image.font(.system(size: 16, weight: .medium)) }
                Text(text).textStyle(Typo.labelLarge)
            }
            .foregroundStyle(enabled ? Scheme.primary : Scheme.onSurface.opacity(0.38))
            .frame(maxWidth: .infinity, minHeight: 52)
            .overlay(RoundedRectangle(cornerRadius: Radius.input).strokeBorder(enabled ? Scheme.outline : Scheme.onSurface.opacity(0.12), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: Radius.input))
        }
        .buttonStyle(PressableStyle(shape: RoundedRectangle(cornerRadius: Radius.input)))
        .disabled(!enabled)
    }
}

/// Material's TextButton: primary-coloured label, no frame.
struct TextButton: View {
    let text: String
    var icon: Icon? = nil
    var color: Color = Scheme.primary
    let action: () -> Void

    init(_ text: String, icon: Icon? = nil, color: Color = Scheme.primary, action: @escaping () -> Void) {
        self.text = text
        self.icon = icon
        self.color = color
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon { icon.image.font(.system(size: 15, weight: .medium)) }
                Text(text).textStyle(Typo.labelLarge)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
        }
        .buttonStyle(PressableStyle(shape: Capsule()))
    }
}

/// A filled button with Material's disabled look (onSurface at 12% / 38%).
struct FilledStyle: ButtonStyle {
    var background: Color
    var foreground: Color
    var radius: CGFloat
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? foreground : Scheme.onSurface.opacity(0.38))
            .background(enabled ? background : Scheme.onSurface.opacity(0.12), in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).fill(Color.black.opacity(configuration.isPressed ? 0.08 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: radius))
    }
}

/// Inline banner: info, warning or error message inside a screen.
struct Banner: View {
    let text: String
    var tone: Tone = .info
    var icon: Icon? = nil

    init(_ text: String, tone: Tone = .info, icon: Icon? = nil) {
        self.text = text
        self.tone = tone
        self.icon = icon
    }

    var body: some View {
        let colors = tone == .neutral ? Tone.info.colors : tone.colors
        HStack(alignment: .center, spacing: 10) {
            if let icon { icon.image.font(.system(size: 18)).foregroundStyle(colors.foreground) }
            Text(text).textStyle(Typo.bodyMedium).foregroundStyle(colors.foreground).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(colors.background, in: RoundedRectangle(cornerRadius: Radius.input))
    }
}

/// A thin divider in the outline-variant colour.
struct HairlineDivider: View {
    var body: some View { Rectangle().fill(Scheme.outlineVariant).frame(height: 1) }
}
