import SwiftUI
import UIKit

struct OnboardingFlowView: View {
  @ObservedObject var viewModel: OnboardingViewModel

  var body: some View {
    VStack(spacing: 24) {
      header

      ScrollView {
        stepContent
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.bottom, viewModel.currentStep.isFinalStep ? 16 : 8)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .padding(.horizontal, 24)
    .padding(.top, 12)
    .safeAreaInset(edge: .top, spacing: 0) {
      topProgressBar
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      footer
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background {
          Color.theme.background
            .ignoresSafeArea(edges: .bottom)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(backgroundLayer)
    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) {
      _ in
      Task { await viewModel.refreshPermissionStatuses() }
    }
    .alert(String(localized: "common.error.title"), isPresented: hasError) {
      Button(String(localized: "common.ok"), role: .cancel) {
        viewModel.errorMessage = nil
      }
    } message: {
      Text(viewModel.errorMessage ?? "")
    }
  }

  private var header: some View {
    VStack(spacing: 18) {
      HStack {
        if viewModel.canGoBack {
          Button {
            viewModel.goBack()
          } label: {
            Image(systemName: "chevron.left")
              .font(.headline)
              .frame(width: 44, height: 44)
              .background(Color.theme.secondaryBackground, in: Circle())
          }
          .accessibilityLabel(String(localized: "onboarding.nav.back"))
        } else {
          Color.clear
            .frame(width: 44, height: 44)
        }

        Spacer()

        if viewModel.currentStep.canSkip {
          Button(String(localized: "onboarding.nav.skip")) {
            viewModel.skipToPermissions()
          }
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.secondary)
          .frame(minWidth: 44, minHeight: 44)
        }
      }

    }
  }

  private var topProgressBar: some View {
    OnboardingProgressBar(progress: viewModel.currentStep.progressValue)
      .padding(.horizontal, 24)
      .padding(.vertical, 10)
      .background {
        Color.theme.background
          .ignoresSafeArea(edges: .top)
      }
  }

  @ViewBuilder
  private var stepContent: some View {
    switch viewModel.currentStep {
    case .welcome:
      welcomeContent
    case .example:
      exampleContent
    case .value:
      valueContent
    case .sharing:
      sharingContent
    case .permissions:
      permissionsContent
    }
  }

  private var welcomeContent: some View {
    VStack(alignment: .leading, spacing: 24) {
      Text(OnboardingContent.welcomeTitle)
        .font(.system(size: 34, weight: .bold, design: .rounded))
        .foregroundStyle(Color.theme.text)
        .fixedSize(horizontal: false, vertical: true)

      Text(OnboardingContent.welcomeBody)
        .font(.title3)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      ViewThatFits(in: .horizontal) {
        HStack(spacing: 12) {
          welcomeTags
        }

        VStack(alignment: .leading, spacing: 12) {
          welcomeTags
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var welcomeTags: some View {
    ForEach(OnboardingContent.welcomeTags, id: \.self) { tag in
      Text(tag)
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
          RoundedRectangle(cornerRadius: 18)
            .fill(Color.theme.secondaryBackground)
            .overlay(
              RoundedRectangle(cornerRadius: 18)
                .stroke(Color.theme.border.opacity(0.2), lineWidth: 1)
            )
        )
    }
  }

  private var exampleContent: some View {
    VStack(alignment: .leading, spacing: 20) {
      titleBlock(
        title: OnboardingContent.sampleTitle,
        body: OnboardingContent.sampleBody
      )

      OnboardingSampleQuestionCard(
        question: OnboardingContent.sampleQuestion,
        answers: OnboardingContent.sampleAnswers,
        symbols: OnboardingContent.sampleAnswerSymbols
      )
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var valueContent: some View {
    VStack(alignment: .leading, spacing: 22) {
      titleBlock(
        title: OnboardingContent.valueTitle,
        body: OnboardingContent.valueBody
      )

      VStack(spacing: 12) {
        ForEach(OnboardingContent.valueHighlights, id: \.self) { highlight in
          Label(highlight, systemImage: "checkmark.circle.fill")
            .font(.subheadline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
              RoundedRectangle(cornerRadius: 18)
                .fill(Color.theme.secondaryBackground)
            )
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var sharingContent: some View {
    VStack(alignment: .leading, spacing: 20) {
      titleBlock(
        title: OnboardingContent.sharingTitle,
        body: OnboardingContent.sharingBody
      )

      OnboardingSharingComparisonCard(
        question: OnboardingContent.sharingQuestion,
        leftTitle: OnboardingContent.sharingLeftTitle,
        leftAnswers: OnboardingContent.sharingLeftAnswers,
        rightTitle: OnboardingContent.sharingRightTitle,
        rightAnswers: OnboardingContent.sharingRightAnswers
      )
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var permissionsContent: some View {
    VStack(alignment: .leading, spacing: 14) {
      titleBlock(
        title: OnboardingContent.permissionsTitle,
        body: OnboardingContent.permissionsBody
      )

      OnboardingPermissionCard(
        title: OnboardingContent.notificationsTitle,
        message: OnboardingContent.notificationsBody,
        status: viewModel.notificationStatus
      ) {
        Task { await viewModel.requestNotificationPermission() }
      }

      OnboardingPermissionCard(
        title: OnboardingContent.photosTitle,
        message: OnboardingContent.photosBody,
        status: viewModel.photoStatus
      ) {
        Task { await viewModel.requestPhotoPermission() }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var footer: some View {
    VStack(spacing: 10) {
      AuthPrimaryChipButton(
        title: viewModel.primaryButtonTitle,
        isLoading: viewModel.isCompleting,
        loadingAccessibilityLabel: String(localized: "onboarding.primaryButton.final"),
        isEnabled: viewModel.isPrimaryActionEnabled
      ) {
        handlePrimaryAction()
      }
      .accessibilityIdentifier("onboarding-continue-button")

      if viewModel.currentStep.isFinalStep {
        legalConsent
      }
    }
  }

  private var legalConsent: some View {
    HStack(alignment: .top, spacing: 10) {
      Button {
        viewModel.hasAcceptedLegal.toggle()
      } label: {
        Image(systemName: viewModel.hasAcceptedLegal ? "checkmark.circle.fill" : "circle")
          .font(.body)
          .foregroundStyle(viewModel.hasAcceptedLegal ? Color.accentColor : .secondary)
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(String(localized: "onboarding.legal.toggleAccessibility"))

      legalConsentText
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
    }
  }

  private var legalConsentText: some View {
    ViewThatFits(in: .horizontal) {
      inlineLegalLine
      VStack(alignment: .leading, spacing: 4) {
        Text(OnboardingContent.legalInlinePrefix)
          .font(.caption)
          .foregroundStyle(.secondary)
        HStack(spacing: 4) {
          legalLinks
        }
        .font(.caption)
      }
    }
  }

  private var inlineLegalLine: some View {
    HStack(spacing: 0) {
      Text(OnboardingContent.legalInlinePrefix + " ")
        .font(.caption)
        .foregroundStyle(.secondary)
      legalLinks
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var legalLinks: some View {
    HStack(spacing: 4) {
      if let termsURL = viewModel.termsURL {
        Link(String(localized: "onboarding.legal.terms"), destination: termsURL)
          .font(.caption.weight(.semibold))
      }

      Text(OnboardingContent.legalMiddle)
        .font(.caption)
        .foregroundStyle(.secondary)

      if let privacyURL = viewModel.privacyURL {
        Link(String(localized: "onboarding.legal.privacy"), destination: privacyURL)
          .font(.caption.weight(.semibold))
      }

      Text(OnboardingContent.legalInlineSuffix)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var backgroundLayer: some View {
    ZStack {
      Color.theme.background

      Circle()
        .fill(Color.accentColor.opacity(0.08))
        .frame(width: 260, height: 260)
        .blur(radius: 24)
        .offset(x: 140, y: -260)

      Circle()
        .fill(Color.orange.opacity(0.06))
        .frame(width: 220, height: 220)
        .blur(radius: 28)
        .offset(x: -150, y: 280)
    }
    .ignoresSafeArea()
  }

  private var hasError: Binding<Bool> {
    Binding(
      get: { viewModel.errorMessage != nil },
      set: { newValue in
        if !newValue {
          viewModel.errorMessage = nil
        }
      }
    )
  }

  private func handlePrimaryAction() {
    if viewModel.currentStep.isFinalStep {
      Task { await viewModel.completeOnboarding() }
    } else {
      viewModel.goToNextStep()
    }
  }

  private func titleBlock(title: String, body: String) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(title)
        .font(.system(size: 30, weight: .bold, design: .rounded))
        .foregroundStyle(Color.theme.text)
        .fixedSize(horizontal: false, vertical: true)

      Text(body)
        .font(.title3)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

#Preview {
  OnboardingFlowView(viewModel: OnboardingViewModel())
}
