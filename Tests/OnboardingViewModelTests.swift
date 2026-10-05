import Testing
@testable import TTB

@MainActor
struct OnboardingViewModelTests {
    @Test(arguments: [OnboardingStep.welcome, .example, .value, .sharing])
    func continueIsEnabledOnEarlierStepsWithoutLegalAcceptance(step: OnboardingStep) {
        let viewModel = OnboardingViewModel()
        viewModel.currentStep = step

        #expect(viewModel.hasAcceptedLegal == false)
        #expect(viewModel.isPrimaryActionEnabled)
    }

    @Test func finalStepNeedsLegalAcceptance() {
        let viewModel = OnboardingViewModel()
        viewModel.currentStep = .permissions

        #expect(viewModel.isPrimaryActionEnabled == false)

        viewModel.hasAcceptedLegal = true

        #expect(viewModel.isPrimaryActionEnabled)
    }
}
