import UIKit

final class CommunityWorksPage: CityPage, SafetyObserving {
    private var loadTask: Task<Void, Never>?
    private let list = Theme.stack()

    private var displayedWorks: [MemberWork] = []

    init(api: CommunityAPI) { super.init("Community videos", api: api) }
    required init?(coder: NSCoder) { return nil }

    func safetyDidChange() {
        displayedWorks.removeAll { api.isHidden($0) }
        renderWorks()
        reload()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeSafetyChanges()
        body.addArrangedSubview(Theme.button("Submit a video", icon: "shorts", accent: true) { [weak self] in
            guard let self else { return }
            self.push(SubmitWorkPage(api: self.api))
        })
        body.addArrangedSubview(list)
        enableRefresh { [weak self] in self?.reload() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        showStatus("Loading community videos…")
        loadTask?.cancel()
        loadTask = Task {
            do {
                let works = try await api.works()
                try Task.checkCancellation()
                showStatus(nil)
                displayedWorks = works
                renderWorks()
                pageRefresh.finish()
            } catch {
                guard !Task.isCancelled else { return }
                showStatus("Community videos could not be refreshed.")
                pageRefresh.finish(error: "Videos could not be updated. Pull down to try again.")
                if list.arrangedSubviews.isEmpty {
                    list.addArrangedSubview(Theme.button("Retry") { [weak self] in self?.reload() })
                }
            }
        }
    }

    private func renderWorks() {
        let works = displayedWorks.filter { !api.isHidden($0) }
        list.clear()
        if works.isEmpty {
            list.addArrangedSubview(Theme.empty("No community videos yet", "Approved videos from members appear here."))
        }
        for work in works {
            let openProfile: () -> Void = { [weak self] in
                guard let self else { return }
                self.push(ProfilePage(memberID: work.ownerId, api: self.api))
            }
            let name = work.author?.displayName ?? "City Resident"
            let avatar = MemberAvatar.button(work.author?.avatar, size: Theme.iconSize, label: "Open \(name)’s profile",
                                             memberID: work.ownerId, action: openProfile)
            let author = Theme.stack([avatar, Theme.textAction(name, action: openProfile)], spacing: 8, axis: .horizontal)
            author.alignment = .center
            list.addArrangedSubview(Theme.card([
                Theme.label(work.title, size: 23, display: true),
                Theme.label(work.caption, color: Theme.secondary),
                author,
                Theme.button("Open video", icon: "shorts") { [weak self] in
                    guard let self else { return }
                    self.push(MemberWorkPage(work: work, api: self.api))
                }
            ]))
        }
    }
}

final class MemberWorkPage: CityPage, SafetyObserving {
    private var work: MemberWork
    private var reloadTask: Task<Void, Never>?
    private var engagement: PublicationReactionBar?

    init(work: MemberWork, api: CommunityAPI) {
        self.work = work
        super.init("Short", api: api)
    }

    required init?(coder: NSCoder) { nil }

    func safetyDidChange() {
        reloadTask?.cancel()
        if api.isHidden(work) { closeHiddenContent(); return }
        reloadWork()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeSafetyChanges()
        guard !api.isHidden(work) else { closeHiddenContent(); return }
        enableRefresh { [weak self] in self?.reloadWork() }
        renderWork()
    }

    private func renderWork() {
        body.clear()
        actions.clear()
        engagement = nil
        body.addArrangedSubview(Theme.label(work.title, size: 26, display: true))
        if !work.caption.isEmpty { body.addArrangedSubview(Theme.label(work.caption, color: Theme.secondary)) }
        body.addArrangedSubview(Theme.button("Watch at source", icon: "shorts", accent: true) { [weak self] in
            guard let self else { return }
            self.open(self.work.sourceUrl)
        })
        if work.status == "approved" {
            let bar = PublicationReactionBar(api: api, source: .work, item: work.id)
            body.addArrangedSubview(bar.view)
            engagement = bar
        }
        if work.ownerId != api.memberID {
            actions.addArrangedSubview(Theme.moreIcon(label: "Video options") { [weak self] in
                guard let self else { return }
                self.menu("Video options", choices: [
                    ("Report video", .destructive, { [weak self] in
                        guard let self else { return }
                        self.report(["work_id": self.work.id.uuidString], subject: "video", detail: self.work.title)
                    })
                ] + self.authorOptions(self.work.ownerId, name: self.work.author?.displayName, source: "work:" + self.work.id.uuidString.lowercased(), api: self.api))
            })
        }
    }

    private func reloadWork() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let rows = try await api.works(owner: work.ownerId, ids: [work.id])
                try Task.checkCancellation()
                guard let updated = rows.first else { closeHiddenContent(); return }
                work = updated
                renderWork()
                if let engagement {
                    engagement.load { [weak self] error in self?.pageRefresh.finish(error: error) }
                } else {
                    pageRefresh.finish()
                }
            } catch {
                guard !Task.isCancelled else { return }
                pageRefresh.finish(error: "This video could not be updated. Pull down to try again.")
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        engagement?.load()
    }
}

@MainActor
final class PublicationReactionBar {
    let view = Theme.stack(spacing: 6)
    private let controls = Theme.stack(spacing: 6, axis: .horizontal)
    private let status = Theme.label("", size: 14, color: Theme.secondary)
    private let api: CommunityAPI
    private let source: PublicationSource
    private let item: UUID
    private var totals: PublicationCounts?
    private var reactions = Set<String>()
    private var ready = false
    private var busy = false
    private var loadTask: Task<Void, Never>?

    init(api: CommunityAPI, source: PublicationSource, item: UUID) {
        self.api = api
        self.source = source
        self.item = item
        controls.distribution = .fillEqually
        view.addArrangedSubview(controls)
        view.addArrangedSubview(status)
        render()
    }

    func load(completion: ((String?) -> Void)? = nil) {
        guard !busy else {
            completion?("Wait for your reaction to finish, then pull down again.")
            return
        }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.refresh()
                completion?(nil)
            } catch {
                guard !Task.isCancelled else { return }
                completion?("Likes and saves could not be updated. Pull down to try again.")
                self.status.text = "Likes and saves could not be refreshed."
                self.status.isHidden = false
                self.render()
            }
        }
    }

    private func refresh() async throws {
        async let counts = api.publicationCounts(source, item: item)
        async let current = api.publicationReactions(source, item: item)
        let (totals, selected) = try await (counts, current)
        try Task.checkCancellation()
        self.totals = totals
        reactions = Set(selected.map(\.kind))
        ready = true
        status.isHidden = true
        render()
    }

    private func render() {
        controls.clear()
        for (kind, normal, selected, total) in [("like", "Like", "Liked", totals?.likes), ("save", "Save", "Saved", totals?.saves)] {
            let active = reactions.contains(kind)
            let label = "\(active ? selected : normal) · \(total.map { $0.formatted() } ?? "—")"
            let button = Theme.button(label, icon: active ? kind : kind + "-outline") { [weak self] in self?.toggle(kind) }
            button.isEnabled = ready && !busy
            button.accessibilityTraits = active ? [.button, .selected] : .button
            controls.addArrangedSubview(button)
        }
        if !ready && !status.isHidden && status.text?.isEmpty == false {
            let retry = Theme.textAction("Retry") { [weak self] in self?.load() }
            controls.addArrangedSubview(retry)
        }
    }

    private func toggle(_ kind: String) {
        guard ready, !busy else { return }
        busy = true
        loadTask?.cancel()
        render()
        let enabled = !reactions.contains(kind)
        Task { [weak self] in
            guard let self else { return }
            defer { self.busy = false; self.render() }
            do {
                try await self.api.setPublicationReaction(kind, source: self.source, item: self.item, enabled: enabled)
                if enabled { self.reactions.insert(kind) } else { self.reactions.remove(kind) }
                self.totals = nil
                try await self.refresh()
            } catch {
                self.status.text = error.localizedDescription
                self.status.isHidden = false
            }
        }
    }
}

final class SubmitWorkPage: CityPage {
    private let name = Theme.field("Title")
    private let caption = Theme.field("Caption")
    private let link = Theme.field("YouTube video URL")
    private var button: UIButton?

    init(api: CommunityAPI) { super.init("Submit a video", api: api) }
    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        link.keyboardType = .URL
        link.autocapitalizationType = .none
        link.autocorrectionType = .no
        body.addArrangedSubview(Theme.label("Share a Zootopia clip you have permission to submit. A reviewer must approve it before it appears in the community.", color: Theme.secondary))
        for field in [name, caption, link] { body.addArrangedSubview(field) }
        let submit = Theme.button("Submit for review", accent: true) { [weak self] in self?.submit() }
        body.addArrangedSubview(submit)
        button = submit
    }

    private func submit() {
        let title = (name.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let text = caption.text ?? ""
        guard (1...80).contains(title.count), text.count <= 350 else {
            alert("Use a title of 1–80 characters and a caption of at most 350 characters.")
            return
        }
        guard let url = canonicalURL(link.text ?? "") else {
            alert("Enter a valid HTTPS YouTube video link.")
            return
        }
        button?.isEnabled = false
        Task {
            defer { button?.isEnabled = true }
            do {
                try await api.submitWork(title: title, caption: text, url: url)
                name.text = nil
                caption.text = nil
                link.text = nil
                view.endEditing(true)
                showStatus("Submitted for review. View the status in Me → Shorts.")
            } catch { alert(error.localizedDescription) }
        }
    }

    private func canonicalURL(_ text: String) -> URL? {
        guard let components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == "https", components.user == nil, components.password == nil else { return nil }
        let segments = components.path.split(separator: "/")
        let id: String?
        switch components.host?.lowercased() {
        case "youtu.be": id = segments.first.map(String.init)
        case "youtube.com", "www.youtube.com", "m.youtube.com":
            id = segments.first == "shorts" ? segments.dropFirst().first.map(String.init) :
                components.queryItems?.first(where: { $0.name == "v" })?.value
        default: return nil
        }
        guard let id, id.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(id)")
    }
}
