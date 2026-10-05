import FirebaseAuth
import SwiftUI

// MARK: - Profile Section Header
struct ProfileSectionHeader: View {
  let title: String
  var trailingText: String?
  var trailingAccessibilityLabel: String?

  var body: some View {
    HStack {
      Text(title)
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .accessibilityAddTraits(.isHeader)

      Spacer()

      if let trailingText {
        Text(trailingText)
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.secondary)
          .accessibilityLabel(trailingAccessibilityLabel ?? trailingText)
      }
    }
    .padding(.horizontal, 20)
  }
}

// MARK: - Profile Header View
struct ProfileHeaderView: View {
  let profileImage: UIImage?
  let username: String
  let email: String
  let onImageTap: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      Button(action: onImageTap) {
        Group {
          if let image = profileImage {
            Image(uiImage: image)
              .resizable()
              .scaledToFill()
              .frame(width: 100, height: 100)
              .clipShape(Circle())
              .overlay(
                Circle()
                  .stroke(Color.accentColor.opacity(0.2), lineWidth: 3)
              )
              .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
              .accessibilityLabel(String(localized: "profile.photo"))
          } else {
            ZStack {
              Circle()
                .fill(Color.accentColor.opacity(0.1))
                .frame(width: 100, height: 100)

              Image(systemName: "person.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
                .foregroundStyle(Color.accentColor)
            }
            .overlay(
              Circle()
                .stroke(Color.accentColor.opacity(0.2), lineWidth: 3)
            )
            .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
            .accessibilityLabel(String(localized: "profile.photo"))
          }
        }
        .overlay(alignment: .bottomTrailing) {
          ZStack {
            Circle()
              .fill(Color(.secondarySystemGroupedBackground))
              .frame(width: 30, height: 30)

            Image(systemName: "magnifyingglass")
              .font(.system(size: 12, weight: .bold))
              .foregroundStyle(Color.accentColor)
          }
          .overlay(
            Circle()
              .stroke(Color(.systemGroupedBackground), lineWidth: 2)
          )
          .offset(x: -2, y: -2)
          .allowsHitTesting(false)
        }
      }
      .buttonStyle(.plain)
      .accessibilityHint(String(localized: "profile.photoHint"))
      .accessibilityIdentifier("profile-photo-button")

      VStack(spacing: 4) {
        Text(username)
          .font(.title2.bold())
          .dynamicTypeSize(.large ... .accessibility5)

        Text(email)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .dynamicTypeSize(.large ... .accessibility5)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 24)
  }
}

// MARK: - Full Profile Photo View
struct FullProfilePhotoView: View {
  let image: UIImage?

  var body: some View {
    NavigationStack {
      ZStack {
        Color(.systemBackground)
          .ignoresSafeArea()

        if let image {
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .padding(20)
        } else {
          Image(systemName: "person.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 160, height: 160)
            .foregroundStyle(Color.accentColor)
            .padding(48)
            .background(
              Circle()
                .fill(Color.accentColor.opacity(0.1))
            )
        }
      }
      .navigationTitle(String(localized: "profile.photo"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          SimulatorSafeSheetDismissButton {
            Image(systemName: "xmark.circle.fill")
              .symbolRenderingMode(.hierarchical)
              .foregroundStyle(.secondary)
              .font(.title2)
              .frame(width: 44, height: 44)
              .contentShape(Rectangle())
          }
          .accessibilityLabel(String(localized: "common.close"))
          .accessibilityIdentifier("profile-photo-close-button")
        }
      }
    }
  }
}

// MARK: - Statistics Section View
struct StatisticsSectionView: View {
  let statistics: ProfileModel.Statistics

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ProfileSectionHeader(title: String(localized: "profile.section.statistics"))

      HStack(spacing: 12) {
        StatisticCard(
          title: String(localized: "profile.statistics.today"),
          value: "\(statistics.daily)",
          icon: "calendar",
          color: .blue
        )

        StatisticCard(
          title: String(localized: "profile.statistics.week"),
          value: "\(statistics.weekly)",
          icon: "calendar.badge.clock",
          color: .purple
        )

        StatisticCard(
          title: String(localized: "profile.statistics.total"),
          value: "\(statistics.total)",
          icon: "chart.bar.fill",
          color: .green
        )
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 16)
      .background(Color(.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .padding(.horizontal, 16)
    }
  }
}

// MARK: - Compact Badge Icon View
private struct CompactBadgeIconView: View {
  let badge: Badge

  var body: some View {
    BadgeIconCircle(
      badge: badge,
      circleSize: 56,
      symbolSize: 19,
      lineWidth: 1.5
    )
  }
}

// MARK: - Overlapping Badge Stack View
private struct OverlappingBadgeStackView: View {
  let badges: [Badge]

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(badges.prefix(3).enumerated()), id: \.element.id) { index, badge in
        BadgeIconCircle(
          badge: badge,
          circleSize: 32,
          symbolSize: 12,
          lineWidth: 1.75
        )
          .offset(x: CGFloat(index) * -10)
          .zIndex(Double(3 - index))
      }
    }
    .padding(
      .trailing, badges.prefix(3).count > 1 ? CGFloat((badges.prefix(3).count - 1)) * -10 : 0)
  }
}

// MARK: - Badges Section View
struct BadgesSectionView: View {
  let badges: [Badge]
  let onBadgeTap: (Badge) -> Void

  private let gridLayout = [
    GridItem(.flexible()),
    GridItem(.flexible()),
    GridItem(.flexible()),
  ]

  private var previewBadges: [Badge] { Array(badges.prefix(6)) }
  private var remainingBadges: [Badge] { badges.count > 6 ? Array(badges.dropFirst(6)) : [] }
  private var remainingCount: Int { max(0, badges.count - 6) }
  private var unlockedCount: Int { badges.filter { !$0.isLocked }.count }
  private var progressText: String { "\(unlockedCount)/\(badges.count)" }
  private var progressAccessibilityText: String {
    String(
      format: String(localized: "profile.badges.progressAccessibility"),
      locale: AppLocalization.currentLocale,
      unlockedCount,
      badges.count
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ProfileSectionHeader(
        title: String(localized: "profile.section.badges"),
        trailingText: progressText,
        trailingAccessibilityLabel: progressAccessibilityText
      )

      VStack(alignment: .leading, spacing: 16) {
        if badges.isEmpty {
          VStack(spacing: 8) {
            Image(systemName: "star.slash")
              .font(.system(size: 40))
              .foregroundStyle(.secondary)

            Text(String(localized: "profile.badges.empty"))
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 32)
        } else {
          LazyVGrid(columns: gridLayout, spacing: 16) {
            ForEach(previewBadges) { badge in
              Button {
                onBadgeTap(badge)
              } label: {
                CompactBadgeIconView(badge: badge)
              }
              .buttonStyle(.plain)
              .accessibilityIdentifier("profile-badge-\(badge.id)-button")
              .accessibilityLabel(
                String(
                  format: String(localized: badge.isLocked ? "badge.accessibility.locked" : "badge.accessibility.unlocked"),
                  locale: AppLocalization.currentLocale,
                  badge.title
                )
              )
              .accessibilityHint(String(localized: "profile.badges.detailsHint"))
            }
          }
          .padding(.horizontal, 20)

          if remainingCount > 0 {
            HStack(spacing: 12) {
              OverlappingBadgeStackView(badges: remainingBadges)

              VStack(alignment: .leading, spacing: 2) {
                Text(
                  String(
                    format: String(localized: "profile.badges.remainingCount"),
                    locale: AppLocalization.currentLocale,
                    remainingCount
                  )
                )
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(.primary)

                NavigationLink(destination: AllBadgesView(badges: badges, onBadgeTap: onBadgeTap)) {
                  Text(String(localized: "profile.badges.showAll"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                }
              }

              Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
          }
        }
      }
      .padding(.vertical, 16)
      .background(Color(.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .padding(.horizontal, 16)
    }
  }
}

// MARK: - All Badges View
struct AllBadgesView: View {
  let badges: [Badge]
  let onBadgeTap: (Badge) -> Void

  private let gridLayout = [
    GridItem(.flexible()),
    GridItem(.flexible()),
    GridItem(.flexible()),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(
            String(
              format: String(localized: "profile.badges.awardedCount"),
              locale: AppLocalization.currentLocale,
              badges.filter { !$0.isLocked }.count,
              badges.count
            )
          )
            .font(.subheadline)
            .foregroundStyle(.secondary)
          Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)

        LazyVGrid(columns: gridLayout, spacing: 16) {
          ForEach(badges) { badge in
            Button {
              onBadgeTap(badge)
            } label: {
              BadgeView(badge: badge)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
      }
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle(String(localized: "profile.section.badges"))
    .navigationBarTitleDisplayMode(.large)
  }
}

// MARK: - Content Section View
struct ContentSectionView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ProfileSectionHeader(title: String(localized: "profile.section.content"))

      VStack(spacing: 0) {
        NavigationLink(destination: FavoritesContentView()) {
          SettingsRowView(
            icon: "star.fill",
            iconColor: .yellow,
            title: String(localized: "profile.content.favorites")
          )
          .padding(.horizontal, 20)
        }
        .buttonStyle(ScaleButtonStyle())

        Divider()
          .padding(.leading, 76)

        NavigationLink(destination: AnswersContentView()) {
          SettingsRowView(
            icon: "text.badge.checkmark",
            iconColor: .green,
            title: String(localized: "profile.content.answers")
          )
          .padding(.horizontal, 20)
        }
        .buttonStyle(ScaleButtonStyle())

        Divider()
          .padding(.leading, 76)

        NavigationLink(destination: QuestionListsContentView()) {
          SettingsRowView(
            icon: "list.bullet.rectangle",
            iconColor: .blue,
            title: String(localized: "profile.content.questionLists")
          )
          .padding(.horizontal, 20)
        }
        .buttonStyle(ScaleButtonStyle())
      }
      .background(Color(.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .padding(.horizontal, 16)
    }
  }
}

// MARK: - Settings Section View
struct SettingsSectionView: View {
  let onEditProfile: () -> Void
  let onSignOut: () async -> Void
  let actionsDisabled: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ProfileSectionHeader(title: String(localized: "profile.section.settings"))

      VStack(spacing: 0) {
        Button(action: onEditProfile) {
          SettingsRowView(
            icon: "pencil",
            iconColor: .blue,
            title: String(localized: "profile.settings.editProfile")
          )
          .padding(.horizontal, 20)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(actionsDisabled)
        .accessibilityIdentifier("profile-edit-button")

        Divider()
          .padding(.leading, 76)

        Link(destination: URL(string: "mailto:support@example.com")!) {
          SettingsRowView(
            icon: "envelope",
            iconColor: .orange,
            title: String(localized: "profile.settings.feedback")
          )
          .padding(.horizontal, 20)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(actionsDisabled)

        Divider()
          .padding(.leading, 76)

        Button(action: signOut) {
          SettingsRowView(
            icon: "rectangle.portrait.and.arrow.right",
            iconColor: .red,
            title: String(localized: "profile.settings.signOut"),
            isDestructive: true
          )
          .padding(.horizontal, 20)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(actionsDisabled)
      }
      .background(Color(.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .padding(.horizontal, 16)
    }
  }

  private func signOut() {
    Task {
      await onSignOut()
    }
  }
}

// MARK: - Settings Row View
struct SettingsRowView: View {
  let icon: String
  let iconColor: Color
  let title: String
  var isDestructive: Bool = false

  var body: some View {
    HStack(spacing: 16) {
      ZStack {
        RoundedRectangle(cornerRadius: 8)
          .fill(iconColor.opacity(0.15))
          .frame(width: 32, height: 32)

        Image(systemName: icon)
          .font(.system(size: 16, weight: .medium))
          .foregroundStyle(iconColor)
      }

      Text(title)
        .font(.body)
        .foregroundStyle(isDestructive ? .red : .primary)

      Spacer()

      Image(systemName: "chevron.right")
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.tertiary)
    }
    .padding(.vertical, 12)
    .contentShape(Rectangle())
  }
}

struct AdminReleaseSectionView: View {
  let profileModel: ProfileModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ProfileSectionHeader(title: String(localized: "admin.releases.title"))

      VStack(spacing: 0) {
        NavigationLink {
          AdminReleaseManagerView()
            .environmentObject(profileModel)
        } label: {
          SettingsRowView(
            icon: "megaphone.fill",
            iconColor: .green,
            title: String(localized: "admin.releases.title")
          )
          .padding(.horizontal, 20)
        }
        .buttonStyle(ScaleButtonStyle())
      }
      .background(Color(.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .padding(.horizontal, 16)
    }
  }
}

private enum ProfileSheet: Identifiable {
  case guestUpgrade
  case profilePhoto(UIImage?)
  case editProfile
  case statistics(ProfileModel.Statistics)
  case deletePassword(email: String)
  case badge(Badge)
  case badgeUnlock(Badge)

  static let deletePasswordID = "deletePassword"

  var id: String {
    switch self {
    case .guestUpgrade:
      return "guestUpgrade"
    case .profilePhoto:
      return "profilePhoto"
    case .editProfile:
      return "editProfile"
    case .statistics:
      return "statistics"
    case .deletePassword:
      return Self.deletePasswordID
    case .badge(let badge):
      return "badge-\(badge.id)"
    case .badgeUnlock(let badge):
      return "badgeUnlock-\(badge.id)"
    }
  }

  var isDeletePassword: Bool {
    if case .deletePassword = self {
      return true
    }
    return false
  }
}

// MARK: - Profile View
struct ProfileView: View {
  @EnvironmentObject var authModel: AuthModel
  @EnvironmentObject var categoryModel: CategoryModel
  @EnvironmentObject var guestFavoriteModel: GuestFavoriteModel
  @Environment(\.dismiss) private var dismiss
  @StateObject private var model: ProfileModel
  @EnvironmentObject private var badgeModel: BadgeModel
  @State private var activeSheet: ProfileSheet?
  @State private var shouldShowDeletePasswordAfterEditDismiss = false
  @State private var isShowingErrorAlert = false

  @MainActor
  init() {
    let userId = Auth.auth().currentUser?.uid ?? ""
    _model = StateObject(wrappedValue: ProfileModel(userId: userId))
  }

  @MainActor
  init(model: @autoclosure @escaping () -> ProfileModel) {
    _model = StateObject(wrappedValue: model())
  }

  var body: some View {
    NavigationStack {
      observedProfileView
    }
  }

  private var canAccessBadgesAndProgress: Bool {
    GuestCapabilityPolicy.canAccessBadgesAndProgress(isAnonymous: authModel.isAnonymous)
  }

  private var actionsDisabled: Bool {
    authModel.isDeletingAccount || model.isLoading
  }

  private var observedProfileView: some View {
    applyingLifecycleHandlers(to: presentedProfileView)
  }

  private var presentedProfileView: some View {
    applyingPresentations(to: navigationConfiguredProfileView)
  }

  private var navigationConfiguredProfileView: some View {
    applyingAdminNavigation(to: profileScrollView)
  }

  private var profileScrollView: some View {
    ScrollView {
      profileContent
    }
    .background(Color(.systemGroupedBackground))
    .navigationTitle(String(localized: "profile.title"))
    .toolbarTitleDisplayMode(.inline)
    .toolbar {
      closeToolbar
    }
    .alert(String(localized: "common.error.title"), isPresented: $isShowingErrorAlert) {
      Button(String(localized: "common.ok"), role: .cancel, action: clearErrors)
    } message: {
      Text(activeErrorMessage)
    }
  }

  @ViewBuilder
  private var profileContent: some View {
    VStack(spacing: 24) {
      if model.isLoading {
        loadingView
      } else {
        loadedProfileContent
      }
    }
    .padding(.top, 8)
    .padding(.bottom, 32)
  }

  private var loadingView: some View {
    ProgressView()
      .frame(maxWidth: .infinity)
      .padding(.top, 100)
  }

  @ViewBuilder
  private var loadedProfileContent: some View {
    profileHeaderSection
    guestUpgradeSection
    ContentSectionView()
    NotificationSettingsSectionView()

    if model.isAdmin {
      AdminToolsView()
    }

    badgesSection
    statisticsSection
    settingsSection
  }

  @ViewBuilder
  private var profileHeaderSection: some View {
    if authModel.isAnonymous {
      GuestProfileHeaderView {
        activeSheet = .guestUpgrade
      }
    } else {
      ProfileHeaderView(
        profileImage: model.profileImage,
        username: model.username,
        email: model.email,
        onImageTap: {
          activeSheet = .profilePhoto(model.profileImage)
        }
      )
    }
  }

  @ViewBuilder
  private var guestUpgradeSection: some View {
    if authModel.isAnonymous {
      GuestUpgradeBannerView(favoriteCount: guestFavoriteModel.getFavoriteCount()) {
        activeSheet = .guestUpgrade
      }
      .padding(.horizontal, 20)

      guestCapabilityNotice
    }
  }

  @ViewBuilder
  private var badgesSection: some View {
    if canAccessBadgesAndProgress {
      BadgesSectionView(
        badges: badgeModel.badges,
        onBadgeTap: { badge in
          activeSheet = .badge(badge)
        }
      )
    }
  }

  @ViewBuilder
  private var statisticsSection: some View {
    if canAccessBadgesAndProgress {
      Button {
        activeSheet = .statistics(model.statistics)
      } label: {
        StatisticsSectionView(statistics: model.statistics)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("profile-statistics-section")
    }
  }

  @ViewBuilder
  private var settingsSection: some View {
    if authModel.isAnonymous {
      GuestSettingsSectionView(
        onSignOut: { await model.signOut() },
        onDeleteAccount: handleDeleteAccountRequest,
        actionsDisabled: actionsDisabled
      )
    } else {
      SettingsSectionView(
        onEditProfile: { activeSheet = .editProfile },
        onSignOut: { await model.signOut() },
        actionsDisabled: actionsDisabled
      )
    }
  }

  @ToolbarContentBuilder
  private var closeToolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarLeading) {
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .contentShape(Rectangle())
      }
      .accessibilityLabel(String(localized: "common.close"))
      .accessibilityHint(String(localized: "profile.closeHint"))
    }
  }

  private func applyingAdminNavigation<Content: View>(to content: Content) -> some View {
    content.navigationDestination(for: AdminRoute.self) { route in
      adminDestination(for: route)
    }
  }

  @ViewBuilder
  private func adminDestination(for route: AdminRoute) -> some View {
    switch route {
    case .questions:
      // No `QuestionModel` here or on `ProfileView` any more: AD-4 moved the moderation corpus and
      // its writes to `QuestionModerationStore`, which `AdminQuestionView` owns itself. This
      // destination was the screen's only reader.
      AdminQuestionView()
        .environmentObject(categoryModel)
      .environmentObject(model)

    case .categories:
      AdminCategoryView()
        .environmentObject(categoryModel)
        .environmentObject(model)

    case .badges:
      AdminBadgeView()
        .environmentObject(categoryModel)
      .environmentObject(model)

    case .releases:
      AdminReleaseManagerView()
        .environmentObject(model)
    }
  }

  private func applyingPresentations<Content: View>(to content: Content) -> some View {
    content
      .sheet(item: $activeSheet) { sheet in
        profileSheetContent(for: sheet)
      }
  }

  @ViewBuilder
  private func profileSheetContent(for sheet: ProfileSheet) -> some View {
    switch sheet {
    case .guestUpgrade:
      GuestUpgradeView()
        .environmentObject(authModel)
        .accessibilityIdentifier("profile-guest-upgrade-sheet")

    case .profilePhoto(let image):
      FullProfilePhotoView(image: image)
        .accessibilityIdentifier("profile-photo-sheet")

    case .editProfile:
      EditProfileView(
        model: model,
        actionsDisabled: actionsDisabled,
        onDeleteAccount: requestDeleteAccountFromEditProfile
      )
      .accessibilityIdentifier("profile-edit-sheet")

    case .statistics(let statistics):
      StatisticsDetailView(statistics: statistics)
        .accessibilityIdentifier("profile-statistics-sheet")

    case .deletePassword(let email):
      DeleteAccountPasswordSheetView(
        email: email,
        isDeleting: authModel.isDeletingAccount,
        errorMessage: authModel.errorState.isShowing ? authModel.errorState.message : nil,
        onDelete: { password in
          await deleteCurrentAccount(password: password)
        }
      )
      .accessibilityIdentifier("profile-delete-password-sheet")

    case .badge(let badge):
      BadgeDetailView(badge: badge)
        .accessibilityIdentifier("profile-badge-detail-sheet")

    case .badgeUnlock(let badge):
      BadgeUnlockView(badge: badge) {
        activeSheet = nil
        badgeModel.newlyUnlockedBadge = nil
      }
      .accessibilityIdentifier("profile-badge-unlock-sheet")
    }
  }

  private func applyingLifecycleHandlers<Content: View>(to content: Content) -> some View {
    content
      .onAppear {
        badgeModel.loadBadges()
      }
      .onChange(of: authModel.isAnonymous) { _, isAnonymous in
        handleAnonymousStateChange(isAnonymous)
      }
      .onChange(of: badgeModel.newlyUnlockedBadge) { _, newBadge in
        if let newBadge {
          activeSheet = .badgeUnlock(newBadge)
        }
      }
      .onChange(of: authModel.isAuthenticated) { _, isAuthenticated in
        if !isAuthenticated && activeSheet?.isDeletePassword == true {
          activeSheet = nil
        }
      }
      .onChange(of: model.showingAlert) { _, _ in
        isShowingErrorAlert = shouldShowErrorAlert
      }
      .onChange(of: authModel.errorState.isShowing) { _, _ in
        isShowingErrorAlert = shouldShowErrorAlert
      }
      .onChange(of: activeSheet?.id) { oldSheetID, newSheetID in
        if oldSheetID == ProfileSheet.deletePasswordID,
          newSheetID != ProfileSheet.deletePasswordID,
          authModel.errorState.isShowing
        {
          authModel.dismissError()
        }

        guard newSheetID == nil, shouldShowDeletePasswordAfterEditDismiss else { return }

        shouldShowDeletePasswordAfterEditDismiss = false
        handleDeleteAccountRequest()
      }
  }

  private func handleAnonymousStateChange(_ isAnonymous: Bool) {
    // Guest account was just upgraded to a real account.
    // The UID stays the same after linking, so ProfileModel's
    // userId.didSet won't fire — reload the profile manually.
    if !isAnonymous {
      Task {
        await model.loadUserProfile()
        await model.loadStatistics()
      }
    }
  }

  private var guestCapabilityNotice: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(String(localized: "profile.guest.noticeTitle"))
        .font(.headline)

      Text(String(localized: "profile.guest.noticeBody"))
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(Color.accentColor.opacity(0.08))
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
        )
    )
    .padding(.horizontal, 20)
  }

  private var activeErrorMessage: String {
    if model.showingAlert {
      model.alertMessage
    } else {
      authModel.errorState.message
    }
  }

  private var shouldShowErrorAlert: Bool {
    model.showingAlert || (activeSheet?.isDeletePassword != true && authModel.errorState.isShowing)
  }

  private func handleDeleteAccountRequest() {
    authModel.dismissError()

    if authModel.isAnonymous {
      Task {
        await deleteCurrentAccount(password: nil)
      }
    } else {
      activeSheet = .deletePassword(email: model.email)
    }
  }

  private func requestDeleteAccountFromEditProfile() {
    shouldShowDeletePasswordAfterEditDismiss = true
    activeSheet = nil
  }

  private func deleteCurrentAccount(password: String?) async {
    await authModel.deleteAccount(password: password)
  }

  private func clearErrors() {
    isShowingErrorAlert = false
    model.showingAlert = false
    authModel.dismissError()
  }
}

// MARK: - Preview
#Preview("Profile View") {
  ProfileView()
    .environmentObject(AuthModel())
    .environmentObject(QuestionModel())
    .environmentObject(FavoriteStore.previews)
    .environmentObject(GuestFavoriteModel())
    .environmentObject(CategoryModel())
    .environmentObject(BadgeModel())
}

#Preview("Profile View - Dark Mode") {
  ProfileView()
    .environmentObject(AuthModel())
    .environmentObject(QuestionModel())
    .environmentObject(FavoriteStore.previews)
    .environmentObject(GuestFavoriteModel())
    .environmentObject(CategoryModel())
    .environmentObject(BadgeModel())
    .preferredColorScheme(.dark)
}

// MARK: - Guest Profile Header

struct GuestProfileHeaderView: View {
  let onUpgrade: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      ZStack {
        Circle()
          .fill(Color(.systemGray5))
          .frame(width: 100, height: 100)
        Image(systemName: "person.fill")
          .resizable()
          .scaledToFit()
          .frame(width: 50, height: 50)
          .foregroundStyle(Color(.systemGray2))
      }
      .overlay(Circle().stroke(Color(.systemGray4), lineWidth: 3))
      .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)

      VStack(spacing: 4) {
        Text(String(localized: "profile.guest.user"))
          .font(.title2.bold())
        Text(String(localized: "profile.guest.notSignedIn"))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 8)
  }
}

// MARK: - Guest Upgrade Banner

struct GuestUpgradeBannerView: View {
  /// Number of device-local favorites, used to make an otherwise generic prompt
  /// specific. Zero falls back to the original copy.
  var favoriteCount: Int = 0
  var favoriteLimit: Int = GuestFavoriteModel.maxGuestFavorites
  let onUpgrade: () -> Void

  var body: some View {
    Button(action: onUpgrade) {
      HStack(spacing: 14) {
        ZStack {
          Circle()
            .fill(Color.accentColor.opacity(0.15))
            .frame(width: 44, height: 44)
          Image(systemName: "person.badge.plus")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Color.accentColor)
        }

        VStack(alignment: .leading, spacing: 2) {
          Text(String(localized: "profile.guest.saveProgress"))
            .font(.subheadline.bold())
            .foregroundStyle(.primary)
          Text(bodyText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }

        Spacer()

        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Color.accentColor)
      }
      .padding(16)
      .background(
        RoundedRectangle(cornerRadius: 14)
          .fill(Color.accentColor.opacity(0.06))
          .overlay(
            RoundedRectangle(cornerRadius: 14)
              .stroke(Color.accentColor.opacity(0.25), lineWidth: 1)
          )
      )
    }
    .buttonStyle(ScaleButtonStyle())
    .accessibilityLabel(String(localized: "profile.guest.saveProgressAccessibility"))
    .accessibilityHint(String(localized: "profile.guest.saveProgressHint"))
    .accessibilityIdentifier("profile-guest-upgrade-button")
  }

  private var bodyText: String {
    guard favoriteCount > 0 else {
      return String(localized: "profile.guest.saveProgressBody")
    }

    return String(
      format: String(localized: "profile.guest.saveProgressBody.withFavorites"),
      locale: AppLocalization.currentLocale,
      favoriteCount,
      favoriteLimit
    )
  }
}

#Preview("Guest Upgrade Banner") {
  VStack(spacing: 16) {
    GuestUpgradeBannerView(onUpgrade: {})
    GuestUpgradeBannerView(favoriteCount: 3, onUpgrade: {})
  }
  .padding()
}

// MARK: - Guest Settings Section

struct GuestSettingsSectionView: View {
  let onSignOut: () async -> Void
  let onDeleteAccount: () -> Void
  let actionsDisabled: Bool

  @State private var showingDeleteConfirmation = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ProfileSectionHeader(title: String(localized: "common.account"))

      VStack(spacing: 0) {
        Button {
          signOut()
        } label: {
          SettingsRowView(
            icon: "rectangle.portrait.and.arrow.right",
            iconColor: .red,
            title: String(localized: "profile.settings.signOut"),
            isDestructive: true
          )
          .padding(.horizontal, 20)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(actionsDisabled)

        Divider()
          .padding(.leading, 76)

        Button(role: .destructive, action: requestDeleteAccount) {
          SettingsRowView(
            icon: "trash",
            iconColor: .red,
            title: String(localized: "profile.settings.deleteAccount"),
            isDestructive: true
          )
          .padding(.horizontal, 20)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(actionsDisabled)
        .confirmationDialog(String(localized: "profile.deleteAccount.title"), isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
          Button(String(localized: "profile.guest.deleteAccountConfirm"), role: .destructive, action: onDeleteAccount)
          Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
          Text(String(localized: "profile.guest.deleteAccountMessage"))
        }
      }
      .background(Color(.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .padding(.horizontal, 16)
    }
  }

  private func signOut() {
    Task {
      await onSignOut()
    }
  }

  private func requestDeleteAccount() {
    showingDeleteConfirmation = true
  }
}

struct ScaleButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
      .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
  }
}

struct StatisticCard: View {
  let title: String
  let value: String
  let icon: String
  let color: Color

  var body: some View {
    VStack(spacing: 10) {
      ZStack {
        Circle()
          .fill(color.opacity(0.15))
          .frame(width: 44, height: 44)

        Image(systemName: icon)
          .font(.system(size: 20, weight: .semibold))
          .foregroundStyle(color)
      }

      VStack(spacing: 2) {
        Text(value)
          .font(.title2.bold())
          .foregroundStyle(.primary)

        Text(title)
          .font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 16)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color(.secondarySystemBackground))
    )
  }
}
