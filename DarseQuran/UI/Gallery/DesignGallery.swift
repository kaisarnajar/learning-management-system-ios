#if DEBUG
import SwiftUI

/// Debug builds only: every shared component on one screen, to compare with the Android app side by side in light and
/// dark. Open it by launching with `SIMCTL_CHILD_DQA_GALLERY=1`.
struct DesignGallery: View {
    @State private var text = ""
    @State private var filled = "student@example.com"
    @State private var password = "secret"
    @State private var pill = 0
    @State private var chip: String? = nil
    @State private var on = true
    @State private var radio = 0
    @State private var checked = true
    @State private var dropdown = "Monthly"

    var body: some View {
        VStack(spacing: 0) {
            BackTopBar("Design system", onBack: {}) { IconButton(.cart, label: "Cart") {} }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    group("Colours") { colours }
                    group("Type scale") { typeScale }
                    SectionHeader(title: "Featured courses", action: "See all", onAction: {})
                        .padding(.horizontal, -Spacing.screen)
                    group("Cards") { cards }
                    group("Status chips") { chips }
                    group("Buttons") { buttons }
                    group("Inputs") { inputs }
                    group("Banners") {
                        Banner("Payment under review. The academy will confirm it shortly.", tone: .info, icon: .info)
                        Banner("Your March fee is due.", tone: .warning, icon: .warning)
                        Banner("Payment approved.", tone: .success, icon: .checkCircle)
                        Banner("Couldn't load the academy's payment details.", tone: .danger, icon: .error)
                    }
                    group("Inspiration") { inspiration }
                    group("States") {
                        EmptyState(title: "No courses yet", message: "Courses you join appear here.", action: "Browse courses", onAction: {})
                        ErrorState(message: "No connection. Check your internet and try again.") {}
                        SkeletonList(rows: 2).padding(-Spacing.screen)
                    }
                    group("Avatars, prices, Arabic") {
                        HStack(spacing: 12) {
                            Avatar(name: "Bilal Ahmad", image: nil)
                            Avatar(name: "Aisha", image: nil, size: 56)
                            PriceLine(pricePaise: 34900, mrpPaise: 49900)
                        }
                        ArabicText(text: "إِنَّ مَعَ الْعُسْرِ يُسْرًا", color: Scheme.onSurface)
                    }
                }
                .padding(Spacing.screen)
            }
            StickyBottomBar { PrimaryButton("Apply") {} }
            BottomBarPreview()
        }
        .background(Scheme.background.ignoresSafeArea())
    }

    private var hero: some View {
        HeroBox {
            VStack(alignment: .leading, spacing: 8) {
                Overline(text: "Quran · Beginner", color: Brand.goldSoft)
                Text("Quran Nazira (Reading)").textStyle(Typo.headlineMedium).foregroundStyle(Brand.onHero)
                GoldRule()
            }
            .padding(Spacing.screen)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }

    private var colours: some View {
        let swatches: [(String, Color)] = [
            ("primary", Scheme.primary), ("primaryContainer", Scheme.primaryContainer), ("secondary", Scheme.secondary),
            ("secondaryContainer", Scheme.secondaryContainer), ("background", Scheme.background), ("surfaceContainer", Scheme.surfaceContainer),
            ("cta", Brand.cta), ("gold", Brand.gold), ("hero", Brand.hero), ("error", Scheme.error),
            ("success", Brand.successContainer), ("warning", Brand.warningContainer), ("info", Brand.infoContainer), ("danger", Brand.dangerContainer),
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(swatches, id: \.0) { name, color in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: Radius.input).fill(color).frame(height: 40)
                        .overlay(RoundedRectangle(cornerRadius: Radius.input).strokeBorder(Brand.outlineSoft))
                    Text(name).textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
        }
    }

    private var typeScale: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Headline medium (serif)").textStyle(Typo.headlineMedium)
            Text("Headline small").textStyle(Typo.headlineSmall)
            Text("Title large").textStyle(Typo.titleLarge)
            Text("Title medium").textStyle(Typo.titleMedium)
            Text("Body large — the quick brown fox").textStyle(Typo.bodyLarge)
            Text("Body medium — the quick brown fox").textStyle(Typo.bodyMedium)
            Text("Body small").textStyle(Typo.bodySmall)
            Text("Label large").textStyle(Typo.labelLarge)
            Overline(text: "Overline")
        }
        .foregroundStyle(Scheme.onSurface)
    }

    private var cards: some View {
        VStack(spacing: 12) {
            AppCard(onClick: {}) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Brand.warningContainer).frame(width: 44, height: 44)
                        Icon.payments.image.foregroundStyle(Brand.warning)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("November 2026 fee is due").textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
                        Text("Quran Nazira (Reading) · ₹349").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
                    }
                    Spacer()
                    Icon.forward.image.foregroundStyle(Scheme.onSurfaceVariant)
                }
            }
            AppCard(padding: 0) {
                RemoteImage(path: nil).frame(height: 120)
                VStack(alignment: .leading, spacing: 6) {
                    StatusChip("Active", tone: .info)
                    Text("Quran Nazira (Reading)").textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
                    Text("Ustadh Bilal · Roll 12").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                }
                .padding(Spacing.card)
            }
        }
    }

    private var chips: some View {
        let statuses = ["active", "completed", "pending_approval", "pending_verification", "approved", "rejected", "shipped", "refunded"]
        return GalleryFlow(spacing: 8) {
            ForEach(statuses, id: \.self) { s in
                let (label, tone) = statusLabel(s, kind: .payment)
                StatusChip(label, tone: tone)
            }
        }
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            PrimaryButton("Pay ₹349 with a UPI app") {}
            PrimaryButton("Submitting", loading: true) {}
            PrimaryButton("Disabled", enabled: false) {}
            SecondaryButton("Attach payment screenshot (optional)") {}
            HStack {
                CtaButton("Try again") {}
                TextButton("See all", icon: .forward) {}
                IconButton(.bell, label: "Notifications") {}
            }
        }
    }

    private var inputs: some View {
        VStack(spacing: 14) {
            SearchField(initial: "", placeholder: "Search courses") { _ in }
            OutlinedField(label: "Full name", text: $text)
            OutlinedField(label: "E-mail", text: $filled, keyboard: .emailAddress)
            OutlinedField(label: "Password", text: $password, secure: true)
            OutlinedField(label: "Transaction reference (UTR)", text: $text, error: "Enter the reference from your UPI app.")
            Dropdown(value: dropdown, options: ["Monthly", "Yearly"], label: "Frequency") { dropdown = ["Monthly", "Yearly"][$0] }
            HStack(spacing: 10) {
                ChoicePill(label: "UPI", selected: pill == 0) { pill = 0 }
                ChoicePill(label: "Bank transfer", selected: pill == 1) { pill = 1 }
            }
            ChipRow(options: [(nil, "All"), ("aqeedah", "Aqeedah"), ("fiqh", "Fiqh"), ("seerah", "Seerah")], selected: chip) { chip = $0 }
            SwitchRow(label: "Featured on home", supporting: "Shown on the home screen", isOn: $on)
            RadioRow(label: "System default", selected: radio == 0) { radio = 0 }
            RadioRow(label: "Dark", selected: radio == 1) { radio = 1 }
            CheckboxRow(checked: checked, onToggle: { checked.toggle() }) { Text("I agree").textStyle(Typo.bodyLarge) }
        }
    }

    private var inspiration: some View {
        HeroBox {
            VStack(spacing: 10) {
                Overline(text: "Verse of the day", color: Brand.goldSoft)
                ArabicText(text: "وَاسْتَغْفِرُوا رَبَّكُمْ ثُمَّ تُوبُوا إِلَيْهِ", color: Brand.onHero)
                Text("Seek forgiveness from your Lord, then turn towards Him in repentance.")
                    .textStyle(Typo.serifItalic).foregroundStyle(Brand.onHero.opacity(0.85)).multilineTextAlignment(.center)
                Text("— Surah Hud 11:90").textStyle(Typo.labelLarge).foregroundStyle(Brand.goldSoft)
            }
            .padding(20)
            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Brand.goldSoft.opacity(0.6), lineWidth: 1))
            .padding(Spacing.screen)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }

    private func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Overline(text: title)
            content()
        }
    }
}

/// The tab bar as students see it, without a navigator.
private struct BottomBarPreview: View {
    @State private var nav = Navigator(shell: .admin)
    var body: some View { BottomBar().environment(nav) }
}

/// Lays children out left to right, wrapping onto new lines.
struct GalleryFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
#endif
