import Observation
import SwiftUI

/*
 * The book catalogue: /admin/bookstore (list), /admin/bookstore/[bookId] (detail), /new and /[bookId]/edit (form).
 * Ported from Android's ui/manage/bookstore/BooksAdmin.kt (adminBookStatusTone from BookstoreGraph.kt).
 */

/// A book's availability tone in the admin (Android's bookStatusTone in BookstoreGraph.kt; the public store has its own).
func adminBookStatusTone(_ status: String) -> Tone {
    switch status {
    case "AVAILABLE": .success
    case "OUT_OF_STOCK": .danger
    case "COMING_SOON": .warning
    default: .neutral
    }
}

/// A book's cover, small corners (Material's shapes.small).
private struct BookstoreCover: View {
    let path: String?
    let title: String
    var width: CGFloat = 40
    var height: CGFloat = 54

    var body: some View {
        RemoteImage(path: path, contentDescription: title)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - list

struct BooksListScreen: View {
    var body: some View {
        WithModel({ app in
            PagedListModel<AdminBook>(app: app) { app, page, q, _ in
                try await app.service(BookstoreAdminAPI.self).books(page: page, q: q.trimmed.isEmpty ? nil : q)
            }
        }) { model in BooksListContent(model: model) }
    }
}

private struct BooksListContent: View {
    let model: PagedListModel<AdminBook>
    @Environment(Navigator.self) private var nav

    var body: some View {
        ManageListScreen(
            "Bookstore", model: model, key: \.id, emptyTitle: "No books yet", searchHint: "Search by title or author",
            actions: { IconButton(.receipt, label: "Book orders") { nav.push(.manage(.bookOrdersAdmin)) } },
            fab: { AddFab("Add book") { nav.push(.manage(.bookNew)) } }
        ) { book in
            RecordCard(
                title: book.title,
                subtitle: "\(book.author) · \(rupees(book.priceInrPaise))",
                meta: [book.published ? "Published" : "Draft", book.featured ? "Featured on homepage" : "Not featured"].joined(separator: " · "),
                chip: (book.statusLabel.trimmed.isEmpty ? book.status : book.statusLabel, adminBookStatusTone(book.status)),
                onClick: { nav.push(.manage(.bookAdmin(id: book.id))) },
                leading: { BookstoreCover(path: book.imagePath, title: book.title) }
            )
        }
        .reloadOnReturn { model.refresh() }
    }
}

// MARK: - detail

@MainActor
@Observable
final class BookDetailModel {
    let loader: Loader<AdminBookResponse>
    let runner: ActionRunner
    var confirmDelete = false

    init(app: AppContainer, id: String) {
        loader = Loader(app: app) { try await $0.service(BookstoreAdminAPI.self).book(id) }
        runner = ActionRunner(app: app)
    }
}

struct BookDetailScreen: View {
    let id: String

    var body: some View {
        WithModel({ BookDetailModel(app: $0, id: id) }) { model in BookDetailContent(id: id, model: model) }
    }
}

private struct BookDetailContent: View {
    let id: String
    @Bindable var model: BookDetailModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        ManageScaffold("Book details", actions: {
            IconButton(.edit, label: "Edit book") { nav.push(.manage(.bookEdit(id: id))) }
            IconButton(.delete, label: "Delete book", tint: model.runner.busy ? Scheme.onSurface.opacity(0.38) : Scheme.onSurface) {
                model.confirmDelete = true
            }
            .disabled(model.runner.busy)
        }) {
            LoadedColumn(model.loader) { r in
                let b = r.book
                DetailCard {
                    HStack(alignment: .top, spacing: 14) {
                        BookstoreCover(path: b.imagePath, title: b.title, width: 96, height: 128)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(b.title).textStyle(Typo.titleLarge).foregroundStyle(Scheme.onSurface)
                            Text(b.author).textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurfaceVariant)
                            PriceLine(pricePaise: b.priceInrPaise, mrpPaise: b.mrpInrPaise > 0 ? b.mrpInrPaise : nil)
                            StatusChip(b.statusLabel.trimmed.isEmpty ? b.status : b.statusLabel, tone: adminBookStatusTone(b.status))
                            StatusChip(b.published ? "Published" : "Draft", tone: b.published ? .success : .neutral)
                        }
                    }
                }
                DetailCard("Details") {
                    Field("Title", b.title)
                    Field("Author", b.author)
                    Field("Selling price", rupees(b.priceInrPaise))
                    Field("MRP", b.mrpInrPaise > 0 ? rupees(b.mrpInrPaise) : nil)
                    Field("Purchase price", rupees(b.purchasePriceInrPaise))
                    Field("Weight", "\(b.weightInGrams) g")
                    Field("Homepage", b.featured ? "Featured" : "Not featured")
                    Field("Description", b.description)
                    Field("Added", formatDate(b.createdAt))
                }
                DetailCard("Stock") {
                    FieldRow("Total inventory procured", String(b.inventoryPurchased))
                    if let s = r.stock {
                        if s.adjustments != 0 { FieldRow("Adjustments", (s.adjustments > 0 ? "+" : "") + String(s.adjustments)) }
                        FieldRow("Held by approved or shipped orders", String(s.committed))
                        FieldRow("Available", String(s.available), strong: true)
                    }
                    Text("To change the stock, edit the total inventory procured. Refunded and declined orders do not hold stock.")
                        .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                }
            }
        }
        .reloadOnReturn { model.loader.reload() }
        .confirmDialog(
            "Delete this book?",
            message: "The book and its cover are removed. A book that appears in any order cannot be deleted: unpublish it or set it to Out of Stock instead.",
            isPresented: $model.confirmDelete, confirm: "Delete", destructive: true
        ) {
            model.runner.run({ try await $0.service(BookstoreAdminAPI.self).delete(id) }, success: "Book deleted.") { _ in nav.pop() }
        }
    }
}

// MARK: - form

private let bookDefaultStatusOptions: [(value: String, label: String)] = [
    (value: "AVAILABLE", label: "Available"), (value: "OUT_OF_STOCK", label: "Out of Stock"), (value: "COMING_SOON", label: "Coming Soon"),
]

@MainActor
@Observable
final class BookFormModel {
    let id: String?
    let loader: Loader<AdminBookResponse>
    let runner: ActionRunner
    let files = FormFiles()
    var filled = false
    var title = ""
    var author = ""
    var description = ""
    var mrp = ""
    var price = ""
    var purchase = ""
    var weight = "0"
    var inventory = ""
    var status = "AVAILABLE"
    var published = true
    var featured = false
    var removeImage = false
    var error: String?

    init(app: AppContainer, id: String?) {
        self.id = id
        loader = Loader(app: app) { app in
            let api = app.service(BookstoreAdminAPI.self)
            if let id { return try await api.book(id) }
            let o = try await api.formOptions()
            return AdminBookResponse(book: AdminBook(id: ""), stock: nil, statusOptions: o.statusOptions, featuredCount: o.featuredCount, featuredMax: o.featuredMax)
        }
        runner = ActionRunner(app: app)
    }

    func fill() {
        guard let b = loader.state.value?.book, id != nil, !filled else { return }
        title = b.title; author = b.author; description = b.description
        mrp = b.mrpInrPaise > 0 ? paiseToRupeesText(b.mrpInrPaise) : ""
        price = paiseToRupeesText(b.priceInrPaise); purchase = paiseToRupeesText(b.purchasePriceInrPaise)
        weight = String(b.weightInGrams); inventory = String(b.inventoryPurchased)
        status = b.status; published = b.published; featured = b.featuredOnHomepage
        filled = true
    }

    func validate() -> String? {
        if title.trimmed.count < 2 { return "Title is required." }
        if author.trimmed.count < 2 { return "Author is required." }
        if description.trimmed.count < 10 { return "Description must be at least 10 characters." }
        if price.trimmed.isEmpty { return "Price is required." }
        if purchase.trimmed.isEmpty { return "Purchase price is required." }
        if weight.trimmed.isEmpty { return "Weight is required." }
        if inventory.trimmed.isEmpty { return "Total inventory procured is required." }
        return nil
    }

    func save(onDone: @escaping () -> Void) {
        error = validate()
        guard error == nil else { return }
        let image = files.single
        let parts = formOf { f in
            f.text("title", title.trimmed); f.text("author", author.trimmed); f.text("description", description.trimmed)
            f.text("mrpInr", mrp); f.text("priceInr", price); f.text("purchasePriceInr", purchase)
            f.text("weightInGrams", weight); f.text("inventoryPurchased", inventory); f.text("status", status)
            f.text("published", String(published)); f.text("featuredOnHomepage", String(featured))
            f.text("removeImage", String(removeImage && image == nil))
            f.file("image", image)
        }
        let id = id
        runner.run({ app in
            let api = app.service(BookstoreAdminAPI.self)
            return if let id { try await api.update(id, parts) } else { try await api.create(parts) }
        }, success: id == nil ? "Book created." : "Changes saved.") { _ in onDone() }
    }
}

/// Add ([id] nil) or edit a book: the website's BookForm.
struct BookFormScreen: View {
    let id: String?

    var body: some View {
        WithModel({ BookFormModel(app: $0, id: id) }) { model in BookFormContent(model: model) }
    }
}

private struct BookFormContent: View {
    @Bindable var model: BookFormModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        let state = model.loader.state
        let loaded = state.value
        let loadError: String? = if case .failed(let message) = state { message } else { nil }
        FormScreen(
            model.id == nil ? "Add book" : "Edit book", saving: model.runner.busy, saveLabel: model.id == nil ? "Add book" : "Save changes",
            error: model.error, canSave: loaded != nil && (model.id == nil || model.filled), loadError: loadError,
            onRetry: { model.loader.load() }, onSave: { model.save { nav.pop() } }
        ) {
            if let loaded {
                FormImageField(
                    "Book cover image", currentUrl: model.removeImage ? nil : loaded.book.imagePath, picked: model.files.single,
                    supporting: "Optional, JPEG, PNG, WebP or GIF up to 2 MB.",
                    onRemoveCurrent: model.id != nil ? { model.removeImage = true } : nil
                ) { model.files.single = $0 }
                FormTextField("Title", text: $model.title, maxLength: 200)
                FormTextField("Author", text: $model.author, maxLength: 200)
                FormTextField("Description", text: $model.description, singleLine: false, minLines: 4, maxLength: 5000)

                FormSection("Price and stock") {
                    FormMoneyField("MRP (₹)", text: $model.mrp, supporting: "Optional, e.g. 500")
                    FormMoneyField("Selling price (₹)", text: $model.price, supporting: "e.g. 299")
                    FormMoneyField("Purchase price (₹)", text: $model.purchase, supporting: "e.g. 150")
                    FormNumberField("Weight (grams)", text: $model.weight, supporting: "e.g. 150")
                    FormNumberField("Total inventory procured", text: $model.inventory, supporting: "e.g. 100")
                    FormDropdown(
                        "Availability status",
                        options: loaded.statusOptions.isEmpty ? bookDefaultStatusOptions : loaded.statusOptions.map { (value: $0.value, label: $0.label) },
                        value: model.status
                    ) { model.status = $0 }
                }

                FormSection("Visibility") {
                    FormSwitch("Published", checked: model.published, description: "Turn off to hide from the public bookstore.") { model.published = $0 }
                    FeaturedSwitch(
                        featured: model.featured, currentlyFeatured: loaded.book.featuredOnHomepage, used: loaded.featuredCount, max: loaded.featuredMax,
                        section: "Featured Books", pageName: "bookstore", noun: "books"
                    ) { model.featured = $0 }
                }
                Spacer().frame(height: 4)
            } else {
                Text("Loading…").textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
            }
        }
        .onChange(of: loaded?.book.id, initial: true) { _, _ in model.fill() }
    }
}
