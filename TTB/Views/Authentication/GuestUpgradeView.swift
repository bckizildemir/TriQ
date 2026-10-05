import FirebaseAuth
import SwiftUI

struct GuestUpgradeView: View {
  @EnvironmentObject var authModel: AuthModel
  @Environment(\.dismiss) private var dismiss

  @State private var username = ""
  @State private var email = ""
  @State private var password = ""
  @State private var confirmPassword = ""
  @State private var isPasswordVisible = false
  @State private var isConfirmPasswordVisible = false
  @State private var localError: String? = nil

  var body: some View {
    NavigationStack {
      ZStack {
        Color.theme.background
          .ignoresSafeArea()

        ScrollView {
          VStack(spacing: 28) {
            VStack(spacing: 12) {
              ZStack {
                Circle()
                  .fill(Color.accentColor.opacity(0.12))
                  .frame(width: 80, height: 80)
                Image(systemName: "person.badge.plus")
                  .font(.system(size: 36, weight: .semibold))
                  .foregroundStyle(Color.accentColor)
              }

              Text(String(localized: "auth.guestUpgrade.title"))
                .font(.title2.bold())
                .foregroundStyle(Color.theme.text)

              Text(String(localized: "auth.guestUpgrade.body"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            }
            .padding(.top, 24)

            VStack(spacing: 16) {
              AuthGroupedFieldSection {
                AuthLabeledFieldRow<Never>(
                  label: String(localized: "auth.field.username"),
                  placeholder: String(localized: "auth.register.usernamePlaceholder"),
                  text: $username,
                  textContentType: .username,
                  accessibilityLabel: String(localized: "auth.register.usernameAccessibility")
                )

                AuthFieldDivider()

                AuthLabeledFieldRow<Never>(
                  label: String(localized: "auth.field.email"),
                  placeholder: String(localized: "auth.register.emailPlaceholder"),
                  text: $email,
                  keyboardType: .emailAddress,
                  textContentType: .emailAddress,
                  accessibilityLabel: String(localized: "auth.register.emailAccessibility")
                )

                AuthFieldDivider()

                AuthLabeledFieldRow<Never>(
                  label: String(localized: "auth.field.password"),
                  placeholder: String(localized: "auth.register.passwordPlaceholder"),
                  text: $password,
                  textContentType: .newPassword,
                  isSecure: true,
                  isPasswordVisible: isPasswordVisible,
                  showsPasswordToggle: true,
                  onTogglePasswordVisibility: { isPasswordVisible.toggle() },
                  accessibilityLabel: String(localized: "auth.register.passwordAccessibility")
                )

                AuthFieldDivider()

                AuthLabeledFieldRow<Never>(
                  label: String(localized: "auth.field.confirm"),
                  placeholder: String(localized: "auth.register.confirmPasswordPlaceholder"),
                  text: $confirmPassword,
                  textContentType: .newPassword,
                  isSecure: true,
                  isPasswordVisible: isConfirmPasswordVisible,
                  showsPasswordToggle: true,
                  onTogglePasswordVisibility: { isConfirmPasswordVisible.toggle() },
                  accessibilityLabel: String(localized: "auth.register.confirmPasswordAccessibility")
                )
              }

              if let error = localError {
                Text(error)
                  .font(.caption)
                  .foregroundStyle(.red)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.horizontal, 4)
              }

              AuthPrimaryChipButton(
                title: String(localized: "auth.guestUpgrade.createAccount"),
                isLoading: authModel.isLoading,
                loadingAccessibilityLabel: String(localized: "auth.register.loading"),
                isEnabled: isFormValid
              ) {
                Task { await createAccount() }
              }
              .accessibilityLabel(String(localized: "auth.guestUpgrade.createAccount"))
              .accessibilityHint(String(localized: "auth.guestUpgrade.accessibilityHint"))
            }
            .padding(.horizontal, 24)
          }
          .padding(.bottom, 32)
        }
      }
      .navigationTitle(String(localized: "auth.guestUpgrade.navigationTitle"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          SimulatorSafeSheetDismissButton {
            Text(String(localized: "common.cancel"))
          }
        }
      }
      .alert(String(localized: "common.error.title"), isPresented: $authModel.errorState.isShowing) {
        Button(String(localized: "common.ok"), role: .cancel) { authModel.dismissError() }
      } message: {
        Text(authModel.errorState.message)
      }
      .onChange(of: authModel.isAnonymous) { _, isAnon in
        if !isAnon { dismiss() }
      }
    }
    .accessibilityIdentifier("guest-upgrade-sheet")
  }

  private var isFormValid: Bool {
    !username.isEmpty && !email.isEmpty && !password.isEmpty && !confirmPassword.isEmpty
  }

  private func isValidEmail(_ value: String) -> Bool {
    let pattern = #"^[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
    return value.range(of: pattern, options: .regularExpression) != nil
  }

  private func createAccount() async {
    localError = nil
    guard isValidEmail(email) else {
      localError = String(localized: "auth.error.invalidEmail")
      return
    }
    guard password == confirmPassword else {
      localError = String(localized: "auth.error.passwordsDontMatch")
      return
    }
    await authModel.linkAnonymousAccount(email: email, password: password, username: username)
  }
}

#Preview {
  GuestUpgradeView()
    .environmentObject(AuthModel())
}
