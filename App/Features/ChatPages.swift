import UIKit
import PhotosUI

final class InboxPage: CityPage {
    private let list = Theme.stack()
    private let searchField = Theme.field("Search conversations")
    private var rows: [InboxItem] = []
    private var archived = false
    private var loaded = false
    private var loadTask: Task<Void, Never>?
    private var liveTask: Task<Void, Never>?

    init(api: CommunityAPI) { super.init("Chats", api: api) }
    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        actions.addArrangedSubview(Theme.icon("search", label: "Search chats") { [weak self] in
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
        actions.addArrangedSubview(Theme.icon("filter", label: "Conversation filters") { [weak self] in
            self?.menu("Conversations", choices: [
                ("Inbox", .default, { [weak self] in self?.archived = false; self?.render() }),
                ("Archived", .default, { [weak self] in self?.archived = true; self?.render() })
            ])
        })
        searchField.isHidden = true
        search(searchField, into: body) { [weak self] _ in self?.render() }
        body.addArrangedSubview(list)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
        liveTask?.cancel()
        liveTask = Task { [weak self, api] in
            await api.watchMessages { [weak self] in self?.reload() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        liveTask?.cancel()
        loadTask?.cancel()
    }

    private func browse() { push(MembersPage(api: api)) }

    private func reload() {
        loadTask?.cancel()
        if !loaded { showStatus("Loading conversations…") }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let inbox = try await self.api.inbox()
                guard !Task.isCancelled else { return }
                self.rows = inbox
                self.loaded = true
                self.showStatus(nil)
                self.render()
            } catch {
                guard !Task.isCancelled else { return }
                self.showStatus("Conversations could not be refreshed.")
                self.list.clear()
                self.list.addArrangedSubview(Theme.button("Retry") { [weak self] in self?.reload() })
            }
        }
    }

    private func render() {
        guard loaded else { return }
        list.clear()
        let query = searchField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let matches = rows.filter { $0.archived == archived &&
            (query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query)) }
        if matches.isEmpty {
            if !query.isEmpty { list.addArrangedSubview(Theme.empty("No matches", "Try another name or message.")) }
            else if archived { list.addArrangedSubview(Theme.empty("No archived chats", "Conversations you archive appear here.")) }
            else {
                let empty = Theme.empty("Start a conversation", "Find a resident and follow each other to start chatting.")
                empty.addArrangedSubview(Theme.button("Find members", icon: "chats", accent: true) { [weak self] in self?.browse() })
                list.addArrangedSubview(empty)
            }
            return
        }
        list.addArrangedSubview(Theme.button("Find members", icon: "search") { [weak self] in self?.browse() })
        for row in matches {
            let details = [row.pinned ? "Pinned" : nil, row.muted ? "Muted" : nil, row.unread ? "Unread" : nil].compactMap { $0 }
            let name = Theme.button(row.displayName, icon: "chats") { [weak self] in
                guard let self else { return }
                self.push(ThreadPage(peerID: row.peerId, peerName: row.displayName, api: self.api))
            }
            let preview = Theme.label(row.body, color: Theme.secondary)
            preview.numberOfLines = 2
            let card = Theme.card([name, preview])
            if !details.isEmpty { card.addArrangedSubview(Theme.label(details.joined(separator: " · "), size: 14, color: Theme.mint)) }
            card.addArrangedSubview(Theme.button("Options") { [weak self] in self?.options(row) })
            list.addArrangedSubview(card)
        }
    }

    private func options(_ row: InboxItem) {
        menu(row.displayName, choices: [
            (row.pinned ? "Unpin" : "Pin", .default, { [weak self] in self?.update("pinned", value: !row.pinned, peer: row.peerId) }),
            (row.muted ? "Unmute" : "Mute", .default, { [weak self] in self?.update("muted", value: !row.muted, peer: row.peerId) }),
            (row.archived ? "Move to inbox" : "Archive", .default, { [weak self] in self?.update("archived", value: !row.archived, peer: row.peerId) })
        ])
    }

    private func update(_ key: String, value: Bool, peer: UUID) {
        Task {
            do { try await api.setPreference([key: value], peer: peer); reload() }
            catch { alert(error.localizedDescription) }
        }
    }
}

final class MembersPage: CityPage {
    private let list = Theme.stack()
    private let searchField = Theme.field("Find a resident")
    private var people: [Member] = []
    private var following: Set<UUID> = []
    private var followers: Set<UUID> = []
    private var scope = "Everyone"

    init(api: CommunityAPI) { super.init("Members", api: api) }
    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        actions.addArrangedSubview(Theme.icon("filter", label: "Filter members") { [weak self] in
            let scopes = ["Everyone", "Following", "Followers", "Friends"]
            self?.menu("Members", choices: scopes.map { scope in
                (scope, .default, { [weak self] in self?.scope = scope; self?.render() })
            })
        })
        search(searchField, into: body) { [weak self] _ in self?.render() }
        body.addArrangedSubview(list)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        Task {
            do {
                async let members = api.members()
                async let follows = api.follows()
                let (users, relationships) = try await (members, follows)
                people = users.filter { $0.id != api.memberID }
                following = Set(relationships.filter { $0.followerId == api.memberID }.map(\.targetId))
                followers = Set(relationships.filter { $0.targetId == api.memberID }.map(\.followerId))
                showStatus(nil)
                render()
            } catch {
                showStatus("Members could not be loaded.")
                list.clear()
                list.addArrangedSubview(Theme.button("Retry") { [weak self] in self?.reload() })
            }
        }
    }

    private func render() {
        list.clear()
        let query = searchField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let matches = people.filter { person in
            let visible = scope == "Everyone" ||
                (scope == "Following" && following.contains(person.id)) ||
                (scope == "Followers" && followers.contains(person.id)) ||
                (scope == "Friends" && following.contains(person.id) && followers.contains(person.id))
            return visible && (query.isEmpty || person.displayName.localizedCaseInsensitiveContains(query))
        }
        if matches.isEmpty {
            list.addArrangedSubview(Theme.empty("No members to show", "Profiles appear here when members choose to be discoverable."))
        }
        for person in matches {
            let avatar = MemberAvatar.view(person.avatar, size: 50)
            let open = Theme.button(person.displayName) { [weak self] in
                guard let self else { return }
                self.push(ProfilePage(memberID: person.id, api: self.api))
            }
            let header = Theme.stack([avatar, open], axis: .horizontal)
            header.alignment = .center
            list.addArrangedSubview(Theme.card([header, Theme.label(person.bio, color: Theme.secondary)]))
        }
    }
}

final class ThreadPage: CityPage, PHPickerViewControllerDelegate {
    private let peerID: UUID
    private let list = Theme.stack()
    private let input = Theme.field("Message")
    private var sendButton: UIButton?
    private var photoButton: UIButton?
    private let photoComposer = Theme.stack(spacing: 8)
    private var selectedPhoto: (id: UUID, bytes: Data, image: UIImage)?
    private var maySend = false
    private var isPreparingPhoto = false
    private var newest: [Message] = []
    private var older: [Message] = []
    private var hasEarlier = true
    private var loadingEarlier = false
    private var loadTask: Task<Void, Never>?
    private var liveTask: Task<Void, Never>?
    private var pending: (id: UUID, text: String)?
    private var isSending = false

    init(peerID: UUID, peerName: String, api: CommunityAPI) {
        self.peerID = peerID
        super.init(peerName, api: api)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        actions.addArrangedSubview(Theme.icon("profile", label: "View profile") { [weak self] in
            guard let self else { return }
            self.push(ProfilePage(memberID: self.peerID, api: self.api))
        })
        let send = Theme.button("Send", accent: true) { [weak self] in self?.send() }
        send.isEnabled = false
        sendButton = send
        let photo = Theme.button("Add photo") { [weak self] in self?.choosePhoto() }
        photoButton = photo
        body.addArrangedSubview(Theme.stack([input, send], axis: .horizontal))
        body.addArrangedSubview(photo)
        body.addArrangedSubview(photoComposer)
        body.addArrangedSubview(list)
        updateComposer()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
        liveTask?.cancel()
        liveTask = Task { [weak self, api] in
            await api.watchMessages { [weak self] in self?.reload() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        liveTask?.cancel()
        loadTask?.cancel()
    }

    private func reload() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let records = self.api.thread(self.peerID)
                async let follows = self.api.follows()
                let (messages, relationships) = try await (records, follows)
                guard !Task.isCancelled else { return }
                let maySend = relationships.contains { $0.followerId == self.api.memberID && $0.targetId == self.peerID }
                    && relationships.contains { $0.followerId == self.peerID && $0.targetId == self.api.memberID }
                if let edge = messages.last {
                    let displaced = self.newest.filter { old in old.createdAt < edge.createdAt }
                    let known = Set(self.older.map(\.id))
                    self.older.append(contentsOf: displaced.filter { !known.contains($0.id) })
                }
                if !maySend {
                    self.older.removeAll()
                    self.hasEarlier = true
                }
                self.newest = messages
                self.maySend = maySend
                if let selected = self.selectedPhoto, messages.contains(where: { $0.id == selected.id && $0.senderId == self.api.memberID && $0.photoPath != nil }) {
                    self.selectedPhoto = nil
                }
                self.updateComposer()
                self.showStatus(maySend ? nil : "Messaging is available when both members follow each other.")
                self.render()
                if let observed = messages.first(where: { $0.senderId == self.peerID }) {
                    try? await self.api.setPreference(["last_read_at": observed.createdAt], peer: self.peerID)
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.showStatus("Messages could not be refreshed.")
                self.maySend = false
                self.updateComposer()
                self.list.clear()
                self.list.addArrangedSubview(Theme.button("Retry") { [weak self] in self?.reload() })
            }
        }
    }

    private func render() {
        list.clear()
        let ids = Set(newest.map(\.id))
        let rows = newest + older.filter { !ids.contains($0.id) }.sorted { $0.createdAt > $1.createdAt }
        guard !rows.isEmpty else {
            list.addArrangedSubview(Theme.empty("No messages yet", "Say hello to start the conversation."))
            return
        }
        for message in rows {
            let own = message.senderId == api.memberID
            let title = Theme.label(own ? "You" : heading, size: 15, color: own ? Theme.mint : Theme.gold, display: true)
            let card = Theme.card([title])
            if message.photoPath != nil {
                card.addArrangedSubview(Theme.button("View photo") { [weak self] in
                    guard let self else { return }
                    self.push(ChatPhotoPage(message: message, api: self.api))
                })
            } else {
                card.addArrangedSubview(Theme.label(message.body))
            }
            if !own {
                card.addArrangedSubview(Theme.button("Report message") { [weak self] in
                    self?.report(["message_id": message.id.uuidString])
                })
            }
            list.addArrangedSubview(card)
        }
        if newest.count == 50 && hasEarlier {
            list.addArrangedSubview(Theme.button("Older messages") { [weak self] in self?.loadOlder(rows.last?.createdAt) })
        }
    }

    private func loadOlder(_ timestamp: String?) {
        guard let timestamp, !loadingEarlier else { return }
        loadingEarlier = true
        Task {
            defer { loadingEarlier = false }
            do {
                let messages = try await api.thread(peerID, before: timestamp)
                hasEarlier = messages.count == 50
                let known = Set(older.map(\.id))
                older.append(contentsOf: messages.filter { !known.contains($0.id) })
                if messages.isEmpty { showStatus("You reached the beginning of the conversation.") }
                render()
            } catch { alert(error.localizedDescription) }
        }
    }

    private func send() {
        guard maySend, !isSending else { return }
        let text = (input.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...2000).contains(text.count) else { alert("Use 1–2,000 characters."); return }
        let id = pending?.text == text ? pending?.id ?? UUID() : UUID()
        pending = (id, text)
        isSending = true
        updateComposer()
        Task {
            defer { isSending = false; updateComposer(); reload() }
            do {
                try await api.send(text, to: peerID, id: id)
                pending = nil
                input.text = nil
            } catch { alert(error.localizedDescription) }
        }
    }

    private func updateComposer() {
        let ready = maySend && !isSending && !isPreparingPhoto
        sendButton?.isEnabled = ready
        input.isEnabled = ready
        photoButton?.isEnabled = ready && selectedPhoto == nil
        photoComposer.clear()
        photoComposer.isHidden = selectedPhoto == nil
        guard let selectedPhoto else { return }

        let preview = UIImageView(image: selectedPhoto.image)
        preview.contentMode = .scaleAspectFit
        preview.heightAnchor.constraint(equalToConstant: 140).isActive = true
        preview.isAccessibilityElement = true
        preview.accessibilityLabel = "Selected photo"
        let send = Theme.button(isSending ? "Sending…" : "Send photo", accent: true) { [weak self] in self?.sendSelectedPhoto() }
        send.isEnabled = ready
        let remove = Theme.button("Remove photo") { [weak self] in
            self?.selectedPhoto = nil
            self?.updateComposer()
        }
        remove.isEnabled = !isSending
        let actions = Theme.stack([send, remove], axis: .horizontal)
        actions.distribution = .fillEqually
        photoComposer.addArrangedSubview(Theme.card([preview, actions]))
    }

    private func choosePhoto() {
        guard maySend, !isSending, !isPreparingPhoto, selectedPhoto == nil else { return }
        view.endEditing(true)
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        isPreparingPhoto = true
        updateComposer()
        Task {
            defer { isPreparingPhoto = false; updateComposer() }
            do {
                let bytes = try await ChatPhoto.pick(from: provider)
                let image = await Task.detached(priority: .userInitiated) { ChatPhoto.decode(bytes) }.value
                guard let image else { throw CommunityError.invalidInput("This photo could not be opened.") }
                selectedPhoto = (UUID(), bytes, UIImage(cgImage: image))
            } catch { alert(error.localizedDescription) }
        }
    }

    private func sendSelectedPhoto() {
        guard maySend, !isSending, let selectedPhoto else { return }
        isSending = true
        updateComposer()
        Task {
            defer { isSending = false; updateComposer(); reload() }
            do {
                try await api.sendPhoto(selectedPhoto.bytes, to: peerID, id: selectedPhoto.id)
                self.selectedPhoto = nil
            } catch {
                alert("The photo could not be confirmed. Try sending it again.")
            }
        }
    }

}
