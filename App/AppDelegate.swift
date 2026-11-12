import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate, UITabBarControllerDelegate {
    var window: UIWindow?
    private var api: CommunityAPI?
    private let wallet = Wallet()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        self.window = window
        do {
            api = try CommunityAPI()
            showWelcome()
        } catch {
            window.rootViewController = EntryPage(mode: .unavailable, api: nil) {}
        }
        window.makeKeyAndVisible()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        if let id = api?.memberID { wallet.recover(for: id) }
    }

    private func showWelcome() {
        wallet.bind(nil)
        guard let api else { return }
        let welcome = EntryPage(mode: .welcome, api: api) { [weak self] in self?.showTabs() }
        window?.rootViewController = navigation(welcome)
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
            navigation.tabBarItem = item
            Task { [weak item] in
                let image = await Artwork.image(icon)?.scaled(to: 27)
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
            layout.normal.titleTextAttributes = [.font: Theme.font(11, display: true), .foregroundColor: Theme.secondary]
            layout.selected.titleTextAttributes = [.font: Theme.font(11, display: true), .foregroundColor: Theme.mint]
        }
        tabs.tabBar.standardAppearance = appearance
        tabs.tabBar.scrollEdgeAppearance = appearance
        window?.rootViewController = tabs
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        if tabBarController.selectedViewController !== viewController,
           let navigation = viewController as? UINavigationController,
           let shorts = navigation.viewControllers.first as? ShortsFeedPage {
            shorts.returnFromCreatorProfileIfNeeded()
        }
        return true
    }

    private func navigation(_ root: UIViewController) -> UINavigationController {
        let controller = UINavigationController(rootViewController: root)
        controller.setNavigationBarHidden(true, animated: false)
        return controller
    }
}
