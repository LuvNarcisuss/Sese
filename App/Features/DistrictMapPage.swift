import UIKit

private struct DistrictStop {
    let name: String
    let description: String
}

private extension CityDistrict {
    var artwork: String { self == .central ? "background" : rawValue }

    var coordinate: CGPoint {
        switch self {
        case .central: return CGPoint(x: 0.5, y: 0.50)
        case .sahara: return CGPoint(x: 0.21, y: 0.23)
        case .tundra: return CGPoint(x: 0.79, y: 0.25)
        case .rainforest: return CGPoint(x: 0.50, y: 0.78)
        }
    }

    var overview: String {
        switch self {
        case .central: return "Start in the city center, where the transit lines meet beneath the skyline."
        case .sahara: return "Follow the palm-lined avenues into warm stone plazas lit by evening lanterns."
        case .tundra: return "Cross snowy streets and watch elevated trains pass through the city's coldest district."
        case .rainforest: return "Explore misty terraces and suspended paths among the layered tree canopy."
        }
    }

    var stops: [DistrictStop] {
        switch self {
        case .central:
            return [
                .init(name: "Central Station", description: "The city's transit hub links the downtown concourse with each climate district."),
                .init(name: "City Hall Plaza", description: "Follow the plaza's broad steps for a view of the downtown skyline and elevated trains.")
            ]
        case .sahara:
            return [
                .init(name: "Lantern Market", description: "At sundown, lanterns light the stalls along this warm sandstone lane."),
                .init(name: "Palm Promenade", description: "Palm trees frame an open avenue with shaded benches and views across the district.")
            ]
        case .tundra:
            return [
                .init(name: "Frostline Station", description: "Watch trains cross the snow on a route above the district's streets."),
                .init(name: "Glacier Walk", description: "Snowbanks and blue ice line this sheltered pedestrian route.")
            ]
        case .rainforest:
            return [
                .init(name: "Canopy Walk", description: "A suspended walkway crosses the trees and looks down through several levels of canopy."),
                .init(name: "Mist Terrace", description: "At the lower terrace, fine mist drifts around platforms woven through the forest.")
            ]
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

    func update(selected: CityDistrict, active: CityDistrict, ledger: WalletLedger?) {
        for (district, marker) in markers {
            let visited = district == active
            let locked = district != .central && ledger?.isUnlocked(district) != true
            marker.layer.borderColor = (district == selected ? Theme.mint : Theme.line).cgColor
            marker.layer.borderWidth = district == selected ? 2 : 1
            marker.setTitleColor(locked ? Theme.secondary : Theme.paper, for: .normal)
            marker.accessibilityLabel = district.name
            marker.accessibilityValue = visited ? "Current district" : locked ? "Locked" : "Unlocked"
            marker.accessibilityTraits = district == selected ? [.button, .selected] : .button
        }
    }
}

final class DistrictMapPage: CityPage {
    private let wallet: Wallet
    private let memberID: UUID
    private let summary = Theme.label("", size: 16, color: Theme.secondary)
    private let detail = Theme.stack()
    private var selected = CityDistrict.central
    private var active = CityDistrict.central
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

    override func viewDidLoad() {
        super.viewDidLoad()
        let walletButton = Theme.icon("wallet", label: "Wallet") { [weak self] in self?.showWallet() }
        actions.addArrangedSubview(walletButton)
        body.addArrangedSubview(summary)
        map.heightAnchor.constraint(equalTo: map.widthAnchor, multiplier: 0.75).isActive = true
        body.addArrangedSubview(map)
        body.addArrangedSubview(detail)
        NotificationCenter.default.addObserver(self, selector: #selector(render), name: Wallet.didChange, object: wallet)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        render()
        if districtGuides.isEmpty, catalogTask == nil {
            catalogTask = Task { [weak self, api] in
                let guides = try? await api.catalog().filter { $0.kind == "District" }
                guard let self, !Task.isCancelled else { return }
                self.districtGuides = guides ?? []
                self.catalogTask = nil
                self.render()
            }
        }
    }

    @objc private func render() {
        let ledger = try? wallet.ledger(for: memberID)
        let diamondBalance = ledger.map { "\($0.balance.formatted()) diamonds" } ?? "Balance unavailable"
        summary.text = "You are in \(active.name) · \(diamondBalance)"
        map.update(selected: selected, active: active, ledger: ledger)
        detail.clear()

        let district = selected
        let cover = Theme.artwork(district.artwork)
        cover.layer.cornerRadius = 12
        cover.heightAnchor.constraint(equalToConstant: 116).isActive = true
        let title = Theme.label(district.name, size: 25, display: true)
        title.accessibilityTraits.insert(.header)
        let card = Theme.card([cover, title, Theme.label(district.overview, color: Theme.secondary)])
        detail.addArrangedSubview(card)

        if district != .central && ledger?.isUnlocked(district) != true {
            let price = district.diamondCost.formatted()
            let unlock = Theme.button("Unlock for \(price) diamonds", accent: true) { [weak self] in self?.confirmUnlock(district) }
            unlock.isEnabled = ledger != nil
            card.addArrangedSubview(unlock)
            return
        }
        if district != active {
            card.addArrangedSubview(Theme.button("Visit district", accent: true) { [weak self] in
                self?.active = district
                self?.render()
            })
            return
        }

        detail.addArrangedSubview(Theme.label("Explore landmarks", size: 22, display: true))
        for stop in district.stops {
            detail.addArrangedSubview(Theme.button(stop.name) { [weak self] in
                let alert = UIAlertController(title: stop.name, message: stop.description, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Close", style: .cancel))
                self?.present(alert, animated: true)
            })
        }
        if let index = districtGuides.firstIndex(where: { $0.id == district.rawValue }) {
            detail.addArrangedSubview(Theme.button("Read the district guide") { [weak self] in
                guard let self else { return }
                self.push(CatalogDetail(items: [self.districtGuides[index]], index: 0, api: self.api))
            })
        }
    }

    private func confirmUnlock(_ district: CityDistrict) {
        guard let ledger = try? wallet.ledger(for: memberID), !ledger.isUnlocked(district) else { return }
        let price = district.diamondCost.formatted()
        guard ledger.balance >= district.diamondCost else {
            let alert = UIAlertController(title: "Not enough diamonds",
                                          message: "\(district.name) costs \(price) diamonds.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Wallet", style: .default) { [weak self] _ in self?.showWallet() })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
            return
        }
        let alert = UIAlertController(title: "Unlock \(district.name)?",
                                      message: "Spend \(price) diamonds to unlock this district and its landmarks.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Unlock", style: .default) { [weak self] _ in
            guard let self else { return }
            do {
                try self.wallet.unlock(district, for: self.memberID)
                self.active = district
                self.render()
            } catch { self.alert(error.localizedDescription) }
        })
        present(alert, animated: true)
    }

    private func showWallet() { push(WalletPage(memberID: memberID, wallet: wallet, api: api)) }
}
