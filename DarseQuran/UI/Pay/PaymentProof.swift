import PhotosUI
import SwiftUI
import UIKit

/*
 * The "pay, then tell us how" part shared by fee payments and book checkout, so both show the same details and ask for
 * the transaction reference the same way (Android's PaymentProof.kt).
 */

/// Opens the payer's UPI app with the amount filled in (when the academy has a UPI ID).
struct PayWithUpiButton: View {
    let settings: PaymentSettings?
    let amountPaise: Int
    let note: String
    @Environment(Toaster.self) private var toaster

    var body: some View {
        if let settings, settings.upiId?.trimmed.nilIfBlank != nil {
            PrimaryButton("Pay \(rupees(amountPaise)) with a UPI app") {
                launchUpi(settings, amountPaise: amountPaise, note: note) { opened in
                    if !opened { toaster.show("No UPI app found. Use the details below.", long: true) }
                }
            }
        }
    }
}

/// Opens the payer's UPI app with payee, amount and note filled in. On iOS the system picks the app registered for
/// upi:// (declared in LSApplicationQueriesSchemes); [completion] says false when none is installed (always the case in
/// the Simulator), so the caller points to the details to copy.
@MainActor
func launchUpi(_ settings: PaymentSettings, amountPaise: Int, note: String, completion: @escaping @MainActor (Bool) -> Void) {
    guard let url = upiLaunchUri(settings, amountPaise: amountPaise, note: note), UIApplication.shared.canOpenURL(url) else {
        completion(false)
        return
    }
    UIApplication.shared.open(url) { opened in Task { @MainActor in completion(opened) } }
}

/// The payment details failed to load: without them there is nothing to pay to, so say so and offer a retry.
struct PaymentDetailsError: View {
    let message: String?
    let onRetry: () -> Void

    var body: some View {
        if let message {
            Banner("Couldn't load the academy's payment details. \(message)", tone: .danger)
            SecondaryButton("Try again", action: onRetry)
        }
    }
}

/// The academy's UPI and bank details, each with a copy button, and the UPI QR code the website shows. The QR code
/// carries [amountPaise] and [note] when given (else only the UPI ID); [paymentRef] adds the website's "Payment
/// reference (include if asked)" line.
struct PaymentDetailsCard: View {
    let settings: PaymentSettings?
    var amountPaise: Int? = nil
    var note: String? = nil
    var paymentRef: String? = nil

    var body: some View {
        if let settings {
            AppCard {
                if let upi = settings.upiId?.nilIfBlank {
                    HStack(spacing: 10) {
                        Icon.qr.image.font(.system(size: 18)).foregroundStyle(Brand.gold)
                        Overline(text: "UPI")
                    }
                    Spacer().frame(height: 10)
                    QrCode(text: upiQrUri(settings, amountPaise: amountPaise, note: note, paymentRef: paymentRef),
                           description: "UPI QR code — scan with Google Pay, PhonePe, or Paytm")
                        .frame(maxWidth: .infinity)
                    Text("Scan with Google Pay, PhonePe, Paytm, or any UPI app")
                        .textStyle(Typo.bodyMedium.with(name: FontName.sansMedium))
                        .foregroundStyle(Scheme.onSurface)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8).padding(.bottom, 6)
                    CopyRow(label: "UPI ID", value: upi)
                    CopyRow(label: "UPI Number", value: settings.upiNumber)
                    CopyRow(label: "Payee", value: settings.upiPayeeName, copy: false)
                    CopyRow(label: "Payment reference (include if asked)", value: paymentRef)
                }
                if settings.bankAccountNumber?.nilIfBlank != nil {
                    Spacer().frame(height: 10)
                    HStack(spacing: 10) {
                        Icon.bank.image.font(.system(size: 18)).foregroundStyle(Brand.gold)
                        Overline(text: "Bank transfer")
                    }
                    CopyRow(label: "Account name", value: settings.bankAccountName, copy: false)
                    CopyRow(label: "Account number", value: settings.bankAccountNumber)
                    CopyRow(label: "IFSC", value: settings.bankIfsc)
                    CopyRow(label: "Bank", value: [settings.bankName, settings.bankBranch].compactMap { $0 }.joined(separator: ", "), copy: false)
                }
            }
        }
    }
}

/// How the student paid (asked only when there is more than one way), the transaction reference and the screenshot.
struct PaymentConfirmFields: View {
    let settings: PaymentSettings?
    @Binding var method: String
    @Binding var reference: String
    let proof: ProofImagePicker

    var body: some View {
        let methods: [(String, String)] = [("upi", "UPI")] + (settings?.bankAccountNumber?.nilIfBlank != nil ? [("bank", "Bank transfer")] : [])
        if methods.count > 1 {
            HStack(spacing: 10) {
                ForEach(methods, id: \.0) { value, label in
                    ChoicePill(label: label, selected: method == value) { method = value }
                }
            }
        }
        OutlinedField(
            label: "Transaction reference (UTR)",
            text: Binding(get: { reference }, set: { reference = String($0.filter { $0.isLetter || $0.isNumber }.prefix(40)) }),
            supporting: "The 12-digit reference shown in your UPI or bank app after paying.",
            keyboard: .asciiCapable,
            capitalization: .characters,
            autocorrect: false,
            submitLabel: .done
        )
        ScreenshotPicker(proof: proof)
    }
}

/// One detail with a copy button ("UPI ID  academy@upi  ⧉").
struct CopyRow: View {
    let label: String
    let value: String?
    var copy: Bool = true
    @Environment(Toaster.self) private var toaster

    var body: some View {
        if let value = value?.nilIfBlank {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text(label).textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant)
                    Text(value).textStyle(Typo.bodyLarge.with(name: FontName.sansMedium)).foregroundStyle(Scheme.onSurface).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if copy {
                    IconButton(.copy, label: "Copy \(label)", tint: Scheme.primary, size: 18) {
                        UIPasteboard.general.string = value
                        toaster.show("\(label) copied")
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - proof picker (ProofPicker.kt)

/// A picked payment screenshot, ready to upload ([data], [mime]) and to show ([preview]).
struct ProofImage {
    let data: Data
    let mime: String
    let preview: UIImage

    /// The (data, mime) pair the submit calls take.
    var upload: (Data, String) { (data, mime) }
}

/// A screenshot attached to a payment or order: from the photo library or the camera.
@MainActor
@Observable
final class ProofImagePicker {
    var image: ProofImage?
    var showingLibrary = false
    var showingCamera = false
    var libraryItem: PhotosPickerItem? {
        didSet { if let item = libraryItem { load(item) } }
    }
    @ObservationIgnored var onUnreadable: () -> Void = {}

    func clear() { image = nil; libraryItem = nil }

    private func load(_ item: PhotosPickerItem) {
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            set(data.flatMap(UIImage.init(data:)))
        }
    }

    func set(_ picked: UIImage?) {
        guard let picked, let jpeg = jpegForUpload(picked) else {
            image = nil
            onUnreadable()
            return
        }
        image = ProofImage(data: jpeg, mime: "image/jpeg", preview: picked)
    }
}

/// A picked image as a JPEG no larger than [maxSide] pixels on its longer side, upright (Android's readImageAsJpeg):
/// phone photos can be 50+ megapixels.
func jpegForUpload(_ image: UIImage, maxSide: CGFloat = 1600) -> Data? {
    let longest = max(image.size.width, image.size.height)
    guard longest > 0 else { return nil }
    let scale = min(1, maxSide / longest)
    let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    // Drawing applies the photo's orientation, so a portrait shot isn't uploaded sideways.
    let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    return upright.jpegData(compressionQuality: 0.85)
}

/// "Attach payment screenshot (optional)", or the attached one with Change / Remove (Android's ScreenshotPicker).
struct ScreenshotPicker: View {
    @Bindable var proof: ProofImagePicker
    var attachLabel: String = "Attach payment screenshot (optional)"
    @Environment(Toaster.self) private var toaster
    @State private var askSource = false

    var body: some View {
        Group {
            if let image = proof.image {
                HStack(spacing: 12) {
                    Image(uiImage: image.preview).resizable().scaledToFill()
                        .frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: Radius.input))
                        .accessibilityLabel("Payment screenshot")
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Screenshot attached").textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface)
                        HStack(spacing: 0) {
                            TextButton("Change", icon: .addPhoto) { askSource = true }
                            TextButton("Remove") { proof.clear() }
                        }
                    }
                }
            } else {
                SecondaryButton(attachLabel) { askSource = true }
            }
        }
        .confirmationDialog("Add a screenshot", isPresented: $askSource) {
            Button("Choose from photos") { proof.showingLibrary = true }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take a photo") { proof.showingCamera = true }
            }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $proof.showingLibrary, selection: $proof.libraryItem, matching: .images)
        .fullScreenCover(isPresented: $proof.showingCamera) {
            CameraPicker { proof.set($0) }.ignoresSafeArea()
        }
        .onAppear { proof.onUnreadable = { toaster.show("That image couldn't be read. Try another screenshot.", long: true) } }
    }
}

/// The camera, for photographing a receipt.
struct CameraPicker: UIViewControllerRepresentable {
    let onPicked: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.onPicked(info[.originalImage] as? UIImage)
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
