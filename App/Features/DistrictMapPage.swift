import UIKit

private extension CityDistrict {
    var coordinate: CGPoint {
        switch self {
        case .central: return CGPoint(x: 0.5, y: 0.50)
        case .sahara: return CGPoint(x: 0.21, y: 0.23)
        case .tundra: return CGPoint(x: 0.79, y: 0.25)
        case .rainforest: return CGPoint(x: 0.50, y: 0.78)
        }
    }
}

private final class DistrictMapView: UIView {
    private let routes = CAShapeLayer()
    private var markers: [CityDistrict: UIButton] = [:]

    init(select: @escaping (CityDistrict) -> Void) {
        super.init(frame: .zero)
        clipsToBounds = true
        layer.cornerRadius = 22
        backgroundColor = Theme.panel
        let artwork = Theme.artwork("city-map")
        artwork.alpha = 0.85
        artwork.translatesAutoresizingMaskIntoConstraints = false
        addSubview(artwork)
        NSLayoutConstraint.activate([
            artwork.leadingAnchor.constraint(equalTo: leadingAnchor),
            artwork.trailingAnchor.constraint(equalTo: trailingAnchor),
            artwork.topAnchor.constraint(equalTo: topAnchor),
            artwork.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        routes.strokeColor = Theme.mint.withAlphaComponent(0.65).cgColor
        routes.lineWidth = 2
        routes.lineDashPattern = [4, 5]
        routes.fillColor = nil
        layer.addSublayer(routes)
        for district in CityDistrict.allCases {
            let marker = UIButton(type: .custom)
            marker.layer.cornerRadius = 14
            marker.layer.borderWidth = 1
            marker.backgroundColor = Theme.ink.withAlphaComponent(0.92)
            marker.titleLabel?.font = Theme.font(13, display: true)
            marker.titleLabel?.numberOfLines = 2
            marker.titleLabel?.textAlignment = .center
            marker.setTitle(district.name, for: .normal)
            marker.setTitleColor(Theme.paper, for: .normal)
            marker.addAction(UIAction { _ in select(district) }, for: .touchUpInside)
            addSubview(marker)
            markers[district] = marker
        }
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        routes.frame = bounds
        let path = UIBezierPath()
        let center = point(for: .central)
        let markerWidth = min(120, bounds.width * 0.35)
        for district in CityDistrict.allCases {
            let position = point(for: district)
            let marker = markers[district]
            marker?.bounds = CGRect(x: 0, y: 0, width: markerWidth, height: 52)
            marker?.center = position
            if district != .central {
                path.move(to: center)
                path.addLine(to: position)
            }
        }
        routes.path = path.cgPath
    }

    private func point(for district: CityDistrict) -> CGPoint {
        CGPoint(x: bounds.width * district.coordinate.x, y: bounds.height * district.coordinate.y)
    }

    func update(selected: CityDistrict, activeID: String, ledger: WalletLedger?) {
        for (district, marker) in markers {
            let isCurrent = district.rawValue == activeID
            let locked = district != .central && ledger?.isUnlocked(district) != true
            marker.layer.borderColor = (district == selected ? Theme.mint : Theme.line).cgColor
            marker.layer.borderWidth = district == selected ? 2 : 1
            marker.setTitleColor(locked ? Theme.secondary : Theme.paper, for: .normal)
            marker.accessibilityLabel = district.name
            marker.accessibilityValue = isCurrent ? "Current district" : locked ? "Locked" : "Unlocked"
            marker.accessibilityTraits = district == selected ? [.button, .selected] : .button
        }
    }
}

final class DistrictMapPage: CityPage, SafetyObserving {
    private let wallet: Wallet
    private let memberID: UUID
    private let summary = Theme.label("", size: 16, color: Theme.secondary)
    private let detail = Theme.stack()
    private let builtDistricts = Theme.stack()
    private var selected = CityDistrict.central
    private var activeID = CityDistrict.central.rawValue
    private var districtGuides: [CatalogItem] = []
    private var catalogTask: Task<Void, Never>?
    private lazy var map = DistrictMapView { [weak self] district in
        self?.selected = district
        self?.render()
    }

    init(memberID: UUID, wallet: Wallet, api: CommunityAPI) {
        self.memberID = memberID
        self.wallet = wallet
        super.init("Districts", api: api)
    }

    required init?(coder: NSCoder) { nil }

    func safetyDidChange() {
        districtGuides.removeAll { api.isHidden($0) }
        reloadGuides()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeSafetyChanges()
        let walletButton = Theme.icon("wallet", label: "Wallet") { [weak self] in self?.showWallet() }
        actions.addArrangedSubview(walletButton)
        body.addArrangedSubview(summary)
        map.heightAnchor.constraint(equalTo: map.widthAnchor, multiplier: 0.75).isActive = true
        body.addArrangedSubview(map)
        body.addArrangedSubview(detail)
        body.addArrangedSubview(Theme.card([
            Theme.label("Build your own district", size: 23, display: true),
            Theme.label("Choose a theme and put your own streets, buildings, and attractions on the map.", color: Theme.secondary),
            Theme.button("Build a district · \(BuiltDistrict.price.formatted()) diamonds", icon: "diamond") { [weak self] in
                self?.openBuilder()
            }
        ]))
        body.addArrangedSubview(builtDistricts)
        NotificationCenter.default.addObserver(self, selector: #selector(render), name: Wallet.didChange, object: wallet)
        enableRefresh { [weak self] in self?.reloadGuides() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        render()
        if districtGuides.isEmpty, catalogTask == nil { reloadGuides() }
    }

    private func reloadGuides() {
        catalogTask?.cancel()
        catalogTask = Task { [weak self, api] in
            guard let self else { return }
            defer { if !Task.isCancelled { self.catalogTask = nil } }
            do {
                let guides = try await api.catalog().filter { $0.kind == "District" }
                try Task.checkCancellation()
                _ = try wallet.ledger(for: memberID)
                districtGuides = guides
                render()
                showStatus(nil)
                pageRefresh.finish()
            } catch {
                guard !Task.isCancelled else { return }
                showStatus("The city could not be updated. Pull down to try again.")
                pageRefresh.finish(error: "The city could not be updated. Pull down to try again.")
            }
        }
    }

    @objc private func render() {
        let ledger = try? wallet.ledger(for: memberID)
        let custom = ledger?.builtDistricts ?? []
        let activeName = CityDistrict(rawValue: activeID)?.name ?? custom.first(where: { $0.mapID == activeID })?.name
        let diamondBalance = ledger.map { "\($0.balance.formatted()) diamonds" } ?? "Balance unavailable"
        summary.text = activeName.map { "You are in \($0) · \(diamondBalance)" } ?? diamondBalance
        map.update(selected: selected, activeID: activeID, ledger: ledger)
        renderOfficialDistrict(ledger)
        renderBuiltDistricts(custom, walletAvailable: ledger != nil)
    }

    private func renderOfficialDistrict(_ ledger: WalletLedger?) {
        detail.clear()
        let district = selected
        let title = Theme.label(district.name, size: 25, display: true)
        title.accessibilityTraits.insert(.header)
        let card = Theme.card([title, Theme.label(district.overview, color: Theme.secondary)])
        detail.addArrangedSubview(card)
        if district != .central && ledger?.isUnlocked(district) != true {
            let price = district.diamondCost.formatted()
            let unlock = Theme.button("Unlock for \(price) diamonds", accent: true) { [weak self] in self?.confirmUnlock(district) }
            unlock.isEnabled = ledger != nil
            card.addArrangedSubview(unlock)
        } else {
            card.addArrangedSubview(Theme.label("2 streets · 2 buildings · 2 attractions", size: 15, color: Theme.secondary))
            card.addArrangedSubview(Theme.button("Explore district", accent: true) { [weak self] in self?.openDistrict(district) })
        }
    }

    private func renderBuiltDistricts(_ districts: [BuiltDistrict], walletAvailable: Bool) {
        builtDistricts.clear()
        let title = Theme.label("My districts", size: 24, display: true)
        title.accessibilityTraits.insert(.header)
        builtDistricts.addArrangedSubview(title)
        if districts.isEmpty {
            let message = walletAvailable ? "Districts you build will appear here." : "Your districts are unavailable. Open the wallet to check your balance."
            builtDistricts.addArrangedSubview(Theme.label(message, color: Theme.secondary))
        }
        for district in districts {
            let details = Theme.label("\(district.style.title) · \(district.places.count) places to explore", size: 15, color: Theme.secondary)
            let open = Theme.textAction(district.name) { [weak self] in self?.openBuiltDistrict(district) }
            open.accessibilityHint = "Opens the district map"
            builtDistricts.addArrangedSubview(Theme.card([open, details], spacing: 4))
        }
    }

    private func openDistrict(_ district: CityDistrict) {
        activeID = district.rawValue
        render()
        let guide = districtGuides.first { $0.id == district.rawValue }
        push(DistrictExplorePage(name: district.name, districtID: district.rawValue, artwork: district.artwork,
                                 overview: district.overview, places: district.places, memberID: memberID, guide: guide, api: api))
    }

    private func openBuilder() {
        push(DistrictBuilderPage(memberID: memberID, wallet: wallet, api: api) { [weak self] district in
            self?.openBuiltDistrict(district, replacingBuilder: true)
        })
    }

    private func openBuiltDistrict(_ district: BuiltDistrict, replacingBuilder: Bool = false) {
        activeID = district.mapID
        render()
        let page = DistrictExplorePage(name: district.name, districtID: district.mapID, artwork: district.style.artwork,
                                       overview: "Your \(district.style.title.lowercased()) district is ready to explore.",
                                       places: district.places, memberID: memberID, api: api)
        if replacingBuilder, let navigationController, navigationController.topViewController is DistrictBuilderPage {
            navigationController.setViewControllers(Array(navigationController.viewControllers.dropLast()) + [page], animated: true)
        } else {
            push(page)
        }
    }

    private func confirmUnlock(_ district: CityDistrict) {
        guard let ledger = try? wallet.ledger(for: memberID), !ledger.isUnlocked(district) else { return }
        let price = district.diamondCost.formatted()
        guard ledger.balance >= district.diamondCost else {
            let alert = ThemedDialog(title: "Not enough diamonds",
                                          message: "\(district.name) costs \(price) diamonds.", preferredStyle: .alert)
            alert.addChoice("Wallet", style: .default) { [weak self] in self?.showWallet() }
            alert.addChoice("Cancel", style: .cancel)
            present(alert, animated: true)
            return
        }
        let alert = ThemedDialog(title: "Unlock \(district.name)?",
                                      message: "Spend \(price) diamonds to unlock this district and its places.", preferredStyle: .alert)
        alert.addChoice("Cancel", style: .cancel)
        alert.addChoice("Unlock", style: .default) { [weak self] in
            guard let self else { return }
            do {
                try self.wallet.unlock(district, for: self.memberID)
                self.openDistrict(district)
            } catch { self.alert(error.localizedDescription) }
        }
        present(alert, animated: true)
    }

    private func showWallet() { push(WalletPage(memberID: memberID, wallet: wallet, api: api)) }
}
