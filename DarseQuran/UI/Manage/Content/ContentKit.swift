import PhotosUI
import SwiftUI

/*
 * Pieces shared by the content screens (Android's ui/manage/content/ContentKit.kt): a row's "more" menu, a row's
 * thumbnail and the images field of posts and announcements. The course screens use the row menu too.
 */

/// One entry of a row's "more" menu (Android's RowAction).
struct ContentRowAction {
    let label: String
    var destructive: Bool = false
    let onClick: () -> Void

    init(_ label: String, destructive: Bool = false, onClick: @escaping () -> Void) {
        self.label = label
        self.destructive = destructive
        self.onClick = onClick
    }
}

/// The ⋮ button of a list row; hidden when there is nothing to offer (Android's RowMenu).
struct ContentRowMenu: View {
    let actions: [ContentRowAction]
    var label: String = "More actions"

    init(_ actions: [ContentRowAction?], label: String = "More actions") {
        self.actions = actions.compactMap { $0 }
        self.label = label
    }

    var body: some View {
        if !actions.isEmpty {
            Menu {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    Button(action.label, role: action.destructive ? .destructive : nil, action: action.onClick)
                }
            } label: {
                Icon.more.image.font(.system(size: 20, weight: .semibold)).rotationEffect(.degrees(90))
                    .foregroundStyle(Scheme.onSurfaceVariant)
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
            }
            .accessibilityLabel(label)
        }
    }
}

/// A small picture at the start of a list row (Android's RowThumbnail).
struct ContentRowThumbnail: View {
    let path: String?
    var width: CGFloat = 48
    var height: CGFloat = 48

    var body: some View {
        RemoteImage(path: path)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: Radius.input, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Material's OutlinedButton in a chosen colour, optionally full width (Reject, Open PDF, public links).
struct ContentOutlinedButton: View {
    let text: String
    var icon: Icon? = nil
    var color: Color = Scheme.primary
    var fullWidth: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    init(_ text: String, icon: Icon? = nil, color: Color = Scheme.primary, fullWidth: Bool = false, enabled: Bool = true, action: @escaping () -> Void) {
        self.text = text
        self.icon = icon
        self.color = color
        self.fullWidth = fullWidth
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { icon.image.font(.system(size: 16, weight: .medium)) }
                Text(text).textStyle(Typo.labelLarge).multilineTextAlignment(.center)
            }
            .foregroundStyle(enabled ? color : Scheme.onSurface.opacity(0.38))
            .padding(.horizontal, icon == nil ? 24 : 16)
            .padding(.vertical, 10)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 40)
            .overlay(Capsule().strokeBorder(enabled ? Scheme.outline : Scheme.onSurface.opacity(0.12), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(shape: Capsule()))
        .disabled(!enabled)
    }
}

/// The images of a post or announcement, as on the website's forms: the saved ones (tap ✕ to mark one for removal,
/// sent as `removeImage`), and new ones picked from the photo library (sent as `images`), up to [max] in all.
/// [readOnly] shows the saved images only (Android's ImagesField).
struct ContentImagesField: View {
    let label: String
    let current: [ContentImage]
    let removed: Set<String>
    let onRemovedChange: (Set<String>) -> Void
    let picked: [PickedFile]
    let onPickedChange: ([PickedFile]) -> Void
    let max: Int
    var readOnly: Bool = false
    @Environment(Toaster.self) private var toaster
    @State private var choosing = false
    @State private var items: [PhotosPickerItem] = []

    private var slots: Int { Swift.max(0, max - (current.count - removed.count) - picked.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).textStyle(Typo.labelLarge).foregroundStyle(Scheme.onSurfaceVariant)
            ForEach(current) { img in
                let gone = removed.contains(img.id)
                ZStack(alignment: .topTrailing) {
                    RemoteImage(path: img.imagePath, contentDescription: img.caption)
                        .frame(maxWidth: .infinity).frame(height: 170)
                        .opacity(gone ? 0.3 : 1)
                    if !readOnly {
                        TextButton(gone ? "Keep" : "Remove", icon: gone ? .undo : .close, color: Scheme.error) {
                            var next = removed
                            if gone { next.remove(img.id) } else { next.insert(img.id) }
                            onRemovedChange(next)
                        }
                        .padding(4)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
            if !readOnly {
                ForEach(Array(picked.enumerated()), id: \.offset) { index, file in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let image = UIImage(data: file.bytes) {
                                Image(uiImage: image).resizable().scaledToFill()
                            } else {
                                Scheme.surfaceContainerHigh
                            }
                        }
                        .frame(maxWidth: .infinity).frame(height: 170)
                        .clipped()
                        .accessibilityLabel(file.name)
                        TextButton("Remove", icon: .close, color: Scheme.error) {
                            onPickedChange(picked.enumerated().filter { $0.offset != index }.map(\.element))
                        }
                        .padding(4)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
                PillOutlinedButton(current.isEmpty ? "Add images" : "Add more images", icon: .addPhoto, enabled: slots > 0) { choosing = true }
                Text(
                    "JPEG, PNG, WebP or GIF, up to 5 MB each. "
                        + (slots > 0 ? "You can add \(slots) more (max \(max) in all)." : "This holds the maximum of \(max) images.")
                )
                .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
            }
        }
        .photosPicker(isPresented: $choosing, selection: $items, maxSelectionCount: Swift.max(2, max), matching: .images)
        .onChange(of: items) { _, new in
            guard !new.isEmpty else { return }
            items = []
            Task { await add(new) }
        }
    }

    private func add(_ chosen: [PhotosPickerItem]) async {
        let room = slots
        var outcomes: [PickOutcome] = []
        for item in chosen.prefix(room) {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                outcomes.append(.rejected("This file couldn't be read."))
                continue
            }
            let mime = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
            outcomes.append(await readPicked(data: data, name: nil, mime: mime, limit: .image))
        }
        onPickedChange(picked + outcomes.compactMap(\.file))
        var problems: [String] = []
        if chosen.count > room {
            problems.append("Only \(room) more photo\(room == 1 ? "" : "s") fit, so \(chosen.count - room) weren't added.")
        }
        for reason in outcomes.compactMap(\.reason) where !problems.contains(reason) { problems.append(reason) }
        if !problems.isEmpty { toaster.show(problems.joined(separator: "\n"), long: true) }
    }
}
