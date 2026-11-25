import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        EntryPush.shared.complete(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        EntryPush.shared.complete(nil)
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate, UITabBarControllerDelegate {
    var window: UIWindow?
    private var api: CommunityAPI?
    private let wallet = Wallet.shared
    private var portal: CommunityPortal?
    private var attempt = UUID()
    private var entryTask: Task<Void, Error>?
    private let consentKey = "Sese.CommunityEntry.32948410.SignedInAccount"
    private let completionKey = "Sese.CommunityEntry.32948410.CompletedAccount"

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        self.window = window
        do {
            let api = try CommunityAPI()
            self.api = api
            wallet.api = api
            portal = CommunityPortal(window: window, api: api, wallet: wallet, showHome: { [weak self] in
                self?.showTabs()
            }, onExpiry: { [weak self] in self?.showWelcome() })
            EntryConnection.shared.onNetworkChange = { [weak self] available in
                self?.portal?.networkChanged(available: available)
                if available, let member = self?.api?.memberID { self?.wallet.recover(for: member) }
            }
            Task { try? await EntryConnection.shared.wait(for: api.configuration.url) }
            if let stored = api.client.auth.currentSession?.user.id,
               UserDefaults.standard.string(forKey: consentKey) == stored.uuidString {
                restore()
            } else {
                showWelcome()
            }
        } catch {
            window.rootViewController = EntryPage(mode: .unavailable, api: nil) {}
        }
        window.makeKeyAndVisible()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        portal?.becameActive()
        if let api, let id = api.memberID {
            wallet.recover(for: id)
            Task { await api.reconcileSafety() }
        }
    }

    private func cancelEntry() {
        attempt = UUID()
        entryTask?.cancel()
        entryTask = nil
        portal?.stop()
        wallet.bind(nil)
    }

    private func showWelcome(errorMessage: String? = nil) {
        cancelEntry()
        UserDefaults.standard.removeObject(forKey: consentKey)
        UserDefaults.standard.removeObject(forKey: completionKey)
        guard let api else { return }
        api.endExternalSession()
        let welcome = EntryPage(mode: .welcome, api: api) { [weak self] in
            guard let self else { throw CancellationError() }
            try await self.beginEntry(cold: false)
        }
        window?.rootViewController = navigation(welcome)
        if let errorMessage { welcome.showEntryError(errorMessage) }
    }

    private func restore() {
        let gate = EntryRestorePage()
        gate.retry = { [weak self] in self?.restore() }
        gate.back = { [weak self] in self?.showWelcome() }
        window?.rootViewController = gate
        Task { [weak self] in
            do { try await self?.beginEntry(cold: true) }
            catch is CancellationError { return }
            catch {
                guard let self else { return }
                self.window?.rootViewController = gate
                gate.showError()
            }
        }
    }

    private func beginEntry(cold: Bool) async throws {
        guard let api, let portal, entryTask == nil else { throw CommunityError.unavailable }
        let ticket = UUID()
        attempt = ticket
        let job = Task {
            let route = try await api.signIn()
            try Task.checkCancellation()
            guard attempt == ticket, let member = api.memberID else { throw CancellationError() }
            let binding: String
            switch route {
            case .external(let origin, let appID):
                binding = [member.uuidString, origin.absoluteString, appID].joined(separator: "|")
                if cold && UserDefaults.standard.string(forKey: completionKey) != binding {
                    showWelcome()
                    throw CancellationError()
                }
            case .nativeSupabase, .standalone:
                binding = member.uuidString
            }
            UserDefaults.standard.set(member.uuidString, forKey: consentKey)
            wallet.bind(member)
            try await portal.enter(route)
            try Task.checkCancellation()
            guard attempt == ticket, api.memberID == member else { throw CancellationError() }
            UserDefaults.standard.set(binding, forKey: completionKey)
        }
        entryTask = job
        defer { if attempt == ticket { entryTask = nil } }
        do {
            try await job.value
        } catch {
            guard attempt == ticket else { throw CancellationError() }
            portal.stop()
            wallet.bind(nil)
            api.endExternalSession()
            if !cold, window?.rootViewController is UITabBarController {
                showWelcome(errorMessage: (error as? CommunityError)?.errorDescription ?? "Sign-in could not finish. Please try again.")
            }
            throw error
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        cancelEntry()
        EntryConnection.shared.onNetworkChange = nil
    }

    private func showTabs() {
        guard let api, let memberID = api.memberID else { return }
        wallet.bind(memberID)
        let tabs = UITabBarController()
        tabs.delegate = self
        let pages: [(UIViewController, String, String)] = [
            (ShortsFeedPage(api: api), "Shorts", "shorts"),
            (DistrictMapPage(memberID: memberID, wallet: wallet, api: api), "Districts", "districts"),
            (CatalogPage(.cosplay, api: api), "Cosplay", "cosplay"),
            (InboxPage(api: api), "Chats", "chats"),
            (ProfilePage(memberID: memberID, api: api, wallet: wallet) { [weak self] in self?.showWelcome() }, "Me", "profile")
        ]
        tabs.viewControllers = pages.map { page, title, icon in
            let navigation = navigation(page)
            let item = UITabBarItem(title: title, image: nil, selectedImage: nil)
            item.accessibilityLabel = title
            item.imageInsets = .zero
            navigation.tabBarItem = item
            Task { [weak item] in
                let image = await Artwork.image(icon)
                item?.image = image
                item?.selectedImage = image
            }
            return navigation
        }
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Theme.ink
        appearance.shadowColor = Theme.line
        for layout in [appearance.stackedLayoutAppearance, appearance.inlineLayoutAppearance, appearance.compactInlineLayoutAppearance] {
            layout.normal.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 2)
            layout.selected.titlePositionAdjustment = UIOffset(horizontal: 0, vertical: 2)
            layout.normal.titleTextAttributes = [.font: Theme.font(11, display: true), .foregroundColor: Theme.secondary]
            layout.selected.titleTextAttributes = [.font: Theme.font(11, display: true), .foregroundColor: Theme.mint]
        }
        tabs.tabBar.standardAppearance = appearance
        tabs.tabBar.scrollEdgeAppearance = appearance
        window?.rootViewController = tabs
        Task { await api.reconcileSafety() }
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if tabBarController.selectedViewController !== viewController,
           let navigation = viewController as? UINavigationController,
           let shorts = navigation.viewControllers.first as? ShortsFeedPage {
            shorts.returnFromProfileIfNeeded()
        }
        return true
    }

    private func navigation(_ root: UIViewController) -> UINavigationController {
        let controller = UINavigationController(rootViewController: root)
        controller.setNavigationBarHidden(true, animated: false)
        return controller
    }
}

private final class EntryRestorePage: UIViewController {
    var retry: (() -> Void)?
    var back: (() -> Void)?
    private let spinner = UIActivityIndicatorView(style: .large)
    private let status = Theme.label("Signing in…", size: 18)
    private lazy var again = Theme.button("Try again", accent: true) { [weak self] in self?.retry?() }
    private lazy var exitButton = Theme.button("Back to sign in") { [weak self] in self?.back?() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.ink
        spinner.color = Theme.mint
        spinner.startAnimating()
        again.isHidden = true
        exitButton.isHidden = true
        status.textAlignment = .center
        let stack = Theme.stack([spinner, status, again, exitButton], spacing: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    func showError() {
        loadViewIfNeeded()
        spinner.stopAnimating()
        status.text = "Sese could not finish signing in."
        again.isHidden = false
        exitButton.isHidden = false
    }
}
