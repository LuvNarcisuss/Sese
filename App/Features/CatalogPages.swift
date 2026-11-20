import UIKit
import AVKit
import AVFoundation

enum CatalogSection {
    case districts, cosplay

    var title: String {
        switch self {
        case .districts: return "Districts"
        case .cosplay: return "Cosplay"
        }
    }

    var subtitle: String {
        switch self {
        case .districts: return "Explore the city's neighborhoods."
        case .cosplay: return "Costumes from the convention floor."
        }
    }

    var filters: [String] {
        switch self {
        case .districts: return ["All", "Saved"]
        case .cosplay: return ["All", "Cosplay Look", "Cosplay Video", "Community", "My posts"]
        }
    }

    func includes(_ item: CatalogItem) -> Bool {
        switch self {
        case .districts: return item.kind == "District"
        case .cosplay: return item.kind == "Cosplay Look" || item.kind == "Cosplay Video"
        }
    }
}

@MainActor
protocol SafetyObserving: AnyObject {
    func safetyDidChange()
}

extension UIViewController {
    private func safetyPresenter() -> UIViewController {
        if let presented = presentedViewController, !presented.isBeingDismissed { return presented.safetyPresenter() }
        if let tab = self as? UITabBarController, let selected = tab.selectedViewController { return selected.safetyPresenter() }
        if let navigation = self as? UINavigationController, let top = navigation.topViewController { return top.safetyPresenter() }
        return self
    }

    private func showSafetyResult(_ title: String, api: CommunityAPI, actor: UUID, message: String? = nil, retry: (() -> Void)? = nil) {
        Task { @MainActor [weak self] in
            // A committed write may close its detail page or finish while another dialog is visible.
            while let self, api.memberID == actor {
                let host = self.safetyPresenter()
                guard host.viewIfLoaded?.window != nil || self.viewIfLoaded?.window != nil else { return }
                if host.viewIfLoaded?.window != nil, host.transitionCoordinator == nil,
                   host.presentedViewController == nil, !(host is ThemedDialog), !(host is UIAlertController) {
                    let result = ThemedDialog(title: title, message: message, preferredStyle: .alert)
                    if let retry {
                        result.addChoice("Retry", style: .default) { retry() }
                    }
                    result.addChoice(retry == nil ? "OK" : "Cancel", style: .cancel)
                    host.present(result, animated: true)
                    return
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    func chooseReportReason(_ target: [String: String], api: CommunityAPI, subject: String, detail: String, video: Bool = true) {
        guard let root = view.window?.rootViewController, let actor = api.memberID else { return }
        let requestID = UUID()
        func submit(_ reason: String) {
            guard api.memberID == actor else { return }
            Task { @MainActor in
                do {
                    try await api.report(target, reason: reason, video: video, requestID: requestID)
                    guard api.memberID == actor else { return }
                    root.showSafetyResult("\(subject.capitalized) reported.", api: api, actor: actor, message: detail)
                } catch {
                    guard api.memberID == actor else { return }
                    root.showSafetyResult("Could not report \(subject)", api: api, actor: actor, message: detail + "\n\n" + error.localizedDescription) { submit(reason) }
                }
            }
        }
        let menu = ThemedDialog(title: "Report \(subject)", message: detail, preferredStyle: .actionSheet)
        for reason in ["Harassment", "Spam", "Inappropriate content", "Other"] {
            menu.addChoice(reason, style: .default) { submit(reason) }
        }
        menu.addChoice("Cancel", style: .cancel)
        present(menu, animated: true)
    }

    func confirmMemberBlock(_ peer: UUID, name: String?, api: CommunityAPI, source: String? = nil) {
        guard let root = view.window?.rootViewController, let actor = api.memberID else { return }
        let navigation = navigationController
        let member = name ?? "this member"
        let blockedMessage = name.map { "\($0)’s posts and comments are now hidden." } ?? "This member’s posts and comments are now hidden."
        let prompt = ThemedDialog(title: "Block \(member)?", message: "Their posts and comments will be hidden.",
                                       preferredStyle: .alert)
        prompt.addChoice("Cancel", style: .cancel)
        prompt.addChoice("Block", style: .destructive) {
            Task { @MainActor in
                guard api.memberID == actor else { return }
                do {
                    try await api.blockMember(peer, source: source)
                    guard api.memberID == actor else { return }
                    if let navigation, navigation.topViewController === self {
                        if navigation.viewControllers.count > 1 { navigation.popViewController(animated: false) }
                        else if navigation.presentingViewController != nil {
                            navigation.dismiss(animated: true) { root.showSafetyResult("User blocked.", api: api, actor: actor, message: blockedMessage) }
                            return
                        }
                    }
                    root.showSafetyResult("User blocked.", api: api, actor: actor, message: blockedMessage)
                } catch {
                    guard api.memberID == actor else { return }
                    root.showSafetyResult("Could not block \(member)", api: api, actor: actor, message: error.localizedDescription)
                }
            }
        }
        present(prompt, animated: true)
    }

    func reportMember(_ peer: UUID, name: String?, source: String?, api: CommunityAPI) {
        var target = ["reported_id": peer.uuidString]
        target["source_key"] = source
        let detail = (name ?? "Private member") + "\n\nTo hide this user's posts and comments, choose Block."
        chooseReportReason(target, api: api, subject: "user", detail: detail)
    }

    func authorOptions(_ peer: UUID, name: String?, source: String?, api: CommunityAPI) -> [(String, UIAlertAction.Style, () -> Void)] {
        guard peer != api.memberID else { return [] }
        return [
            ("Report author", .destructive, { [weak self] in self?.reportMember(peer, name: name, source: source, api: api) }),
            ("Block author", .destructive, { [weak self] in self?.confirmMemberBlock(peer, name: name, api: api, source: source) })
        ]
    }
}

extension CityPage {
    func observeSafetyChanges() {
        NotificationCenter.default.addObserver(self, selector: #selector(receiveSafetyChange(_:)),
                                               name: CommunityAPI.safetyChanged, object: nil)
    }

    @objc private func receiveSafetyChange(_ notification: Notification) {
        guard (notification.object as? CommunityAPI) === api else { return }
        (self as? SafetyObserving)?.safetyDidChange()
    }

    // Remove a detail even when it sits underneath another tab or a presented player.
    func closeHiddenContent() {
        body.isHidden = true
        actions.isHidden = true
        view.endEditing(true)
        if let player = presentedViewController as? AVPlayerViewController { player.player?.pause() }
        presentedViewController?.dismiss(animated: false)
        guard let navigation = navigationController else { return }
        if navigation.viewControllers.first === self {
            if navigation.presentingViewController != nil { navigation.dismiss(animated: false) }
        } else if navigation.viewControllers.contains(where: { $0 === self }) {
            navigation.setViewControllers(navigation.viewControllers.filter { $0 !== self }, animated: false)
        }
    }
}

final class CatalogPage: CityPage, SafetyObserving {
    private let section: CatalogSection
    private let grid = Theme.stack()
    private let cosplayGrid = Theme.stack()
    private var publicPosts: [CosplayPost] = []
    private var ownPosts: [CosplayPost] = []
    private var cosplayLoaded = false
    private var cosplayFailure = false
    private let searchField = Theme.field("Search")
    private var items: [CatalogItem] = []
    private var saved: Set<String> = []
    private var scope = "All"
    private var loaded = false
    private var loadTask: Task<Void, Never>?

    init(_ section: CatalogSection, api: CommunityAPI) {
        self.section = section
        super.init(section.title, api: api)
    }
    required init?(coder: NSCoder) { return nil }

    func safetyDidChange() {
        items.removeAll { api.isHidden($0) }
        publicPosts.removeAll { api.isHidden($0) }
        ownPosts.removeAll { api.isHidden($0) }
        render()
        reload()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeSafetyChanges()
        actions.addArrangedSubview(Theme.icon("search", label: "Search") { [weak self] in
            guard let self else { return }
            self.searchField.isHidden.toggle()
            if self.searchField.isHidden {
                self.searchField.resignFirstResponder()
                self.searchField.text = nil
                self.render()
            } else {
                self.searchField.becomeFirstResponder()
            }
        })
        actions.addArrangedSubview(Theme.icon("filter", label: "Filter") { [weak self] in self?.chooseScope() })
        body.addArrangedSubview(Theme.label(section.subtitle, color: Theme.secondary))
        searchField.isHidden = true
        search(searchField, into: body) { [weak self] _ in self?.render() }
        body.addArrangedSubview(cosplayGrid)
        body.addArrangedSubview(grid)
        if section == .cosplay {
            actions.addArrangedSubview(Theme.icon("shorts", label: "Post cosplay") { [weak self] in self?.composeCosplay() })
        }
        enableRefresh { [weak self] in self?.reload() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func composeCosplay() {
        guard cosplayLoaded else {
            alert("Posting is unavailable right now. Pull down or try again later.")
            return
        }
        push(ComposeCosplayPage(api: api) { [weak self] in self?.scope = "My posts" })
    }

    private func renderCosplay() {
        cosplayGrid.clear()
        let dedicated = scope == "Community" || scope == "My posts"
        grid.isHidden = dedicated
        guard section == .cosplay else { return }
        let query = searchField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let posts = scope == "My posts" ? ownPosts : publicPosts
        let matches = posts.filter { post in
            let correctKind = (scope != "Cosplay Look" || post.mediaKind == .photo) &&
                (scope != "Cosplay Video" || post.mediaKind == .video)
            return !api.isHidden(post) && correctKind && (query.isEmpty ||
                "\(post.title) \(post.caption) \(post.author?.displayName ?? "")".localizedCaseInsensitiveContains(query))
        }
        if cosplayFailure {
            cosplayGrid.addArrangedSubview(Theme.label("Community posts could not be refreshed.", color: Theme.secondary))
            cosplayGrid.addArrangedSubview(Theme.textAction("Try again") { [weak self] in self?.reload() })
        }
        if dedicated && !cosplayLoaded && !cosplayFailure {
            cosplayGrid.addArrangedSubview(Theme.label("Loading posts…", color: Theme.secondary))
        }
        if dedicated && cosplayLoaded && matches.isEmpty {
            let message = query.isEmpty ? "No posts to show yet." : "No posts match your search."
            let title = scope == "My posts" ? "My posts" : "Community"
            cosplayGrid.addArrangedSubview(Theme.empty(title, message))
        }
        if !matches.isEmpty {
            cosplayGrid.addArrangedSubview(Theme.label(scope == "My posts" ? "My posts" : "Community", size: 23, display: true))
        }
        for post in matches {
            let openAuthor: ((UUID) -> Void)? = scope == "My posts" ? nil : { [weak self] author in
                guard let self else { return }
                self.push(ProfilePage(memberID: author, api: self.api))
            }
            let card = CosplayPostCard.make(post, api: api, open: { [weak self] in
                guard let self else { return }
                self.push(CosplayPostPage(post: post, api: self.api))
            }, openAuthor: openAuthor)
            cosplayGrid.addArrangedSubview(card)
        }
    }

    private func reload() {
        loadTask?.cancel()
        if !loaded { showStatus("Loading…") }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let catalog = self.api.catalog()
                async let reactions = self.api.reactions()
                let (items, reactionsList) = try await (catalog, reactions)
                if section == .cosplay {
                    guard let member = api.memberID else { throw CommunityError.unavailable }
                    async let community = api.cosplayPosts()
                    async let mine = api.cosplayPosts(owner: member)
                    let (published, owned) = try await (community, mine)
                    try Task.checkCancellation()
                    guard api.memberID == member else { throw CommunityError.unavailable }
                    publicPosts = published
                    ownPosts = owned
                    cosplayLoaded = true
                    cosplayFailure = false
                }
                guard !Task.isCancelled else { return }
                self.items = items.filter(self.section.includes)
                self.saved = Set(reactionsList.filter { $0.kind == "save" }.map(\.catalogId))
                self.loaded = true
                self.showStatus(nil)
                self.render()
                self.pageRefresh.finish()
            } catch {
                guard !Task.isCancelled else { return }
                self.showStatus("Content could not be refreshed.")
                if section == .cosplay {
                    cosplayFailure = true
                    renderCosplay()
                }
                self.pageRefresh.finish(error: "Content could not be updated. Pull down to try again.")
                if !loaded {
                    self.grid.clear()
                    self.grid.addArrangedSubview(Theme.button("Retry") { [weak self] in self?.reload() })
                }
            }
        }
    }

    private func chooseScope() {
        menu("Filter", choices: section.filters.map { choice in
            (choice, .default, { [weak self] in
                self?.scope = choice
                self?.render()
            })
        })
    }

    private func render() {
        renderCosplay()
        guard loaded, !grid.isHidden else { return }
        let query = searchField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let filtered = items.filter { item in
            let matchesScope = scope == "All" || (scope == "Saved" ? saved.contains(item.id) : item.kind == scope)
            return !api.isHidden(item) && matchesScope && (query.isEmpty || "\(item.title) \(item.description) \(item.credit)".localizedCaseInsensitiveContains(query))
        }
        grid.clear()
        guard !filtered.isEmpty else {
            grid.addArrangedSubview(Theme.empty("No matches", "Try another search or filter."))
            return
        }
        if section == .districts || traitCollection.preferredContentSizeCategory.isAccessibilityCategory {
            filtered.enumerated().forEach { grid.addArrangedSubview(card($0.element, index: $0.offset, items: filtered)) }
            return
        }
        for start in stride(from: 0, to: filtered.count, by: 2) {
            let cards = filtered[start..<min(start + 2, filtered.count)].enumerated().map {
                card($0.element, index: start + $0.offset, items: filtered)
            }
            let row = Theme.stack(cards, spacing: 10, axis: .horizontal)
            row.distribution = .fillEqually
            if cards.count == 1 { row.addArrangedSubview(UIView()) }
            grid.addArrangedSubview(row)
        }
    }

    private func card(_ item: CatalogItem, index: Int, items: [CatalogItem]) -> UIView {
        let cover = EditorialImage(item: item)
        cover.heightAnchor.constraint(equalToConstant: section == .districts ? 170 : 156).isActive = true
        let openItem: () -> Void = { [weak self] in
            guard let self else { return }
            self.push(CatalogDetail(items: items, index: index, api: self.api))
        }
        let open = Theme.textAction(item.title, action: openItem)
        let target = UIButton(type: .custom)
        target.accessibilityLabel = "Open \(item.title)"
        target.addAction(UIAction { _ in openItem() }, for: .touchUpInside)
        cover.isUserInteractionEnabled = true
        cover.addSubview(target)
        target.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            target.topAnchor.constraint(equalTo: cover.topAnchor), target.bottomAnchor.constraint(equalTo: cover.bottomAnchor),
            target.leadingAnchor.constraint(equalTo: cover.leadingAnchor), target.trailingAnchor.constraint(equalTo: cover.trailingAnchor)
        ])
        let credit = Theme.textAction(item.credit) { [weak self] in self?.open(item.sourceUrl) }
        credit.accessibilityLabel = "Source: \(item.credit)"
        return Theme.card([cover, Theme.label(item.kind, size: 13, color: Theme.mint, display: true), open, credit], spacing: 6)
    }
}

final class CatalogDetail: CityPage, SafetyObserving {
    private var items: [CatalogItem]
    private var index: Int
    private let originalIDs: [String]
    private var item: CatalogItem { items[index] }
    private var reactions: Set<String> = []
    private var reactionTask: Task<Void, Never>?
    private let reactionBar = Theme.stack(spacing: 6, axis: .horizontal)
    private var busy = Set<String>()

    init(items: [CatalogItem], index: Int, api: CommunityAPI) {
        self.items = items
        self.index = index
        originalIDs = items.map(\.id)
        super.init(items[index].isVideo ? "Watch" : items[index].kind, api: api)
    }

    required init?(coder: NSCoder) { return nil }

    func safetyDidChange() {
        reactionTask?.cancel()
        if api.isHidden(item) { closeHiddenContent(); return }
        let selectedID = item.id
        items.removeAll { api.isHidden($0) }
        guard let selected = items.firstIndex(where: { $0.id == selectedID }) else { closeHiddenContent(); return }
        index = selected
        render()
        loadReactions(reloadItem: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeSafetyChanges()
        guard !api.isHidden(item) else { closeHiddenContent(); return }
        render()
        enableRefresh { [weak self] in self?.loadReactions(reloadItem: true) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadReactions()
    }

    private func render() {
        body.clear()
        let selected = item
        let cover = EditorialImage(item: selected)
        if selected.isVideo && items.count > 1 {
            cover.isUserInteractionEnabled = true
            let next = UISwipeGestureRecognizer(target: self, action: #selector(nextItem))
            next.direction = .left
            let previous = UISwipeGestureRecognizer(target: self, action: #selector(previousItem))
            previous.direction = .right
            cover.addGestureRecognizer(next)
            cover.addGestureRecognizer(previous)
        }
        cover.heightAnchor.constraint(equalToConstant: selected.isVideo ? 310 : 260).isActive = true
        body.addArrangedSubview(cover)
        body.addArrangedSubview(Theme.label(selected.kind, size: 14, color: Theme.mint, display: true))
        body.addArrangedSubview(Theme.label(selected.title, size: 33, display: true))
        body.addArrangedSubview(Theme.label(selected.description, color: Theme.secondary))
        if selected.isVideo {
            body.addArrangedSubview(Theme.button(selected.mediaUrl == nil ? "Watch at source" : "Play", icon: "shorts", accent: true) { [weak self] in
                self?.play(selected)
            })
        }
        body.addArrangedSubview(Theme.button(selected.credit) { [weak self] in self?.open(selected.sourceUrl) })
        reactionBar.distribution = .fillEqually
        body.addArrangedSubview(reactionBar)
        renderReactions()
        let tools = Theme.stack([Theme.button("Share", icon: "share") { [weak self] in self?.share(selected.sourceUrl) }], axis: .horizontal)
        if selected.publisherId == nil || selected.publisherId != api.memberID {
            tools.addArrangedSubview(Theme.moreIcon(label: "Content options") { [weak self] in
                guard let self else { return }
                let authors = selected.publisherId.map { self.authorOptions($0, name: selected.publisher?.displayName, source: "catalog:" + selected.id, api: self.api) } ?? []
                self.menu("Content options", choices: [
                    (selected.isVideo ? "Report video" : "Report content", .destructive, { [weak self] in
                        self?.report(["catalog_id": selected.id], subject: selected.isVideo ? "video" : "content", detail: selected.title, video: selected.isVideo)
                    })
                ] + authors)
            })
        }
        tools.distribution = .fillEqually
        body.addArrangedSubview(tools)
        if items.count > 1 {
            let previous = Theme.button("Previous") { [weak self] in self?.move(-1) }
            let next = Theme.button("Next") { [weak self] in self?.move(1) }
            previous.isEnabled = items.prefix(index).contains { !api.isHidden($0) }
            next.isEnabled = items.dropFirst(index + 1).contains { !api.isHidden($0) }
            let controls = Theme.stack([previous, next], axis: .horizontal)
            controls.distribution = .fillEqually
            body.addArrangedSubview(controls)
        }
    }

    @objc private func nextItem() { move(1) }
    @objc private func previousItem() { move(-1) }

    private func move(_ offset: Int) {
        var candidate = index + offset
        while items.indices.contains(candidate), api.isHidden(items[candidate]) { candidate += offset }
        guard items.indices.contains(candidate) else { return }
        index = candidate
        reactions = []
        render()
        scroll.setContentOffset(.zero, animated: false)
        loadReactions()
    }

    private func play(_ item: CatalogItem) {
        if let url = item.mediaUrl, url.scheme == "https" {
            let controller = AVPlayerViewController()
            controller.player = AVPlayer(url: url)
            present(controller, animated: true) { controller.player?.play() }
        } else {
            open(item.sourceUrl)
        }
    }

    private func share(_ url: URL) {
        present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
    }

    private func loadReactions(reloadItem: Bool = false) {
        reactionTask?.cancel()
        let id = item.id
        reactionTask = Task { [weak self] in
            guard let self else { return }
            do {
                if reloadItem {
                    let catalog = try await api.catalog()
                    try Task.checkCancellation()
                    let available = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
                    let visible = originalIDs.compactMap { available[$0] }.filter { !api.isHidden($0) }
                    guard let position = visible.firstIndex(where: { $0.id == id }) else { closeHiddenContent(); return }
                    items = visible
                    index = position
                    render()
                }
                let values = try await self.api.reactions()
                guard !Task.isCancelled, self.item.id == id else { return }
                self.reactions = Set(values.filter { $0.catalogId == id }.map(\.kind))
                self.showStatus(nil)
                self.renderReactions()
                self.pageRefresh.finish()
            } catch {
                guard !Task.isCancelled else { return }
                self.showStatus("Likes and saves could not be loaded.")
                self.pageRefresh.finish(error: "This item could not be updated. Pull down to try again.")
            }
        }
    }

    private func renderReactions() {
        reactionBar.clear()
        let id = item.id
        let like = Theme.button(reactions.contains("like") ? "Liked" : "Like", icon: reactions.contains("like") ? "like" : "like-outline") { [weak self] in self?.toggle("like") }
        let save = Theme.button(reactions.contains("save") ? "Saved" : "Save", icon: reactions.contains("save") ? "save" : "save-outline") { [weak self] in self?.toggle("save") }
        like.isEnabled = !busy.contains("\(id)-like")
        save.isEnabled = !busy.contains("\(id)-save")
        reactionBar.addArrangedSubview(like)
        reactionBar.addArrangedSubview(save)
        reactionBar.addArrangedSubview(Theme.button("Comments", icon: "comments") { [weak self] in
            guard let self else { return }
            self.push(CommentsPage(item: self.item, api: self.api))
        })
    }

    private func toggle(_ kind: String) {
        let id = item.id
        let operation = "\(id)-\(kind)"
        guard busy.insert(operation).inserted else { return }
        let enabled = !reactions.contains(kind)
        reactionTask?.cancel()
        renderReactions()
        Task {
            defer { busy.remove(operation); if item.id == id { renderReactions() } }
            do {
                try await api.setReaction(kind, item: id, enabled: enabled)
                if item.id == id {
                    if enabled { reactions.insert(kind) } else { reactions.remove(kind) }
                }
            } catch { alert(error.localizedDescription) }
        }
    }
}

final class CommentsPage: CityPage, SafetyObserving {
    var openAuthorProfile: ((ProfilePage) -> Void)?
    private let item: CatalogItem
    private let list = Theme.stack()
    private let input = Theme.field("Write a comment")
    private let total = Theme.label("Comments", size: 15, color: Theme.secondary)
    private var sendButton: UIButton?
    private let sheet: Bool
    private let didChange: (() -> Void)?
    private var loadTask: Task<Void, Never>?

    init(item: CatalogItem, api: CommunityAPI, sheet: Bool = false,
         didChange: (() -> Void)? = nil) {
        self.item = item
        self.sheet = sheet
        self.didChange = didChange
        super.init("Comments", api: api)
    }
    required init?(coder: NSCoder) { return nil }

    func safetyDidChange() {
        if api.isHidden(item) { loadTask?.cancel(); closeHiddenContent(); return }
        displayedRows.removeAll { api.isHidden($0) }
        renderRows()
        reload()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeSafetyChanges()
        guard !api.isHidden(item) else { closeHiddenContent(); return }
        if sheet {
            actions.addArrangedSubview(Theme.textAction("Done") { [weak self] in self?.navigationController?.dismiss(animated: true) })
        }
        let button = Theme.button("Post", accent: true) { [weak self] in self?.post() }
        sendButton = button
        button.accessibilityIdentifier = "comments.post"
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        input.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        body.addArrangedSubview(Theme.stack([input, button], axis: .horizontal))
        total.accessibilityIdentifier = "comments.total"
        body.addArrangedSubview(total)
        body.addArrangedSubview(list)
        enableRefresh { [weak self] in self?.reload() }
        reload()
    }

    private func reload() {
        loadTask?.cancel()
        loadTask = Task {
            do {
                let rows = try await api.comments(item.id)
                guard !Task.isCancelled else { return }
                displayedRows = rows
                renderRows()
                didChange?()
                pageRefresh.finish()
            } catch {
                guard !Task.isCancelled else { return }
                pageRefresh.finish(error: "Comments could not be updated. Pull down to try again.")
                showStatus("Comments could not be loaded.")
                if list.arrangedSubviews.isEmpty {
                    list.addArrangedSubview(Theme.button("Retry") { [weak self] in self?.reload() })
                }
            }
        }
    }

    private var displayedRows: [Comment] = []

    private func renderRows() {
        let rows = displayedRows.filter { !api.isHidden($0) }
        total.text = "\(rows.count) comments"
        showStatus(nil)
        list.clear()
        if rows.isEmpty { list.addArrangedSubview(Theme.empty("Start the conversation", "Share what stood out to you.")) }
        for row in rows {
            let name: UIView
            if let id = row.authorId {
                let nickname = row.author?.displayName ?? "Private member"
                let openProfile: () -> Void = { [weak self] in
                    guard let self else { return }
                    let profile = ProfilePage(memberID: id, api: self.api, commentID: row.id)
                    if let openAuthorProfile = self.openAuthorProfile { openAuthorProfile(profile) }
                    else { self.push(profile) }
                }
                let avatar = MemberAvatar.button(row.author?.avatar, size: Theme.iconSize, label: "Open \(nickname)’s profile",
                                                 memberID: id, action: openProfile)
                let byline = Theme.textAction(nickname, action: openProfile)
                avatar.accessibilityIdentifier = "comment.author.avatar"
                byline.accessibilityIdentifier = "comment.author.name"
                byline.configuration?.titleLineBreakMode = .byWordWrapping
                let identity = Theme.stack([avatar, byline], spacing: 8, axis: .horizontal)
                identity.alignment = .center
                name = identity
            } else {
                name = Theme.label(row.editorialKey == nil ? "City Resident" : "Sese Editorial", display: true)
            }
            let own = row.authorId != nil && row.authorId == api.memberID
            let commentBody = Theme.label(row.body)
            commentBody.accessibilityIdentifier = "comment.body"
            let header = Theme.stack([name], spacing: 6, axis: .horizontal)
            header.alignment = .top
            let card = Theme.card([header, commentBody])
            if own {
                card.addArrangedSubview(Theme.button("Delete") { [weak self] in self?.remove(row.id) })
            } else {
                header.addArrangedSubview(Theme.moreIcon(label: "Comment options", size: commentBody.font.pointSize) { [weak self] in
                    guard let self else { return }
                    let source = "comment:" + row.id.uuidString.lowercased()
                    let authors = row.authorId.map { self.authorOptions($0, name: row.author?.displayName, source: source, api: self.api) } ?? []
                    self.menu("Comment options", choices: [
                        ("Report comment", .destructive, { [weak self] in
                            let excerpt = String(row.body.prefix(100)) + (row.body.count > 100 ? "…" : "")
                            self?.report(["comment_id": row.id.uuidString], subject: "comment", detail: "“\(excerpt)”")
                        })
                    ] + authors)
                })
            }
            list.addArrangedSubview(card)
        }
    }

    private func post() {
        let text = (input.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...200).contains(text.count) else { alert("Use 1–200 characters."); return }
        sendButton?.isEnabled = false
        input.isEnabled = false
        Task {
            defer { sendButton?.isEnabled = true; input.isEnabled = true }
            do {
                try await api.addComment(item.id, text: text)
                input.text = nil
                input.resignFirstResponder()
                didChange?()
                reload()
            } catch { alert(error.localizedDescription) }
        }
    }

    private func remove(_ id: UUID) {
        menu("Delete this comment?", choices: [("Delete", .destructive, { [weak self] in
            guard let self else { return }
            Task {
                do {
                    try await self.api.removeComment(id)
                    self.didChange?()
                    self.reload()
                }
                catch { self.alert(error.localizedDescription) }
            }
        })])
    }
}
