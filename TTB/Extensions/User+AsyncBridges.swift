import FirebaseAuth
import Foundation

/// The completion-handler bridges for Firebase `User`. The SDK's own `async` overloads are not
/// `nonisolated(nonsending)`, so calling them from an actor that holds the `User` is a region
/// error. These run on the caller's executor instead.
extension User {
    /// Account deletion and `AuthModelUser` both call this.
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
}
