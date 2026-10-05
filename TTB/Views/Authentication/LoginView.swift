import FirebaseAuth
import SwiftUI
import UIKit

struct LoginView: View {
  @EnvironmentObject var model: AuthModel
  @State private var isPasswordVisible = false
  @FocusState private var focusedField: Field?

  private enum Field: Hashable {
    case identifier
    case password
  }

  var body: some View {
    NavigationStack(path: $model.navigationPath) {
      ZStack {
        Color.theme.background
          .ignoresSafeArea()

        ScrollView {
          VStack(spacing: 25) {
            Text(String(localized: "auth.login.title"))
              .font(.system(size: 40, weight: .bold))
              .foregroundColor(Color.theme.text)
              .padding(.top, 50)

            VStack(spacing: 20) {
              AuthGroupedFieldSection {
                AuthLabeledFieldRow(
                  label: String(localized: "auth.field.account"),
                  placeholder: String(localized: "auth.login.identifierPlaceholder"),
                  text: $model.identifier,
                  keyboardType: .emailAddress,
                  textContentType: .username,
                  accessibilityLabel: String(localized: "auth.login.identifierAccessibility"),
                  focusBinding: $focusedField,
                  focusValue: .identifier
                )
                .submitLabel(.next)
                .onSubmit {
                  focusedField = .password
                }

                AuthFieldDivider()

                AuthLabeledFieldRow(
                  label: String(localized: "auth.field.password"),
                  placeholder: String(localized: "auth.login.passwordPlaceholder"),
                  text: $model.password,
                  keyboardType: .asciiCapable,
                  textContentType: .password,
                  isSecure: true,
                  isPasswordVisible: isPasswordVisible,
                  showsPasswordToggle: true,
                  onTogglePasswordVisibility: { isPasswordVisible.toggle() },
                  accessibilityLabel: String(localized: "auth.login.passwordAccessibility"),
                  focusBinding: $focusedField,
                  focusValue: .password
                )
                .submitLabel(.go)
                .onSubmit {
                  signIn()
                }
              }

              AuthPrimaryChipButton(
                title: String(localized: "auth.login.signIn"),
                isLoading: model.isLoading,
                loadingAccessibilityLabel: String(localized: "auth.login.loading")
              ) {
                signIn()
              }

              NavigationLink {
                RegistrationView()
              } label: {
                Text(String(localized: "auth.login.noAccountPrompt"))
                  .foregroundColor(.accentColor)
              }
              .accessibilityHint(String(localized: "auth.login.registrationHint"))

              HStack {
                Rectangle()
                  .frame(height: 1)
                  .foregroundColor(Color(.systemGray4))
                Text(String(localized: "auth.common.or"))
                  .font(.footnote)
                  .foregroundColor(.secondary)
                  .padding(.horizontal, 8)
                Rectangle()
                  .frame(height: 1)
                  .foregroundColor(Color(.systemGray4))
              }
              .padding(.top, 4)

              AuthSecondaryChipButton(
                title: String(localized: "auth.login.guestContinue"),
                isLoading: model.isLoading,
                loadingAccessibilityLabel: String(localized: "auth.login.guestLoading")
              ) {
                dismissKeyboard()
                Task {
                  await model.signInAnonymously()
                }
              }
              .accessibilityLabel(String(localized: "auth.login.guestContinue"))
              .accessibilityHint(String(localized: "auth.login.guestHint"))
            }
            .padding(.horizontal, 24)
          }
        }
        .alert(String(localized: "common.error.title"), isPresented: $model.errorState.isShowing) {
          Button(String(localized: "common.ok"), role: .cancel) {
            model.dismissError()
          }
        } message: {
          Text(model.errorState.message)
        }
      }
    }
  }

  private func signIn() {
    dismissKeyboard()
    Task {
      await model.signIn()
    }
  }

  private func dismissKeyboard() {
    focusedField = nil
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder),
      to: nil,
      from: nil,
      for: nil
    )
  }
}

#Preview {
  LoginView()
    .environmentObject(AuthModel())
}
