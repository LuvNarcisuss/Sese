import UIKit
import PhotosUI

final class InboxPage: CityPage {
    private let list = Theme.stack()
    private let searchField = Theme.field("Search chats")
    private var rows: [InboxItem] = []
    private enum Scope { case friends, conversations, archived }
    private var scope = Scope.friends
    private var friends: [ChatFriend] = []
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
            self?.menu("Chats", choices: [
                ("Friends", .default, { [weak self] in self?.select(.friends) }),
                ("Conversations", .default, { [weak self] in self?.select(.conversations) }),
                ("Archived", .default, { [weak self] in self?.select(.archived) })
            ])
        })
        actions.addArrangedSubview(Theme.icon("profile", label: "Find friends") { [weak self] in self?.browse() })
        searchField.isHidden = true
        search(searchField, into: body) { [weak self] _ in self?.render() }
        body.addArrangedSubview(list)
        enableRefresh { [weak self] in self?.reload() }
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

    private func select(_ scope: Scope) {
        self.scope = scope
        searchField.resignFirstResponder()
        searchField.text = nil
        searchField.isHidden = true
        render()
    }

    private func reload() {
        loadTask?.cancel()
        if !loaded { showStatus("Loading chats…") }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let inbox = self.api.inbox()
                async let contacts = self.api.chatFriends()
                let (rows, friends) = try await (inbox, contacts)
                guard !Task.isCancelled else { return }
                self.rows = rows
                self.friends = friends
                self.loaded = true
                self.showStatus(nil)
                self.render()
                self.pageRefresh.finish()
            } catch {
                guard !Task.isCancelled else { return }
                self.showStatus("Chats could not be refreshed.")
                self.pageRefresh.finish(error: "Chats could not be updated. Pull down to try again.")
                if !self.loaded {
                    self.list.clear()
                    self.list.addArrangedSubview(Theme.button("Retry") { [weak self] in self?.reload() })
                }
            }
        }
    }

    private func render() {
        guard loaded else { return }
        list.clear()
        let query = searchField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch scope {
        case .friends:
            if friends.isEmpty {
                showInvitation()
                return
            }
            let recent = Dictionary(uniqueKeysWithValues: rows.filter { !$0.archived }.map { ($0.peerId, $0) })
            let matched = friends.compactMap { friend -> (ChatFriend, InboxItem?)? in
                let row = recent[friend.id]
                let name = friend.profile?.displayName ?? row?.displayName ?? "City Resident"
                guard query.isEmpty || name.localizedCaseInsensitiveContains(query) ||
                    row?.body.localizedCaseInsensitiveContains(query) == true else { return nil }
                return (friend, row)
            }.sorted { left, right in
                if (left.1?.pinned ?? false) != (right.1?.pinned ?? false) { return left.1?.pinned == true }
                let leftName = left.0.profile?.displayName ?? left.1?.displayName ?? ""
                let rightName = right.0.profile?.displayName ?? right.1?.displayName ?? ""
                return leftName.localizedStandardCompare(rightName) == .orderedAscending
            }
            if matched.isEmpty {
                list.addArrangedSubview(Theme.empty("No matching friends", "Try a different name."))
            }
            for (friend, row) in matched {
                list.addArrangedSubview(chatRow(peer: friend.id, name: friend.profile?.displayName ?? row?.displayName ?? "City Resident",
                                                avatarID: friend.profile?.avatar ?? row?.avatar, conversation: row))
            }
        case .conversations, .archived:
            let archive = scope == .archived
            let matches = rows.filter { $0.archived == archive &&
                (query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query)) }
            if matches.isEmpty {
                if !query.isEmpty { list.addArrangedSubview(Theme.empty("No matching conversations", "Try another name or message.")) }
                else if archive { list.addArrangedSubview(Theme.empty("No archived chats", "Conversations you archive appear here.")) }
                else { list.addArrangedSubview(Theme.empty("No conversations", "Messages you send or receive appear here.")) }
            }
            for row in matches {
                list.addArrangedSubview(chatRow(peer: row.peerId, name: row.displayName, avatarID: row.avatar, conversation: row))
            }
        }
    }

    private func showInvitation() {
        let heading = Theme.label("Good conversations start with hello", size: 32, display: true)
        heading.accessibilityTraits.insert(.header)
        list.addArrangedSubview(heading)
        list.addArrangedSubview(Theme.label("Meet the people who make this city feel like home.", color: Theme.secondary))
        let artwork = Theme.artwork("chats", mode: .scaleAspectFit)
        artwork.heightAnchor.constraint(equalToConstant: Theme.iconSize).isActive = true
        list.addArrangedSubview(Theme.card([
            artwork,
            Theme.label("Find your first friend", size: 24, display: true),
            Theme.label("Follow each other to start a private chat.", color: Theme.secondary),
            Theme.button("Find friends", accent: true) { [weak self] in self?.browse() }
        ]))
    }

    private func chatRow(peer: UUID, name: String, avatarID: String?, conversation: InboxItem?) -> UIView {
        let avatar = MemberAvatar.button(avatarID, size: Theme.iconSize, label: "Open \(name)’s profile", memberID: peer) { [weak self] in
            guard let self else { return }
            self.push(ProfilePage(memberID: peer, api: self.api))
        }
        let chat = Theme.textAction(name) { [weak self] in
            guard let self else { return }
            self.push(ThreadPage(peerID: peer, peerName: name, api: self.api))
        }
        let header = Theme.stack([avatar, chat], spacing: 8, axis: .horizontal)
        header.alignment = .center
        if let conversation {
            header.addArrangedSubview(Theme.moreIcon(label: "Conversation options") { [weak self] in self?.options(conversation) })
        }
        let card = Theme.card([header])
        if let conversation {
            let preview = Theme.label(conversation.body, color: Theme.secondary)
            preview.numberOfLines = 2
            card.addArrangedSubview(preview)
            let details = [conversation.pinned ? "Pinned" : nil, conversation.muted ? "Muted" : nil,
                           conversation.unread ? "Unread" : nil].compactMap { $0 }
            if !details.isEmpty {
                card.addArrangedSubview(Theme.label(details.joined(separator: " · "), size: 14, color: Theme.mint))
            }
        }
        return card
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
    private var loadTask: Task<Void, Never>?
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
        enableRefresh { [weak self] in self?.reload() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    private func reload() {
        loadTask?.cancel()
        loadTask = Task {
            do {
                async let members = api.members()
                async let follows = api.follows()
                let (users, relationships) = try await (members, follows)
                try Task.checkCancellation()
                people = users.filter { $0.id != api.memberID }
                following = Set(relationships.filter { $0.followerId == api.memberID }.map(\.targetId))
                followers = Set(relationships.filter { $0.targetId == api.memberID }.map(\.followerId))
                showStatus(nil)
                render()
                pageRefresh.finish()
            } catch {
                guard !Task.isCancelled else { return }
                showStatus("Members could not be loaded.")
                pageRefresh.finish(error: "Members could not be updated. Pull down to try again.")
                if list.arrangedSubviews.isEmpty {
                    list.addArrangedSubview(Theme.button("Retry") { [weak self] in self?.reload() })
                }
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
            let openProfile: () -> Void = { [weak self] in
                guard let self else { return }
                self.push(ProfilePage(memberID: person.id, api: self.api))
            }
            let avatar = MemberAvatar.button(person.avatar, size: 50, label: "Open \(person.displayName)’s profile",
                                             memberID: person.id, action: openProfile)
            let open = Theme.textAction(person.displayName, action: openProfile)
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
        enableRefresh { [weak self] in self?.reload() }
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
                if !Task.isCancelled { self.pageRefresh.finish() }
            } catch {
                guard !Task.isCancelled else { return }
                self.showStatus("Messages could not be refreshed.")
                self.pageRefresh.finish(error: "Messages could not be updated. Pull down to try again.")
                self.maySend = false
                self.updateComposer()
                if self.list.arrangedSubviews.isEmpty {
                    self.list.addArrangedSubview(Theme.button("Retry") { [weak self] in self?.reload() })
                }
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
