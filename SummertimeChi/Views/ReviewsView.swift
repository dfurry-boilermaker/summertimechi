import SwiftUI

struct ReviewsView: View {
    let barID: UUID
    let reviews: [UserReview]
    @State private var showingAddReview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Community Reviews")
                    .font(.headline)
                Spacer()
                Button {
                    showingAddReview = true
                } label: {
                    Label("Write Review", systemImage: "square.and.pencil")
                        .font(.subheadline)
                }
            }

            if reviews.isEmpty {
                Text("No reviews yet. Be the first to review this patio's sun situation!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(reviews) { review in
                    ReviewRow(review: review)
                    Divider()
                }
            }
        }
        .sheet(isPresented: $showingAddReview) {
            AddReviewView(barID: barID)
        }
    }
}

// MARK: - Review Row

struct ReviewRow: View {
    let review: UserReview

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                SunRatingView(rating: review.sunRating)
                Spacer()
                Text(review.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(review.authorDisplayName)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            if let text = review.reviewText, !text.isEmpty {
                Text(text)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sun Rating Display

struct SunRatingView: View {
    let rating: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "sun.max.fill" : "sun.max")
                    .foregroundStyle(star <= rating ? .yellow : .gray)
                    .font(.caption)
            }
        }
    }
}

// MARK: - Add Review Sheet

struct AddReviewView: View {
    let barID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var sunRating = 3
    @State private var reviewText = ""
    @State private var authorName = ""
    @State private var isSubmitting = false
    @State private var submitError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Sun Rating") {
                    HStack {
                        Text("How sunny is this patio?")
                            .font(.subheadline)
                        Spacer()
                        HStack(spacing: 4) {
                            ForEach(1...5, id: \.self) { star in
                                Button {
                                    sunRating = star
                                } label: {
                                    Image(systemName: star <= sunRating ? "sun.max.fill" : "sun.max")
                                        .foregroundStyle(star <= sunRating ? .yellow : .gray)
                                        .font(.title3)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Section("Your Review (optional)") {
                    TextField("Describe the patio's sun situation…", text: $reviewText, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Display Name") {
                    TextField("Your name or nickname", text: $authorName)
                }

                if let error = submitError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Write a Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Submit") {
                        Task { await submitReview() }
                    }
                    .disabled(authorName.isEmpty || isSubmitting)
                    .bold()
                }
            }
            .overlay {
                if isSubmitting {
                    ProgressView("Submitting…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func submitReview() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await ReviewService.shared.submitReview(
                barID: barID,
                sunRating: sunRating,
                reviewText: reviewText.isEmpty ? nil : reviewText,
                authorDisplayName: authorName
            )
            dismiss()
        } catch {
            submitError = error.localizedDescription
        }
    }
}

#Preview {
    ReviewsView(barID: UUID(), reviews: [
        UserReview(
            id: UUID(), barID: UUID(), sunRating: 4,
            reviewText: "Gets great afternoon sun from about 3pm to 7pm!",
            authorDisplayName: "Patio Pete",
            createdAt: Date().addingTimeInterval(-86400),
            cloudKitRecordID: nil
        ),
        UserReview(
            id: UUID(), barID: UUID(), sunRating: 2,
            reviewText: "Building across the street casts shade most of the day.",
            authorDisplayName: "ShadeHater",
            createdAt: Date().addingTimeInterval(-3600),
            cloudKitRecordID: nil
        )
    ])
    .padding()
}
