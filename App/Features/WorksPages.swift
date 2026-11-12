import UIKit

final class CommunityWorksPage: CityPage {
    private let list = Theme.stack()

    init(api: CommunityAPI) { super.init("Community videos", api: api) }
    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        body.addArrangedSubview(Theme.button("Submit a video", icon: "shorts", accent: true) { [weak self] in
            guard let self else { return }
            self.push(SubmitWorkPage(api: self.api))
        })
        body.addArrangedSubview(list)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        showStatus("Loading community videos…")
        Task {
            do {
                let works = try await api.works()
                showStatus(nil)
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
                    let avatar = MemberAvatar.button(work.author?.avatar, size: 44, label: "Open \(name)’s profile",
                                                     memberID: work.ownerId, action: openProfile)
                    let author = Theme.stack([avatar, Theme.textAction(name, action: openProfile)], spacing: 8, axis: .horizontal)
                    author.alignment = .center
                    list.addArrangedSubview(Theme.card([
                        Theme.label(work.title, size: 23, display: true),
                        Theme.label(work.caption, color: Theme.secondary),
                        author,
                        Theme.button("Watch at source", icon: "shorts") { [weak self] in self?.open(work.sourceUrl) },
                        Theme.button("Report") { [weak self] in self?.report(["work_id": work.id.uuidString]) }
                    ]))
                }
            } catch {
                showStatus("Community videos could not be refreshed.")
                list.clear()
                list.addArrangedSubview(Theme.button("Retry") { [weak self] in self?.reload() })
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
                showStatus("Submitted for review. View the status in Me → Works.")
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
