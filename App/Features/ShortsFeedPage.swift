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

private extension CatalogItem {
    var creatorName: String { credit.components(separatedBy: " · ").first ?? credit }

    var creatorPortrait: String {
        switch id {
        case "fox-costume-in-motion": return "expo-judy"
        case "narcon-conga-line": return "fan-duo"
        case "costume-meetup-hug": return "expo-nick"
        default: return "expo-duo"
        }
    }
}

private final class EditorialShortsProfile: CityPage, SafetyObserving {
    private let item: CatalogItem
    private var videos: [CatalogItem]
    private let openShort: (CatalogItem) -> Void
    private let metrics = Theme.stack(spacing: 8, axis: .horizontal)
    private let tabs = Theme.stack()
    private let gallery = Theme.stack()
    private var cosplay: [CatalogItem] = []
    private var selection = "Shorts"
    private var loadedCosplay = false
    private var loadTask: Task<Void, Never>?

    init(item: CatalogItem, videos: [CatalogItem], api: CommunityAPI, openShort: @escaping (CatalogItem) -> Void) {
        self.item = item
        self.videos = videos
        self.openShort = openShort
        super.init("Creator", api: api)
    }

    required init?(coder: NSCoder) { nil }

    func safetyDidChange() {
        videos.removeAll { api.isHidden($0) }
        cosplay.removeAll { api.isHidden($0) }
        showMetrics(videos.compactMap { api.cachedShortCount($0.id) })
        renderWorks()
        reload()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeSafetyChanges()
        let name = Theme.label(item.creatorName, size: 26, display: true)
        let bio = Theme.label("An editorial collection of credited films and costume work.", color: Theme.secondary)
        let identity = Theme.stack([MemberAvatar.view(item.creatorPortrait, size: 70), Theme.stack([name, bio], spacing: 4)], axis: .horizontal)
        identity.alignment = .center
        metrics.distribution = .fillEqually
        body.addArrangedSubview(Theme.card([identity, metrics]))
        let portraitCredit = item.creatorPortrait == "fan-duo" ? MemberAvatar.fanCredit : MemberAvatar.credit
        body.addArrangedSubview(Theme.textAction("Source and portrait credits") { [weak self] in
            guard let self else { return }
            var choices: [(String, UIAlertAction.Style, () -> Void)] = [
                ("Original video", .default, { [weak self, source = self.item.sourceUrl] in self?.open(source) })
            ]
            if let portraitCredit {
                choices.append(("Cosplay portrait", .default, { [weak self] in self?.open(portraitCredit) }))
            }
            self.menu("Credits", choices: choices)
        })
        body.addArrangedSubview(tabs)
        body.addArrangedSubview(gallery)
        showMetrics(videos.compactMap { api.cachedShortCount($0.id) })
        renderWorks()
        enableRefresh { [weak self] in self?.reload() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        loadTask?.cancel()
        loadTask = Task { [weak self, api] in
            guard let self else { return }
            do {
                let catalog = try await api.catalog()
                let hosted = catalog.filter { $0.publisherId == nil && $0.creatorName == item.creatorName &&
                    HostedShort(item: $0, projectURL: api.configuration.url) != nil }
                let rows = try await api.shortCounts(hosted.map(\.id))
                try Task.checkCancellation()
                videos = hosted
                showMetrics(rows)
                let hostedIDs = Set(hosted.map(\.id))
                cosplay = catalog.filter { $0.publisherId == nil && $0.creatorName == item.creatorName &&
                    ($0.kind == "Cosplay Look" || $0.kind == "Cosplay Video") && !hostedIDs.contains($0.id) }
                loadedCosplay = true
                renderWorks()
                pageRefresh.finish()
            } catch {
                guard !Task.isCancelled else { return }
                pageRefresh.finish(error: "This creator could not be updated. Pull down to try again.")
            }
        }
    }

    private func showMetrics(_ rows: [ShortCounts]?) {
        metrics.clear()
        let complete = rows.flatMap { $0.count == videos.count ? $0 : nil }
        metrics.addArrangedSubview(profileStat(complete?.reduce(0) { $0 + $1.likes }, title: "Likes"))
        metrics.addArrangedSubview(profileStat(complete?.reduce(0) { $0 + $1.saves }, title: "Saves"))
        metrics.addArrangedSubview(profileStat(0, title: "Following"))
        if complete?.contains(where: { $0.isLimited == true }) == true {
            showStatus("Counts include estimates and available Sese activity.")
        } else {
            let estimates = complete?.contains(where: \.editorialBaseline) == true
            showStatus(estimates ? "Counts include editorial estimates." : nil)
        }
    }

    private func renderWorks() {
        tabs.clear()
        tabs.addArrangedSubview(profileTabs(["Shorts", "Cosplay"], selected: selection) { [weak self] name in
            self?.selection = name
            self?.renderWorks()
        })
        gallery.clear()
        let shown = selection == "Shorts" ? videos : cosplay
        guard !shown.isEmpty else {
            let message = loadedCosplay ? "No other cosplay work is credited here." : "Cosplay work is unavailable."
            gallery.addArrangedSubview(Theme.label(message, color: Theme.secondary))
            return
        }
        addVideoTiles(shown, to: gallery, accessible: traitCollection.preferredContentSizeCategory.isAccessibilityCategory) { [weak self] item in
            guard let self else { return }
            if self.selection == "Shorts" { self.openShort(item) }
            else if let index = shown.firstIndex(where: { $0.id == item.id }) {
                self.push(CatalogDetail(items: shown, index: index, api: self.api))
            }
        }
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
        let avatar = MemberAvatar.button(item.creatorPortrait, size: Theme.iconSize, label: "Open \(item.creatorName)’s creator profile") {
            [weak self] in self?.openProfile?()
        }
        avatar.accessibilityIdentifier = "shorts.creator"

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
        let actions = Theme.stack([avatar] + actionRows + [more], spacing: 5)
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
    private var loaded = false
    private var current: ShortsClipPage? { pager.viewControllers?.first as? ShortsClipPage }

    init(api: CommunityAPI) {
        self.api = api
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    func returnFromCreatorProfileIfNeeded() {
        guard let navigationController,
              let openedPage = navigationController.viewControllers.dropFirst().first,
              openedPage is EditorialShortsProfile || openedPage is ProfilePage else { return }
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
            guard let self, !self.paging else { return }
            if let id = item.publisherId {
                self.navigationController?.pushViewController(ProfilePage(memberID: id, api: self.api), animated: true)
            } else {
                self.showEditorialProfile(item)
            }
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
        // Pulling the discussion refreshes it; Done closes the sheet.
        navigation.isModalInPresentation = true
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.medium()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        present(navigation, animated: true)
    }

    private func showEditorialProfile(_ item: CatalogItem) {
        let videos = catalog.map(\.item).filter { $0.publisherId == nil && $0.creatorName == item.creatorName }
        let profile = EditorialShortsProfile(item: item, videos: videos, api: api) { [weak self] item in
            guard let self else { return }
            if let kind = self.kind, kind != item.kind { self.kind = nil }
            self.applyFilters(preferredID: item.id)
            self.navigationController?.popToViewController(self, animated: true)
        }
        navigationController?.pushViewController(profile, animated: true)
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
        if let publisher = item.publisherId, publisher != api.memberID {
            menu.addAction(UIAlertAction(title: "Block author", style: .destructive) { [weak self] _ in
                guard let self else { return }
                self.confirmMemberBlock(publisher, api: self.api)
            })
        }
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
