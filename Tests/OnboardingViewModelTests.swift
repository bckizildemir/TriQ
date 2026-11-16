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

    @Test func movingForwardAndSkippingAreNotBackwards() {
        let viewModel = OnboardingViewModel()

        viewModel.goToNextStep()
        #expect(viewModel.currentStep == .example)
        #expect(viewModel.isMovingBack == false)

        viewModel.skipToPermissions()
        #expect(viewModel.currentStep == .permissions)
        #expect(viewModel.isMovingBack == false)
    }

    @Test func goingBackSetsTheDirectionAndNextClearsIt() {
        let viewModel = OnboardingViewModel()
        viewModel.currentStep = .value

        viewModel.goBack()
        #expect(viewModel.currentStep == .example)
        #expect(viewModel.isMovingBack)

        viewModel.goToNextStep()
        #expect(viewModel.isMovingBack == false)
    }
}
