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

    @Test func nextPublishesTheTargetAndDirectionWithoutMovingYet() {
        let viewModel = OnboardingViewModel()
        viewModel.currentStep = .value

        viewModel.goToNextStep()

        #expect(viewModel.pendingStep == .sharing)
        #expect(viewModel.isMovingBack == false)
        #expect(viewModel.currentStep == .value)

        viewModel.commit(.sharing)

        #expect(viewModel.currentStep == .sharing)
        #expect(viewModel.pendingStep == nil)
    }

    @Test func skipTargetsPermissionsForward() {
        let viewModel = OnboardingViewModel()

        viewModel.skipToPermissions()

        #expect(viewModel.pendingStep == .permissions)
        #expect(viewModel.isMovingBack == false)
    }

    @Test func backPublishesABackwardsDirection() {
        let viewModel = OnboardingViewModel()
        viewModel.currentStep = .value

        viewModel.goBack()

        #expect(viewModel.pendingStep == .example)
        #expect(viewModel.isMovingBack)
        #expect(viewModel.currentStep == .value)
    }

    @Test func aSecondRequestBeforeTheChangeFinishesIsDropped() {
        let viewModel = OnboardingViewModel()
        viewModel.currentStep = .value

        viewModel.goToNextStep()
        viewModel.goBack()

        #expect(viewModel.pendingStep == .sharing)
        #expect(viewModel.isMovingBack == false)

        // Still dropped after the commit, until the slide ends.
        viewModel.commit(.sharing)
        viewModel.goBack()
        #expect(viewModel.pendingStep == nil)

        viewModel.finishStepChange()
        viewModel.goBack()
        #expect(viewModel.pendingStep == .value)
        #expect(viewModel.isMovingBack)
    }
}
