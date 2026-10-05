import Firebase
import FirebaseAuth
import FirebaseFirestore
import SwiftUI

private enum ProfileModelError: LocalizedError {
  case creatorAttributionBatchTooLarge

  var errorDescription: String? {
    switch self {
    case .creatorAttributionBatchTooLarge:
      return String(localized: "profile.error.creatorAttributionBatchTooLarge")
    }
  }
}

@MainActor
class ProfileModel: ObservableObject {
  @Published var username: String = ""
  @Published var email: String = ""
  @Published var profileImage: UIImage?
  @Published var tempImage: UIImage?
  @Published var isEditing: Bool = false
  @Published var showingImagePicker: Bool = false
  @Published var showingAlert: Bool = false
  @Published var alertMessage: String = ""
  @Published private(set) var isAdmin: Bool = false
  @Published private(set) var statistics: Statistics = Statistics()
  @Published private(set) var isLoading: Bool = false

  private let db = Firestore.firestore()
  private let fileManager = LocalFileManager.shared
  private let usernameService = UsernameService()
  private var loadedUsername: String = ""
  private(set) var userId: String {
    didSet {
      if oldValue != userId && !userId.isEmpty {
        Task { @MainActor in
          // `loadUserProfile()` applies the statistics from the same document.
          await loadUserProfile()
        }
      }
    }
  }
  private var authListener: AuthStateDidChangeListenerHandle?

  struct Statistics {
    var daily: Int = 0
    var weekly: Int = 0
    var total: Int = 0
  }

  init(userId: String = "", startsAuthListener: Bool = true, loadsRemoteData: Bool = true) {
    self.userId = userId
    if startsAuthListener {
      setupAuthListener()
    }
    // Only load data if userId is not empty
    if loadsRemoteData && !userId.isEmpty {
      Task { @MainActor in
        // `loadUserProfile()` applies the statistics from the same document.
        await loadUserProfile()
      }
    }
  }

  #if DEBUG
  convenience init(
    uiTestUsername: String,
    email: String,
    statistics: Statistics,
    isAdmin: Bool = false
  ) {
    self.init(userId: "ui-test-profile-user", startsAuthListener: false, loadsRemoteData: false)
    username = uiTestUsername
    loadedUsername = uiTestUsername
    self.email = email
    self.statistics = statistics
    self.isAdmin = isAdmin
    isLoading = false
  }
  #endif

  deinit {
    if let authListener = authListener {
      Auth.auth().removeStateDidChangeListener(authListener)
    }
  }

  private func setupAuthListener() {
    authListener = Auth.auth().addStateDidChangeListener { [weak self] (_, user) in
      guard let self = self else { return }
      Task { @MainActor in
        self.userId = user?.uid ?? ""
      }
    }
  }

  @MainActor
  func loadUserProfile() async {
    guard !userId.isEmpty else { return }
    isLoading = true

    do {
      let document = try await db.collection("users").document(userId).getDocument()
      if let data = document.data() {
        username = data["username"] as? String ?? ""
        loadedUsername = username
        email = data["email"] as? String ?? ""
        isAdmin = data["isAdmin"] as? Bool ?? false

        // The statistics live on this same document, and every caller loads both — so read them
        // here rather than making `loadStatistics()` fetch `users/{uid}` a second time.
        await applyStatistics(from: data)

        if let urlString = data["profileImageURL"] as? String {
          // Try loading from Firebase Storage URL; fall back to local cache on failure
          if let remote = try? await ImageService.shared.loadProfileImage(from: urlString) {
            profileImage = remote
          } else if let local = loadLocalProfileImage() {
            profileImage = local
          }
        } else {
          // Legacy: load from local storage for users who haven't uploaded to Firebase yet
          profileImage = loadLocalProfileImage()
        }
      }
      isLoading = false
    } catch {
      alertMessage = String(
        format: String(localized: "profile.error.loadProfile"),
        locale: AppLocalization.currentLocale,
        error.localizedDescription
      )
      showingAlert = true
      isLoading = false
    }
  }

  /// The avatar is shown in a 28 pt toolbar button, a 100 pt circle, and a full-screen viewer, so it
  /// never needs more than the picked-photo cap — and locally cached copies written before that cap
  /// existed are at the original camera resolution.
  private func loadLocalProfileImage() -> UIImage? {
    fileManager.loadImage(
      name: "profile_\(userId)",
      maxPixelSize: DownsampledImageDecoder.pickedPhotoMaxPixelSize
    )
  }

  /// Refreshes just the answer counters. `loadUserProfile()` already applies them from the document
  /// it fetches, so this is for standalone refreshes rather than the initial load.
  @MainActor
  func loadStatistics() async {
    guard !userId.isEmpty else { return }
    do {
      let document = try await db.collection("users").document(userId).getDocument()
      await applyStatistics(from: document.data())
    } catch {
      alertMessage = String(
        format: String(localized: "profile.error.loadStatistics"),
        locale: AppLocalization.currentLocale,
        error.localizedDescription
      )
      showingAlert = true
    }
  }

  @MainActor
  private func applyStatistics(from data: [String: Any]?) async {
    guard let data else { return }

    statistics.daily = data["dailyAnswers"] as? Int ?? 0
    statistics.weekly = data["weeklyAnswers"] as? Int ?? 0

    if let totalAnswered = data["totalAnswered"] as? Int {
      statistics.total = totalAnswered
      return
    }

    let legacyTotal = data["totalAnswers"] as? Int ?? 0
    statistics.total = legacyTotal
    if data["totalAnswers"] != nil {
      try? await db.collection("users").document(userId).setData(
        [
          "totalAnswered": legacyTotal
        ], merge: true)
    }
  }

  @MainActor
  func updateProfile() async {
    guard !userId.isEmpty else { return }
    isLoading = true
    defer { isLoading = false }

    do {
      let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

      // Validate email format
      guard email.contains("@") else {
        alertMessage = String(localized: "profile.error.invalidEmail")
        showingAlert = true
        return
      }

      _ = try await usernameService.claimUsername(
        normalizedUsername,
        email: email,
        isAnonymous: Auth.auth().currentUser?.isAnonymous
      )

      try await commitProfileUpdate(username: normalizedUsername, email: email)

      username = normalizedUsername
      loadedUsername = normalizedUsername

      isEditing = false
    } catch UsernameServiceError.usernameAlreadyExists {
      alertMessage = String(localized: "profile.error.usernameTaken")
      showingAlert = true
    } catch {
      alertMessage = String(
        format: String(localized: "profile.error.updateProfile"),
        locale: AppLocalization.currentLocale,
        error.localizedDescription
      )
      showingAlert = true
    }
  }

  private func commitProfileUpdate(username: String, email: String) async throws {
    let batch = db.batch()
    let userRef = db.collection("users").document(userId)

    batch.updateData([
      "username": username,
      "email": email,
      "updatedAt": FieldValue.serverTimestamp(),
    ], forDocument: userRef)

    if username != loadedUsername {
      let authoredQuestions = try await db.collection("questions")
        .whereField("createdBy", isEqualTo: userId)
        .getDocuments()

      let userCreatedQuestionRefs = authoredQuestions.documents
        .filter { $0.data()["source"] as? String == QuestionSource.userCreated.rawValue }
        .map(\.reference)

      guard userCreatedQuestionRefs.count <= 499 else {
        throw ProfileModelError.creatorAttributionBatchTooLarge
      }

      for questionRef in userCreatedQuestionRefs {
        batch.updateData(["creatorUsername": username], forDocument: questionRef)
      }
    }

    try await batch.commit()
  }

  @MainActor
  func updateProfileImage() async {
    guard !userId.isEmpty else { return }
    guard let image = tempImage else { return }

    let didUpload = await uploadProfileImage(image)
    guard didUpload else { return }

    withAnimation(.easeInOut(duration: 0.2)) {
      profileImage = image
    }
    tempImage = nil
  }

  @MainActor
  @discardableResult
  func uploadProfileImage(_ image: UIImage) async -> Bool {
    guard !userId.isEmpty else { return false }

    do {
      let downloadURL = try await ImageService.shared.uploadProfileImage(image)

      // Persist download URL to Firestore so other devices can load it
      try await db.collection("users").document(userId).updateData([
        "profileImageURL": downloadURL,
        "hasProfilePicture": true,
        "updatedAt": FieldValue.serverTimestamp(),
      ])

      // Also cache locally for offline access. The JPEG encode plus disk write is several hundred
      // milliseconds, and this method is `@MainActor`, so keep it off the main thread.
      let localName = "profile_\(userId)"
      await Task.detached(priority: .utility) {
        try? LocalFileManager.shared.saveImage(image, name: localName)
      }.value
      return true
    } catch {
      alertMessage = String(
        format: String(localized: "profile.error.saveImage"),
        locale: AppLocalization.currentLocale,
        error.localizedDescription
      )
      showingAlert = true
      return false
    }
  }

  @MainActor
  private func showAlert(with message: String) {
    alertMessage = message
    showingAlert = true
  }

  @MainActor
  func signOut() async {
    isLoading = true

    do {
      try Auth.auth().signOut()
    } catch {
      alertMessage = String(
        format: String(localized: "profile.error.signOut"),
        locale: AppLocalization.currentLocale,
        error.localizedDescription
      )
      showingAlert = true
    }

    isLoading = false
  }
}
