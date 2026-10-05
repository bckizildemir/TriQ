import FirebaseAuth
import SwiftUI

struct RegistrationView: View {
  @EnvironmentObject var model: AuthModel
  @State private var isPasswordVisible = false
  @State private var isConfirmPasswordVisible = false
  @FocusState private var focusedField: Field?

  private enum Field: Hashable {
    case username
    case email
    case password
    case confirmPassword
  }

  var body: some View {
    ZStack {
      Color.theme.background
        .ignoresSafeArea()

      ScrollViewReader { proxy in
        ScrollView {
          VStack(spacing: 25) {
            Text(String(localized: "auth.register.title"))
              .font(.system(size: 32, weight: .bold))
              .foregroundColor(Color.theme.text)
              .padding(.top, 30)

            VStack(spacing: 20) {
              AuthGroupedFieldSection {
                AuthLabeledFieldRow(
                  label: String(localized: "auth.field.username"),
                  placeholder: String(localized: "auth.register.usernamePlaceholder"),
                  text: $model.username,
                  textContentType: .username,
                  accessibilityLabel: String(localized: "auth.register.usernameAccessibility"),
                  focusBinding: $focusedField,
                  focusValue: .username
                )
                .id(Field.username)

                AuthFieldDivider()

                AuthLabeledFieldRow(
                  label: String(localized: "auth.field.email"),
                  placeholder: String(localized: "auth.register.emailPlaceholder"),
                  text: $model.email,
                  keyboardType: .emailAddress,
                  textContentType: .emailAddress,
                  accessibilityLabel: String(localized: "auth.register.emailAccessibility"),
                  focusBinding: $focusedField,
                  focusValue: .email
                )
                .id(Field.email)

                AuthFieldDivider()

                AuthLabeledFieldRow(
                  label: String(localized: "auth.field.password"),
                  placeholder: String(localized: "auth.register.passwordPlaceholder"),
                  text: $model.password,
                  keyboardType: .asciiCapable,
                  textContentType: .newPassword,
                  isSecure: true,
                  isPasswordVisible: isPasswordVisible,
                  showsPasswordToggle: true,
                  onTogglePasswordVisibility: { isPasswordVisible.toggle() },
                  accessibilityLabel: String(localized: "auth.register.passwordAccessibility"),
                  focusBinding: $focusedField,
                  focusValue: .password
                )
                .id(Field.password)

                AuthFieldDivider()

                AuthLabeledFieldRow(
                  label: String(localized: "auth.field.confirm"),
                  placeholder: String(localized: "auth.register.confirmPasswordPlaceholder"),
                  text: $model.confirmPassword,
                  keyboardType: .asciiCapable,
                  textContentType: .newPassword,
                  isSecure: true,
                  isPasswordVisible: isConfirmPasswordVisible,
                  showsPasswordToggle: true,
                  onTogglePasswordVisibility: { isConfirmPasswordVisible.toggle() },
                  accessibilityLabel: String(localized: "auth.register.confirmPasswordAccessibility"),
                  focusBinding: $focusedField,
                  focusValue: .confirmPassword
                )
                .id(Field.confirmPassword)
              }

              AuthPrimaryChipButton(
                title: String(localized: "auth.register.signUp"),
                isLoading: model.isLoading,
                loadingAccessibilityLabel: String(localized: "auth.register.loading")
              ) {
                Task {
                  await model.signUp()
                }
              }
            }
            .padding(.horizontal, 24)
          }
        }
        .onChange(of: focusedField) { _, field in
          guard let field, field == .password || field == .confirmPassword else {
            return
          }

          DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeInOut(duration: 0.2)) {
              proxy.scrollTo(field, anchor: .center)
            }
          }
        }
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .navigationTitle(String(localized: "auth.register.navigationTitle"))
    .alert(String(localized: "common.error.title"), isPresented: $model.errorState.isShowing) {
      Button(String(localized: "common.ok"), role: .cancel) {
        model.dismissError()
      }
    } message: {
      Text(model.errorState.message)
    }
  }
}

#Preview {
  NavigationStack {
    RegistrationView()
      .environmentObject(AuthModel())
  }
}
