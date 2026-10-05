import SwiftUI
import UIKit

/// An optional tap target on a toast. A toast is never a decision surface — this is a
/// shortcut *to* one, so the destination must be something untimed like a sheet.
struct ToastAction {
    let accessibilityHint: String?
    let handler: () -> Void

    init(accessibilityHint: String? = nil, handler: @escaping () -> Void) {
        self.accessibilityHint = accessibilityHint
        self.handler = handler
    }
}

struct AppToast: Identifiable {
    enum Style: Equatable {
        case success
        case status
        case favorite

        var systemImage: String {
            switch self {
            case .success:
                return "checkmark.circle.fill"
            case .status:
                return "info.circle.fill"
            case .favorite:
                return "star.fill"
            }
        }

        /// Nil means "inherit the label color". Favorites are yellow everywhere else in
        /// the app, so the toast wears the same symbol and tint.
        var tint: Color? {
            switch self {
            case .success, .status:
                return nil
            case .favorite:
                return .yellow
            }
        }
    }

    static let defaultDuration: TimeInterval = 4.0
    /// Actionable toasts live longer: a tap target that expires before it can be reached
    /// is decoration.
    static let actionableDuration: TimeInterval = 6.0

    let id = UUID()
    let title: String
    let subtitle: String?
    let style: Style
    let duration: TimeInterval
    let accessibilityIdentifier: String
    let playsHaptic: Bool
    let action: ToastAction?

    init(
        title: String,
        subtitle: String? = nil,
        style: Style = .status,
        duration: TimeInterval? = nil,
        accessibilityIdentifier: String = "app-toast",
        playsHaptic: Bool = false,
        action: ToastAction? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.duration = duration ?? (action == nil ? Self.defaultDuration : Self.actionableDuration)
        self.accessibilityIdentifier = accessibilityIdentifier
        self.playsHaptic = playsHaptic
        self.action = action
    }
}

@MainActor
final class ToastCenter: ObservableObject {
    @Published private(set) var currentToast: AppToast?
    /// Drives the guest favorite signup sheet. It lives here, the single owner of a favorite
    /// toggle's UI consequences, and is raised only from the outcome `toggleFavorite` returns —
    /// so the guest cap reaches the UI through one channel instead of a flag `GuestFavoriteModel`
    /// used to publish on the side.
    @Published var isGuestFavoriteLimitPromptPresented = false
    private var dismissalTask: Task<Void, Never>?

    /// Nonisolated so the environment default (`unhosted`) can be built off the main actor. It
    /// touches no isolated state: every stored property starts from its declared default.
    nonisolated init() {}

    func show(_ toast: AppToast) {
        dismissalTask?.cancel()

        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
            currentToast = toast
        }

        if toast.playsHaptic {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        UIAccessibility.post(
            notification: .announcement,
            argument: [toast.title, toast.subtitle].compactMap { $0 }.joined(separator: ". ")
        )

        dismissalTask = Task { [weak self] in
            let nanoseconds = UInt64(Self.effectiveDuration(for: toast) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            self?.dismiss(id: toast.id)
        }
    }

    /// VoiceOver reads the toast aloud after it appears, so an actionable toast that
    /// expires on the visual timeline can die mid-announcement — before its tap target
    /// was ever reachable.
    private static func effectiveDuration(for toast: AppToast) -> TimeInterval {
        guard toast.action != nil, UIAccessibility.isVoiceOverRunning else {
            return toast.duration
        }
        return toast.duration * 2
    }

    func showSuccess(
        title: String,
        subtitle: String? = nil,
        accessibilityIdentifier: String = "app-toast"
    ) {
        show(
            AppToast(
                title: title,
                subtitle: subtitle,
                style: .success,
                accessibilityIdentifier: accessibilityIdentifier
            )
        )
    }

    /// Surfaces a failure that used to roll back silently — a toggle that reads as instant but
    /// did not actually save must still tell the user, or they keep trusting a state the backend
    /// rejected.
    func showError(
        _ message: String,
        accessibilityIdentifier: String = "app-toast-error"
    ) {
        show(
            AppToast(
                title: message,
                style: .status,
                accessibilityIdentifier: accessibilityIdentifier
            )
        )
    }

    /// Performs the shared favorite action and presents its UI consequences — the two the store
    /// does not own itself: an account-write failure raises an error toast, and the guest cap
    /// raises the signup prompt. Both are decided by the returned outcome.
    func toggleFavorite(_ question: Question, using favoriteStore: FavoriteStore) async {
        switch await favoriteStore.toggle(question) {
        case .failed:
            if let message = favoriteStore.error {
                showError(message)
            }
        case .guestLimitReached:
            isGuestFavoriteLimitPromptPresented = true
        case .added, .removed:
            break
        }
    }

    func dismiss(id: UUID? = nil) {
        guard id == nil || currentToast?.id == id else { return }
        dismissalTask?.cancel()
        dismissalTask = nil

        withAnimation(.easeOut(duration: 0.18)) {
            currentToast = nil
        }
    }
}

extension ToastCenter {
    /// The environment default: one shared center that no host displays, so a toast raised outside
    /// a host goes nowhere. Stored once rather than built in the `@Entry` default, which SwiftUI
    /// evaluates on every read — a new object each time would invalidate every reader on every
    /// update. Nonisolated is sound because a `@MainActor` class is `Sendable`.
    nonisolated static let unhosted = ToastCenter()
}

extension EnvironmentValues {
    /// The center a screen raises toasts on. The app and every hosted sheet install their own.
    @Entry var toastCenter: ToastCenter = .unhosted
}

struct AppToastHostModifier: ViewModifier {
    let toastCenter: ToastCenter

    func body(content: Content) -> some View {
        content
            .environment(\.toastCenter, toastCenter)
            .background(ToastOverlayInstaller(toastCenter: toastCenter))
    }
}

extension View {
    func appToastHost(_ toastCenter: ToastCenter) -> some View {
        modifier(AppToastHostModifier(toastCenter: toastCenter))
    }
}

private extension View {
    /// Registers a default accessibility action only when there is one to run. `accessibilityAction`
    /// has no optional-friendly overload, so an actionless toast that always registered one would
    /// tell VoiceOver a double-tap does something when it is actually a no-op.
    @ViewBuilder
    func conditionalDefaultAccessibilityAction(
        _ action: @escaping () -> Void,
        isActionable: Bool
    ) -> some View {
        if isActionable {
            accessibilityAction(.default, action)
        } else {
            self
        }
    }
}

private struct AppToastView: View {
    let toast: AppToast
    let onDismiss: () -> Void
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                toastContent
                    .glassEffect(
                        .regular.tint(.black.opacity(0.20)),
                        in: .capsule
                    )
            }
        } else {
            toastContent
                .background(.ultraThinMaterial, in: Capsule())
                .background(.black.opacity(0.18), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
        }
    }

    private var toastContent: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.style.systemImage)
                .font(.headline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(toast.style.tint ?? .primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                if let subtitle = toast.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if toast.action != nil {
                // Visible affordance on purpose: a silently tappable toast is an
                // invisible target, which sighted and VoiceOver users both lose.
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(maxWidth: 360, alignment: .leading)
        .offset(y: dragOffset)
        .opacity(dragOffset < 0 ? max(0.25, 1 + dragOffset / 120) : 1)
        .gesture(dismissGesture)
        .onTapGesture(perform: activateAction)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(toast.accessibilityIdentifier)
        .accessibilityAddTraits(toast.action != nil ? .isButton : [])
        .accessibilityHint(toast.action?.accessibilityHint ?? "")
        .conditionalDefaultAccessibilityAction(activateAction, isActionable: toast.action != nil)
    }

    private func activateAction() {
        guard let action = toast.action else { return }
        onDismiss()
        action.handler()
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard value.translation.height < 0 else { return }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                let shouldDismiss = value.translation.height < -24
                    || value.predictedEndTranslation.height < -48

                if shouldDismiss {
                    onDismiss()
                } else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        dragOffset = 0
                    }
                }
            }
    }
}

private struct ToastOverlayInstaller: UIViewRepresentable {
    let toastCenter: ToastCenter

    func makeCoordinator() -> Coordinator {
        Coordinator(toastCenter: toastCenter)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isHidden = true

        DispatchQueue.main.async {
            context.coordinator.install(from: view)
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.toastCenter = toastCenter

        DispatchQueue.main.async {
            context.coordinator.install(from: uiView)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var toastCenter: ToastCenter
        private let region = ToastInteractionRegion()
        private var window: PassThroughToastWindow?
        private var hostingController: UIHostingController<ToastOverlayContainer>?

        init(toastCenter: ToastCenter) {
            self.toastCenter = toastCenter
        }

        @MainActor
        func install(from view: UIView) {
            guard let scene = view.window?.windowScene ?? Self.foregroundWindowScene else {
                return
            }

            if window?.windowScene === scene {
                hostingController?.rootView = makeContainer()
                return
            }

            uninstall()

            let controller = UIHostingController(rootView: makeContainer())
            controller.view.backgroundColor = .clear

            let overlayWindow = PassThroughToastWindow(windowScene: scene, region: region)
            overlayWindow.backgroundColor = .clear
            overlayWindow.windowLevel = .alert + 1
            overlayWindow.rootViewController = controller
            overlayWindow.isHidden = false

            hostingController = controller
            window = overlayWindow
        }

        @MainActor
        private func makeContainer() -> ToastOverlayContainer {
            let region = region
            return ToastOverlayContainer(toastCenter: toastCenter) { frame in
                region.interactiveFrame = frame
            }
        }

        @MainActor
        func uninstall() {
            window?.isHidden = true
            window?.rootViewController = nil
            window = nil
            hostingController = nil
        }

        @MainActor
        private static var foregroundWindowScene: UIWindowScene? {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
        }
    }
}

/// Shared mutable box letting the SwiftUI overlay tell the UIKit window which part of the
/// screen, if any, should actually receive touches.
private final class ToastInteractionRegion {
    var interactiveFrame: CGRect = .zero
}

private final class PassThroughToastWindow: UIWindow {
    let region: ToastInteractionRegion

    init(windowScene: UIWindowScene, region: ToastInteractionRegion) {
        self.region = region
        super.init(windowScene: windowScene)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Comparing the hit view against `rootViewController.view` is not enough on its own:
    /// SwiftUI gestures are serviced by the hosting view itself rather than by per-view
    /// subviews, so treating a hit on that view as "nothing here" swallows every tap the
    /// toast wants. Geometry decides instead — touches inside the toast's own frame reach
    /// it, everything else falls through to the app beneath.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard !region.interactiveFrame.isEmpty,
              region.interactiveFrame.contains(point) else {
            return nil
        }

        return super.hitTest(point, with: event)
    }
}

private struct ToastOverlayContainer: View {
    @ObservedObject var toastCenter: ToastCenter
    let onInteractiveFrameChange: (CGRect) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .ignoresSafeArea()

            toastOverlay
        }
        .allowsHitTesting(toastCenter.currentToast != nil)
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast = toastCenter.currentToast {
            AppToastView(
                toast: toast,
                onDismiss: {
                    toastCenter.dismiss(id: toast.id)
                }
            )
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .id(toast.id)
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                onInteractiveFrameChange(frame)
            }
            .onDisappear {
                onInteractiveFrameChange(.zero)
            }
            .transition(
                reduceMotion
                    ? .opacity
                    : .move(edge: .top).combined(with: .opacity)
            )
            .zIndex(100)
        }
    }
}
