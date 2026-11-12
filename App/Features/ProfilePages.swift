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
        Choice(id: "expo-duo", name: "Anime Expo duo", crop: nil)
    ]
    static let credit = URL(string: "https://commons.wikimedia.org/wiki/File:Cosplay_of_Judy_Hopps_and_Nick_Wilde_from_Zootopia_at_Anime_Expo_2016_(28086759383).jpg")
    static func view(_ id: String?, size: CGFloat) -> UIView {
        let avatar = UIImageView()
        avatar.contentMode = .scaleAspectFit
        let choice = choices.first { $0.id == id }
        Task { [weak avatar] in
            if let choice, let photo = await Artwork.image(at: Artwork.expoPortrait) {
                let crop = choice.crop.flatMap { photo.cgImage?.cropping(to: $0) }
                avatar?.contentMode = .scaleAspectFill
                avatar?.image = crop.map { UIImage(cgImage: $0) } ?? photo
            } else {
                avatar?.image = await Artwork.image("profile")
            }
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
}

final class ProfilePage: CityPage {
    private let memberID: UUID
    private let wallet: Wallet?
    private let onSignOut: (() -> Void)?
    private var profile: Member?
    private var stats: MemberCounts?
    private var relations: [Follow] = []
    private var items: [CatalogItem] = []
    private var works: [MemberWork] = []
    private var reactions: [Reaction] = []
    private var scope = "Saved"
    private let content = Theme.stack(spacing: 10)
    private var loadTask: Task<Void, Never>?
    private var own: Bool { memberID == api.memberID }

    init(memberID: UUID, api: CommunityAPI, wallet: Wallet? = nil, onSignOut: (() -> Void)? = nil) {
        self.memberID = memberID
        self.wallet = wallet
        self.onSignOut = onSignOut
        super.init(memberID == api.memberID ? "Me" : "Profile", api: api)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        if own, let onSignOut {
            actions.addArrangedSubview(Theme.icon("settings", label: "Settings") { [weak self] in
                guard let self else { return }
                self.push(SettingsPage(memberID: self.memberID, api: self.api, onSignOut: onSignOut))
            })
        }
        if let wallet {
            NotificationCenter.default.addObserver(self, selector: #selector(walletChanged),
                                                   name: Wallet.didChange, object: wallet)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    @objc private func walletChanged() { if isViewLoaded, view.window != nil { render() } }

    private func reload() {
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                async let member = self.api.member(self.memberID)
                async let counts = self.api.counts(self.memberID)
                async let relations = self.api.follows()
                async let works = self.api.works(owner: self.memberID)
                let (profile, stats, follows, memberWorks) = try await (member, counts, relations, works)
                let collection = self.own ? try await self.api.catalog() : []
                let reactions = self.own ? try await self.api.reactions() : []
                guard !Task.isCancelled else { return }
                self.profile = profile
                self.stats = stats
                self.relations = follows
                self.items = collection
                self.works = memberWorks
                self.reactions = reactions
                self.showStatus(nil)
                self.render()
            } catch {
                guard !Task.isCancelled else { return }
                self.showStatus("This profile could not be loaded.")
                self.body.clear()
                self.body.addArrangedSubview(Theme.button("Retry") { [weak self] in self?.reload() })
            }
        }
    }

    private func render() {
        guard let profile, let stats else { return }
        body.clear()
        let name = Theme.label(profile.displayName, size: 25, display: true)
        let bio = Theme.label(profile.bio.isEmpty && own ? "Add a bio in Settings." : profile.bio, color: Theme.secondary)
        let identity = Theme.stack([MemberAvatar.view(profile.avatar, size: 70), Theme.stack([name, bio], spacing: 4)], axis: .horizontal)
        identity.alignment = .center
        let statsRow = Theme.stack([
            stat(stats.followers, title: "Followers"),
            stat(stats.following, title: "Following"),
            stat(stats.friends, title: "Friends")
        ], axis: .horizontal)
        statsRow.distribution = .fillEqually
        body.addArrangedSubview(Theme.card([identity, statsRow]))
        if own {
            if let wallet {
                let balance = (try? wallet.ledger(for: memberID)).map { "\($0.balance) diamonds" } ?? "Balance unavailable"
                body.addArrangedSubview(Theme.card([
                    Theme.label(balance, size: 22, color: Theme.gold, display: true),
                    Theme.button("Wallet & top up", icon: "wallet", accent: true) { [weak self] in
                        guard let self else { return }
                        self.push(WalletPage(memberID: self.memberID, wallet: wallet, api: self.api))
                    }
                ]))
            }
            let categories = Theme.stack(["Saved", "Liked", "Works"].map { name in
                Theme.button(name, accent: scope == name) { [weak self] in self?.scope = name; self?.render() }
            }, spacing: 8, axis: .horizontal)
            categories.distribution = .fillEqually
            body.addArrangedSubview(categories)
            body.addArrangedSubview(content)
            renderCollection()
        } else {
            renderRelationships(profile)
            body.addArrangedSubview(Theme.label("Works", size: 22, display: true))
            if works.isEmpty { body.addArrangedSubview(Theme.empty("No public works", "Approved works appear here.")) }
            for work in works { body.addArrangedSubview(workCard(work)) }
        }
    }

    private func stat(_ count: Int, title: String) -> UIView {
        let value = Theme.label(String(count), size: 21, color: Theme.mint, display: true)
        let caption = Theme.label(title, size: 13, color: Theme.secondary)
        value.textAlignment = .center
        caption.textAlignment = .center
        return Theme.stack([value, caption], spacing: 2)
    }

    private func renderCollection() {
        content.clear()
        if scope == "Works" {
            content.addArrangedSubview(Theme.button("Submit a video", icon: "shorts", accent: true) { [weak self] in
                guard let self else { return }
                self.push(SubmitWorkPage(api: self.api))
            })
            if works.isEmpty { content.addArrangedSubview(Theme.empty("No works", "Submitted videos and their review status appear here.")) }
            for work in works { content.addArrangedSubview(workCard(work)) }
            return
        }
        let kind = scope == "Liked" ? "like" : "save"
        let ids = Set(reactions.filter { $0.kind == kind }.map(\.catalogId))
        let matches = items.filter { ids.contains($0.id) }
        if matches.isEmpty {
            content.addArrangedSubview(Theme.empty("Nothing here yet", scope == "Liked" ? "Like something to find it here." : "Save shorts, districts, and looks to revisit them here."))
        }
        let columns = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 1 : 2
        for start in stride(from: 0, to: matches.count, by: columns) {
            let cards = matches[start..<min(start + columns, matches.count)].enumerated().map { entry in
                let item = entry.element
                let picture = EditorialImage(item: item)
                picture.heightAnchor.constraint(equalToConstant: 88).isActive = true
                return Theme.card([picture, Theme.button(item.title) { [weak self] in
                    guard let self else { return }
                    self.push(CatalogDetail(items: matches, index: start + entry.offset, api: self.api))
                }])
            }
            let row = Theme.stack(cards, spacing: 8, axis: .horizontal)
            row.distribution = .fillEqually
            if columns == 2 && cards.count == 1 { row.addArrangedSubview(UIView()) }
            content.addArrangedSubview(row)
        }
    }

    private func workCard(_ work: MemberWork) -> UIView {
        let card = Theme.card([
            Theme.label(work.title, size: 22, display: true),
            Theme.label(work.caption, color: Theme.secondary),
            Theme.button("Watch at source", icon: "shorts") { [weak self] in self?.open(work.sourceUrl) }
        ])
        if own {
            card.addArrangedSubview(Theme.label(work.status == "pending" ? "Pending review" : work.status.capitalized,
                                                size: 15, color: Theme.mint))
            card.addArrangedSubview(Theme.button("Remove submission") { [weak self] in self?.removeWork(work) })
        } else {
            card.addArrangedSubview(Theme.button("Report") { [weak self] in self?.report(["work_id": work.id.uuidString]) })
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
        let row = Theme.stack([follow, message], axis: .horizontal)
        row.distribution = .fillEqually
        body.addArrangedSubview(row)
        body.addArrangedSubview(Theme.button("Safety options") { [weak self] in self?.safety() })
    }

    private func changeFollow(to enabled: Bool) {
        Task {
            do { try await api.setRelationship("follows", peer: memberID, enabled: enabled); reload() }
            catch { alert(error.localizedDescription) }
        }
    }

    private func safety() {
        menu("Safety", choices: [
            ("Report member", .default, { [weak self] in
                guard let self else { return }
                self.report(["reported_id": self.memberID.uuidString])
            }),
            ("Block member", .destructive, { [weak self] in
                guard let self else { return }
                Task {
                    do {
                        try await self.api.setRelationship("blocks", peer: self.memberID, enabled: true)
                        self.navigationController?.popToRootViewController(animated: true)
                    } catch { self.alert(error.localizedDescription) }
                }
            })
        ])
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
        preview.addArrangedSubview(MemberAvatar.view(avatar, size: 64))
        preview.addArrangedSubview(Theme.button("Choose avatar") { [weak self] in
            guard let self else { return }
            var choices: [(String, UIAlertAction.Style, () -> Void)] = [
                ("City badge", .default, { [weak self] in self?.avatar = nil; self?.renderAvatar() })
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
        body.addArrangedSubview(Theme.card([Theme.label("Diamond balance", color: Theme.secondary), balance]))
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
    }

    @objc private func updateLedger() {
        history.clear()
        do {
            let ledger = try wallet.ledger(for: memberID)
            balance.text = ledger.balance.formatted()
            if ledger.purchases.isEmpty { history.addArrangedSubview(Theme.empty("No purchases yet", "Completed purchases appear here.")) }
            for purchase in ledger.purchases {
                history.addArrangedSubview(Theme.card([
                    Theme.label("+\(purchase.diamonds.formatted()) diamonds", color: Theme.mint, display: true),
                    Theme.label(purchase.date.formatted(date: .abbreviated, time: .shortened), color: Theme.secondary)
                ]))
            }
        } catch { balance.text = "Unavailable"; showStatus(error.localizedDescription) }
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
