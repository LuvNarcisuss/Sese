import UIKit
import StoreKit

@MainActor
enum MemberAvatar {
    struct Choice {
        let id: String
        let name: String
        let crop: CGRect?
    }

    static let choices: [Choice] = [
        Choice(id: "expo-judy", name: "Judy Hopps cosplay", crop: CGRect(x: 410, y: 135, width: 373, height: 373)),
        Choice(id: "expo-nick", name: "Nick Wilde cosplay", crop: CGRect(x: 249, y: 0, width: 303, height: 303)),
        Choice(id: "expo-duo", name: "Anime Expo duo", crop: CGRect(x: 115, y: 0, width: 740, height: 740)),
        Choice(id: "fan-duo", name: "KodachiCon duo", crop: CGRect(x: 355, y: 255, width: 920, height: 920))
    ]
    static let credit = URL(string: "https://commons.wikimedia.org/wiki/File:Cosplay_of_Judy_Hopps_and_Nick_Wilde_from_Zootopia_at_Anime_Expo_2016_(28086759383).jpg")
    static let fanCredit = URL(string: "https://commons.wikimedia.org/wiki/File:KodachiCon_2026_19_-_Judy_%26_Nick.jpg")

    static func view(_ id: String?, size: CGFloat, memberID: UUID? = nil) -> UIView {
        let avatar = UIImageView()
        avatar.contentMode = .scaleAspectFill
        let fallbackIndex = Int(memberID?.uuid.0 ?? 0) % choices.count
        let choice = choices.first { $0.id == id } ?? choices[fallbackIndex]
        Task { [weak avatar] in
            let url = choice.id == "fan-duo" ? Artwork.fanPortrait : Artwork.expoPortrait
            guard let photo = await Artwork.image(at: url) else { return }
            let crop = choice.crop.flatMap { photo.cgImage?.cropping(to: $0) }
            avatar?.image = crop.map { UIImage(cgImage: $0) } ?? photo
        }
        avatar.backgroundColor = Theme.ink
        avatar.clipsToBounds = true
        avatar.layer.cornerRadius = size / 2
        avatar.layer.borderColor = Theme.line.cgColor
        avatar.layer.borderWidth = 1
        avatar.widthAnchor.constraint(equalToConstant: size).isActive = true
        avatar.heightAnchor.constraint(equalTo: avatar.widthAnchor).isActive = true
        return avatar
    }

    static func button(_ id: String?, size: CGFloat, label: String, memberID: UUID? = nil,
                       action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .custom)
        let portrait = view(id, size: size, memberID: memberID)
        portrait.isUserInteractionEnabled = false
        portrait.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(portrait)
        NSLayoutConstraint.activate([
            portrait.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            portrait.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            portrait.topAnchor.constraint(equalTo: button.topAnchor),
            portrait.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        button.accessibilityLabel = label
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
}

final class ProfilePage: CityPage {
    private enum Category: String {
        case shorts = "Shorts"
        case cosplay = "Cosplay"
        case liked = "Liked"
        case saved = "Saved"
    }

    private let memberID: UUID
    private let wallet: Wallet?
    private let onSignOut: (() -> Void)?
    private let avatar = Theme.stack()
    private let name = Theme.label("", size: 25, display: true)
    private let bio = Theme.label("", color: Theme.secondary)
    private let metrics = Theme.stack(spacing: 6, axis: .horizontal)
    private let relationshipActions = Theme.stack()
    private let balance = Theme.label("", size: 22, color: Theme.gold, display: true)
    private let categories = Theme.stack()
    private let content = Theme.stack(spacing: 10)
    private var profile: Member?
    private var stats: MemberCounts?
    private var relations: [Follow] = []
    private var items: [CatalogItem] = []
    private var works: [MemberWork] = []
    private var cosplayPosts: [CosplayPost]?
    private var reactions: [Reaction] = []
    private var workReactions: [PublicationReaction]?
    private var cosplayReactions: [PublicationReaction]?
    private var reactedWorks: [MemberWork] = []
    private var reactedCosplay: [CosplayPost] = []
    private var category: Category = .shorts
    private var loadTask: Task<Void, Never>?
    private var own: Bool { memberID == api.memberID }

    init(memberID: UUID, api: CommunityAPI, wallet: Wallet? = nil, onSignOut: (() -> Void)? = nil) {
        self.memberID = memberID
        self.wallet = wallet
        self.onSignOut = onSignOut
        super.init(memberID == api.memberID ? "Me" : "Profile", api: api)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        if own, let onSignOut {
            actions.addArrangedSubview(Theme.icon("settings", label: "Settings") { [weak self] in
                guard let self else { return }
                self.push(SettingsPage(memberID: self.memberID, api: self.api, onSignOut: onSignOut))
            })
        } else if !own {
            actions.addArrangedSubview(Theme.moreIcon(label: "Report member") { [weak self] in
                guard let self, self.profile != nil else { return }
                self.report(["reported_id": self.memberID.uuidString])
            })
        }
        let identity = Theme.stack([avatar, Theme.stack([name, bio], spacing: 4)], axis: .horizontal)
        identity.alignment = .center
        metrics.distribution = .fillEqually
        body.addArrangedSubview(Theme.card([identity, metrics]))
        if own, let wallet {
            body.addArrangedSubview(Theme.card([
                balance,
                Theme.button("Wallet & top up", icon: "wallet", accent: true) { [weak self] in
                    guard let self else { return }
                    self.push(WalletPage(memberID: self.memberID, wallet: wallet, api: self.api))
                }
            ]))
            walletChanged()
            NotificationCenter.default.addObserver(self, selector: #selector(walletChanged),
                                                   name: Wallet.didChange, object: wallet)
        }
        if !own { body.addArrangedSubview(relationshipActions) }
        body.addArrangedSubview(categories)
        body.addArrangedSubview(content)
        renderCategories()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    @objc private func walletChanged() {
        guard let wallet else { return }
        balance.text = (try? wallet.ledger(for: memberID)).map { "\($0.balance.formatted()) diamonds" } ?? "Balance unavailable"
    }

    private func reload() {
        loadTask?.cancel()
        if profile == nil { showStatus("Loading profile…") }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let member = api.member(memberID)
                async let counts = api.counts(memberID)
                async let follows = api.follows()
                async let memberWorks = api.works(owner: memberID)
                async let cosplay = try? api.cosplayPosts(owner: memberID)
                async let catalog = api.catalog()
                let (person, countsValue, followsValue, ownedWorks, availableCatalog) =
                    try await (member, counts, follows, memberWorks, catalog)
                let ownedCosplay = await cosplay
                guard !Task.isCancelled else { return }
                let previous = profile
                profile = person
                stats = countsValue
                relations = followsValue
                works = ownedWorks
                cosplayPosts = ownedCosplay
                items = availableCatalog
                if previous == nil || previous?.avatar != person.avatar {
                    avatar.clear()
                    avatar.addArrangedSubview(MemberAvatar.view(person.avatar, size: 70, memberID: person.id))
                }
                name.text = person.displayName
                bio.text = person.bio.isEmpty && own ? "Add a bio in Settings." : person.bio
                renderMetrics()
                if !own { renderRelationships(person) }
                showStatus(nil)
                renderCollection()
            } catch {
                guard !Task.isCancelled else { return }
                showStatus("This profile could not be refreshed.")
                if profile == nil {
                    content.clear()
                    content.addArrangedSubview(Theme.button("Retry") { [weak self] in self?.reload() })
                }
                return
            }
            if own { await reloadCollections() }
        }
    }

    private func reloadCollections() async {
        async let editorial = try? api.reactions()
        async let videos = try? api.publicationReactions(.work)
        async let cosplay = try? api.publicationReactions(.cosplay)
        let (editorialRows, videoRows, cosplayRows) = await (editorial, videos, cosplay)
        async let videoItems = try? api.works(ids: Set((videoRows ?? []).map(\.item)))
        async let cosplayItems = try? api.cosplayPosts(ids: Set((cosplayRows ?? []).map(\.item)))
        let (relatedVideos, relatedCosplay) = await (videoItems, cosplayItems)
        guard !Task.isCancelled else { return }
        if let editorialRows { reactions = editorialRows }
        workReactions = relatedVideos == nil ? nil : videoRows
        cosplayReactions = relatedCosplay == nil ? nil : cosplayRows
        reactedWorks = relatedVideos ?? []
        reactedCosplay = relatedCosplay ?? []
        collectionError = editorialRows == nil || videoRows == nil || cosplayRows == nil || relatedVideos == nil || relatedCosplay == nil
        collectionsLoaded = true
        if category == .liked || category == .saved { renderCollection() }
    }

    private var collectionsLoaded = false
    private var collectionError = false

    private func renderMetrics() {
        metrics.clear()
        let hasShorts = works.contains { $0.status == "approved" } || items.contains { $0.publisherId == memberID && $0.isVideo }
        let hasCosplayVideos = cosplayPosts.map { posts in posts.contains { $0.mediaKind == .video && $0.status == "approved" } }
        let emptyTotal: Int? = !hasShorts && hasCosplayVideos == false ? 0 : nil
        metrics.addArrangedSubview(profileStat(stats?.likes ?? emptyTotal, title: "Likes"))
        metrics.addArrangedSubview(profileStat(stats?.saves ?? emptyTotal, title: "Saves"))
        metrics.addArrangedSubview(profileStat(stats?.following, title: "Following"))
    }

    private func renderCategories() {
        let tabs: [Category] = own ? [.shorts, .cosplay, .liked, .saved] : [.shorts, .cosplay]
        categories.clear()
        categories.addArrangedSubview(profileTabs(tabs.map(\.rawValue), selected: category.rawValue, compact: own) { [weak self] name in
            guard let self, let selected = Category(rawValue: name), selected != self.category else { return }
            self.category = selected
            self.renderCategories()
            self.renderCollection()
        })
    }

    private func renderCollection() {
        guard profile != nil else { return }
        content.clear()
        switch category {
        case .shorts: renderShorts()
        case .cosplay: renderCosplay()
        case .liked: renderReactions(kind: "like")
        case .saved: renderReactions(kind: "save")
        }
    }

    private func renderReactions(kind: String) {
        guard collectionsLoaded else {
            content.addArrangedSubview(Theme.label("Loading collection…", color: Theme.secondary))
            return
        }
        let ids = Set(reactions.filter { $0.kind == kind }.map(\.catalogId))
        let videos = Set((workReactions ?? []).filter { $0.kind == kind }.map(\.item))
        let cosplay = Set((cosplayReactions ?? []).filter { $0.kind == kind }.map(\.item))
        let matches = items.filter { ids.contains($0.id) }
        let memberVideos = reactedWorks.filter { videos.contains($0.id) }
        let memberCosplay = reactedCosplay.filter { cosplay.contains($0.id) }
        if collectionError {
            content.addArrangedSubview(Theme.label("Some saved activity could not be loaded.", color: Theme.secondary))
            content.addArrangedSubview(Theme.textAction("Retry") { [weak self] in self?.reload() })
        } else if matches.isEmpty && memberVideos.isEmpty && memberCosplay.isEmpty {
            content.addArrangedSubview(Theme.empty("Nothing here yet", kind == "like" ? "Videos you like will appear here." : "Saved items will appear here."))
        }
        addCatalog(matches)
        for work in memberVideos { content.addArrangedSubview(workCard(work)) }
        addCosplayPosts(memberCosplay)
    }

    private func renderShorts() {
        let hosted = items.filter { $0.publisherId == memberID && $0.isVideo && $0.mediaUrl != nil }
        let card = hosted.isEmpty && works.isEmpty
            ? Theme.empty("No shorts yet", own ? "Submitted shorts and their review status appear here." : "Published shorts appear here.")
            : Theme.card([])
        if own {
            card.addArrangedSubview(Theme.button("Submit a video", icon: "shorts", accent: true) { [weak self] in
                guard let self else { return }
                self.push(SubmitWorkPage(api: self.api))
            })
        }
        if !card.arrangedSubviews.isEmpty { content.addArrangedSubview(card) }
        addCatalog(hosted)
        for work in works { content.addArrangedSubview(workCard(work)) }
    }

    private func renderCosplay() {
        let card = cosplayPosts?.isEmpty == true
            ? Theme.empty("No cosplay posts", own ? "Your submissions and their review status appear here." : "Published photos and videos appear here.")
            : Theme.card([])
        if cosplayPosts == nil {
            card.addArrangedSubview(Theme.label("Cosplay posts could not be loaded.", color: Theme.secondary))
            card.addArrangedSubview(Theme.textAction("Retry") { [weak self] in self?.reload() })
        }
        if own {
            card.addArrangedSubview(Theme.button("Post cosplay", icon: "shorts", accent: true) { [weak self] in
                guard let self else { return }
                self.push(ComposeCosplayPage(api: self.api) {})
            })
        }
        if !card.arrangedSubviews.isEmpty { content.addArrangedSubview(card) }
        if let cosplayPosts { addCosplayPosts(cosplayPosts) }
    }

    private func addCatalog(_ items: [CatalogItem]) {
        addVideoTiles(items, to: content, accessible: traitCollection.preferredContentSizeCategory.isAccessibilityCategory) { [weak self] item in
            guard let self, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
            self.push(CatalogDetail(items: items, index: index, api: self.api))
        }
    }

    private func addCosplayPosts(_ posts: [CosplayPost]) {
        let cards = posts.map { post in
            CosplayPostCard.make(post, api: api, open: { [weak self] in
                guard let self else { return }
                self.push(CosplayPostPage(post: post, api: self.api))
            })
        }
        addProfileTiles(cards, to: content, accessible: traitCollection.preferredContentSizeCategory.isAccessibilityCategory)
    }

    private func workCard(_ work: MemberWork) -> UIView {
        let card = Theme.card([
            Theme.textAction(work.title) { [weak self] in
                guard let self else { return }
                self.push(MemberWorkPage(work: work, api: self.api))
            },
            Theme.label(work.caption, color: Theme.secondary)
        ])
        if own && work.ownerId == memberID {
            card.addArrangedSubview(Theme.label(work.status == "pending" ? "Pending review" : work.status.capitalized,
                                                size: 15, color: Theme.mint))
            card.addArrangedSubview(Theme.textAction("Remove submission") { [weak self] in self?.removeWork(work) })
        }
        return card
    }

    private func removeWork(_ work: MemberWork) {
        menu("Remove this submission?", choices: [("Remove", .destructive, { [weak self] in
            guard let self else { return }
            Task {
                do { try await self.api.removeWork(work.id); self.reload() }
                catch { self.alert(error.localizedDescription) }
            }
        })])
    }

    private func renderRelationships(_ profile: Member) {
        relationshipActions.clear()
        let following = relations.contains { $0.followerId == api.memberID && $0.targetId == memberID }
        let followedBy = relations.contains { $0.followerId == memberID && $0.targetId == api.memberID }
        let follow = Theme.button(following ? "Following" : "Follow", accent: !following) { [weak self] in
            self?.changeFollow(to: !following)
        }
        let message = Theme.button("Message", icon: "chats") { [weak self] in
            guard let self else { return }
            if following && followedBy {
                self.push(ThreadPage(peerID: profile.id, peerName: profile.displayName, api: self.api))
            } else {
                self.alert("Follow each other to start a conversation.")
            }
        }
        let block = Theme.button("Block") { [weak self] in self?.confirmBlock() }
        let accessible = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        let row = Theme.stack([follow, message, block], spacing: 6, axis: accessible ? .vertical : .horizontal)
        row.distribution = .fillEqually
        relationshipActions.addArrangedSubview(row)
    }

    private func changeFollow(to enabled: Bool) {
        Task {
            do { try await api.setRelationship("follows", peer: memberID, enabled: enabled); reload() }
            catch { alert(error.localizedDescription) }
        }
    }

    private func confirmBlock() {
        menu("Block this member?", choices: [("Block", .destructive, { [weak self] in
            guard let self else { return }
            Task {
                do {
                    try await self.api.setRelationship("blocks", peer: self.memberID, enabled: true)
                    self.navigationController?.popToRootViewController(animated: true)
                } catch { self.alert(error.localizedDescription) }
            }
        })])
    }
}

@MainActor
func profileStat(_ value: Int?, title: String) -> UIView {
    let count = Theme.label(value.map { $0.formatted() } ?? "—", size: 21, color: Theme.mint, display: true)
    let caption = Theme.label(title, size: 13, color: Theme.secondary)
    count.textAlignment = .center
    caption.textAlignment = .center
    return Theme.stack([count, caption], spacing: 2)
}

@MainActor
func profileTabs(_ names: [String], selected: String, compact: Bool = false, choose: @escaping (String) -> Void) -> UIStackView {
    let row = Theme.stack(names.map { name in
        let button = Theme.button(name, accent: selected == name) { choose(name) }
        if compact {
            button.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 4, bottom: 10, trailing: 4)
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.4
        }
        button.accessibilityTraits = selected == name ? [.button, .selected] : .button
        return button
    }, spacing: 8, axis: .horizontal)
    row.distribution = .fillEqually
    return row
}

@MainActor
func addVideoTiles(_ items: [CatalogItem], to stack: UIStackView, accessible: Bool, open: @escaping (CatalogItem) -> Void) {
    let tiles = items.map { item -> UIView in
        let photo = EditorialImage(item: item)
        photo.heightAnchor.constraint(equalTo: photo.widthAnchor, multiplier: 0.86).isActive = true
        let tile = Theme.card([photo, Theme.label(item.title, size: 16, display: true)], spacing: 6)
        let target = UIButton(type: .custom)
        target.accessibilityLabel = item.title
        target.translatesAutoresizingMaskIntoConstraints = false
        target.addAction(UIAction { _ in open(item) }, for: .touchUpInside)
        tile.addSubview(target)
        NSLayoutConstraint.activate([
            target.leadingAnchor.constraint(equalTo: tile.leadingAnchor), target.trailingAnchor.constraint(equalTo: tile.trailingAnchor),
            target.topAnchor.constraint(equalTo: tile.topAnchor), target.bottomAnchor.constraint(equalTo: tile.bottomAnchor)
        ])
        tile.arrangedSubviews.forEach { $0.isAccessibilityElement = false }
        return tile
    }
    addProfileTiles(tiles, to: stack, accessible: accessible)
}

@MainActor
private func addProfileTiles(_ tiles: [UIView], to stack: UIStackView, accessible: Bool) {
    if accessible {
        tiles.forEach { stack.addArrangedSubview($0) }
        return
    }
    for start in stride(from: 0, to: tiles.count, by: 2) {
        let cards = Array(tiles[start..<min(start + 2, tiles.count)])
        let row = Theme.stack(cards.count == 1 ? cards + [UIView()] : cards, spacing: 8, axis: .horizontal)
        row.distribution = .fillEqually
        row.alignment = .top
        stack.addArrangedSubview(row)
    }
}

final class SettingsPage: CityPage {
    private let memberID: UUID
    private let onSignOut: () -> Void

    init(memberID: UUID, api: CommunityAPI, onSignOut: @escaping () -> Void) {
        self.memberID = memberID
        self.onSignOut = onSignOut
        super.init("Settings", api: api)
    }
    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        body.addArrangedSubview(Theme.card([
            Theme.button("Edit profile", icon: "profile") { [weak self] in
                guard let self else { return }
                self.push(EditProfilePage(memberID: self.memberID, api: self.api))
            },
            Theme.button("Blocked members") { [weak self] in
                guard let self else { return }
                self.push(BlockedPage(api: self.api))
            }
        ]))
        body.addArrangedSubview(Theme.card([
            Theme.button("Terms of Service") { [weak self] in self?.agreement(.terms) },
            Theme.button("Privacy Policy") { [weak self] in self?.agreement(.privacy) },
            Theme.button("Media credits") { [weak self] in
                guard let self else { return }
                self.push(CreditsPage(api: self.api))
            }
        ]))
        body.addArrangedSubview(Theme.card([
            Theme.button("Sign out") { [weak self] in self?.accountAction(delete: false) },
            Theme.button("Delete account") { [weak self] in self?.accountAction(delete: true) }
        ]))
    }

    private func agreement(_ kind: AgreementKind) {
        push(AgreementPage(kind: kind, agreement: api.agreements?.document(kind)))
    }

    private func accountAction(delete: Bool) {
        let title = delete ? "Delete your account?" : "Sign out?"
        let message = delete ? "Your community profile, reactions, messages, and shared chat photos will be removed." :
            "Use the same Apple Account to sign back in and access your community profile on this device."
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: delete ? "Delete account" : "Sign out", style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task {
                do {
                    if delete { try await self.api.deleteAccount() } else { try await self.api.signOut() }
                    self.onSignOut()
                } catch { self.alert(error.localizedDescription) }
            }
        })
        present(alert, animated: true)
    }
}

final class EditProfilePage: CityPage {
    private let memberID: UUID
    private let name = Theme.field("Display name")
    private let bio = Theme.field("Bio")
    private let directory = UISwitch()
    private let preview = Theme.stack(axis: .horizontal)
    private var avatar: String?
    private var saveButton: UIButton?

    init(memberID: UUID, api: CommunityAPI) {
        self.memberID = memberID
        super.init("Edit profile", api: api)
    }
    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        directory.accessibilityLabel = "Show in member directory"
        let privacy = Theme.stack([Theme.label("Show in member directory"), directory], axis: .horizontal)
        privacy.alignment = .center
        body.addArrangedSubview(preview)
        if let credit = MemberAvatar.credit {
            body.addArrangedSubview(Theme.button("Photo: Oliver Ayala · CC BY 2.0") { [weak self] in self?.open(credit) })
        }
        if let credit = MemberAvatar.fanCredit {
            body.addArrangedSubview(Theme.button("Photo: Rose Abrams · CC BY 4.0") { [weak self] in self?.open(credit) })
        }
        body.addArrangedSubview(name)
        body.addArrangedSubview(bio)
        body.addArrangedSubview(Theme.card([privacy]))
        let save = Theme.button("Save profile", accent: true) { [weak self] in self?.save() }
        body.addArrangedSubview(save)
        saveButton = save
        reload()
    }

    private func reload() {
        saveButton?.isEnabled = false
        showStatus("Loading profile…")
        Task {
            do {
                let profile = try await api.member(memberID)
                name.text = profile.displayName
                bio.text = profile.bio
                directory.isOn = profile.discoverable
                avatar = profile.avatar
                renderAvatar()
                showStatus(nil)
                saveButton?.isEnabled = true
            } catch {
                showStatus("Profile could not be loaded.")
                if let saveButton {
                    body.addArrangedSubview(Theme.button("Retry") { [weak self, weak saveButton] in
                        guard saveButton?.isEnabled == false else { return }
                        self?.reload()
                    })
                }
            }
        }
    }

    private func renderAvatar() {
        preview.clear()
        preview.alignment = .center
        preview.addArrangedSubview(MemberAvatar.view(avatar, size: 64, memberID: memberID))
        preview.addArrangedSubview(Theme.button("Choose avatar") { [weak self] in
            guard let self else { return }
            var choices: [(String, UIAlertAction.Style, () -> Void)] = [
                ("Community portrait", .default, { [weak self] in self?.avatar = nil; self?.renderAvatar() })
            ]
            choices.append(contentsOf: MemberAvatar.choices.map { choice in
                (choice.name, .default, { [weak self] in self?.avatar = choice.id; self?.renderAvatar() })
            })
            self.menu("Avatar", choices: choices)
        })
    }

    private func save() {
        saveButton?.isEnabled = false
        Task {
            defer { saveButton?.isEnabled = true }
            do {
                try await api.updateProfile(memberID, name: name.text ?? "", bio: bio.text ?? "",
                                            avatar: avatar, discoverable: directory.isOn)
                navigationController?.popViewController(animated: true)
            } catch { alert(error.localizedDescription) }
        }
    }
}

final class BlockedPage: CityPage {
    init(api: CommunityAPI) { super.init("Blocked members", api: api) }
    required init?(coder: NSCoder) { return nil }
    override func viewDidLoad() { super.viewDidLoad(); reload() }

    private func reload() {
        Task {
            do {
                let records = try await api.blocks()
                body.clear()
                if records.isEmpty { body.addArrangedSubview(Theme.empty("No blocked members", "Members you block will appear here.")) }
                for (index, record) in records.enumerated() {
                    body.addArrangedSubview(Theme.card([
                        Theme.label("Blocked member \(index + 1)", display: true),
                        Theme.button("Unblock") { [weak self] in self?.unblock(record.targetId) }
                    ]))
                }
            } catch { showStatus("Blocked members could not be loaded.") }
        }
    }

    private func unblock(_ peer: UUID) {
        Task {
            do { try await api.setRelationship("blocks", peer: peer, enabled: false); reload() }
            catch { alert(error.localizedDescription) }
        }
    }
}

final class CreditsPage: CityPage {
    init(api: CommunityAPI) { super.init("Media credits", api: api) }
    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        body.addArrangedSubview(Theme.empty("Fan community", "Zootopia and its characters belong to Disney. This community is independently operated."))
        body.addArrangedSubview(Theme.empty("Artwork and type", "The interface artwork was created with ImageGen. Fredoka and Comic Neue are distributed under the SIL Open Font License."))
        Task {
            do {
                for item in try await api.catalog() {
                    body.addArrangedSubview(Theme.card([Theme.label(item.title, display: true),
                        Theme.button(item.credit) { [weak self] in self?.open(item.sourceUrl) }]))
                }
            } catch { showStatus("Source credits could not be refreshed.") }
        }
    }
}

final class WalletPage: CityPage {
    private let memberID: UUID
    private let wallet: Wallet
    private let balance = Theme.label("", size: 38, color: Theme.gold, display: true)
    private let offerGrid = Theme.stack(spacing: 8)
    private let offerStatus = Theme.label("", size: 15, color: Theme.secondary)
    private let history = Theme.stack()
    private let refresh = UIRefreshControl()
    private var offers: [WalletOffer] = []
    private var products: [String: Product] = [:]
    private var diamondImage: UIImage?
    private var catalogRequest: Task<Void, Never>?
    private var catalogTimeout: Task<Void, Never>?
    private var buying = false

    init(memberID: UUID, wallet: Wallet, api: CommunityAPI) {
        self.memberID = memberID
        self.wallet = wallet
        super.init("Wallet", api: api)
    }
    required init?(coder: NSCoder) { return nil }

    deinit {
        catalogRequest?.cancel()
        catalogTimeout?.cancel()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        balance.accessibilityIdentifier = "wallet.balance"
        let balanceRow = Theme.stack([diamondArtwork(size: 58), balance], spacing: 10, axis: .horizontal)
        balanceRow.alignment = .center
        body.addArrangedSubview(Theme.card([Theme.label("Diamond balance", color: Theme.secondary), balanceRow]))
        body.addArrangedSubview(Theme.label("Diamond packs", size: 24, display: true))
        body.addArrangedSubview(offerStatus)
        body.addArrangedSubview(offerGrid)
        body.addArrangedSubview(Theme.label("Purchase history", size: 24, display: true))
        body.addArrangedSubview(history)
        scroll.alwaysBounceVertical = true
        refresh.tintColor = Theme.mint
        refresh.addTarget(self, action: #selector(refreshWallet), for: .valueChanged)
        scroll.refreshControl = refresh
        NotificationCenter.default.addObserver(self, selector: #selector(updateLedger), name: Wallet.didChange, object: wallet)
        NotificationCenter.default.addObserver(self, selector: #selector(renderOffers),
                                               name: UIContentSizeCategory.didChangeNotification, object: nil)
        updateLedger()
        loadOffers()
        Task { [weak self] in
            guard let art = await Artwork.image("diamond"), let self else { return }
            self.diamondImage = art.scaled(to: 52)
            self.renderOffers()
        }
    }

    private func diamondArtwork(size: CGFloat) -> UIView {
        let icon = Theme.artwork("diamond", mode: .scaleAspectFit)
        icon.widthAnchor.constraint(equalToConstant: size).isActive = true
        icon.heightAnchor.constraint(equalToConstant: size).isActive = true
        return icon
    }

    @objc private func updateLedger() {
        history.clear()
        do {
            let ledger = try wallet.ledger(for: memberID)
            balance.text = ledger.balance.formatted()
            if ledger.purchases.isEmpty { history.addArrangedSubview(Theme.empty("No purchases yet", "Completed purchases appear here.")) }
            for purchase in ledger.purchases {
                let row = Theme.stack([
                    diamondArtwork(size: 40),
                    Theme.stack([
                        Theme.label("+\(purchase.diamonds.formatted()) diamonds", color: Theme.mint, display: true),
                        Theme.label(purchase.date.formatted(date: .abbreviated, time: .shortened), color: Theme.secondary)
                    ], spacing: 4)
                ], spacing: 8, axis: .horizontal)
                row.alignment = .center
                history.addArrangedSubview(Theme.card([row]))
            }
            let unlocks = (ledger.districtUnlocks ?? [:]).sorted { $0.value.date > $1.value.date }
            if !unlocks.isEmpty {
                history.addArrangedSubview(Theme.label("District unlocks", size: 22, display: true))
                for (id, unlock) in unlocks {
                    guard let district = CityDistrict(rawValue: id) else { continue }
                    addDistrictDebit(district.name, diamonds: unlock.diamonds, date: unlock.date)
                }
            }
            if let districts = ledger.builtDistricts, !districts.isEmpty {
                history.addArrangedSubview(Theme.label("District builds", size: 22, display: true))
                for district in districts.sorted(by: { $0.date > $1.date }) {
                    addDistrictDebit(district.name, diamonds: district.diamonds, date: district.date)
                }
            }
        } catch { balance.text = "Unavailable"; showStatus(error.localizedDescription) }
    }

    private func addDistrictDebit(_ title: String, diamonds: Int, date: Date) {
        let row = Theme.stack([
            diamondArtwork(size: 40),
            Theme.stack([
                Theme.label(title, size: 17, display: true),
                Theme.label("−\(diamonds.formatted()) diamonds", color: Theme.gold),
                Theme.label(date.formatted(date: .abbreviated, time: .shortened), color: Theme.secondary)
            ], spacing: 4)
        ], spacing: 8, axis: .horizontal)
        row.alignment = .center
        history.addArrangedSubview(Theme.card([row]))
    }

    @objc private func refreshWallet() {
        guard !buying else { refresh.endRefreshing(); return }
        showStatus(nil)
        updateLedger()
        wallet.recover(for: memberID)
        loadOffers()
    }

    private func loadOffers() {
        guard catalogRequest == nil else { return }
        do {
            offers = try wallet.offers()
            guard !offers.isEmpty else { throw WalletError.invalidCatalog }
        } catch {
            finishLoading([:], message: "Diamond packs are unavailable. Pull down to try again.")
            return
        }

        products = [:]
        setOfferStatus("Checking the App Store…")
        catalogRequest = Task { [weak self, wallet] in
            do {
                let products = try await wallet.catalog()
                guard !Task.isCancelled, let self else { return }
                self.finishLoading(products, message: self.availabilityMessage(for: products))
            } catch {
                guard !Task.isCancelled else { return }
                self?.finishLoading([:], message: "The App Store could not load prices. Pull down to try again.")
            }
        }
        catalogTimeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.catalogRequest?.cancel()
            self.finishLoading([:], message: "The App Store is taking too long. Pull down to try again.")
        }
        renderOffers()
    }

    private func availabilityMessage(for products: [String: Product]) -> String? {
        if !AppStore.canMakePayments { return WalletError.paymentsRestricted.errorDescription }
        if products.isEmpty { return "No diamond packs are available right now. Pull down to check again." }
        if products.count < offers.count { return "Some packs are unavailable. Pull down to check again." }
        return nil
    }

    private func finishLoading(_ products: [String: Product], message: String?) {
        catalogTimeout?.cancel()
        catalogTimeout = nil
        catalogRequest = nil
        self.products = products
        setOfferStatus(message)
        renderOffers()
        refresh.endRefreshing()
    }

    private func setOfferStatus(_ message: String?) {
        offerStatus.text = message
        offerStatus.isHidden = message == nil
    }

    @objc private func renderOffers() {
        offerGrid.clear()
        offerGrid.isHidden = offers.isEmpty
        let columns = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 1 : 3
        for start in stride(from: 0, to: offers.count, by: columns) {
            let row = Theme.stack(spacing: 8, axis: .horizontal)
            row.distribution = .fillEqually
            for offer in offers[start..<min(start + columns, offers.count)] {
                row.addArrangedSubview(offerButton(offer, product: products[offer.productID]))
            }
            offerGrid.addArrangedSubview(row)
        }
    }

    private func offerButton(_ offer: WalletOffer, product: Product?) -> UIButton {
        let quantity = offer.diamonds.formatted()
        let price = product?.displayPrice ?? (catalogRequest == nil ? "Unavailable" : "—")
        var titleAttributes = AttributeContainer()
        titleAttributes.font = Theme.font(21, display: true)
        var priceAttributes = AttributeContainer()
        priceAttributes.font = Theme.font(14)
        var config = UIButton.Configuration.filled()
        config.attributedTitle = AttributedString(quantity, attributes: titleAttributes)
        config.attributedSubtitle = AttributedString(price, attributes: priceAttributes)
        config.image = diamondImage
        config.imagePlacement = .top
        config.imagePadding = 2
        config.baseForegroundColor = Theme.paper
        config.baseBackgroundColor = Theme.panel
        config.background.strokeColor = Theme.line
        config.background.strokeWidth = 1
        config.cornerStyle = .large
        config.titleAlignment = .center
        config.titlePadding = 4
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 6, bottom: 10, trailing: 6)
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            self?.confirmPurchase(offer)
        })
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 68).isActive = true
        button.isEnabled = product != nil && !buying && AppStore.canMakePayments
        button.accessibilityIdentifier = "wallet.package.\(offer.diamonds)"
        button.accessibilityLabel = "\(quantity) diamonds"
        button.accessibilityValue = product?.displayPrice ?? (catalogRequest == nil ? "Unavailable" : "Checking price")
        return button
    }

    private func confirmPurchase(_ offer: WalletOffer) {
        guard !buying, let product = products[offer.productID], presentedViewController == nil else { return }
        let confirmation = UIAlertController(title: "Buy \(offer.diamonds.formatted()) diamonds?",
                                             message: product.displayPrice, preferredStyle: .alert)
        confirmation.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        confirmation.addAction(UIAlertAction(title: "Continue", style: .default) { [weak self] _ in
            self?.buy(product)
        })
        present(confirmation, animated: true)
    }

    private func buy(_ product: Product) {
        guard !buying, products[product.id] != nil, let scene = viewIfLoaded?.window?.windowScene else { return }
        buying = true
        showStatus(nil)
        renderOffers()
        Task {
            defer { buying = false; renderOffers() }
            do { if let message = try await wallet.buy(product, member: memberID, in: scene) { showStatus(message) } }
            catch WalletError.productUnavailable {
                products.removeValue(forKey: product.id)
                setOfferStatus(availabilityMessage(for: products))
                showStatus(WalletError.productUnavailable.errorDescription)
            }
            catch let error as WalletError { showStatus(error.localizedDescription) }
            catch { showStatus("The purchase could not be completed. Please try again.") }
        }
    }
}
