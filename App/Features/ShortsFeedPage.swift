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

private final class ShortsAction: UIButton {
    private let art = UIImageView()
    private let fallback = Theme.label("", size: 12, display: true)
    private var artworkKey: String?
    let count = Theme.label("—", size: 13, display: true)

    init(size: CGFloat, action: @escaping (UIView) -> Void) {
        super.init(frame: .zero)
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
        art.contentMode = .scaleAspectFit
        fallback.textAlignment = .center
        for view in [art, fallback] as [UIView] {
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            art.centerXAnchor.constraint(equalTo: centerXAnchor), art.centerYAnchor.constraint(equalTo: centerYAnchor),
            art.widthAnchor.constraint(equalToConstant: Theme.iconSize), art.heightAnchor.constraint(equalToConstant: Theme.iconSize),
            fallback.leadingAnchor.constraint(equalTo: leadingAnchor), fallback.trailingAnchor.constraint(equalTo: trailingAnchor),
            fallback.topAnchor.constraint(equalTo: topAnchor), fallback.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        count.textAlignment = .center
        count.isAccessibilityElement = false
        addAction(UIAction { [weak self] _ in
            if let self { action(self) }
        }, for: .touchUpInside)
    }

    required init?(coder: NSCoder) { nil }

    func render(icon: String, label: String, total: Int?, selected: Bool = false, enabled: Bool = true) {
        accessibilityLabel = label
        accessibilityValue = total.map { $0.formatted() } ?? "Count unavailable"
        accessibilityTraits = selected ? [.button, .selected] : .button
        isEnabled = enabled
        isSelected = selected
        count.text = total.map { $0.formatted() } ?? "—"
        fallback.text = label
        guard artworkKey != icon else { return }
        artworkKey = icon
        if let image = Artwork.iconImage(icon) {
            art.image = image
            fallback.isHidden = true
            return
        }
        art.image = nil
        fallback.isHidden = false
        Task { [weak self] in
            let image = await Artwork.image(icon)
            guard let self, self.artworkKey == icon else { return }
            self.art.image = image
            self.fallback.isHidden = image != nil
            if image == nil { self.artworkKey = nil }
        }
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
    private var like: ShortsAction!
    private var save: ShortsAction!
    private var commentAction: ShortsAction!
    private var shareAction: ShortsAction!
    private var baselineLabel: UILabel!

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
        let actionSize = Theme.iconTouchSize
        let credit = Theme.label(item.credit, size: 15, display: true)
        credit.numberOfLines = 2
        let title = Theme.label(item.title, size: 22, display: true)
        title.numberOfLines = 2
        title.accessibilityTraits.insert(.header)
        title.accessibilityIdentifier = "shorts.title"
        let caption = Theme.label(item.description, size: 14, color: Theme.paper)
        caption.numberOfLines = 2
        let baseline = Theme.label("", size: 12, color: Theme.paper)
        baseline.isHidden = true
        baselineLabel = baseline
        let metadata = Theme.stack([credit, title, caption, baseline], spacing: 4)
        let more = Theme.moreIcon(label: "Video options") { [weak self] in self?.options?() }

        like = ShortsAction(size: actionSize) { [weak self] _ in self?.react?("like") }
        like.accessibilityIdentifier = "shorts.like"
        save = ShortsAction(size: actionSize) { [weak self] _ in self?.react?("save") }
        save.accessibilityIdentifier = "shorts.save"
        commentAction = ShortsAction(size: actionSize) { [weak self] _ in self?.comments?() }
        commentAction.accessibilityIdentifier = "shorts.comments"
        shareAction = ShortsAction(size: actionSize) { [weak self] view in self?.share?(view) }
        shareAction.accessibilityIdentifier = "shorts.share"
        let counted: [ShortsAction] = [like, commentAction, save, shareAction]
        let actionRows: [UIView] = counted.map { Theme.stack([$0, $0.count], spacing: 0) }
        let actions = Theme.stack(spacing: 5)
        if let publisherID = item.publisherId {
            let label = item.publisher.map { "Open \($0.displayName)’s profile" } ?? "Open publisher profile"
            let avatar = MemberAvatar.button(item.publisher?.avatar, size: Theme.iconSize, label: label, memberID: publisherID) {
                [weak self] in self?.openProfile?()
            }
            avatar.accessibilityIdentifier = "shorts.publisher"
            actions.addArrangedSubview(avatar)
        }
        for row in actionRows { actions.addArrangedSubview(row) }
        actions.addArrangedSubview(more)
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

    func renderEngagement(_ reactions: Set<String>, counts: ShortCounts?, busy: Set<String>, ready: Bool) {
        loadViewIfNeeded()
        let liked = reactions.contains("like")
        let saved = reactions.contains("save")
        like.render(icon: liked ? "like" : "like-outline", label: liked ? "Liked" : "Like", total: counts?.likes,
                    selected: liked, enabled: ready && busy.isEmpty)
        save.render(icon: saved ? "save" : "save-outline", label: saved ? "Saved" : "Save", total: counts?.saves,
                    selected: saved, enabled: ready && busy.isEmpty)
        commentAction.render(icon: "comments", label: "Comments", total: counts?.comments)
        shareAction.render(icon: "share", label: "Share", total: counts?.shares)
        if counts?.isLimited == true {
            baselineLabel.text = counts?.editorialBaseline == true ? "Estimates + available activity" : "Available Sese activity"
        } else {
            baselineLabel.text = "Counts include editorial estimates"
        }
        baselineLabel.isHidden = counts?.isLimited != true && counts?.editorialBaseline != true
    }
}

final class ShortsFeedPage: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate,
                            SFSafariViewControllerDelegate, UIGestureRecognizerDelegate {
    private let api: CommunityAPI
    private let pager = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .vertical)
    private let state = Theme.stack()
    private let pageRefresh = PageRefresh()
    private var pullTask: Task<Void, Never>?
    private var pendingPullShuffle: Bool?
    private lazy var pullGesture = UIPanGestureRecognizer(target: self, action: #selector(pulledToRefresh(_:)))
    private var catalog: [HostedShort] = []
    private var items: [HostedShort] = []
    private var seenClipIDs: Set<String> = []
    private var reactions: [String: Set<String>] = [:]
    private var pending: [String: Set<String>] = [:]
    private var catalogTask: Task<Void, Never>?
    private var reactionsTask: Task<Void, Never>?
    private var countsTask: Task<Void, Never>?
    private var visibleCatalogTask: Task<Void, Never>?
    private var reactionsReady = false
    private let normalHeader = Theme.stack(spacing: 8, axis: .horizontal)
    private let searchHeader = Theme.stack(spacing: 8, axis: .horizontal)
    private let searchField = Theme.field("Search shorts")
    private weak var searchButton: UIButton?
    private let searchPanel = ContentScrollView()
    private let searchContent = Theme.stack(spacing: 12)
    private var searchScope = "All"
    private var searching = false
    private var kind: String?
    private var visible = false
    private var paging = false
    private var overlayOpen = false
    private var returningDiscussion: (navigation: UINavigationController, item: CatalogItem,
                                      height: UISheetPresentationController.Detent.Identifier)?
    private var loaded = false
    private var current: ShortsClipPage? { pager.viewControllers?.first as? ShortsClipPage }

    init(api: CommunityAPI) {
        self.api = api
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    func returnFromProfileIfNeeded() {
        guard let navigationController,
              let openedPage = navigationController.viewControllers.dropFirst().first,
              openedPage is ProfilePage else { return }
        navigationController.popToRootViewController(animated: false)
    }

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
        let search = Theme.icon("search", label: "Search shorts") { [weak self] in self?.search() }
        searchButton = search
        for control in [
            title,
            search,
            Theme.icon("filter", label: "Filter shorts") { [weak self] in self?.filter() },
            Theme.icon("shorts", label: "Community videos") { [weak self] in self?.showCommunity() }
        ] as [UIView] { normalHeader.addArrangedSubview(control) }
        normalHeader.alignment = .center
        let header = Theme.stack([normalHeader, searchHeader], spacing: 0)
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

        state.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(state)
        view.addSubview(header)
        configureSearch(below: header)
        pageRefresh.install(on: searchPanel) { [weak self] in self?.reloadFromPull() }
        pullGesture.delegate = self
        pullGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(pullGesture)
        pager.view.subviews.compactMap { $0 as? UIScrollView }.first?
            .panGestureRecognizer.require(toFail: pullGesture)
        let refreshFeedback = pageRefresh.feedback
        refreshFeedback.textAlignment = .center
        refreshFeedback.backgroundColor = Theme.ink.withAlphaComponent(0.75)
        header.addArrangedSubview(refreshFeedback)
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
        NotificationCenter.default.addObserver(self, selector: #selector(safetyChanged(_:)),
                                               name: CommunityAPI.safetyChanged, object: nil)
        loadCatalog()
    }

    @objc private func safetyChanged(_ notification: Notification) {
        guard (notification.object as? CommunityAPI) === api else { return }
        catalogTask?.cancel()
        visibleCatalogTask?.cancel()
        pullTask?.cancel()
        pendingPullShuffle = nil
        pageRefresh.cancel()
        let previousCount = catalog.count
        let currentIndex = items.firstIndex { $0.item.id == current?.item.id } ?? 0
        let successor = items.dropFirst(currentIndex).first { !api.isHidden($0.item) }
        catalog.removeAll { api.isHidden($0.item) }
        if previousCount != catalog.count {
            applyFilters(preferredID: successor?.item.id)
            renderSearchResults()
        }
        // Blocking a commenter changes counts even for clips published by someone else.
        renderReactions()
        refreshCounts()
        if loaded { refreshVisibleCatalog() } else { loadCatalog() }
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
        refreshCounts()
        if loaded { refreshVisibleCatalog() }
        playbackVisibilityChanged()
        if let discussion = returningDiscussion {
            returningDiscussion = nil
            if !api.isHidden(discussion.item), presentedViewController == nil {
                presentComments(discussion.navigation, height: discussion.height)
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        visible = false
        pullTask?.cancel()
        pendingPullShuffle = nil
        pageRefresh.cancel()
        updateTabBarAppearance(fullBleed: false)
        playbackVisibilityChanged()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pullGesture else { return true }
        let velocity = pullGesture.velocity(in: view)
        let startY = pullGesture.location(in: view).y
        guard presentedViewController == nil, !searching, !paging, !overlayOpen, !pageRefresh.isRefreshing,
              velocity.y > abs(velocity.x), startY > view.safeAreaInsets.top + 60 else { return false }
        // A deliberate pull refreshes any page. A quick downward flick can still go back.
        return current?.item.id == items.first?.item.id || velocity.y < 1_200
    }

    @objc private func pulledToRefresh(_ gesture: UIPanGestureRecognizer) {
        let distance = gesture.translation(in: view).y
        if gesture.state == .changed && !pageRefresh.isRefreshing {
            pageRefresh.feedback.isHidden = false
            pageRefresh.feedback.text = distance >= 80 ? "Release to refresh" : "Pull down to refresh"
        } else if gesture.state == .ended {
            if distance >= 80 { pageRefresh.begin() }
            else { pageRefresh.feedback.isHidden = true }
        } else if gesture.state == .cancelled || gesture.state == .failed {
            if !pageRefresh.isRefreshing { pageRefresh.feedback.isHidden = true }
        }
    }

    private func reloadFromPull() {
        guard pending.isEmpty else {
            pageRefresh.finish(error: "Wait for your reaction to finish, then pull down again.")
            return
        }
        catalogTask?.cancel()
        visibleCatalogTask?.cancel()
        reactionsTask?.cancel()
        countsTask?.cancel()
        pullTask?.cancel()
        pendingPullShuffle = nil
        let reorderFeed = !searching
        pullTask = Task { [weak self, api] in
            guard let self else { return }
            do {
                async let fetchedCatalog = api.catalog()
                async let fetchedReactions = api.reactions()
                let (rows, values) = try await (fetchedCatalog, fetchedReactions)
                let updated = rows.compactMap { HostedShort(item: $0, projectURL: api.configuration.url) }
                _ = try await api.shortCounts(updated.map { $0.item.id })
                try Task.checkCancellation()
                guard pageRefresh.isRefreshing else { return }
                catalog = updated
                loaded = true
                reactions = Dictionary(grouping: values, by: \.catalogId).mapValues { Set($0.map(\.kind)) }
                reactionsReady = true
                pendingPullShuffle = reorderFeed
                finishPullWhenSettled()
            } catch {
                guard !Task.isCancelled else { return }
                pageRefresh.finish(error: "Shorts could not be updated. Pull down to try again.")
            }
        }
    }

    private func finishPullWhenSettled() {
        guard !paging, let shuffle = pendingPullShuffle else { return }
        pendingPullShuffle = nil
        guard pageRefresh.isRefreshing else { return }
        applyFilters(shuffle: shuffle)
        renderReactions()
        renderSearchResults()
        pageRefresh.finish()
    }

    @objc private func willResignActive() { current?.playback.setActive(false) }

    @objc private func playbackVisibilityChanged() {
        guard let current else { return }
        current.playback.setActive(!api.isHidden(current.item) && visible && !pager.view.isHidden && !paging && !overlayOpen && !searching &&
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
                self.refreshCounts()
                self.renderSearchResults()
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

    private func applyFilters(preferredID: String? = nil, shuffle: Bool = false) {
        guard loaded else { return }
        let previous = current?.item
        let previousOrder = items.map { $0.item.id }
        let eligible = catalog.filter { !api.isHidden($0.item) && (kind == nil || kind == $0.item.kind) }
        seenClipIDs.formIntersection(catalog.map { $0.item.id })
        if shuffle {
            if eligible.allSatisfy({ seenClipIDs.contains($0.item.id) }) {
                seenClipIDs.subtract(eligible.map { $0.item.id })
                if let previous { seenClipIDs.insert(previous.id) }
            }
            let shuffled = eligible.shuffled()
            items = shuffled.filter { !seenClipIDs.contains($0.item.id) } +
                shuffled.filter { seenClipIDs.contains($0.item.id) }
        } else {
            // Keep the playback order across background reloads and append newly eligible clips.
            var fresh = Dictionary(uniqueKeysWithValues: eligible.map { ($0.item.id, $0) })
            items = previousOrder.compactMap { fresh.removeValue(forKey: $0) } +
                eligible.filter { fresh[$0.item.id] != nil }
        }
        let selectedID = shuffle ? items.first?.item.id : (preferredID ?? previous?.id)
        guard let short = items.first(where: { $0.item.id == selectedID }) ?? items.first else {
            current?.playback.releasePlayback()
            showState(catalog.isEmpty ? "No shorts are available yet." : "No shorts match your search or filter.")
            return
        }
        seenClipIDs.insert(short.item.id)
        if !pager.view.isHidden, short.item == previous, previousOrder == items.map({ $0.item.id }) { return }
        current?.playback.releasePlayback()
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
            self.showComments(item)
        }
        page.share = { [weak self] button in self?.share(item, from: button) }
        page.options = { [weak self] in self?.showVideoOptions(item) }
        page.openProfile = { [weak self] in
            guard let self, !self.paging, let id = item.publisherId else { return }
            self.navigationController?.pushViewController(ProfilePage(memberID: id, api: self.api), animated: true)
        }
        page.renderEngagement(reactions[item.id] ?? [], counts: api.cachedShortCount(item.id), busy: pending[item.id] ?? [], ready: reactionsReady)
        return page
    }

    private func adjacent(_ page: UIViewController, offset: Int) -> UIViewController? {
        guard let page = page as? ShortsClipPage,
              items.count > 1,
              let index = items.firstIndex(where: { $0.item.id == page.item.id }) else { return nil }
        let next = (index + offset) % items.count
        guard next >= 0 else { return nil }
        return makePage(items[next])
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
        if let current {
            if api.isHidden(current.item) { applyFilters() }
            else if completed { seenClipIDs.insert(current.item.id) }
        }
        finishPullWhenSettled()
        renderReactions()
        playbackVisibilityChanged()
    }

    private func refreshReactions() {
        guard pending.isEmpty else { return }
        reactionsTask?.cancel()
        reactionsTask = Task { [weak self, api] in
            guard let values = try? await api.reactions(), !Task.isCancelled, let self else { return }
            self.reactions = Dictionary(grouping: values, by: \.catalogId).mapValues { Set($0.map(\.kind)) }
            self.reactionsReady = true
            self.renderReactions()
            self.renderSearchResults()
        }
    }

    private func renderReactions() {
        guard let current else { return }
        let id = current.item.id
        current.renderEngagement(reactions[id] ?? [], counts: api.cachedShortCount(id), busy: pending[id] ?? [], ready: reactionsReady)
    }

    private func toggle(_ kind: String, for item: CatalogItem) {
        guard reactionsReady, pending[item.id]?.isEmpty != false else { return }
        pending[item.id] = [kind]
        let enabled = !(reactions[item.id]?.contains(kind) ?? false)
        reactionsTask?.cancel()
        countsTask?.cancel()
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
                if api.cachedShortCount(item.id)?.isLimited != true {
                    _ = try? await api.shortCounts([item.id])
                }
            } catch { showAlert(error.localizedDescription) }
        }
    }

    private func configureSearch(below header: UIView) {
        searchField.returnKeyType = .search
        searchField.clearButtonMode = .whileEditing
        searchField.addAction(UIAction { [weak self] _ in self?.renderSearchResults() }, for: .editingChanged)
        searchField.addAction(UIAction { [weak self] _ in self?.searchField.resignFirstResponder() }, for: .editingDidEndOnExit)
        searchHeader.alignment = .center
        searchHeader.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        searchHeader.addArrangedSubview(searchField)
        searchHeader.addArrangedSubview(Theme.textAction("Cancel") { [weak self] in self?.setSearchOpen(false) })
        searchHeader.isHidden = true
        searchPanel.isHidden = true
        searchPanel.alpha = 0
        searchPanel.backgroundColor = Theme.ink.withAlphaComponent(0.76)
        searchPanel.keyboardDismissMode = .onDrag
        searchPanel.accessibilityIdentifier = "shorts.search.results"
        searchPanel.translatesAutoresizingMaskIntoConstraints = false
        searchContent.translatesAutoresizingMaskIntoConstraints = false
        view.insertSubview(searchPanel, belowSubview: header)
        searchPanel.addSubview(searchContent)
        NSLayoutConstraint.activate([
            searchPanel.topAnchor.constraint(equalTo: header.bottomAnchor),
            searchPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            searchPanel.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            searchContent.topAnchor.constraint(equalTo: searchPanel.contentLayoutGuide.topAnchor, constant: 10),
            searchContent.bottomAnchor.constraint(equalTo: searchPanel.contentLayoutGuide.bottomAnchor, constant: -14),
            searchContent.leadingAnchor.constraint(equalTo: searchPanel.contentLayoutGuide.leadingAnchor, constant: 16),
            searchContent.trailingAnchor.constraint(equalTo: searchPanel.contentLayoutGuide.trailingAnchor, constant: -16),
            searchContent.widthAnchor.constraint(equalTo: searchPanel.frameLayoutGuide.widthAnchor, constant: -32)
        ])
    }

    private func search() {
        guard !paging else { return }
        setSearchOpen(true)
    }

    private func setSearchOpen(_ open: Bool) {
        guard open != searching else { return }
        let origin = searchButton.map { $0.convert($0.bounds, to: view) }
        searching = open
        pager.view.isUserInteractionEnabled = !open
        pager.view.accessibilityElementsHidden = open
        state.accessibilityElementsHidden = open
        let animated = !UIAccessibility.isReduceMotionEnabled
        if open {
            normalHeader.isHidden = true
            searchHeader.isHidden = false
            searchPanel.isHidden = false
            renderSearchResults()
            view.layoutIfNeeded()
            if animated, let origin, searchField.bounds.width > origin.width {
                let destination = searchField.convert(searchField.bounds, to: view)
                searchField.transform = CGAffineTransform(translationX: origin.midX - destination.midX,
                                                          y: origin.midY - destination.midY)
                    .scaledBy(x: origin.width / destination.width, y: 1)
            }
            searchField.becomeFirstResponder()
        } else {
            searchField.resignFirstResponder()
            searchField.text = nil
            searchScope = "All"
            searchHeader.isHidden = true
            normalHeader.isHidden = false
        }
        UIView.animate(withDuration: animated ? 0.24 : 0, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.searchField.transform = .identity
            self.searchPanel.alpha = open ? 1 : 0
            self.pager.view.alpha = open ? 0.5 : 1
            self.view.layoutIfNeeded()
        } completion: { _ in
            if self.searching == open { self.searchPanel.isHidden = !open }
        }
        playbackVisibilityChanged()
    }

    private func renderSearchResults() {
        guard searching else { return }
        searchContent.clear()
        let categories = ["All", "Film Clip", "Cosplay Video", "Saved"]
        let names = ["All", "Clips", "Cosplay", "Saved"]
        let filters = Theme.stack(zip(categories, names).map { scope, name in
            Theme.button(name, accent: searchScope == scope) { [weak self] in
                self?.searchScope = scope
                self?.renderSearchResults()
            }
        }, spacing: 5, axis: traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal)
        filters.distribution = .fillEqually
        searchContent.addArrangedSubview(filters)
        let query = searchField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let matches = catalog.filter { short in
            let item = short.item
            let inScope = searchScope == "All" || searchScope == item.kind ||
                (searchScope == "Saved" && reactions[item.id]?.contains("save") == true)
            return inScope && (query.isEmpty || "\(item.title) \(item.description) \(item.credit)".localizedCaseInsensitiveContains(query))
        }
        guard !matches.isEmpty else {
            searchContent.addArrangedSubview(Theme.empty(loaded ? "No matching shorts" : "Shorts are unavailable",
                                                         loaded ? "Try another search or category." : "Return to Shorts and try again."))
            return
        }
        addVideoTiles(matches.map(\.item), to: searchContent, accessible: traitCollection.preferredContentSizeCategory.isAccessibilityCategory) { [weak self] item in
            guard let self else { return }
            if let kind = self.kind, kind != item.kind { self.kind = nil }
            self.applyFilters(preferredID: item.id)
            self.setSearchOpen(false)
        }
    }

    private func showComments(_ item: CatalogItem) {
        guard !paging, presentedViewController == nil else { return }
        let page = CommentsPage(item: item, api: api, sheet: true) {
            [weak self] in self?.refreshCounts()
        }
        let navigation = UINavigationController(rootViewController: page)
        navigation.setNavigationBarHidden(true, animated: false)
        navigation.modalPresentationStyle = .pageSheet
        navigation.isModalInPresentation = true
        page.openAuthorProfile = { [weak self, weak navigation] profile in
            guard let self, let navigation, !navigation.isBeingDismissed,
                  let host = self.navigationController, host.topViewController === self else { return }
            let height = navigation.sheetPresentationController?.selectedDetentIdentifier ?? .medium
            navigation.dismiss(animated: true) { [weak self] in
                guard let self, host.topViewController === self, !self.api.isHidden(item) else { return }
                self.returningDiscussion = (navigation, item, height)
                profile.hidesBottomBarWhenPushed = true
                host.pushViewController(profile, animated: true)
            }
        }
        presentComments(navigation, height: .medium)
    }

    private func presentComments(_ navigation: UINavigationController, height: UISheetPresentationController.Detent.Identifier) {
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = height
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        }
        present(navigation, animated: true)
    }

    private func refreshCounts() {
        let ids = catalog.map { $0.item.id }
        countsTask?.cancel()
        guard !ids.isEmpty else { return }
        countsTask = Task { [weak self, api] in
            guard (try? await api.shortCounts(ids)) != nil, let self, !Task.isCancelled else { return }
            self.renderReactions()
        }
    }

    private func refreshVisibleCatalog() {
        visibleCatalogTask?.cancel()
        visibleCatalogTask = Task { [weak self, api] in
            guard let self, let rows = try? await api.catalog(), !Task.isCancelled else { return }
            let updated = rows.compactMap { HostedShort(item: $0, projectURL: api.configuration.url) }
            let oldIDs = self.catalog.map { $0.item.id }
            self.catalog = updated
            self.applyFilters()
            if oldIDs != updated.map({ $0.item.id }) { self.refreshCounts() }
            self.renderSearchResults()
        }
    }

    private func filter() {
        guard !paging else { return }
        let menu = ThemedDialog(title: "Filter shorts", message: nil, preferredStyle: .actionSheet)
        menu.addChoice("All shorts", style: .default) { [weak self] in
            self?.kind = nil
            self?.applyFilters()
        }
        for kind in Set(catalog.map { $0.item.kind }).sorted() {
            menu.addChoice(kind, style: .default) { [weak self] in
                self?.kind = kind
                self?.applyFilters()
            }
        }
        menu.addChoice("Cancel", style: .cancel)
        present(menu, animated: true)
    }

    private func showVideoOptions(_ item: CatalogItem) {
        guard !paging else { return }
        let menu = ThemedDialog(title: "Video options", message: nil, preferredStyle: .actionSheet)
        menu.addChoice("Source & license", style: .default) { [weak self] in
            self?.openSource(item.sourceUrl)
        }
        if item.publisherId == nil || item.publisherId != api.memberID {
            menu.addChoice("Report video", style: .destructive) { [weak self] in
                guard let self else { return }
                self.chooseReportReason(["catalog_id": item.id], api: self.api, subject: "video", detail: item.title)
            }
        }
        if let peer = item.publisherId {
            for (title, style, action) in authorOptions(peer, name: item.publisher?.displayName, source: "catalog:" + item.id, api: api) {
                menu.addChoice(title, style: style) { action() }
            }
        }
        menu.addChoice("Cancel", style: .cancel)
        present(menu, animated: true)
    }

    private func showAlert(_ message: String) {
        guard visible, presentedViewController == nil else { return }
        let alert = ThemedDialog(title: nil, message: message, preferredStyle: .alert)
        alert.addChoice("OK", style: .default)
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
        let event = UUID()
        sheet.completionWithItemsHandler = { [weak self] _, completed, _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.overlayOpen = false
                self.playbackVisibilityChanged()
                guard completed else { return }
                do {
                    try await self.api.recordShortShare(item.id, event: event)
                    self.refreshCounts()
                } catch { self.showAlert("Your share finished, but the count could not be updated.") }
            }
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
