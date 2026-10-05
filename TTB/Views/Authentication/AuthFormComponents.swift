import SwiftUI

enum AuthFormMetrics {
  static let groupedCornerRadius: CGFloat = 22
  static let labelWidth: CGFloat = 96
  static let dividerLeadingInset: CGFloat = 112
  static let rowHorizontalPadding: CGFloat = 16
  static let rowMinHeight: CGFloat = 48
  static let primaryButtonHeight: CGFloat = 52
  static let secondaryButtonHeight: CGFloat = 48
}

struct AuthGroupedFieldSection<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(spacing: 0) {
      content()
    }
    .background(Color.theme.secondaryBackground)
    .clipShape(RoundedRectangle(cornerRadius: AuthFormMetrics.groupedCornerRadius, style: .continuous))
  }
}

struct AuthFieldDivider: View {
  var body: some View {
    Divider()
      .padding(.leading, AuthFormMetrics.dividerLeadingInset)
  }
}

struct AuthLabeledFieldRow<Field: Hashable>: View {
  let label: String
  let placeholder: String
  @Binding var text: String
  var keyboardType: UIKeyboardType = .default
  var textContentType: UITextContentType? = nil
  var isSecure = false
  var isPasswordVisible = false
  var showsPasswordToggle = false
  var onTogglePasswordVisibility: (() -> Void)? = nil
  var accessibilityLabel: String
  var focusBinding: FocusState<Field>.Binding? = nil
  var focusValue: Field? = nil

  var body: some View {
    HStack(spacing: 12) {
      Text(label)
        .font(.body)
        .foregroundStyle(Color.theme.text)
        .frame(width: AuthFormMetrics.labelWidth, alignment: .leading)

      Group {
        if isSecure, !isPasswordVisible {
          secureField
        } else {
          plainField
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if showsPasswordToggle {
        Button {
          onTogglePasswordVisibility?()
        } label: {
          Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .frame(width: 32, height: 32)
        .accessibilityLabel(
          isPasswordVisible
            ? String(localized: "auth.password.hide")
            : String(localized: "auth.password.show")
        )
      }
    }
    .padding(.horizontal, AuthFormMetrics.rowHorizontalPadding)
    .frame(minHeight: AuthFormMetrics.rowMinHeight)
  }

  @ViewBuilder
  private var plainField: some View {
    let field = TextField(placeholder, text: $text)
      .textInputAutocapitalization(.never)
      .keyboardType(keyboardType)
      .textContentType(textContentType)
      .autocorrectionDisabled()
      .textFieldStyle(.plain)
      .foregroundStyle(Color.theme.text)
      .accessibilityLabel(accessibilityLabel)

    if let focusBinding, let focusValue {
      field.focused(focusBinding, equals: focusValue)
    } else {
      field
    }
  }

  @ViewBuilder
  private var secureField: some View {
    let field = SecureField(placeholder, text: $text)
      .textInputAutocapitalization(.never)
      .keyboardType(keyboardType)
      .textContentType(textContentType)
      .autocorrectionDisabled()
      .textFieldStyle(.plain)
      .foregroundStyle(Color.theme.text)
      .accessibilityLabel(accessibilityLabel)

    if let focusBinding, let focusValue {
      field.focused(focusBinding, equals: focusValue)
    } else {
      field
    }
  }
}

struct AuthPrimaryChipButton: View {
  let title: String
  let isLoading: Bool
  let loadingAccessibilityLabel: String
  var isEnabled = true
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Group {
        if isLoading {
          ProgressView()
            .tint(.white)
            .accessibilityLabel(loadingAccessibilityLabel)
        } else {
          Text(title)
            .font(.headline)
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: AuthFormMetrics.primaryButtonHeight)
    }
    .foregroundStyle(.white)
    .background(isEnabled ? Color.accentColor : Color.accentColor.opacity(0.4))
    .clipShape(Capsule())
    .contentShape(Capsule())
    .disabled(isLoading || !isEnabled)
  }
}

struct AuthSecondaryChipButton: View {
  let title: String
  let isLoading: Bool
  let loadingAccessibilityLabel: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Group {
        if isLoading {
          ProgressView()
            .tint(Color.accentColor)
            .accessibilityLabel(loadingAccessibilityLabel)
        } else {
          Text(title)
            .font(.subheadline)
            .foregroundStyle(Color.accentColor)
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: AuthFormMetrics.secondaryButtonHeight)
    }
    .background(Color.theme.secondaryBackground)
    .clipShape(Capsule())
    .overlay {
      Capsule()
        .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
    }
    .contentShape(Capsule())
    .disabled(isLoading)
  }
}
