import SwiftUI

/// The first tab: greeting and inspiration, what the student should do now, their courses, then the academy's content
/// (Android's HomeScreen).
struct HomeScreen: View {
    var body: some View {
        WithModel({ HomeModel(repo: $0.repo, auth: $0.auth) }) { model in
            HomeContent(model: model)
        }
    }
}

private struct HomeContent: View {
    let model: HomeModel
    @Environment(Navigator.self) private var nav

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    HomeHero(
                        session: model.session, unread: model.unread, inspiration: model.content?.dailyInspiration,
                        topInset: geo.safeAreaInsets.top,
                        onNotifications: { nav.push(.notifications) }, onSignIn: { nav.push(.signIn) }
                    )
                    if let content = model.content {
                        sections(content)
                    } else if let error = model.error {
                        ErrorState(message: error) { Task { await model.refresh() } }
                    } else {
                        SkeletonList(rows: 4)
                    }
                }
                .padding(.bottom, 24)
            }
            .ignoresSafeArea(edges: .top)
            .refreshable { await model.refresh() }
        }
        .background(Scheme.background)
        .reloadOnReturn { model.reload() }
    }

    @ViewBuilder
    private func sections(_ content: HomeResponse) -> some View {
        if !model.actions.isEmpty {
            Spacer().frame(height: 20)
            // Its own stack, so these row ids can't clash with other rows of the LazyVStack around it.
            VStack(spacing: 0) {
                ForEach(Array(model.actions.enumerated()), id: \.offset) { _, action in
                    ActionCardView(action: action) { open(action) }
                        .padding(.horizontal, 20).padding(.vertical, 5)
                    if action.kind == .verifyEmail {
                        VerifyEmailResend(state: model.resend) { model.resendVerification() }
                    }
                }
            }
        }

        if model.session != nil, !model.enrollments.isEmpty {
            Spacer().frame(height: 24)
            SectionHeader(title: "My courses", action: "All") { nav.switchTab(.courses) }
            Strip(model.enrollments) { e in
                MyCourseCard(enrollment: e) {
                    if EnrollmentStatus.opensLearn(e.status) {
                        nav.push(.learn(courseId: e.courseId, title: e.course?.title ?? "Course"))
                    } else {
                        nav.push(.course(id: e.courseId))
                    }
                }
            }
        } else if model.session == nil {
            JoinCard(onSignIn: { nav.push(.signIn) }, onBrowse: { nav.switchTab(.courses) })
        }

        if !content.announcements.isEmpty {
            Spacer().frame(height: 20)
            SectionHeader(title: "Announcements", action: "All") { nav.switchTab(.explore) }
            Strip(content.announcements) { a in AnnouncementCard(item: a) { nav.push(.announcement(id: a.id)) } }
        }

        if !content.courses.isEmpty {
            Spacer().frame(height: 12)
            SectionHeader(title: "Featured courses", action: "Catalogue") { nav.switchTab(.courses) }
            Strip(content.courses) { c in HomeCourseTile(course: c) { nav.push(.course(id: c.id)) } }
        }

        if !content.blogPosts.isEmpty {
            Spacer().frame(height: 12)
            SectionHeader(title: "From the blog", action: "More") { nav.switchTab(.explore) }
            ForEach(content.blogPosts.prefix(3)) { post in
                BlogPostRow(post: post) { nav.push(.blogPost(id: post.id)) }
                    .padding(.horizontal, 20).padding(.vertical, 6)
            }
        }

        if !content.fatwas.isEmpty {
            Spacer().frame(height: 18)
            SectionHeader(title: "Recent fatwas", action: "More") { nav.switchTab(.explore) }
            ForEach(content.fatwas.prefix(3)) { fatwa in
                FatwaSummaryRow(fatwa: fatwa) { nav.push(.fatwaDetail(id: fatwa.id)) }
                    .padding(.horizontal, 20).padding(.vertical, 6)
            }
        }

        // The website's FeaturedResources: "Study Materials" from the digital library.
        if !content.libraryItems.isEmpty {
            Spacer().frame(height: 18)
            SectionHeader(title: "Study Materials", action: "View all") { nav.push(.library) }
            SectionIntro(text: "Books and study materials from the academy digital library.")
            Strip(content.libraryItems) { item in LibraryCard(item: item) { nav.push(.libraryItem(id: item.id)) } }
        }

        if !content.books.isEmpty {
            Spacer().frame(height: 18)
            SectionHeader(title: "Bookstore", action: "Shop") { nav.push(.bookstore) }
            Strip(content.books) { book in HomeBookTile(book: book) { nav.push(.book(id: book.id)) } }
        }

        testimonials(content.reviews)
    }

    /// The website's StudentTestimonials: approved reviews, or an invitation to write the first.
    @ViewBuilder
    private func testimonials(_ reviews: [Review]) -> some View {
        Spacer().frame(height: 18)
        SectionHeader(title: "What our students say", action: "Write Review") { nav.signedIn(.reviews) }
        SectionIntro(text: "Hear from learners across Jammu & Kashmir and beyond who study Quran, Tajweed, and Islamic sciences with us online.")
        if reviews.isEmpty {
            Text("Be the first to share your experience — your review may appear here after admin approval.")
                .textStyle(Typo.bodySmall)
                .foregroundStyle(Scheme.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20).padding(.vertical, 16)
        } else {
            Strip(reviews) { TestimonialCard(review: $0) }
        }
    }

    private func open(_ action: ActionCard) {
        switch action.kind {
        case .payEnrollment: nav.push(.pay(courseId: action.courseId ?? "", type: "enrollment", title: action.courseTitle ?? ""))
        case .payCourseFee: nav.push(.pay(courseId: action.courseId ?? "", type: "course", title: action.courseTitle ?? ""))
        case .underReview: nav.push(.payments)
        case .completeProfile, .verifyEmail: nav.push(.editProfile)
        }
    }
}

/// A sideways row of cards with the screen padding (Android's LazyRow with 20/12 content padding and 12 between).
private struct Strip<Item: Identifiable, Card: View>: View {
    let items: [Item]
    @ViewBuilder let card: (Item) -> Card

    init(_ items: [Item], @ViewBuilder card: @escaping (Item) -> Card) {
        self.items = items
        self.card = card
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(items) { card($0) }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
    }
}

private struct SectionIntro: View {
    let text: String
    var body: some View {
        Text(text)
            .textStyle(Typo.bodySmall)
            .foregroundStyle(Scheme.onSurfaceVariant)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, 8)
    }
}

// MARK: - hero

private struct HomeHero: View {
    let session: Session?
    let unread: Int
    let inspiration: Inspiration?
    let topInset: CGFloat
    let onNotifications: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        HeroBox {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Image("Logo")
                        .resizable().scaledToFit()
                        .frame(width: 40, height: 40)
                        .background(Color.white)
                        .clipShape(Circle())
                        .accessibilityLabel("Darse Quran Academy")
                    Spacer().frame(width: 12)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Assalamu alaikum").textStyle(Typo.bodySmall).foregroundStyle(Brand.mint)
                        Text(greetingName)
                            .textStyle(Typo.titleLarge)
                            .foregroundStyle(Brand.onHero)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if session != nil {
                        Button(action: onNotifications) {
                            Icon.bellFilled.image
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(Brand.onHero)
                                .overlay(alignment: .topTrailing) {
                                    if unread > 0 { UnreadBadge(count: unread).offset(x: 10, y: -8) }
                                }
                                .frame(width: 48, height: 48)
                                .contentShape(Circle())
                        }
                        .buttonStyle(PressableStyle(shape: Circle()))
                        .accessibilityLabel(unread > 0 ? "Notifications, \(unread) unread" : "Notifications")
                    } else {
                        Button(action: onSignIn) {
                            Text("Sign in")
                                .textStyle(Typo.labelLarge)
                                .foregroundStyle(Brand.goldSoft)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(PressableStyle(shape: Capsule()))
                    }
                }
                if let inspiration {
                    Spacer().frame(height: 18)
                    InspirationCard(inspiration: inspiration).padding(.trailing, 12)
                }
            }
            .padding(.leading, 20).padding(.trailing, 8)
            .padding(.top, topInset + 8).padding(.bottom, 20)
        }
        .clipped() // HeroBox's pattern would otherwise spill past the hero's bottom edge
    }

    /// The first name; the academy's name for a visitor.
    private var greetingName: String {
        guard let name = session?.user.name else { return "Darse Quran Academy" }
        return name.components(separatedBy: " ").first ?? ""
    }
}

/// Material's Badge: a small gold pill with the count ("9+" above nine).
private struct UnreadBadge: View {
    let count: Int
    var body: some View {
        Text(count > 9 ? "9+" : "\(count)")
            .textStyle(Typo.labelSmall)
            .foregroundStyle(Color.black)
            .padding(.horizontal, 4)
            .frame(minWidth: 16, minHeight: 16)
            .background(Brand.goldSoft, in: Capsule())
            .fixedSize()
    }
}

/// The verse or hadith of the day on the green hero: Arabic, its translation and the reference, in a thin gold frame.
struct InspirationCard: View {
    let inspiration: Inspiration

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        VStack(spacing: 0) {
            Overline(text: inspiration.kind == "HADITH" ? "Hadith of the day" : "Verse of the day", color: Brand.goldSoft)
            // Amiri's marks rise well above the cap height; leave them room.
            Spacer().frame(height: 18)
            ArabicText(text: inspiration.arabicText, color: Brand.onHero, size: 24)
            Spacer().frame(height: 6)
            Text(inspiration.englishTranslation)
                .font(slantedFont(Typo.bodyMedium))
                .tracking(Typo.bodyMedium.tracking)
                .lineSpacing(Typo.bodyMedium.lineSpacing)
                .foregroundStyle(Brand.onHero.opacity(0.9))
                .multilineTextAlignment(.center)
            if let reference = inspiration.reference {
                Spacer().frame(height: 8)
                Text("— \(reference)").textStyle(Typo.labelMedium).foregroundStyle(Brand.goldSoft)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18).padding(.vertical, 16)
        .background(Color.white.opacity(0.06), in: shape)
        .overlay(shape.strokeBorder(Brand.goldSoft.opacity(0.55), lineWidth: 1))
    }
}

// MARK: - the student's cards

private struct ActionCardView: View {
    let action: ActionCard
    let onClick: () -> Void

    var body: some View {
        let (icon, tint, background): (Icon, Color, Color) = switch action.kind {
        case .payEnrollment, .payCourseFee: (.payments, Brand.warning, Brand.warningContainer)
        case .underReview: (.pending, Brand.info, Brand.infoContainer)
        case .completeProfile: (.badge, Scheme.primary, Scheme.primaryContainer)
        case .verifyEmail: (.mailUnread, Brand.danger, Brand.dangerContainer)
        }
        AppCard(padding: 14, onClick: onClick) {
            HStack(spacing: 0) {
                ZStack {
                    Circle().fill(background)
                    icon.image.font(.system(size: 20, weight: .medium)).foregroundStyle(tint)
                }
                .frame(width: 44, height: 44)
                Spacer().frame(width: 14)
                VStack(alignment: .leading, spacing: 0) {
                    Text(action.title).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
                    Text(action.message)
                        .textStyle(Typo.bodySmall)
                        .foregroundStyle(Scheme.onSurfaceVariant)
                        .lineLimit(2).truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Icon.forward.image.font(.system(size: 17, weight: .medium)).foregroundStyle(Scheme.onSurfaceVariant).frame(width: 20, height: 20)
            }
            .multilineTextAlignment(.leading)
        }
    }
}

/// The website's "Resend Verification Email" button, under the verify-email card, with its outcome.
private struct VerifyEmailResend: View {
    let state: ResendState
    let onResend: () -> Void

    var body: some View {
        let enabled = !state.sending && !state.sent
        VStack(alignment: .leading, spacing: 0) {
            TextButton(resendLabel(state), color: enabled ? Scheme.primary : Scheme.onSurface.opacity(0.38), action: onResend)
                .disabled(!enabled)
            if let message = state.message {
                Text(message)
                    .textStyle(Typo.labelSmall)
                    .foregroundStyle(state.sent ? Brand.success : Brand.danger)
                    .padding(.leading, 12).padding(.bottom, 6)
            }
        }
        .padding(.horizontal, 20)
    }
}

/// A visitor's invitation: sign in, or browse the catalogue.
private struct JoinCard: View {
    let onSignIn: () -> Void
    let onBrowse: () -> Void

    var body: some View {
        AppCard(color: Scheme.primaryContainer) {
            HStack(spacing: 0) {
                Icon.school.image.font(.system(size: 26)).foregroundStyle(Scheme.onPrimaryContainer).frame(width: 32, height: 32)
                Spacer().frame(width: 14)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Learn with the academy").textStyle(Typo.titleMedium).foregroundStyle(Scheme.onPrimaryContainer)
                    Text("Quran, Tajweed, Fiqh and more with qualified teachers.").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onPrimaryContainer)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer().frame(height: 14)
            HStack(spacing: 10) {
                CtaButton("Sign in", fullWidth: true, action: onSignIn)
                OutlinedPillButton(text: "Browse courses", action: onBrowse)
            }
        }
        .padding(20)
    }
}

/// Material's OutlinedButton: a pill outline with the label in the primary colour.
struct OutlinedPillButton: View {
    let text: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).textStyle(Typo.labelLarge).foregroundStyle(Scheme.primary).lineLimit(1)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 40)
                .overlay(Capsule().strokeBorder(Scheme.outline, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle(shape: Capsule()))
    }
}

private struct MyCourseCard: View {
    let enrollment: Enrollment
    let onClick: () -> Void

    var body: some View {
        let course = enrollment.course
        let (label, tone) = statusLabel(enrollment.status)
        AppCard(onClick: onClick) {
            StatusChip(label, tone: tone)
            Spacer().frame(height: 10)
            Text(course?.title ?? "Course")
                .textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
                .lineLimit(2).truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .frame(height: 44, alignment: .topLeading)
            Spacer().frame(height: 8)
            HStack(spacing: 0) {
                Avatar(name: course?.teacher?.name, image: course?.teacher?.imageUrl, size: 26)
                Spacer().frame(width: 8)
                Text(course?.teacher?.name ?? "")
                    .textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let roll = enrollment.rollNumber {
                    Text("Roll \(roll)").textStyle(Typo.labelMedium).foregroundStyle(Brand.gold)
                }
            }
        }
        .frame(width: 250)
    }
}

// MARK: - the academy's content

private struct AnnouncementCard: View {
    let item: SiteAnnouncement
    let onClick: () -> Void

    var body: some View {
        AppCard(padding: 0, onClick: onClick) {
            if let image = item.images.first {
                RemoteImage(path: image.imagePath).frame(maxWidth: .infinity).frame(height: 120)
            }
            VStack(alignment: .leading, spacing: 0) {
                Overline(text: item.eventDate.map { formatDate($0) } ?? relativeTime(item.createdAt))
                Spacer().frame(height: 4)
                Text(item.title).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface).lineLimit(2)
                Spacer().frame(height: 4)
                Text(plainText(item.body)).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).lineLimit(2)
            }
            .multilineTextAlignment(.leading)
            .padding(14)
        }
        .frame(width: 280)
    }
}

/// A featured course on Home: the green band with category and level, then title, teacher and fee.
struct HomeCourseTile: View {
    let course: Course
    let onClick: () -> Void

    var body: some View {
        AppCard(padding: 0, onClick: onClick) {
            HeroBox {
                VStack(alignment: .leading, spacing: 0) {
                    Overline(text: course.category.trimmed.isEmpty ? "Course" : course.category, color: Brand.goldSoft)
                    Spacer().frame(height: 4)
                    Text(course.level).textStyle(Typo.labelMedium).foregroundStyle(Brand.mint)
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: 86)
            VStack(alignment: .leading, spacing: 0) {
                Text(course.title)
                    .textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface)
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .frame(height: 44, alignment: .topLeading)
                Spacer().frame(height: 6)
                Text(course.teacher?.name ?? "").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).lineLimit(1)
                Spacer().frame(height: 8)
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(course.monthlyFeeInrPaise > 0 ? rupees(course.monthlyFeeInrPaise) : "Free")
                        .textStyle(Typo.titleMedium).foregroundStyle(Scheme.primary)
                    if course.monthlyFeeInrPaise > 0 {
                        Text(feeFrequencySuffix(course.feeFrequency)).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant)
                    }
                }
            }
            .padding(14)
        }
        .frame(width: 240)
    }
}

/// A blog post in a list: picture, title, excerpt, author and date (Android's BlogRow).
struct BlogPostRow: View {
    let post: BlogPost
    let onClick: () -> Void

    var body: some View {
        AppCard(padding: 12, onClick: onClick) {
            HStack(alignment: .top, spacing: 0) {
                RemoteImage(path: post.images.first?.imagePath)
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.input, style: .continuous))
                Spacer().frame(width: 12)
                VStack(alignment: .leading, spacing: 0) {
                    Text(post.title).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface).lineLimit(2)
                    Spacer().frame(height: 4)
                    Text(plainText(post.excerpt ?? post.body)).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).lineLimit(2)
                    Spacer().frame(height: 4)
                    Text([post.createdBy?.name, formatDate(post.createdAt)].compactMap { $0 }.joined(separator: " · "))
                        .textStyle(Typo.labelSmall).foregroundStyle(Brand.gold)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// A fatwa in a list: category, title and the start of the answer (Android's FatwaRow).
struct FatwaSummaryRow: View {
    let fatwa: Fatwa
    let onClick: () -> Void

    var body: some View {
        AppCard(onClick: onClick) {
            Overline(text: fatwa.category)
            Spacer().frame(height: 4)
            Text(fatwa.title).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface).lineLimit(2).multilineTextAlignment(.leading)
            Spacer().frame(height: 4)
            Text(plainText(fatwa.answer)).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).lineLimit(2).multilineTextAlignment(.leading)
        }
    }
}

/// A book: cover, title, author and price (Android's BookTile; the bookstore's grid uses it at full width).
struct HomeBookTile: View {
    let book: Book
    var width: CGFloat? = 150
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .aspectRatio(0.72, contentMode: .fit)
                    .overlay { RemoteImage(path: book.imagePath, contentDescription: book.title) }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.input, style: .continuous))
                Spacer().frame(height: 8)
                Text(book.title).textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface).lineLimit(2).multilineTextAlignment(.leading)
                Text(book.author).textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).lineLimit(1)
                Spacer().frame(height: 2)
                PriceLine(pricePaise: book.priceInrPaise, mrpPaise: book.mrpInrPaise)
            }
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct LibraryCard: View {
    let item: LibraryItem
    let onClick: () -> Void

    var body: some View {
        AppCard(padding: 0, onClick: onClick) {
            if let path = item.imagePath {
                Color.clear
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay { RemoteImage(path: path, contentDescription: item.title) }
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 0) {
                if !item.topic.trimmed.isEmpty { Overline(text: item.topic) }
                Spacer().frame(height: 4)
                Text(item.title).textStyle(Typo.titleMedium).foregroundStyle(Scheme.onSurface).lineLimit(2)
                if !item.author.trimmed.isEmpty {
                    Text("by \(item.author)").textStyle(Typo.bodySmall).foregroundStyle(Scheme.onSurfaceVariant).lineLimit(1)
                }
                let facts = [item.level, item.language].filter { !$0.trimmed.isEmpty }
                if !facts.isEmpty {
                    Spacer().frame(height: 6)
                    Text(facts.joined(separator: " · ")).textStyle(Typo.labelSmall).foregroundStyle(Brand.gold)
                }
            }
            .multilineTextAlignment(.leading)
            .padding(14)
        }
        .frame(width: 260)
    }
}

private struct TestimonialCard: View {
    let review: Review

    var body: some View {
        AppCard {
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { i in
                    (i < review.rating ? Icon.star : Icon.starOutline).image
                        .font(.system(size: 15))
                        .foregroundStyle(i < review.rating ? Brand.gold : Scheme.outline)
                        .frame(width: 18, height: 18)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(review.rating) out of 5 stars")
            Spacer().frame(height: 10)
            Text("“\(review.quote)”")
                .textStyle(Typo.bodyMedium).foregroundStyle(Scheme.onSurface)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            Spacer().frame(height: 14)
            VStack(spacing: 0) {
                Avatar(name: review.name, image: nil)
                Spacer().frame(height: 8)
                if let name = review.name { Text(name).textStyle(Typo.titleSmall).foregroundStyle(Scheme.onSurface) }
                if let location = review.location { Text(location).textStyle(Typo.labelSmall).foregroundStyle(Scheme.onSurfaceVariant) }
                if let course = review.course { Text(course).textStyle(Typo.labelSmall).foregroundStyle(Brand.gold) }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
        .frame(width: 280)
    }
}

/// [style] slanted like Compose's synthesized italic (Poppins has no italic face in the app), scaled with Dynamic Type.
@MainActor
func slantedFont(_ style: AppTextStyle) -> Font {
    let size = UIFontMetrics(forTextStyle: .callout).scaledValue(for: style.size)
    let base = UIFont(name: style.fontName, size: size) ?? .systemFont(ofSize: size)
    let slant = CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0)
    return Font(UIFont(descriptor: base.fontDescriptor.withMatrix(slant), size: size))
}
