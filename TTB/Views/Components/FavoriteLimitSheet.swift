import SwiftUI

struct FavoriteLimitSheet: View {
    let savedQuestions: [Question]
    let onCreateAccount: () -> Void
    /// Both actions close the sheet through its owner, which presents it from the topmost
    /// controller (`docs/adr/0010`). The sheet never calls `dismiss()` itself: a second dismissal
    /// racing the owner's could swallow the completion that opens the upgrade sheet.
    let onMaybeLater: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    hero
                    previewSection
                    actions
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 32)
            }
            .background(Color.theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.close"), action: onMaybeLater)
                }
            }
        }
        .accessibilityIdentifier("favorite-limit-sheet")
    }

    private var hero: some View {
        VStack(spacing: 14) {
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.yellow)
                }
            }
            .accessibilityHidden(true)

            Text(String(localized: "guest.favorite.limit.title"))
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(String(localized: "guest.favorite.limit.message"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if !savedQuestions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "guest.favorite.limit.previewTitle"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(savedQuestions.prefix(4)) { question in
                        Text(question.text)
                            .font(.caption.weight(.medium))
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                            .padding(12)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.theme.border.opacity(0.16), lineWidth: 1)
                            }
                    }
                }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button(action: onCreateAccount) {
                Text(String(localized: "guest.favorite.signup.cta"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("favorite-limit-create-account")

            Button(action: onMaybeLater) {
                Text(String(localized: "guest.favorite.notnow.button"))
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("favorite-limit-maybe-later")
        }
    }
}

#Preview {
    FavoriteLimitSheet(
        savedQuestions: Array(Question.sampleQuestions.prefix(4)),
        onCreateAccount: {},
        onMaybeLater: {}
    )
}
