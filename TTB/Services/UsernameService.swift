import FirebaseFunctions
import Foundation

struct ClaimedUsername {
  let username: String
  let usernameNormalized: String
}

enum UsernameServiceError: LocalizedError {
  case invalidUsername
  case usernameAlreadyExists
  case userNotFound
  case missingEmail
  case serviceUnavailable
  case unknown(Error)

  var errorDescription: String? {
    switch self {
    case .invalidUsername:
      return AppLocalization.prefersEnglish
        ? "Enter a valid username."
        : "Geçerli bir kullanıcı adı gir."
    case .usernameAlreadyExists:
      return String(localized: "auth.error.usernameTaken")
    case .userNotFound:
      return String(localized: "auth.error.userNotFound")
    case .missingEmail:
      return String(localized: "auth.error.userNotFound")
    case .serviceUnavailable:
      return String(localized: "auth.error.usernameServiceUnavailable")
    case .unknown(let error):
      return error.localizedDescription
    }
  }
}

final class UsernameService: Sendable {
  private var functions: Functions { Functions.functions(region: "europe-west1") }

  func claimUsername(
    _ username: String,
    email: String? = nil,
    isAnonymous: Bool? = nil
  ) async throws -> ClaimedUsername {
    var payload: [String: Any] = ["username": username]
    if let email {
      payload["email"] = email
    }
    if let isAnonymous {
      payload["isAnonymous"] = isAnonymous
    }

    do {
      let result = try await functions.httpsCallable("claimUsername").call(payload)
      guard let data = result.data as? [String: Any],
        let claimedUsername = data["username"] as? String,
        let normalizedUsername = data["usernameNormalized"] as? String
      else {
        throw UsernameServiceError.invalidUsername
      }

      return ClaimedUsername(
        username: claimedUsername,
        usernameNormalized: normalizedUsername
      )
    } catch {
      throw mapFunctionsError(error, context: .claimUsername)
    }
  }

  func resolveEmail(for username: String) async throws -> String {
    do {
      let result = try await functions.httpsCallable("resolveUsername")
        .call(["username": username])
      guard let data = result.data as? [String: Any],
        let email = data["email"] as? String,
        !email.isEmpty
      else {
        throw UsernameServiceError.missingEmail
      }

      return email
    } catch {
      throw mapFunctionsError(error, context: .resolveUsername)
    }
  }

  func releaseUsername(
    _ username: String,
    restoreUsername: String?,
    restoreEmail: String?,
    restoreIsAnonymous: Bool?
  ) async {
    var payload: [String: Any] = ["username": username]
    if let restoreUsername {
      payload["restoreUsername"] = restoreUsername
    }
    if let restoreEmail {
      payload["restoreEmail"] = restoreEmail
    }
    if let restoreIsAnonymous {
      payload["restoreIsAnonymous"] = restoreIsAnonymous
    }

    do {
      _ = try await functions.httpsCallable("releaseUsername").call(payload)
    } catch {
      // Best-effort cleanup for failed guest upgrade attempts.
    }
  }

  private func mapFunctionsError(_ error: Error, context: FunctionCallContext) -> Error {
    let nsError = error as NSError
    guard nsError.domain == FunctionsErrorDomain else {
      return error
    }

    switch FunctionsErrorCode(rawValue: nsError.code) {
    case .alreadyExists:
      return UsernameServiceError.usernameAlreadyExists
    case .notFound:
      switch context {
      case .claimUsername:
        return UsernameServiceError.serviceUnavailable
      case .resolveUsername:
        return UsernameServiceError.userNotFound
      }
    case .invalidArgument:
      return UsernameServiceError.invalidUsername
    default:
      return UsernameServiceError.unknown(error)
    }
  }
}

private enum FunctionCallContext {
  case claimUsername
  case resolveUsername
}
