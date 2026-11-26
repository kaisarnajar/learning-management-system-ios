import PhotosUI
import SwiftUI
import UIKit

// Pieces the account screens share: the verification banner, the profile photo, and the Material bits the shared
// components don't have (a pill button, an alert dialog with custom content, a weighted row).

// MARK: - verification banner (VerificationBanner.kt)

/// Shown to a signed-in user whose e-mail is not verified, as the website's profile pages do.
struct VerificationBanner: View {
    let state: ResendState
    let onResend: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Icon.warningFilled.image.font(.system(size: 20)).foregroundStyle(Brand.warning).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Email Verification Required").textStyle(Typo.titleSmall).foregroundStyle(Brand.warning)
                Text("Please verify your email address to access all features like enrolling in courses and making purchases.")
                    .textStyle(Typo.bodyMedium).foregroundStyle(Brand.warning)
                TextButton(resendLabel(state), action: onResend)
                    .disabled(state.sending || state.sent)
                    .opacity(state.sending || state.sent ? 0.38 : 1)
                    .padding(.leading, -12)
                if let message = state.message {
                    Text(message).textStyle(Typo.bodySmall).foregroundStyle(state.sent ? Brand.success : Brand.danger)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Brand.warningContainer, in: RoundedRectangle(cornerRadius: Radius.card))
    }
}

// MARK: - profile photo (ProfilePhoto.kt)

/// The avatar with its camera button and the website's hint. As on the website, a photo can be chosen only once the
/// (unsaved) gender is Male. The photo comes from the library or the camera.
struct ProfilePhoto: View {
    let profile: Profile
    let gender: String
    let busy: Bool
    let onPhoto: (Data, String) -> Void
    @Environment(Toaster.self) private var toaster
    @State private var askSource = false
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var item: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Avatar(name: profile.name, image: profile.image, size: 96)
                if photoAllowed(gender) {
                    Button { askSource = true } label: {
                        ZStack {
                            Circle().fill(Scheme.primary)
                            if busy {
                                ProgressView().tint(Scheme.onPrimary).controlSize(.small)
                            } else {
                                Icon.cameraFilled.image.font(.system(size: 15)).foregroundStyle(Scheme.onPrimary)
                            }
                        }
                        .frame(width: 36, height: 36)
                    }
                    .buttonStyle(PressableStyle(shape: Circle()))
                    .disabled(busy) // one upload at a time
                    .accessibilityLabel("Change photo")
                }
            }
            Text(photoHint(gender.isEmpty ? nil : gender))
                .textStyle(Typo.labelMedium)
                .foregroundStyle(Scheme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity)
        .confirmationDialog("Change photo", isPresented: $askSource) {
            Button("Choose from photos") { showLibrary = true }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take a photo") { showCamera = true }
            }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showLibrary, selection: $item, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { picked($0) }.ignoresSafeArea()
        }
        .onChange(of: item) { _, new in
            guard let new else { return }
            // Forgotten once handed on, so picking the same photo again after a failed upload still uploads it.
            item = nil
            Task {
                let data = try? await new.loadTransferable(type: Data.self)
                // A chosen photo that can't be read says so (only a cancelled camera stays silent).
                guard let image = data.flatMap(UIImage.init(data:)) else {
                    toaster.show("That photo couldn't be read. Try another one.", long: true)
                    return
                }
                picked(image)
            }
        }
    }

    private func picked(_ image: UIImage?) {
        if let image, let jpeg = jpegForUpload(image) {
            onPhoto(jpeg, "image/jpeg")
        } else if image != nil {
            toaster.show("That photo couldn't be read. Try another one.", long: true)
        }
    }
}

// MARK: - Material bits

/// Material's filled / outlined Button: a pill, 40pt tall, 24pt side padding.
struct PillButton: View {
    let text: String
    var background: Color? = nil
    var foreground: Color
    var outline: Color? = nil
    var fullWidth = false
    var height: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text).textStyle(Typo.labelLarge)
                .padding(.horizontal, 24)
                .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
                .foregroundStyle(foreground)
                .background(background ?? .clear, in: Capsule())
                .overlay { if let outline { Capsule().strokeBorder(outline, lineWidth: 1) } }
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(shape: Capsule()))
    }
}

/// Material 3's AlertDialog with custom content: a title, the content, and the buttons at the bottom right. Shown over
/// everything (the tab bar included) on a dimmed background; tapping outside dismisses it.
struct MaterialDialog<Content: View, Buttons: View>: View {
    let title: String
    let onDismiss: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var buttons: () -> Buttons

    var body: some View {
        ZStack {
            Color.black.opacity(0.32).ignoresSafeArea().onTapGesture(perform: onDismiss).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 16) {
                Text(title).textStyle(Typo.headlineSmall).foregroundStyle(Scheme.onSurface).accessibilityAddTraits(.isHeader)
                content()
                HStack(spacing: 8) { Spacer(); buttons() }.padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .background(Scheme.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 28))
            .padding(.horizontal, 48)
        }
        .accessibilityAddTraits(.isModal)
    }
}

extension View {
    /// Presents a [MaterialDialog] over the whole window, without the sheet's slide.
    func materialDialog<Content: View, Buttons: View>(
        _ title: String, isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content, @ViewBuilder buttons: @escaping () -> Buttons
    ) -> some View {
        fullScreenCover(isPresented: isPresented) {
            MaterialDialog(title: title, onDismiss: { dismissWithoutAnimation(isPresented) }, content: content, buttons: buttons)
                .presentationBackground(.clear)
        }
    }
}

/// Closes a full-screen cover without the slide-down.
@MainActor
func dismissWithoutAnimation(_ binding: Binding<Bool>) { setWithoutAnimation(binding, false) }

/// Opens or closes a full-screen cover without the slide.
@MainActor
func setWithoutAnimation(_ binding: Binding<Bool>, _ value: Bool) {
    var t = Transaction()
    t.disablesAnimations = true
    withTransaction(t) { binding.wrappedValue = value }
}

