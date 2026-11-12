import SafariServices
import UIKit

private struct HostedShort {
    let item: CatalogItem
    let videoURL: URL
    let posterURL: URL?

    init?(item: CatalogItem, projectURL: URL) {
        func isShortAsset(_ url: URL, fileExtension: String) -> Bool {
            url.scheme == "https" && url.host == projectURL.host && url.port == projectURL.port &&
            url.user == nil && url.password == nil && url.query == nil && url.fragment == nil &&
            url.path.hasPrefix("/storage/v1/object/public/editorial/shorts/") && url.pathExtension == fileExtension
        }

        guard item.isVideo, let videoURL = item.mediaUrl, isShortAsset(videoURL, fileExtension: "mp4") else { return nil }
        self.item = item
        self.videoURL = videoURL
        self.posterURL = item.imageUrl.flatMap { isShortAsset($0, fileExtension: "jpg") ? $0 : nil }
    }
}

private struct ShortsPublisher {
    let name: String
    let portrait: String

    init(_ item: CatalogItem) {
        name = item.credit.components(separatedBy: " · ").first ?? item.credit
        switch item.id {
        case "fox-costume-in-motion": portrait = "expo-judy"
        case "narcon-conga-line": portrait = "fan-duo"
        case "costume-meetup-hug": portrait = "expo-nick"
        default: portrait = "expo-duo"
        }
    }
}

private final class ShortsPublisherPage: CityPage {
    private let short: HostedShort

    init(short: HostedShort, api: CommunityAPI) {
        self.short = short
        super.init("Creator", api: api)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        let item = short.item
        let publisher = ShortsPublisher(item)
        let identity = Theme.stack([
            MemberAvatar.view(publisher.portrait, size: 72),
            Theme.stack([
                Theme.label(publisher.name, size: 26, display: true),
                Theme.label("Editorial creator", size: 15, color: Theme.secondary)
            ], spacing: 4)
        ], spacing: 12, axis: .horizontal)
        identity.alignment = .center
        body.addArrangedSubview(Theme.card([identity, Theme.label(item.credit, size: 15, color: Theme.secondary)]))
        let portraitCredit = publisher.portrait == "fan-duo" ? MemberAvatar.fanCredit : MemberAvatar.credit
        if let portraitCredit {
            body.addArrangedSubview(Theme.button("Cosplay portrait credit") { [weak self] in self?.open(portraitCredit) })
        }
        body.addArrangedSubview(Theme.label("Works", size: 22, display: true))
        body.addArrangedSubview(Theme.button(item.title, icon: "shorts") { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        })
        body.addArrangedSubview(Theme.button("View original source") { [weak self] in self?.open(item.sourceUrl) })
    }
}

private final class ShortsVideoGradient: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let gradient = layer as! CAGradientLayer
        gradient.colors = [
            UIColor.black.withAlphaComponent(0.58).cgColor,
            UIColor.clear.cgColor,
            UIColor.clear.cgColor,
            UIColor.black.withAlphaComponent(0.78).cgColor
        ]
        gradient.locations = [0, 0.22, 0.62, 1]
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { nil }
}

private final class ShortsClipPage: UIViewController {
    let item: CatalogItem
    let playback: ShortsPlaybackView
    var react: ((String) -> Void)?
    var comments: (() -> Void)?
    var share: ((UIView) -> Void)?
    var options: (() -> Void)?
    var openProfile: (() -> Void)?
    private var like: UIButton?
    private var save: UIButton?

    init(short: HostedShort) {
        item = short.item
        playback = ShortsPlaybackView(videoURL: short.videoURL, posterURL: short.posterURL)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.ink
        view.accessibilityIdentifier = "shorts.clip.\(item.id)"
        let publisher = ShortsPublisher(item)
        let avatar = MemberAvatar.button(publisher.portrait, size: 48, label: "Open \(publisher.name)’s creator profile") {
            [weak self] in self?.openProfile?()
        }
        avatar.accessibilityIdentifier = "shorts.creator"

        let credit = Theme.label(item.credit, size: 15, display: true)
        credit.numberOfLines = 2
        let title = Theme.label(item.title, size: 22, display: true)
        title.numberOfLines = 2
        title.accessibilityTraits.insert(.header)
        let caption = Theme.label(item.description, size: 14, color: Theme.secondary)
        caption.numberOfLines = 2
        let metadata = Theme.stack([credit, title, caption], spacing: 4)
        let more = Theme.moreIcon(label: "Video options") { [weak self] in self?.options?() }

        let like = Theme.icon("like", label: "Like") { [weak self] in self?.react?("like") }
        like.accessibilityIdentifier = "shorts.like"
        self.like = like
        let save = Theme.icon("save", label: "Save") { [weak self] in self?.react?("save") }
        save.accessibilityIdentifier = "shorts.save"
        self.save = save
        let comments = Theme.icon("comments", label: "Comments") { [weak self] in self?.comments?() }
        comments.accessibilityIdentifier = "shorts.comments"
        let share = Theme.icon("share", label: "Share") {}
        share.accessibilityIdentifier = "shorts.share"
        share.addAction(UIAction { [weak self, weak share] _ in
            guard let share else { return }
            self?.share?(share)
        }, for: .touchUpInside)
        let actions = Theme.stack([avatar, like, comments, save, share, more], spacing: 8)
        actions.alignment = .center

        let gradient = ShortsVideoGradient(frame: .zero)
        let progress = UIProgressView()
        progress.progressTintColor = Theme.mint
        progress.trackTintColor = Theme.paper.withAlphaComponent(0.24)
        progress.isAccessibilityElement = false
        playback.progressChanged = { [weak progress] in progress?.progress = $0 }

        for element in [playback, gradient, metadata, actions, progress] as [UIView] {
            element.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(element)
        }
        NSLayoutConstraint.activate([
            playback.topAnchor.constraint(equalTo: view.topAnchor),
            playback.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            playback.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            playback.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gradient.topAnchor.constraint(equalTo: view.topAnchor),
            gradient.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            gradient.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gradient.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progress.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progress.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            actions.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            actions.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            actions.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),
            metadata.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            metadata.trailingAnchor.constraint(equalTo: actions.leadingAnchor, constant: -12),
            metadata.bottomAnchor.constraint(equalTo: actions.bottomAnchor)
        ])
    }

    func renderReactions(_ enabled: Set<String>, busy: Set<String>) {
        loadViewIfNeeded()
        update(like, name: "Like", selectedName: "Liked", enabled: enabled.contains("like"), busy: busy.contains("like"))
        update(save, name: "Save", selectedName: "Saved", enabled: enabled.contains("save"), busy: busy.contains("save"))
    }

    private func update(_ button: UIButton?, name: String, selectedName: String, enabled: Bool, busy: Bool) {
        button?.accessibilityLabel = enabled ? selectedName : name
        button?.isSelected = enabled
        button?.layer.shadowColor = Theme.mint.cgColor
        button?.layer.shadowOffset = .zero
        button?.layer.shadowRadius = 6
        button?.layer.shadowOpacity = enabled ? 1 : 0
        button?.accessibilityTraits = enabled ? [.button, .selected] : .button
        button?.isEnabled = !busy
    }
}

final class ShortsFeedPage: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate,
                            SFSafariViewControllerDelegate {
    private let api: CommunityAPI
    private let pager = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .vertical)
    private let state = Theme.stack()
    private var catalog: [HostedShort] = []
    private var items: [HostedShort] = []
    private var reactions: [String: Set<String>] = [:]
    private var pending: [String: Set<String>] = [:]
    private var catalogTask: Task<Void, Never>?
    private var reactionsTask: Task<Void, Never>?
    private var query = ""
    private var kind: String?
    private var visible = false
    private var paging = false
    private var overlayOpen = false
    private var loaded = false
    private var current: ShortsClipPage? { pager.viewControllers?.first as? ShortsClipPage }

    init(api: CommunityAPI) {
        self.api = api
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.ink
        extendedLayoutIncludesOpaqueBars = true
        let title = Theme.label("Shorts", size: 30, display: true)
        title.accessibilityTraits.insert(.header)
        title.numberOfLines = 1
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.65
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let header = Theme.stack([
            title,
            Theme.icon("search", label: "Search shorts") { [weak self] in self?.search() },
            Theme.icon("filter", label: "Filter shorts") { [weak self] in self?.filter() },
            Theme.icon("shorts", label: "Community videos") { [weak self] in self?.showCommunity() }
        ], spacing: 8, axis: .horizontal)
        header.alignment = .center
        header.isLayoutMarginsRelativeArrangement = true
        header.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 2, leading: 16, bottom: 6, trailing: 16)
        header.translatesAutoresizingMaskIntoConstraints = false

        addChild(pager)
        pager.dataSource = self
        pager.delegate = self
        pager.view.translatesAutoresizingMaskIntoConstraints = false
        pager.view.backgroundColor = .black
        pager.view.clipsToBounds = true
        pager.view.accessibilityIdentifier = "shorts.feed"
        pager.view.subviews.compactMap { $0 as? UIScrollView }.first?
            .contentInsetAdjustmentBehavior = .never
        view.addSubview(pager.view)
        pager.didMove(toParent: self)

        view.addSubview(header)
        state.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(state)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            pager.view.topAnchor.constraint(equalTo: view.topAnchor),
            pager.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            header.topAnchor.constraint(equalTo: safe.topAnchor),
            header.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            pager.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pager.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            state.centerYAnchor.constraint(equalTo: pager.view.centerYAnchor),
            state.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 20),
            state.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -20)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(playbackVisibilityChanged),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willResignActive),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        loadCatalog()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateTabBarAppearance(fullBleed: !pager.view.isHidden)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        visible = true
        updateTabBarAppearance(fullBleed: !pager.view.isHidden)
        refreshReactions()
        playbackVisibilityChanged()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        visible = false
        updateTabBarAppearance(fullBleed: false)
        playbackVisibilityChanged()
    }

    @objc private func willResignActive() { current?.playback.setActive(false) }

    @objc private func playbackVisibilityChanged() {
        guard let current else { return }
        current.playback.setActive(visible && !pager.view.isHidden && !paging && !overlayOpen &&
                                   UIApplication.shared.applicationState == .active)
    }

    private func updateTabBarAppearance(fullBleed: Bool) {
        guard let item = navigationController?.tabBarItem else { return }
        let appearance: UITabBarAppearance?
        if fullBleed, let standard = tabBarController?.tabBar.standardAppearance.copy() as? UITabBarAppearance {
            standard.configureWithTransparentBackground()
            standard.backgroundColor = Theme.ink.withAlphaComponent(0.48)
            appearance = standard
        } else {
            appearance = nil
        }
        item.standardAppearance = appearance
        item.scrollEdgeAppearance = appearance
    }

    private func loadCatalog() {
        catalogTask?.cancel()
        showState("Loading shorts…")
        catalogTask = Task { [weak self, api] in
            do {
                let catalog = try await api.catalog()
                guard !Task.isCancelled, let self else { return }
                self.catalog = catalog.compactMap { HostedShort(item: $0, projectURL: api.configuration.url) }
                self.loaded = true
                self.applyFilters()
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.showState("Shorts could not be loaded.", retry: true)
            }
        }
    }

    private func showState(_ message: String, retry: Bool = false) {
        state.clear()
        state.isHidden = false
        pager.view.isHidden = true
        playbackVisibilityChanged()
        if visible { updateTabBarAppearance(fullBleed: false) }
        let text = Theme.label(message, color: Theme.secondary)
        text.textAlignment = .center
        state.addArrangedSubview(text)
        if retry { state.addArrangedSubview(Theme.button("Retry") { [weak self] in self?.loadCatalog() }) }
    }

    private func applyFilters() {
        guard loaded else { return }
        let previous = current?.item.id
        current?.playback.releasePlayback()
        items = catalog.filter { short in
            let item = short.item
            return (kind == nil || kind == item.kind) &&
                (query.isEmpty || "\(item.title) \(item.description) \(item.credit)".localizedCaseInsensitiveContains(query))
        }
        guard let short = items.first(where: { $0.item.id == previous }) ?? items.first else {
            showState(catalog.isEmpty ? "No shorts are available yet." : "No shorts match your search or filter.")
            return
        }
        state.isHidden = true
        pager.view.isHidden = false
        pager.setViewControllers([makePage(short)], direction: .forward, animated: false)
        if visible { updateTabBarAppearance(fullBleed: true) }
        playbackVisibilityChanged()
    }

    private func makePage(_ short: HostedShort) -> ShortsClipPage {
        let item = short.item
        let page = ShortsClipPage(short: short)
        page.react = { [weak self] kind in self?.toggle(kind, for: item) }
        page.comments = { [weak self] in
            guard let self else { return }
            self.navigationController?.pushViewController(CommentsPage(item: item, api: self.api), animated: true)
        }
        page.share = { [weak self] button in self?.share(item, from: button) }
        page.options = { [weak self] in self?.showVideoOptions(item) }
        page.openProfile = { [weak self] in
            guard let self, !self.paging else { return }
            self.navigationController?.pushViewController(ShortsPublisherPage(short: short, api: self.api), animated: true)
        }
        page.renderReactions(reactions[item.id] ?? [], busy: pending[item.id] ?? [])
        return page
    }

    private func adjacent(_ page: UIViewController, offset: Int) -> UIViewController? {
        guard let page = page as? ShortsClipPage,
              let index = items.firstIndex(where: { $0.item.id == page.item.id }),
              items.indices.contains(index + offset) else { return nil }
        return makePage(items[index + offset])
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        adjacent(viewController, offset: -1)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        adjacent(viewController, offset: 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            willTransitionTo pendingViewControllers: [UIViewController]) {
        paging = true
        playbackVisibilityChanged()
    }

    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        paging = false
        if completed, let previous = previousViewControllers.first as? ShortsClipPage {
            previous.playback.releasePlayback()
        }
        renderReactions()
        playbackVisibilityChanged()
    }

    private func refreshReactions() {
        guard pending.isEmpty else { return }
        reactionsTask?.cancel()
        reactionsTask = Task { [weak self, api] in
            guard let values = try? await api.reactions(), !Task.isCancelled, let self else { return }
            self.reactions = Dictionary(grouping: values, by: \.catalogId).mapValues { Set($0.map(\.kind)) }
            self.renderReactions()
        }
    }

    private func renderReactions() {
        guard let current else { return }
        let id = current.item.id
        current.renderReactions(reactions[id] ?? [], busy: pending[id] ?? [])
    }

    private func toggle(_ kind: String, for item: CatalogItem) {
        guard pending[item.id, default: []].insert(kind).inserted else { return }
        let enabled = !(reactions[item.id]?.contains(kind) ?? false)
        reactionsTask?.cancel()
        renderReactions()
        Task {
            defer {
                pending[item.id]?.remove(kind)
                if pending[item.id]?.isEmpty == true { pending.removeValue(forKey: item.id) }
                renderReactions()
            }
            do {
                try await api.setReaction(kind, item: item.id, enabled: enabled)
                if enabled { reactions[item.id, default: []].insert(kind) }
                else { reactions[item.id]?.remove(kind) }
            } catch { showAlert(error.localizedDescription) }
        }
    }

    private func search() {
        guard !paging else { return }
        let alert = UIAlertController(title: "Search shorts", message: nil, preferredStyle: .alert)
        alert.addTextField { [query] field in
            field.text = query
            field.font = Theme.font(17)
            field.placeholder = "Title or creator"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Search", style: .default) { [weak self, weak alert] _ in
            self?.query = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self?.applyFilters()
        })
        if !query.isEmpty {
            alert.addAction(UIAlertAction(title: "Clear search", style: .default) { [weak self] _ in
                self?.query = ""
                self?.applyFilters()
            })
        }
        present(alert, animated: true)
    }

    private func filter() {
        guard !paging else { return }
        let menu = UIAlertController(title: "Filter shorts", message: nil, preferredStyle: .actionSheet)
        menu.addAction(UIAlertAction(title: "All shorts", style: .default) { [weak self] _ in
            self?.kind = nil
            self?.applyFilters()
        })
        for kind in Set(catalog.map { $0.item.kind }).sorted() {
            menu.addAction(UIAlertAction(title: kind, style: .default) { [weak self] _ in
                self?.kind = kind
                self?.applyFilters()
            })
        }
        menu.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(menu, animated: true)
    }

    private func showVideoOptions(_ item: CatalogItem) {
        guard !paging else { return }
        let menu = UIAlertController(title: "Video options", message: nil, preferredStyle: .actionSheet)
        menu.addAction(UIAlertAction(title: "Source & license", style: .default) { [weak self] _ in
            self?.openSource(item.sourceUrl)
        })
        menu.addAction(UIAlertAction(title: "Report video", style: .destructive) { [weak self] _ in
            self?.report(item)
        })
        menu.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(menu, animated: true)
    }

    private func report(_ item: CatalogItem) {
        let menu = UIAlertController(title: "Report video", message: nil, preferredStyle: .actionSheet)
        for reason in ["Harassment", "Spam", "Inappropriate content", "Other"] {
            menu.addAction(UIAlertAction(title: reason, style: .default) { [weak self] _ in
                guard let self else { return }
                Task {
                    do {
                        try await self.api.report(["catalog_id": item.id], reason: reason)
                        self.showAlert("Your report was submitted.")
                    } catch { self.showAlert(error.localizedDescription) }
                }
            })
        }
        menu.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(menu, animated: true)
    }

    private func showAlert(_ message: String) {
        guard visible, presentedViewController == nil else { return }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    private func showCommunity() {
        navigationController?.pushViewController(CommunityWorksPage(api: api), animated: true)
    }

    private func share(_ item: CatalogItem, from button: UIView) {
        guard presentedViewController == nil else { return }
        let sheet = UIActivityViewController(activityItems: [item.sourceUrl], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = button
        sheet.popoverPresentationController?.sourceRect = button.bounds
        overlayOpen = true
        playbackVisibilityChanged()
        sheet.completionWithItemsHandler = { [weak self] _, _, _, _ in
            self?.overlayOpen = false
            self?.playbackVisibilityChanged()
        }
        present(sheet, animated: true)
    }

    private func openSource(_ url: URL) {
        guard presentedViewController == nil, url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return }
        let browser = SFSafariViewController(url: url)
        browser.delegate = self
        browser.modalPresentationStyle = .fullScreen
        overlayOpen = true
        playbackVisibilityChanged()
        present(browser, animated: true)
    }

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        overlayOpen = false
        playbackVisibilityChanged()
    }
}
