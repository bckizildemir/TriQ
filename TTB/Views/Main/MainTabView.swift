import SwiftUI

enum TabSelection: Int {
    case home = 0
    case mostAnswered = 1
    case ai = 2
}

struct MainTabView: View {
    @EnvironmentObject private var deepLinkRouter: AppDeepLinkRouter
    @EnvironmentObject private var notificationService: NotificationService
    @State private var selectedTab: TabSelection = .home
    @State private var isShowingAITabDisclosure = false
    private let aiTabDisclosureStore = AITabDisclosureStore()
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label(String(localized: "main.tabs.home"), systemImage: "lanyardcard.fill")
                }
                .tag(TabSelection.home)

            MostAnsweredView {
                selectedTab = .home
            }
                .tabItem {
                    Label(String(localized: "main.tabs.bestOf"), systemImage: "medal.star.fill")
                }
                .tag(TabSelection.mostAnswered)

            AIView()
                .tabItem {
                    Label(String(localized: "main.tabs.trio"), systemImage: "sparkles")
                }
                .tag(TabSelection.ai)
            
        }
        .background(Color.theme.background)
        .fullScreenCover(isPresented: $isShowingAITabDisclosure) {
            AITabDisclosureView {
                aiTabDisclosureStore.markSeen()
                isShowingAITabDisclosure = false
            }
        }
        .sheet(
            isPresented: Binding(
                get: { notificationService.presentedReleaseID != nil },
                set: { isPresented in
                    if !isPresented {
                        notificationService.presentedReleaseID = nil
                    }
                }
            )
        ) {
            if let releaseID = notificationService.presentedReleaseID {
                ContentReleaseDetailView(releaseID: releaseID)
            }
        }
        .onAppear {
            // Set the tab bar appearance
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor.secondarySystemBackground
            
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
        .onChange(of: selectedTab) { _, newValue in
            presentAITabDisclosureIfNeeded(for: newValue)
        }
        .onChange(of: deepLinkRouter.acceptedQuestionListShareDetail) { _, request in
            guard request != nil else { return }
            selectedTab = .home
        }
        .accentColor(.accentColor)
    }

    private func presentAITabDisclosureIfNeeded(for tab: TabSelection) {
        guard tab == .ai else { return }
        guard !isShowingAITabDisclosure else { return }
        guard !aiTabDisclosureStore.hasSeenCurrentVersion else { return }

        isShowingAITabDisclosure = true
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environmentObject(QuestionModel())
            .environmentObject(AnswerModel())
            .environmentObject(FavoriteStore.previews)
            .environmentObject(GuestFavoriteModel())
            .environmentObject(AuthModel())
            .environmentObject(AppDeepLinkRouter())
            .environmentObject(NotificationService.shared)
    }
}
