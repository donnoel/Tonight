import SwiftUI

struct TonightView: View {
    private let concepts = [
        RecommendationConcept(
            title: "Best Match",
            description: "The movie with the strongest overall fit for what you want tonight.",
            systemImage: "sparkles"
        ),
        RecommendationConcept(
            title: "Wildcard",
            description: "A less obvious choice that still belongs in the conversation.",
            systemImage: "shuffle"
        ),
        RecommendationConcept(
            title: "Forgotten One",
            description: "Something buried in your own library that deserves another look.",
            systemImage: "archivebox"
        )
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                hero

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: 20)],
                    spacing: 20
                ) {
                    ForEach(concepts) { concept in
                        RecommendationConceptCard(concept: concept)
                    }
                }

                Text("Recommendations will be designed in the next phase and will only choose from movies in your Library.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 620, alignment: .leading)
            }
            .frame(maxWidth: 1080, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 36)
        }
        .navigationTitle("Tonight")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 42))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("What are you in the mood for?")
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)

            Text("Tonight will use your taste, viewing history, and context to help you choose from movies you already own.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 700, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RecommendationConcept: Identifiable {
    let title: String
    let description: String
    let systemImage: String

    var id: String { title }
}

private struct RecommendationConceptCard: View {
    let concept: RecommendationConcept

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: concept.systemImage)
                .font(.title)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(concept.title)
                .font(.title2.bold())

            Text(concept.description)
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text("Coming next")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .leading)
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }
}

