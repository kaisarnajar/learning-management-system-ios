import SwiftUI

/// The Admin (or Developer) tab: what needs action now, then every section of the website's admin panel with its count
/// (Android's AdminDashboardScreen in ManageHome.kt). A card opens the app screen for its website path, or says the
/// section isn't in the app yet.
struct AdminDashboardScreen: View {
    var body: some View {
        WithModel({ app in Loader(app: app) { try await $0.service(DashboardAPI.self).dashboard() } }) { loader in
            AdminDashboardContent(loader: loader)
        }
    }
}

private struct AdminDashboardContent: View {
    let loader: Loader<DashboardResponse>
    @Environment(AppContainer.self) private var app
    @Environment(Navigator.self) private var nav

    var body: some View {
        let user = app.session?.user
        GeometryReader { outer in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    DashboardHero(name: user?.name, role: user?.role ?? Roles.admin, topInset: outer.safeAreaInsets.top)
                    switch loader.state {
                    case .ready(let data):
                        sections(data)
                    case .loading, .failed:
                        LoadContent(state: loader.state, onRetry: { loader.load() }) { _ in EmptyView() }
                    }
                }
                .padding(.bottom, 32)
            }
            .ignoresSafeArea(edges: .top)
            .refreshable { await loader.refresh() }
        }
        .background(Scheme.background.ignoresSafeArea())
        .reloadOnReturn { loader.reload() }
    }

    @ViewBuilder private func sections(_ data: DashboardResponse) -> some View {
        let actionRequired = DashboardLayout.actionRequired(data)
        Spacer().frame(height: 20)
        if !actionRequired.isEmpty {
            SectionHeader(title: "Action Required")
            Text("Items that need your immediate attention.")
                .textStyle(Typo.bodyMedium)
                .foregroundStyle(Scheme.onSurfaceVariant)
                .padding(.horizontal, 20).padding(.vertical, 4)
            Spacer().frame(height: 8)
            tiles(actionRequired)
        } else {
            AppCard(color: Brand.successContainer) {
                Text("All caught up").textStyle(Typo.titleMedium).foregroundStyle(Brand.success)
                Text("No payments, enrolments, waivers or approvals are waiting.").textStyle(Typo.bodyMedium).foregroundStyle(Brand.success)
            }
            .padding(.horizontal, 20)
        }
        ForEach(DashboardLayout.groups(data), id: \.title) { group in
            Spacer().frame(height: 24)
            SectionHeader(title: group.title)
            Spacer().frame(height: 12)
            tiles(group.links)
        }
    }

    @ViewBuilder private func tiles(_ links: [DashboardLink]) -> some View {
        let rows = stride(from: 0, to: links.count, by: 2).map { Array(links[$0..<min($0 + 2, links.count)]) }
        // Its own stack: the LazyVStack around it flattens ForEach rows, and every group numbers its rows from 0, so
        // without one the repeated ids left all but the first group's cards undrawn.
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, pair in
                HStack(spacing: 12) {
                    ForEach(pair, id: \.href) { link in SectionTile(link: link) { open(link.href) } }
                    if pair.count == 1 { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                }
                .padding(.horizontal, 20).padding(.vertical, 6)
            }
        }
    }

    private func open(_ href: String) {
        if let route = routeForAdminHref(href) { nav.push(.manage(route)) } else { app.toaster.show("This section opens on the website for now.") }
    }
}

/// The green welcome band: panel name, greeting with the first name, and today's date.
private struct DashboardHero: View {
    let name: String?
    let role: String
    let topInset: CGFloat

    var body: some View {
        HeroBox {
            VStack(alignment: .leading, spacing: 0) {
                Overline(text: role == Roles.developer ? "Developer panel" : "Admin panel", color: Brand.goldSoft)
                Spacer().frame(height: 6)
                Text("Assalamu alaikum" + (name.map { ", " + ($0.components(separatedBy: " ").first ?? $0) } ?? ""))
                    .textStyle(Typo.headlineSmall).foregroundStyle(Brand.onHero)
                    .accessibilityAddTraits(.isHeader)
                Text(dashboardDate()).textStyle(Typo.bodyMedium).foregroundStyle(Brand.onHero.opacity(0.8))
            }
            .padding(20)
            .padding(.top, 8 + topInset).padding(.bottom, 8)
        }
    }
}

/// Today at the academy, as "Thursday, 26 November".
func dashboardDate(now: Date = Date()) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.calendar = Calendar(identifier: .gregorian)
    f.timeZone = academyZone
    f.dateFormat = "EEEE, d MMMM"
    return f.string(from: now)
}

/// One dashboard card: the section's name, then its count, or "Manage →" for a tool page. Amber when it needs action.
private struct SectionTile: View {
    let link: DashboardLink
    let onClick: () -> Void

    var body: some View {
        let accent = link.highlight ? Brand.warning : Scheme.onSurfaceVariant
        AppCard(padding: 14, color: link.highlight ? Brand.warningContainer : Scheme.surfaceContainerLowest, onClick: onClick) {
            VStack(alignment: .leading, spacing: 0) {
                Text(link.label).textStyle(Typo.labelLarge).foregroundStyle(accent).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if let count = link.count, !DashboardLayout.isQuickLink(link) {
                    Text("\(count)").textStyle(Typo.headlineSmall).foregroundStyle(link.highlight ? Brand.warning : Scheme.onSurface)
                } else {
                    HStack(spacing: 4) {
                        Text("Manage").textStyle(Typo.labelLarge)
                        Icon.forward.image.font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(Scheme.primary)
                }
            }
            .frame(height: 96 - 28, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
