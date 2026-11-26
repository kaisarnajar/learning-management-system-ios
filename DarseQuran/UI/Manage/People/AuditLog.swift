import Observation
import SwiftUI

/*
 * /admin/audit-log: every void, delete, approval and other admin change. Ported from Android's
 * ui/manage/people/AuditLog.kt.
 */

/// [value] as pretty-printed JSON, as kotlinx.serialization's `prettyPrint` writes it (4-space indent, `"key": value`),
/// cut to 1200 characters; "" for nothing or null. Object keys come sorted (Swift's dictionaries don't keep the order).
func auditJsonText(_ value: JSONValue?) -> String {
    guard let value, value != .null else { return "" }
    return String(auditPretty(value, indent: 0).prefix(1200))
}

private func auditPretty(_ value: JSONValue, indent: Int) -> String {
    let pad = String(repeating: " ", count: (indent + 1) * 4)
    let end = String(repeating: " ", count: indent * 4)
    switch value {
    case .null: return "null"
    case .bool(let b): return b ? "true" : "false"
    case .int(let i): return String(i)
    case .double(let d): return String(d)
    case .string(let s): return auditQuoted(s)
    case .array(let items):
        if items.isEmpty { return "[]" }
        return "[\n" + items.map { pad + auditPretty($0, indent: indent + 1) }.joined(separator: ",\n") + "\n\(end)]"
    case .object(let fields):
        if fields.isEmpty { return "{}" }
        return "{\n" + fields.keys.sorted().map { pad + auditQuoted($0) + ": " + auditPretty(fields[$0]!, indent: indent + 1) }
            .joined(separator: ",\n") + "\n\(end)}"
    }
}

private func auditQuoted(_ s: String) -> String {
    var out = "\""
    for c in s.unicodeScalars {
        switch c {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
            if c.value < 0x20 { out += String(format: "\\u%04x", c.value) } else { out.unicodeScalars.append(c) }
        }
    }
    return out + "\""
}

@MainActor
@Observable
final class AuditLogModel {
    /// The entity id the list is filtered by, and what is typed in its field.
    private(set) var entityId = ""
    var entityIdDraft = ""
    let entities: Loader<[String]>
    @ObservationIgnored private(set) var list: PagedListModel<AuditEntry>!

    init(app: AppContainer) {
        entities = Loader(app: app) { try await $0.service(AuditLogAPI.self).entities().entities }
        list = PagedListModel(app: app) { [weak self] app, page, actor, entity in
            let entityId = self?.entityId ?? ""
            return try await app.service(AuditLogAPI.self).list(
                page: page, entity: entity, entityId: entityId.trimmed.isEmpty ? nil : entityId, actor: actor.trimmed.isEmpty ? nil : actor
            )
        }
    }

    /// Filters by [id] (the field's search button or the keyboard's Search), loading the list again from the start.
    func applyEntityId(_ id: String) {
        entityId = id
        list.filter(list.state.filter)
    }

    func clearEntityId() {
        entityIdDraft = ""
        applyEntityId("")
    }
}

/// Every admin change, filtered as on the page: entity (chips), actor e-mail (search box) and entity id (the field
/// above the list).
struct AuditLogScreen: View {
    var body: some View {
        WithModel({ AuditLogModel(app: $0) }) { model in AuditLogContent(model: model) }
    }
}

private struct AuditLogContent: View {
    @Bindable var model: AuditLogModel

    var body: some View {
        let entityList = model.entities.state.value ?? []
        ManageListScreen(
            "Audit log", model: model.list, key: \.id, emptyTitle: "No audit entries match", searchHint: "Actor e-mail",
            filters: [FilterOption(nil, "All entities")] + entityList.map { FilterOption($0, $0) },
            header: {
                // The trailing button sits over the field's end, as Material's trailingIcon does.
                OutlinedField(
                    label: "Entity id", text: $model.entityIdDraft, capitalization: .never, autocorrect: false, submitLabel: .search,
                    onSubmit: { model.applyEntityId(model.entityIdDraft.trimmed) }
                )
                .overlay(alignment: .trailing) {
                    if !model.entityId.trimmed.isEmpty {
                        IconButton(.close, label: "Clear", tint: Scheme.onSurfaceVariant) { model.clearEntityId() }
                    } else {
                        IconButton(.search, label: "Filter", tint: Scheme.onSurfaceVariant) { model.applyEntityId(model.entityIdDraft.trimmed) }
                    }
                }
            }
        ) { e in AuditEntryCard(entry: e) }
        .reloadOnReturn { model.list.refresh() }
    }
}

private struct AuditEntryCard: View {
    let entry: AuditEntry
    @State private var open = false

    var body: some View {
        let e = entry
        let before = auditJsonText(e.before)
        let after = auditJsonText(e.after)
        AppCard {
            HStack(alignment: .center) {
                Text(e.action).textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface).frame(maxWidth: .infinity, alignment: .leading)
                Text(formatDateTime(e.createdAt)).textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant)
            }
            Text(e.actor).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
            Spacer().frame(height: 4)
            Text(e.entity).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
            if let id = e.entityId {
                Text(id).textStyle(Typo.labelSmall).fontDesign(.monospaced).foregroundStyle(Scheme.onSurfaceVariant).textSelection(.enabled)
            }
            Text("Reason: " + (e.reason.flatMap { $0.trimmed.isEmpty ? nil : $0 } ?? "—")).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurface)
            if !before.isEmpty || !after.isEmpty {
                TextButton(open ? "Hide before → after" : "Show before → after") { open.toggle() }
                    .padding(.leading, -12)
                if open {
                    Text([before, after].filter { !$0.isEmpty }.joined(separator: "\n→\n"))
                        .textStyle(Typo.bodySmall).fontDesign(.monospaced).foregroundStyle(Scheme.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
