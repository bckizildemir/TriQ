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

    @Test func movingForwardAndSkippingAreNotBackwards() async {
        let viewModel = OnboardingViewModel()

        await viewModel.goToNextStep()
        #expect(viewModel.currentStep == .example)
        #expect(viewModel.isMovingBack == false)

        await viewModel.skipToPermissions()
        #expect(viewModel.currentStep == .permissions)
        #expect(viewModel.isMovingBack == false)
    }

    @Test func goingBackSetsTheDirectionAndNextClearsIt() async {
        let viewModel = OnboardingViewModel()
        viewModel.currentStep = .value

        await viewModel.goBack()
        #expect(viewModel.currentStep == .example)
        #expect(viewModel.isMovingBack)

        await viewModel.goToNextStep()
        #expect(viewModel.isMovingBack == false)
    }

    @Test func aTapDuringAStepChangeIsIgnored() async {
        let viewModel = OnboardingViewModel()

        async let first: Void = viewModel.goToNextStep()
        async let second: Void = viewModel.goToNextStep()
        _ = await (first, second)

        #expect(viewModel.currentStep == .example)
    }
}
