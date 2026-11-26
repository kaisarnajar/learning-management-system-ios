import SwiftUI

/// Material 3's SecondaryTabRow: equal-width tabs, a 2pt primary underline across the selected tab, a hairline below
/// (Courses: My courses / Catalogue).
struct SecondaryTabRow: View {
    let tabs: [String]
    @Binding var selected: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, label in
                    TabLabel(label: label, selected: selected == index, unselectedColor: Scheme.onSurface) { selected = index }
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .bottom) {
                            if selected == index { Rectangle().fill(Scheme.primary).frame(height: 2) }
                        }
                }
            }
            HairlineDivider()
        }
        .background(Scheme.background)
        .animation(.easeOut(duration: 0.2), value: selected)
    }
}

/// Material 3's PrimaryScrollableTabRow: tabs as wide as their label (at least 90pt) after a 12pt edge padding, a 3pt
/// rounded indicator under the selected label, a hairline below (the enrolled course's tabs).
struct PrimaryScrollableTabRow: View {
    let tabs: [String]
    @Binding var selected: Int

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(Array(tabs.enumerated()), id: \.offset) { index, label in
                            TabLabel(label: label, selected: selected == index, unselectedColor: Scheme.onSurfaceVariant) {
                                selected = index
                                withAnimation { proxy.scrollTo(index, anchor: .center) }
                            }
                            .frame(minWidth: 90)
                            .overlay(alignment: .bottom) {
                                if selected == index {
                                    UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                                        .fill(Scheme.primary)
                                        .frame(height: 3)
                                        .padding(.horizontal, 16)
                                }
                            }
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            HairlineDivider()
        }
        .background(Scheme.background)
        .animation(.easeOut(duration: 0.2), value: selected)
    }
}

private struct TabLabel: View {
    let label: String
    let selected: Bool
    let unselectedColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .textStyle(Typo.titleSmall)
                .foregroundStyle(selected ? Scheme.primary : unselectedColor)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }
}
