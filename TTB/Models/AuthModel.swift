import FirebaseAuth
import Foundation
import SwiftUI
import os

@MainActor
class AuthModel: ObservableObject {
  enum AuthState {
    case checking
    case authenticated
    case signedOut
  }

  // MARK: - Properties
  @Published var identifier = ""
  @Published var email = ""
  @Published var password = ""
  @Published var confirmPassword = ""
  @Published var username = ""
  @Published private(set) var isLoading = false
  @Published private(set) var isDeletingAccount = false
  @Published var errorState = ErrorState()
  @Published private(set) var authState: AuthState = .checking

  var isAuthenticated: Bool {
    authState == .authenticated
  }

  var isAnonymous: Bool {
    dependencies.auth.currentUser?.isAnonymous ?? false
  }

  var currentUserId: String? {
    dependencies.auth.currentUser?.uid
  }

  @Published var showMainView = false
  @Published var navigationPath = NavigationPath()

  private let dependencies: AuthModelDependencies
  private var authStateHandler: AuthStateListenerHandle?
  private var authStateTask: Task<Void, Never>?
  private var authStateGeneration: UInt = 0
#if DEBUG
  private var authStateTaskCount = 0
  private var authStateIdleContinuations: [CheckedContinuation<Void, Never>] = []
#endif
  private var isCompletingSignUpBootstrap = false
  private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.ttb.app",
    category: "AuthModel")

  struct ErrorState {
    var message: String = ""
    var isShowing: Bool = false
  }

  enum AuthError: LocalizedError {
    case userNotFound
    case usernameAlreadyExists
    case invalidEmail
    case invalidPassword
    case passwordsDontMatch
    case unknown(Error)

    var errorDescription: String? {
      switch self {
      case .userNotFound:
        return String(localized: "auth.error.userNotFound")
      case .usernameAlreadyExists:
        return String(localized: "auth.error.usernameTaken")
      case .invalidEmail:
        return String(localized: "auth.error.invalidEmail")
      case .invalidPassword:
        return String(localized: "auth.error.invalidPassword")
      case .passwordsDontMatch:
        return String(localized: "auth.error.passwordsDontMatch")
      case .unknown(let error):
        return error.localizedDescription
      }
    }
  }

  convenience init() {
    self.init(dependencies: .live, registersAuthListener: true)
  }

  init(dependencies: AuthModelDependencies, registersAuthListener: Bool = true) {
    self.dependencies = dependencies
    authState = registersAuthListener ? .checking : .signedOut
    logger.debug("AuthModel initialized")
    if registersAuthListener {
      setupAuthStateHandler()
    }
  }

  /// `isolated` so the cleanup can read the main-actor listener handles. Below iOS 18.4 the
  /// compiler links a main-actor back-deploy shim, so this needs no deployment-target change.
  isolated deinit {
    authStateTask?.cancel()
    dependencies.auth.removeStateDidChangeListener(authStateHandler)
  }

  private func setupAuthStateHandler() {
    authStateHandler = dependencies.auth.addStateDidChangeListener { [weak self] user in
      Task { @MainActor in
        self?.enqueueAuthStateChange(user)
      }
    }
  }

  private func enqueueAuthStateChange(_ user: AuthModelUser?) {
    authStateGeneration &+= 1
    let generation = authStateGeneration
    authStateTask?.cancel()
#if DEBUG
    authStateTaskCount += 1
#endif
    authStateTask = Task { @MainActor [weak self] in
      guard let self else { return }
#if DEBUG
      defer { self.finishAuthStateTaskForTesting() }
#endif
      self.logger.debug("Auth state changed for user \(user?.uid ?? "nil")")

      if self.isCompletingSignUpBootstrap, user != nil {
        return
      }

      if let user {
        await self.handleAuthenticatedUser(user, expectedGeneration: generation)
      } else if generation == self.authStateGeneration, !Task.isCancelled {
        self.handleSignedOutUser()
      }
    }
  }

#if DEBUG
  func waitForAuthStateTasksToFinishForTesting() async {
    guard authStateTaskCount > 0 else { return }
    await withCheckedContinuation { continuation in
      authStateIdleContinuations.append(continuation)
    }
  }

  private func finishAuthStateTaskForTesting() {
    authStateTaskCount -= 1
    guard authStateTaskCount == 0 else { return }
    let continuations = authStateIdleContinuations
    authStateIdleContinuations.removeAll()
    continuations.forEach { $0.resume() }
  }
#endif

  private func handleAuthenticatedUser(
    _ user: AuthModelUser,
    expectedGeneration: UInt? = nil
  ) async {
    await dependencies.userDocumentManager.ensureExists(for: user)
    guard shouldCommitAuthenticatedUser(user, expectedGeneration: expectedGeneration) else {
      return
    }

    await dependencies.badgeBackfillService.backfillBadgeProgressIfNeeded()
    guard shouldCommitAuthenticatedUser(user, expectedGeneration: expectedGeneration) else {
      return
    }

    authState = .authenticated
    logger.info("User is signed in: \(user.uid)")
    let sixMonthsInSeconds: TimeInterval = 180 * 24 * 60 * 60
    UserDefaults.standard.set(
      Date().addingTimeInterval(sixMonthsInSeconds),
      forKey: "authExpirationDate")
  }

  private func shouldCommitAuthenticatedUser(
    _ user: AuthModelUser,
    expectedGeneration: UInt?
  ) -> Bool {
    guard !Task.isCancelled, dependencies.auth.currentUser?.uid == user.uid else {
      return false
    }

    guard let expectedGeneration else {
      return true
    }

    return expectedGeneration == authStateGeneration
  }

  private func handleSignedOutUser() {
    authState = .signedOut
    logger.info("User is signed out")
    UserDefaults.standard.removeObject(forKey: "authExpirationDate")
  }

  @MainActor
  private func clearFields() {
    identifier = ""
    email = ""
    password = ""
    confirmPassword = ""
    username = ""
  }

  @MainActor
  private func showError(message: String) {
    errorState.message = message
    errorState.isShowing = true
  }

  @MainActor
  func dismissError() {
    errorState.isShowing = false
    errorState.message = ""
  }

  @MainActor
  func signIn() async {
    isLoading = true
    errorState.isShowing = false

    do {
      let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmedIdentifier.contains("@") {
        try await dependencies.auth.signIn(withEmail: trimmedIdentifier, password: password)
      } else {
        let resolvedEmail = try await dependencies.usernameService.resolveEmail(for: trimmedIdentifier)
        try await dependencies.auth.signIn(withEmail: resolvedEmail, password: password)
      }

      showMainView = true
      clearFields()
    } catch {
      showError(message: error.localizedDescription)
    }

    isLoading = false
  }

  @MainActor
  func signUp() async {
    let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedEmail.isEmpty, !password.isEmpty, !confirmPassword.isEmpty, !trimmedUsername.isEmpty else {
      showError(message: String(localized: "auth.error.fillAllFields"))
      return
    }

    guard isValidEmailFormat(trimmedEmail) else {
      showError(message: AuthError.invalidEmail.localizedDescription)
      return
    }

    guard password == confirmPassword else {
      showError(message: String(localized: "auth.error.passwordsDontMatch"))
      return
    }

    isLoading = true
    isCompletingSignUpBootstrap = true
    errorState.isShowing = false
    defer {
      isCompletingSignUpBootstrap = false
      isLoading = false
    }

    do {
      let user = try await dependencies.auth.createUser(withEmail: trimmedEmail, password: password)
      do {
        _ = try await dependencies.usernameService.claimUsername(
          trimmedUsername,
          email: trimmedEmail,
          isAnonymous: false
        )
      } catch {
        await deletePartiallyCreatedAccount(user: user)
        authState = .signedOut
        throw error
      }

      await handleAuthenticatedUser(user)
      showMainView = true
      clearFields()
    } catch {
      showError(message: error.localizedDescription)
    }
  }

  @MainActor
  func signOut() async {
    do {
      try dependencies.auth.signOut()
      showMainView = false
    } catch {
      showError(message: error.localizedDescription)
    }
  }

  @MainActor
  func deleteAccount(password: String?) async {
    guard !isDeletingAccount else { return }

    isDeletingAccount = true
    errorState.isShowing = false

    defer {
      isDeletingAccount = false
    }

    do {
      try await dependencies.accountDeletionService.deleteCurrentAccount(password: password)
      showMainView = false
      clearFields()
    } catch {
      showError(message: error.localizedDescription)
    }
  }

  /// Anonymous → tam hesap: UID aynı kaldığından tüm Firestore verisi (favoriler, cevaplar) otomatik korunur.
  @MainActor
  func linkAnonymousAccount(email: String, password: String, username: String) async {
    guard !email.isEmpty, !password.isEmpty, !username.isEmpty else {
      showError(message: String(localized: "auth.error.fillAllFields"))
      return
    }

    guard isValidEmailFormat(email) else {
      showError(message: AuthError.invalidEmail.localizedDescription)
      return
    }

    isLoading = true
    errorState.isShowing = false
    defer { isLoading = false }

    do {
      let credential = EmailAuthProvider.credential(withEmail: email, password: password)
      guard let currentUser = dependencies.auth.currentUser else {
        throw AuthError.userNotFound
      }
      let previousProfile = try? await dependencies.userDocumentManager.profileSnapshot(userId: currentUser.uid)

      _ = try await dependencies.usernameService.claimUsername(
        username,
        email: email,
        isAnonymous: true
      )

      do {
        let linkedUser = try await currentUser.link(with: credential)
        try await linkedUser.forceRefreshIDToken()
        _ = try await dependencies.usernameService.claimUsername(
          username,
          email: email,
          isAnonymous: false
        )
      } catch {
        await dependencies.usernameService.releaseUsername(
          username,
          restoreUsername: previousProfile?.username,
          restoreEmail: previousProfile?.email,
          restoreIsAnonymous: previousProfile?.isAnonymous
        )
        throw error
      }

      clearFields()
    } catch {
      showError(message: error.localizedDescription)
    }
  }

  private func deletePartiallyCreatedAccount(user: AuthModelUser) async {
    await dependencies.userDocumentManager.deleteUserAndAuth(user: user)
  }

  @MainActor
  func signInAnonymously() async {
    isLoading = true
    errorState.isShowing = false

    do {
      let user = try await dependencies.auth.signInAnonymously()
      await dependencies.userDocumentManager.ensureExists(for: user)
      showMainView = true
      clearFields()
    } catch {
      showError(message: error.localizedDescription)
    }

    isLoading = false
  }

  func resetPassword() async {
    guard !email.isEmpty else {
      showError(message: String(localized: "auth.error.enterEmail"))
      return
    }

    isLoading = true
    defer { isLoading = false }

    do {
      try await dependencies.auth.sendPasswordReset(withEmail: email)
      showError(message: String(localized: "auth.error.passwordResetEmailSent"))
      logger.info("Password reset email sent")
    } catch {
      showError(message: error.localizedDescription)
      logger.error("Password reset error: \(error.localizedDescription)")
    }
  }

  private func isValidEmailFormat(_ value: String) -> Bool {
    let pattern = #"^[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
    return value.range(of: pattern, options: .regularExpression) != nil
  }

  nonisolated static func normalizedUsername(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}
