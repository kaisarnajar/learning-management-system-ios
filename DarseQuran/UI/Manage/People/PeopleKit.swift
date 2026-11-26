import SwiftUI

/*
 * Pieces shared by the people screens (Android's ui/manage/people/PeopleKit.kt): a list row with its actions
 * underneath, the small buttons on those rows, and the review stars.
 */

/// A list row with its actions underneath (a table row's buttons, on a phone). Android's ActionCard.
struct PeopleActionCard<Leading: View, Actions: View>: View {
    let title: String
    var subtitle: String? = nil
    var meta: String? = nil
    var chip: (String, Tone)? = nil
    var bodyText: String? = nil
    var onClick: (() -> Void)? = nil
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var actions: () -> Actions

    init(
        title: String, subtitle: String? = nil, meta: String? = nil, chip: (String, Tone)? = nil, body: String? = nil,
        onClick: (() -> Void)? = nil,
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.meta = meta
        self.chip = chip
        self.bodyText = body
        self.onClick = onClick
        self.leading = leading
        self.actions = actions
    }

    var body: some View {
        AppCard(padding: 14, onClick: onClick) {
            HStack(alignment: .center, spacing: 0) {
                if Leading.self != EmptyView.self { leading(); Spacer().frame(width: 12) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).textStyle(Typo.titleSmall).fontWeight(.semibold).foregroundStyle(Scheme.onSurface).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let subtitle, !subtitle.trimmed.isEmpty {
                        Text(subtitle).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    if let meta, !meta.trimmed.isEmpty {
                        Text(meta).textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let bodyText, !bodyText.trimmed.isEmpty {
                Spacer().frame(height: 8)
                Text(bodyText).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface).lineLimit(3).multilineTextAlignment(.leading)
            }
            if let chip {
                Spacer().frame(height: 8)
                StatusChip(chip.0, tone: chip.1)
            }
            Spacer().frame(height: 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 8) { actions() }
            }
        }
    }
}

/// A small gold button (Material Button with the CTA colours, 14pt sides). Android's SmallPrimary.
struct PeopleSmallPrimary: View {
    let label: String
    var enabled: Bool = true
    let action: () -> Void

    init(_ label: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.label = label
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label).textStyle(Typo.labelLarge).lineLimit(1)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .frame(minHeight: 40)
        }
        .buttonStyle(FilledStyle(background: Brand.cta, foreground: Brand.onCta, radius: 20))
        .disabled(!enabled)
    }
}

/// A small outlined pill button. Android's SmallOutlined.
struct PeopleSmallOutlined: View {
    let label: String
    var enabled: Bool = true
    let action: () -> Void

    init(_ label: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.label = label
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label).textStyle(Typo.labelLarge).lineLimit(1)
                .foregroundStyle(enabled ? Scheme.primary : Scheme.onSurface.opacity(0.38))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .frame(minHeight: 40)
                .overlay(Capsule().strokeBorder(enabled ? Scheme.outline : Scheme.onSurface.opacity(0.12), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(shape: Capsule()))
        .disabled(!enabled)
    }
}

/// A text button in the error colour. Android's SmallDanger.
struct PeopleSmallDanger: View {
    let label: String
    var enabled: Bool = true
    let action: () -> Void

    init(_ label: String, enabled: Bool = true, action: @escaping () -> Void) {
        self.label = label
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        BarTextButton(label, enabled: enabled, color: Scheme.error, action: action)
    }
}

/// 1–5 stars. Android's Stars.
struct PeopleStars: View {
    let rating: Int
    var size: CGFloat = 18

    init(_ rating: Int, size: CGFloat = 18) {
        self.rating = rating
        self.size = size
    }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                (i <= rating ? Icon.star : Icon.starOutline).image
                    .font(.system(size: size * 0.8))
                    .foregroundStyle(i <= rating ? Brand.gold : Scheme.outline)
                    .frame(width: size, height: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(rating) out of 5 stars")
    }
}
