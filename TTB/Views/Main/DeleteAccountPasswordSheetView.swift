import SwiftUI

struct DeleteAccountPasswordSheetView: View {
    let email: String
    let isDeleting: Bool
    let errorMessage: String?
    let onDelete: (String) async -> Void

    @State private var password = ""
    @State private var isPasswordVisible = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    warningCard
                    passwordField

                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button(role: .destructive, action: deleteAccount) {
                        if isDeleting {
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity, minHeight: 52)
                        } else {
                            Text(String(localized: "profile.deleteSheet.confirm"))
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isDeleting || password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.top, 8)
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(String(localized: "profile.deleteSheet.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    SimulatorSafeSheetDismissButton {
                        Text(String(localized: "common.cancel"))
                    }
                        .disabled(isDeleting)
                }
            }
        }
    }

    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "profile.deleteSheet.warningTitle"), systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)

            Text(String(localized: "profile.deleteSheet.warningBody"))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(String(localized: "profile.deleteSheet.warningFootnote"))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(email)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "profile.deleteSheet.passwordLabel"))
                .font(.headline)

            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                if isPasswordVisible {
                    TextField(String(localized: "profile.deleteSheet.passwordPlaceholder"), text: $password)
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel(String(localized: "profile.deleteSheet.passwordPlaceholder"))
                } else {
                    SecureField(String(localized: "profile.deleteSheet.passwordPlaceholder"), text: $password)
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel(String(localized: "profile.deleteSheet.passwordPlaceholder"))
                }

                Button(action: togglePasswordVisibility) {
                    Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(String(localized: isPasswordVisible ? "auth.password.hide" : "auth.password.show"))
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
    }

    private func togglePasswordVisibility() {
        isPasswordVisible.toggle()
    }

    private func deleteAccount() {
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPassword.isEmpty else { return }

        Task {
            await onDelete(trimmedPassword)
        }
    }
}

#Preview {
    DeleteAccountPasswordSheetView(
        email: "demo@example.com",
        isDeleting: false,
        errorMessage: nil,
        onDelete: { _ in }
    )
}
