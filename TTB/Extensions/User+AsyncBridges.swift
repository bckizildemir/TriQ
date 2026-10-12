import FirebaseAuth
import Foundation

/// The `nonisolated(nonsending)` completion-handler bridges for Firebase `User`. The SDK's own
/// `async` overloads are not `nonisolated(nonsending)`, so calling them from an actor that holds
/// the `User` is a region error. These run on the caller's executor instead.
extension User {
    /// Satisfies `AuthModelUser.deleteAsync()`.
    nonisolated(nonsending) func deleteAsync() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    /// Satisfies `AccountDeletionService`'s reauthentication step.
    nonisolated(nonsending) func reauthenticateAsync(with credential: AuthCredential) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            reauthenticate(with: credential) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    /// Satisfies `AuthModelUser.forceRefreshIDToken()`.
    nonisolated(nonsending) func forceRefreshIDToken() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            getIDTokenForcingRefresh(true) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
