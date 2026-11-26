import Observation
import SwiftUI

/*
 * Course announcements (website: …/courses/[id]/announcements, /new, /[announcementId]/edit) for admins and teachers,
 * and a teacher's private messages to one student (…/students/[enrollmentId]/announcements) when `enrollmentId` is
 * set. Ported from Android's ui/manage/courses/CourseAnnouncements.kt.
 */

/// File types the website accepts as an announcement attachment.
private let courseAttachmentTypes = [
    "application/pdf", "image/jpeg", "image/png", "image/webp", "image/gif",
    "application/msword", "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
]

private let courseDefaultCategories: [(value: String, label: String)] = [
    ("EXAMS_TESTS", "Exams & Tests"),
    ("ASSIGNMENTS_HOMEWORK", "Assignments & Homework"),
    ("STUDY_MATERIALS", "Study Materials"),
    ("CLASS_SCHEDULE", "Class Schedule"),
    ("COURSE_ANNOUNCEMENT", "Course Announcements"),
    ("GENERAL_NOTICE", "General Notices"),
]

private func courseCategoryTone(_ category: String) -> Tone {
    switch category {
    case "EXAMS_TESTS": .danger
    case "ASSIGNMENTS_HOMEWORK": .warning
    case "STUDY_MATERIALS", "CLASS_SCHEDULE": .info
    case "COURSE_ANNOUNCEMENT": .success
    default: .neutral
    }
}

// MARK: - list

@MainActor
final class CourseAnnouncementsModel {
    let list: PagedListModel<StaffCourseAnnouncement>
    let runner: ActionRunner

    init(app: AppContainer, portal: Portal, courseId: String, enrollmentId: String?) {
        list = PagedListModel(app: app) { app, page, q, _ in
            let api = app.service(CourseToolsAPI.self)
            if let enrollmentId { return try await api.messages(portal, courseId, enrollmentId: enrollmentId, page: page) }
            return try await api.announcements(portal, courseId, page: page, q: q.trimmed.isEmpty ? nil : q)
        }
        runner = ActionRunner(app: app)
    }
}

struct CourseAnnouncementsScreen: View {
    let portal: Portal
    let courseId: String
    let enrollmentId: String?
    let studentName: String?

    var body: some View {
        WithModel({ CourseAnnouncementsModel(app: $0, portal: portal, courseId: courseId, enrollmentId: enrollmentId) }) { model in
            CourseAnnouncementsContent(portal: portal, courseId: courseId, enrollmentId: enrollmentId, studentName: studentName, model: model)
        }
    }
}

private struct CourseAnnouncementsContent: View {
    let portal: Portal
    let courseId: String
    let enrollmentId: String?
    let studentName: String?
    let model: CourseAnnouncementsModel
    @Environment(Navigator.self) private var nav
    @State private var deleting: StaffCourseAnnouncement?

    var body: some View {
        let personal = enrollmentId != nil
        let who = studentName ?? "this student"
        ManageListScreen(
            personal ? "Messages" : "Announcements", model: model.list, key: \.id,
            emptyTitle: personal ? "No private messages for \(who) yet" : "No announcements for this course yet",
            searchHint: personal ? nil : "Search by title, body, or author",
            fab: {
                AddFab(personal ? "New message" : "New announcement") {
                    nav.push(.manage(.announcementForm(portal: portal, courseId: courseId, enrollmentId: enrollmentId, announcementId: nil, studentName: studentName)))
                }
            },
            header: {
                Text(
                    personal
                        ? "Private announcements for \(who) only: exam marks, feedback and personal updates."
                        : portal == .teacher
                        ? "Course-wide updates for all enrolled students. To message one student (e.g. exam marks), use Message on the student's page."
                        : "Post course-wide updates for enrolled students: schedule changes, academy notices, and more."
                )
                .textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        ) { a in
            CourseAnnouncementCard(
                announcement: a, audience: personal ? "For \(who)" : nil,
                onEdit: {
                    nav.push(.manage(.announcementForm(portal: portal, courseId: courseId, enrollmentId: enrollmentId, announcementId: a.id, studentName: studentName)))
                },
                onDelete: { deleting = a }
            )
        }
        .reloadOnReturn { model.list.refresh() }
        .confirmDialog(
            item: $deleting, title: personal ? "Delete this message?" : "Delete this announcement?",
            message: { "\"\($0.title)\" will be removed for students too. This cannot be undone." },
            confirm: "Delete", destructive: true
        ) { a in
            let (portal, courseId, scope) = (portal, courseId, announcementScope(enrollmentId))
            model.runner.run(
                { try await $0.service(CourseToolsAPI.self).deleteAnnouncement(portal, courseId, scope: scope, announcementId: a.id) },
                success: personal ? "Message deleted." : "Announcement deleted."
            ) { _ in model.list.refresh() }
        }
    }
}

private struct CourseAnnouncementCard: View {
    let announcement: StaffCourseAnnouncement
    let audience: String?
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(AppContainer.self) private var app

    var body: some View {
        let a = announcement
        AppCard {
            HStack(alignment: .center, spacing: 0) {
                StatusChip(a.categoryLabel.trimmed.isEmpty ? a.category : a.categoryLabel, tone: courseCategoryTone(a.category))
                Spacer()
                if a.canManage {
                    CourseSmallIconButton(icon: .edit, label: "Edit", tint: Scheme.onSurfaceVariant, action: onEdit)
                    CourseSmallIconButton(icon: .delete, label: "Delete", tint: Scheme.error, action: onDelete)
                }
            }
            Spacer().frame(height: 8)
            Text(a.title).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
            Spacer().frame(height: 4)
            Text(a.body).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
            if let path = a.attachmentPath {
                Spacer().frame(height: 8)
                CourseAssistChip(label: a.attachmentName ?? "Attachment", icon: .attachment) {
                    let name = a.attachmentName ?? "attachment"
                    app.toaster.show("Opening \(name)…")
                    Task { if let problem = await downloadAndOpen(app.client, path: path, fileName: name) { app.toaster.show(problem) } }
                }
            }
            Spacer().frame(height: 8)
            Text(([a.authorName, formatDateTime(a.createdAt)] + (a.edited ? ["Edited"] : []) + [audience].compactMap { $0 }).joined(separator: " · "))
                .textStyle(Typo.labelSmall).foregroundStyle(Brand.gold)
            if !a.canManage && a.postedByAdmin {
                Text("Posted by the academy administration").textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant)
            }
        }
    }
}

/// A 36pt icon button (the card's edit and delete).
private struct CourseSmallIconButton: View {
    let icon: Icon
    let label: String
    var tint: Color = Scheme.onSurfaceVariant
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            icon.image.font(.system(size: 18, weight: .medium)).foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(shape: Circle()))
        .accessibilityLabel(label)
    }
}

/// Material's AssistChip: an outlined 32pt chip with a leading icon.
private struct CourseAssistChip: View {
    let label: String
    let icon: Icon
    let action: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.input, style: .continuous)
        Button(action: action) {
            HStack(spacing: 8) {
                icon.image.font(.system(size: 15, weight: .medium)).foregroundStyle(Scheme.primary).frame(width: 18, height: 18)
                Text(label).textStyle(Typo.labelLarge).foregroundStyle(Scheme.onSurface).lineLimit(1)
            }
            .padding(.leading, 8).padding(.trailing, 16)
            .frame(height: 32)
            .overlay(shape.strokeBorder(Scheme.outline, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(PressableStyle(shape: shape))
    }
}

// MARK: - form

@MainActor
@Observable
final class AnnouncementFormModel {
    let loader: Loader<StaffAnnouncementResponse>?
    let runner: ActionRunner
    let files = FormFiles()
    var loaded: Bool
    var category: String
    var title = ""
    var body = ""
    var removeAttachment = false

    init(app: AppContainer, portal: Portal, courseId: String, enrollmentId: String?, announcementId: String?) {
        let scope = announcementScope(enrollmentId)
        loader = announcementId.map { id in
            Loader(app: app) { try await $0.service(CourseToolsAPI.self).announcement(portal, courseId, scope: scope, announcementId: id) }
        }
        runner = ActionRunner(app: app)
        loaded = announcementId == nil
        category = enrollmentId != nil ? "EXAMS_TESTS" : "COURSE_ANNOUNCEMENT"
    }

    var existing: StaffCourseAnnouncement? { loader?.state.value?.announcement }

    func fillOnce() {
        guard let existing, !loaded else { return }
        category = existing.category; title = existing.title; body = existing.body
        loaded = true
    }

    var categories: [(value: String, label: String)] {
        let fromServer = loader?.state.value?.categories.map { (value: $0.value, label: $0.label) } ?? []
        return fromServer.isEmpty ? courseDefaultCategories : fromServer
    }

    var error: String? {
        if !title.isEmpty && title.trimmed.count < 3 { return "Title must be at least 3 characters." }
        if !body.isEmpty && body.trimmed.count < 10 { return "Message must be at least 10 characters." }
        return nil
    }
}

struct AnnouncementFormScreen: View {
    let portal: Portal
    let courseId: String
    let enrollmentId: String?
    let announcementId: String?
    let studentName: String?

    var body: some View {
        WithModel({ AnnouncementFormModel(app: $0, portal: portal, courseId: courseId, enrollmentId: enrollmentId, announcementId: announcementId) }) { model in
            AnnouncementFormContent(portal: portal, courseId: courseId, enrollmentId: enrollmentId, announcementId: announcementId, studentName: studentName, model: model)
        }
    }
}

private struct AnnouncementFormContent: View {
    let portal: Portal
    let courseId: String
    let enrollmentId: String?
    let announcementId: String?
    let studentName: String?
    @Bindable var model: AnnouncementFormModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let personal = enrollmentId != nil
        let state = model.loader?.state
        let failed: String? = { if case .failed(let m)? = state { m } else { nil } }()
        FormScreen(
            announcementId != nil && personal ? "Edit message"
                : announcementId != nil ? "Edit announcement"
                : personal ? "Message for \(studentName ?? "student")"
                : "New announcement",
            saving: model.runner.busy,
            saveLabel: announcementId != nil ? "Save changes" : personal ? "Send message" : "Post announcement",
            canSave: model.loaded,
            loadError: failed,
            onRetry: { model.loader?.load() },
            onSave: save
        ) {
            if announcementId != nil && model.existing == nil {
                if failed == nil { Text("Loading…").textStyle(Typo.bodyLarge).foregroundStyle(Scheme.onSurface) }
            } else {
                fields(personal: personal)
            }
        }
        .onChange(of: model.existing != nil, initial: true) { _, ready in if ready { model.fillOnce() } }
    }

    @ViewBuilder private func fields(personal: Bool) -> some View {
        let existing = model.existing
        let file = model.files.single
        Text(
            personal
                ? "Only \(studentName ?? "this student") will see this message (e.g. exam score, assignment feedback)."
                : "Students enrolled in this course will see this announcement."
        )
        .textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
        FormDropdown("Category", options: model.categories, value: model.category) { model.category = $0 }
        FormTextField("Title", text: $model.title, supporting: "e.g. Mid-term exam schedule", isError: !model.title.isEmpty && model.title.trimmed.count < 3, maxLength: 200)
        FormTextField("Message", text: $model.body, singleLine: false, minLines: 8, isError: !model.body.isEmpty && model.body.trimmed.count < 10, maxLength: 10000)
        FormFileField(
            "Attachment (optional)", mimeTypes: courseAttachmentTypes, picked: file,
            currentName: model.removeAttachment ? nil : existing?.attachmentName.map { "Current: \($0)" },
            supporting: file != nil && existing?.attachmentName != nil ? "The new file replaces the current attachment." : "PDF, image or Word document."
        ) { model.files.single = $0 }
        if existing?.attachmentPath != nil && file == nil {
            FormCheckbox("Remove the current attachment", checked: model.removeAttachment) { model.removeAttachment = $0 }
        }
        if let error = model.error { Notice(error, tone: .warning) }
    }

    private func save() {
        let personal = enrollmentId != nil
        if model.title.trimmed.count < 3 || model.body.trimmed.count < 10 {
            model.runner.message(model.error ?? "Add a title and a message.")
            return
        }
        let file = model.files.single
        let parts = formOf { f in
            f.text("category", model.category); f.text("title", model.title.trimmed); f.text("body", model.body.trimmed)
            f.file("attachment", file)
            if model.removeAttachment && file == nil { f.text("removeAttachment", "1") }
        }
        let (portal, courseId, scope, announcementId) = (portal, courseId, announcementScope(enrollmentId), announcementId)
        model.runner.run(
            { app in
                let api = app.service(CourseToolsAPI.self)
                return if let announcementId {
                    try await api.updateAnnouncement(portal, courseId, scope: scope, announcementId: announcementId, parts)
                } else {
                    try await api.createAnnouncement(portal, courseId, scope: scope, parts)
                }
            },
            success: announcementId != nil ? (personal ? "Message updated." : "Announcement updated.")
                : personal ? "Message sent to \(studentName ?? "the student"). They will be notified."
                : "Announcement posted. Enrolled students will be notified."
        ) { _ in nav.pop() }
    }
}
