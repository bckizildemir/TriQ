import Foundation

/// The reloads the profile screen runs itself when a guest becomes a permanent account.
///
/// Linking a guest keeps the uid, so neither `ProfileModel`'s `userId` observer nor `BadgeModel`'s
/// user-document listener notices the upgrade, and the upgrade sheet covers Profile, so `.onAppear`
/// does not run again for the upgraded account. Profile runs this list from its `isAnonymous`
/// observer instead (#121).
enum ProfileAccountRefresh: CaseIterable, Hashable {
  /// The user document: username, email, admin flag, photo and answer counters.
  case profile
  /// The answer counters on their own, without the rest of the document.
  case statistics
  /// The badge definitions, the unlocked badges and the user-document listener. Left out of this
  /// list, the badge section stayed empty until Profile reappeared (#121).
  case badges

  /// Everything a guest→permanent upgrade has to reload.
  static let onGuestUpgrade: [ProfileAccountRefresh] = [.profile, .statistics, .badges]

  /// Runs `perform` for each reload in `onGuestUpgrade`, in order, once the account is permanent.
  /// A guest (`isAnonymous`) has nothing to reload, so it returns at once.
  @MainActor
  static func run(
    isAnonymous: Bool,
    perform: @MainActor (ProfileAccountRefresh) async -> Void
  ) async {
    guard !isAnonymous else { return }
    for reload in onGuestUpgrade {
      await perform(reload)
    }
  }
}
