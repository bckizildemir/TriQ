import FirebaseFirestore
import Foundation

actor OnboardingStateStore {
  private let db = Firestore.firestore()

  func hasCompletedCurrentOnboarding(for userId: String) async throws -> Bool {
    let snapshot = try await db.collection("users").document(userId).getDocument()
    let data = snapshot.data() ?? [:]

    let storedOnboardingVersion = data["onboardingVersion"] as? Int ?? 0
    let storedTermsVersion = data["termsAcceptedVersion"] as? String ?? ""
    let storedPrivacyVersion = data["privacyAcceptedVersion"] as? String ?? ""

    return storedOnboardingVersion >= AppConfig.onboardingVersion
      && storedTermsVersion == AppConfig.legalVersion
      && storedPrivacyVersion == AppConfig.legalVersion
  }

  func completeCurrentOnboarding(for userId: String) async throws {
    try await db.collection("users").document(userId).setData(
      [
        "onboardingVersion": AppConfig.onboardingVersion,
        "onboardingCompletedAt": FieldValue.serverTimestamp(),
        "termsAcceptedVersion": AppConfig.legalVersion,
        "privacyAcceptedVersion": AppConfig.legalVersion,
        "legalAcceptedAt": FieldValue.serverTimestamp(),
      ],
      merge: true
    )
  }
}
