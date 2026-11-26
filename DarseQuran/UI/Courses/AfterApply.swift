import SwiftUI

/// Goes where the answer to an application sends the student (see [CourseDetailModel.next]): on to pay the enrollment
/// fee, or to complete the profile. State rather than a callback, so the screen acts on it once it has the course title.
private struct AfterApplyEffect: ViewModifier {
    let model: CourseDetailModel
    let title: String?
    @Environment(Navigator.self) private var nav

    func body(content: Content) -> some View {
        content
            .onChange(of: model.next) { act() }
            .onChange(of: title) { act() }
    }

    private func act() {
        guard let title, let next = model.next else { return }
        switch next {
        case .pay: nav.push(.pay(courseId: model.courseId, type: "enrollment", title: title))
        case .completeProfile: nav.push(.editProfile)
        }
        model.consumeNext()
    }
}

extension View {
    func afterApply(_ model: CourseDetailModel, title: String?) -> some View {
        modifier(AfterApplyEffect(model: model, title: title))
    }
}
