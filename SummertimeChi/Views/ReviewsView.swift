import SwiftUI

struct ReviewsView: View {
    let barID: UUID
    let reviews: [UserReview]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Community Reviews")
                .font(.headline)

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
