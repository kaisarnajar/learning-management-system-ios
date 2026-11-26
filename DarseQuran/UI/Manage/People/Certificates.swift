import Observation
import SwiftUI

/*
 * Certificates: /admin/certificates (list), /admin/certificates/[enrollmentId] (detail) and /new (generate).
 * Ported from Android's ui/manage/people/Certificates.kt.
 */

/// The PDF's file name: "certificate-<number or enrollment id>.pdf", anything but letters, digits and "-" as "-".
func certificateFileName(_ c: CertificateRow) -> String {
    let base = (c.certificateNumber ?? c.enrollmentId).replacing(/[^A-Za-z0-9-]/, with: "-")
    return "certificate-\(base).pdf"
}

// MARK: - list

struct CertificatesListScreen: View {
    var body: some View {
        WithModel({ app in
            PagedListModel<CertificateRow>(app: app) { app, page, q, _ in
                try await app.service(CertificatesAdminAPI.self).list(page: page, q: q.trimmed.isEmpty ? nil : q)
            }
        }) { model in CertificatesListContent(model: model) }
    }
}

private struct CertificatesListContent: View {
    let model: PagedListModel<CertificateRow>
    @Environment(Navigator.self) private var nav

    var body: some View {
        ManageListScreen(
            "Certificates", model: model, key: \.enrollmentId, emptyTitle: "No certificates have been generated yet",
            searchHint: "Certificate number, name or course",
            fab: { AddFab("Generate") { nav.push(.manage(.generateCertificate)) } }
        ) { c in
            let generated = formatDate(c.certificateGeneratedAt)
            RecordCard(
                title: c.user.name ?? c.user.email,
                subtitle: c.course.title,
                meta: [c.certificateNumber, generated.trimmed.isEmpty ? nil : generated].compactMap { $0 }.joined(separator: " · "),
                chip: (c.typeLabel + (c.certificateGrade.map { " · grade \($0)" } ?? ""), .info),
                onClick: { nav.push(.manage(.certificateAdmin(enrollmentId: c.enrollmentId))) },
                leading: { RowIcon(.workspacePremium) }
            )
        }
        .reloadOnReturn { model.refresh() }
    }
}

// MARK: - detail

@MainActor
@Observable
final class CertificateDetailModel {
    let loader: Loader<CertificateRow>
    let runner: ActionRunner
    var confirmDelete = false

    init(app: AppContainer, enrollmentId: String) {
        loader = Loader(app: app) { try await $0.service(CertificatesAdminAPI.self).get(enrollmentId).certificate }
        runner = ActionRunner(app: app)
    }
}

/// /admin/certificates/[enrollmentId]: the certificate's facts, the PDF, "Send via Email" and delete.
struct CertificateDetailScreen: View {
    let enrollmentId: String

    var body: some View {
        WithModel({ CertificateDetailModel(app: $0, enrollmentId: enrollmentId) }) { model in
            CertificateDetailContent(enrollmentId: enrollmentId, model: model)
        }
    }
}

private struct CertificateDetailContent: View {
    let enrollmentId: String
    @Bindable var model: CertificateDetailModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let runner = model.runner
        ManageScaffold("Student certificate", actions: {
            IconButton(.delete, label: "Delete certificate") { model.confirmDelete = true }
        }) {
            LoadedColumn(model.loader) { c in
                DetailCard {
                    Text(c.user.name ?? "N/A").textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
                    Text(c.user.email).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    HStack(spacing: 8) {
                        PillOutlinedButton("View PDF", icon: .pdf, enabled: !runner.busy) {
                            let name = certificateFileName(c)
                            runner.openFile { try await $0.service(CertificatesAdminAPI.self).pdf(enrollmentId, fileName: name) }
                        }
                        PillOutlinedButton("Send via Email", icon: .mail, enabled: !runner.busy) {
                            runner.run(
                                { try await $0.service(CertificatesAdminAPI.self).email(enrollmentId) },
                                success: "Certificate sent successfully. Please check student's Inbox or Spam/Junk folder."
                            ) { _ in model.loader.reload() }
                        }
                    }
                    if runner.busy {
                        Text("Preparing the certificate PDF…").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    }
                }
                DetailCard("Certificate") {
                    Field("Certificate number", c.certificateNumber)
                    Field("Course", c.course.title)
                    Field("Type", "Certificate of " + c.typeLabel)
                    Field("Grade", c.certificateGrade.map { String($0) } ?? "N/A")
                    Field("Date generated", formatDate(c.certificateGeneratedAt))
                    Field("Last e-mailed", c.certificateEmailSentAt.map { formatDateTime($0) }, showEmpty: false)
                }
            }
        }
        .reloadOnReturn { model.loader.reload() }
        .confirmDialog(
            "Delete this certificate?",
            message: "The certificate and its PDF are removed. The enrollment stays and a new certificate can be generated.",
            isPresented: $model.confirmDelete, confirm: "Delete", destructive: true
        ) {
            runner.run({ try await $0.service(CertificatesAdminAPI.self).delete(enrollmentId) }, success: "Certificate deleted successfully.") { _ in nav.pop() }
        }
    }
}

// MARK: - generate

@MainActor
@Observable
final class GenerateCertificateModel {
    let loader: Loader<[CertificateCandidate]>
    let runner: ActionRunner
    var courseId = ""
    var enrollmentId = ""
    var type = "APPRECIATION"
    var grade = ""
    var error: String?

    init(app: AppContainer) {
        loader = Loader(app: app) { try await $0.service(CertificatesAdminAPI.self).eligible().enrollments }
        runner = ActionRunner(app: app)
    }

    var candidates: [CertificateCandidate] { loader.state.value ?? [] }

    /// The courses of the candidates, each once, in order.
    var courses: [CourseRef] {
        var seen = Set<String>()
        return candidates.map(\.course).filter { seen.insert($0.id).inserted }
    }

    var students: [CertificateCandidate] { candidates.filter { $0.course.id == courseId } }

    func save(onGenerated: @escaping (String) -> Void) {
        let g = Int(grade)
        error = if enrollmentId.trimmed.isEmpty { "Please select a student." }
            else if type == "COMPLETION", g.map({ !(0...10).contains($0) }) ?? true {
                "A whole-number grade from 0 to 10 is required for a Certificate of Completion."
            } else { nil }
        guard error == nil else { return }
        let enrollmentId = enrollmentId, type = type, grade = grade
        runner.run({
            try await $0.service(CertificatesAdminAPI.self).generate(formOf { f in
                f.text("enrollmentId", enrollmentId)
                f.text("certificateType", type)
                if type == "COMPLETION" { f.text("certificateGrade", grade) }
            })
        }, success: "Certificate generated successfully.") { _ in onGenerated(enrollmentId) }
    }
}

/// /admin/certificates/new: course → student (enrollments without a certificate) → type → grade.
struct GenerateCertificateScreen: View {
    var body: some View {
        WithModel({ GenerateCertificateModel(app: $0) }) { model in GenerateCertificateContent(model: model) }
    }
}

private struct GenerateCertificateContent: View {
    @Bindable var model: GenerateCertificateModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let students = model.students
        FormScreen(
            "Generate certificate", saving: model.runner.busy, saveLabel: "Generate Certificate", error: model.error,
            onSave: {
                model.save { id in nav.replace(upTo: .manage(.generateCertificate), with: .manage(.certificateAdmin(enrollmentId: id))) }
            }
        ) {
            Text("Issue a certificate of completion or appreciation for an enrolled student.")
                .textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
            switch model.loader.state {
            case .failed(let message): Notice(message)
            case .loading: Text("Loading…").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
            case .ready(let list):
                if list.isEmpty { Notice("All active students currently have certificates generated. No pending enrollments.", tone: .info) }
            }
            FormDropdown(
                "Select course", options: model.courses.map { (value: $0.id, label: $0.title) }, value: model.courseId, placeholder: "Choose course"
            ) { model.courseId = $0; model.enrollmentId = "" }
            FormDropdown(
                "Select student", options: students.map { (value: $0.id, label: $0.user.name ?? $0.user.email) }, value: model.enrollmentId,
                placeholder: "Choose student",
                supporting: !model.courseId.trimmed.isEmpty && students.isEmpty ? "All students in this course already have certificates generated." : nil,
                enabled: !model.courseId.trimmed.isEmpty
            ) { model.enrollmentId = $0 }
            FormDropdown(
                "Certificate type",
                options: [(value: "APPRECIATION", label: "Certificate of Appreciation"), (value: "COMPLETION", label: "Certificate of Completion")],
                value: model.type
            ) { model.type = $0 }
            if model.type == "COMPLETION" {
                FormNumberField("Grade (0 to 10)", text: Binding(get: { model.grade }, set: { model.grade = String($0.prefix(2)) }), supporting: "e.g. 9")
            }
        }
    }
}
