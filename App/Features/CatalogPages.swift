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

final class CatalogPage: CityPage {
    private let section: CatalogSection
    private let grid = Theme.stack()
    private let cosplayGrid = Theme.stack()
    private var publicPosts: [CosplayPost] = []
    private var ownPosts: [CosplayPost] = []
    private var cosplayLoaded = false
    private var cosplayFailure = false
    private var cosplayTask: Task<Void, Never>?
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

    override func viewDidLoad() {
        super.viewDidLoad()
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
            let refresh = UIRefreshControl()
            refresh.tintColor = Theme.mint
            refresh.addAction(UIAction { [weak self] _ in
                self?.reload()
                self?.reloadCosplay()
            }, for: .valueChanged)
            scroll.alwaysBounceVertical = true
            scroll.refreshControl = refresh
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
        if section == .cosplay { reloadCosplay() }
    }

    private func composeCosplay() {
        guard cosplayLoaded else {
            alert("Posting is unavailable right now. Pull down or try again later.")
            return
        }
        push(ComposeCosplayPage(api: api) { [weak self] in self?.scope = "My posts" })
    }

    private func reloadCosplay() {
        cosplayTask?.cancel()
        guard let member = api.memberID else { return }
        cosplayFailure = false
        renderCosplay()
        cosplayTask = Task { [weak self, api] in
            defer { if !Task.isCancelled { self?.scroll.refreshControl?.endRefreshing() } }
            do {
                async let community = api.cosplayPosts()
                async let mine = api.cosplayPosts(owner: member)
                let (publicPosts, ownPosts) = try await (community, mine)
                guard let self, !Task.isCancelled, api.memberID == member else { return }
                self.publicPosts = publicPosts
                self.ownPosts = ownPosts
                self.cosplayLoaded = true
                self.cosplayFailure = false
                self.renderCosplay()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.cosplayFailure = true
                self.renderCosplay()
            }
        }
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
            return correctKind && (query.isEmpty ||
                "\(post.title) \(post.caption) \(post.author?.displayName ?? "")".localizedCaseInsensitiveContains(query))
        }
        if cosplayFailure {
            cosplayGrid.addArrangedSubview(Theme.label("Community posts could not be refreshed.", color: Theme.secondary))
            cosplayGrid.addArrangedSubview(Theme.textAction("Try again") { [weak self] in self?.reloadCosplay() })
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
                guard !Task.isCancelled else { return }
                self.items = items.filter(self.section.includes)
                self.saved = Set(reactionsList.filter { $0.kind == "save" }.map(\.catalogId))
                self.loaded = true
                self.showStatus(nil)
                self.render()
            } catch {
                guard !Task.isCancelled else { return }
                self.showStatus("Content could not be refreshed.")
                self.grid.clear()
                self.grid.addArrangedSubview(Theme.button("Retry") { [weak self] in self?.reload() })
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
            return matchesScope && (query.isEmpty || "\(item.title) \(item.description) \(item.credit)".localizedCaseInsensitiveContains(query))
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

final class CatalogDetail: CityPage {
    private let items: [CatalogItem]
    private var index: Int
    private var item: CatalogItem { items[index] }
    private var reactions: Set<String> = []
    private var reactionTask: Task<Void, Never>?
    private let reactionBar = Theme.stack(spacing: 6, axis: .horizontal)
    private var busy = Set<String>()

    init(items: [CatalogItem], index: Int, api: CommunityAPI) {
        self.items = items
        self.index = index
        super.init(items[index].isVideo ? "Watch" : items[index].kind, api: api)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        render()
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
        let tools = Theme.stack([
            Theme.button("Share", icon: "share") { [weak self] in self?.share(selected.sourceUrl) },
            Theme.button("Report") { [weak self] in self?.report(["catalog_id": selected.id]) }
        ], axis: .horizontal)
        tools.distribution = .fillEqually
        body.addArrangedSubview(tools)
        if items.count > 1 {
            let previous = Theme.button("Previous") { [weak self] in self?.move(-1) }
            let next = Theme.button("Next") { [weak self] in self?.move(1) }
            previous.isEnabled = index > 0
            next.isEnabled = index + 1 < items.count
            let controls = Theme.stack([previous, next], axis: .horizontal)
            controls.distribution = .fillEqually
            body.addArrangedSubview(controls)
        }
    }

    @objc private func nextItem() { move(1) }
    @objc private func previousItem() { move(-1) }

    private func move(_ offset: Int) {
        guard items.indices.contains(index + offset) else { return }
        index += offset
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

    private func loadReactions() {
        reactionTask?.cancel()
        let id = item.id
        reactionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let values = try await self.api.reactions()
                guard !Task.isCancelled, self.item.id == id else { return }
                self.reactions = Set(values.filter { $0.catalogId == id }.map(\.kind))
                self.showStatus(nil)
                self.renderReactions()
            } catch {
                guard !Task.isCancelled else { return }
                self.showStatus("Likes and saves could not be loaded.")
            }
        }
    }

    private func renderReactions() {
        reactionBar.clear()
        let id = item.id
        let like = Theme.button(reactions.contains("like") ? "Liked" : "Like", icon: "like") { [weak self] in self?.toggle("like") }
        let save = Theme.button(reactions.contains("save") ? "Saved" : "Save", icon: "save") { [weak self] in self?.toggle("save") }
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

final class CommentsPage: CityPage {
    private let item: CatalogItem
    private let list = Theme.stack()
    private let input = Theme.field("Write a comment")
    private var sendButton: UIButton?

    init(item: CatalogItem, api: CommunityAPI) {
        self.item = item
        super.init("Comments", api: api)
    }
    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        let button = Theme.button("Post", accent: true) { [weak self] in self?.post() }
        sendButton = button
        body.addArrangedSubview(Theme.stack([input, button], axis: .horizontal))
        body.addArrangedSubview(list)
        reload()
    }

    private func reload() {
        Task {
            do {
                let rows = try await api.comments(item.id)
                showStatus(nil)
                list.clear()
                if rows.isEmpty { list.addArrangedSubview(Theme.empty("Start the conversation", "Share what stood out to you.")) }
                for row in rows {
                    let name: UIView
                    if let author = row.author {
                        let openProfile: () -> Void = { [weak self] in
                            guard let self else { return }
                            self.push(ProfilePage(memberID: author.id, api: self.api))
                        }
                        let avatar = MemberAvatar.button(author.avatar, size: 44, label: "Open \(author.displayName)’s profile",
                                                         memberID: author.id, action: openProfile)
                        let identity = Theme.stack([avatar, Theme.textAction(author.displayName, action: openProfile)], axis: .horizontal)
                        identity.alignment = .center
                        name = identity
                    } else {
                        name = Theme.label("City Resident", display: true)
                    }
                    let own = row.authorId == api.memberID
                    let button = Theme.button(own ? "Delete" : "Report") { [weak self] in
                        if own { self?.remove(row.id) } else { self?.report(["comment_id": row.id.uuidString]) }
                    }
                    list.addArrangedSubview(Theme.card([name, Theme.label(row.body), button]))
                }
            } catch { showStatus("Comments could not be loaded."); list.addArrangedSubview(Theme.button("Retry") { [weak self] in self?.reload() }) }
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
                reload()
            } catch { alert(error.localizedDescription) }
        }
    }

    private func remove(_ id: UUID) {
        menu("Delete this comment?", choices: [("Delete", .destructive, { [weak self] in
            guard let self else { return }
            Task {
                do { try await self.api.removeComment(id); self.reload() }
                catch { self.alert(error.localizedDescription) }
            }
        })])
    }
}
