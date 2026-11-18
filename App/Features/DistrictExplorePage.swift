import UIKit

private extension DistrictPlaceKind {
    var tint: UIColor {
        switch self {
        case .street: return Theme.mint
        case .building: return Theme.gold
        case .attraction: return UIColor(red: 0.84, green: 0.69, blue: 1, alpha: 1)
        }
    }
}

private final class DistrictStreetMap: UIView {
    private let routes = CAShapeLayer()
    private let places: [DistrictPlace]
    private var pins: [UIButton] = []

    init(artwork: String, places: [DistrictPlace], open: @escaping (DistrictPlace) -> Void) {
        self.places = places
        super.init(frame: .zero)
        layer.cornerRadius = 22
        clipsToBounds = true
        backgroundColor = Theme.panel
        let scene = Theme.artwork(artwork)
        scene.alpha = 0.58
        scene.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scene)
        NSLayoutConstraint.activate([
            scene.leadingAnchor.constraint(equalTo: leadingAnchor), scene.trailingAnchor.constraint(equalTo: trailingAnchor),
            scene.topAnchor.constraint(equalTo: topAnchor), scene.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        routes.strokeColor = Theme.paper.withAlphaComponent(0.8).cgColor
        routes.lineWidth = 2
        routes.lineDashPattern = [5, 5]
        routes.fillColor = nil
        layer.addSublayer(routes)
        for (index, place) in places.enumerated() {
            let pin = UIButton(type: .custom)
            pin.titleLabel?.font = Theme.font(17, display: true)
            pin.setTitle("\(index + 1)", for: .normal)
            pin.backgroundColor = Theme.ink
            pin.setTitleColor(place.kind.tint, for: .normal)
            pin.layer.borderWidth = 2
            pin.layer.borderColor = place.kind.tint.cgColor
            pin.layer.cornerRadius = 22
            pin.accessibilityLabel = "\(place.name), \(place.kind.title)"
            pin.addAction(UIAction { _ in open(place) }, for: .touchUpInside)
            pins.append(pin)
            addSubview(pin)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        routes.frame = bounds
        let path = UIBezierPath()
        var hasFirstStop = false
        for (pin, place) in zip(pins, places) {
            let coordinate = coordinate(for: place)
            let position = CGPoint(x: coordinate.x * bounds.width, y: coordinate.y * bounds.height)
            pin.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
            pin.center = position
            if hasFirstStop {
                let previous = path.currentPoint
                let middle = CGPoint(x: (previous.x + position.x) / 2, y: (previous.y + position.y) / 2)
                path.addQuadCurve(to: position, controlPoint: CGPoint(x: middle.x, y: middle.y - 18))
            } else {
                path.move(to: position)
                hasFirstStop = true
            }
        }
        routes.path = path.cgPath
    }

    private func coordinate(for place: DistrictPlace) -> CGPoint {
        let row = places.filter { $0.kind == place.kind }
        let isFirst = row.first?.id == place.id
        switch place.kind {
        case .street: return CGPoint(x: isFirst ? 0.23 : 0.72, y: 0.22)
        case .building: return CGPoint(x: isFirst ? 0.77 : 0.25, y: 0.51)
        case .attraction: return CGPoint(x: isFirst ? 0.23 : 0.72, y: 0.79)
        }
    }

    func showVisits(_ visited: Set<String>) {
        for (pin, place) in zip(pins, places) {
            let seen = visited.contains(place.id)
            pin.backgroundColor = seen ? place.kind.tint : Theme.ink
            pin.setTitleColor(seen ? Theme.ink : place.kind.tint, for: .normal)
            pin.accessibilityValue = seen ? "Visited" : "Not visited"
        }
    }
}

final class DistrictExplorePage: CityPage, SafetyObserving {
    private let artwork: String
    private let overview: String
    private let places: [DistrictPlace]
    private weak var guideButton: UIButton?
    private let guide: CatalogItem?
    private let visitsKey: String
    private let progress = Theme.label("", size: 16, color: Theme.mint, display: true)
    private let list = Theme.stack(spacing: 14)
    private lazy var map = DistrictStreetMap(artwork: artwork, places: places) { [weak self] in self?.openPlace($0) }

    init(name: String, districtID: String, artwork: String, overview: String, places: [DistrictPlace],
         memberID: UUID, guide: CatalogItem? = nil, api: CommunityAPI) {
        self.artwork = artwork
        self.overview = overview
        self.places = places
        self.guide = guide
        visitsKey = "SeseDistrictVisits.\(memberID.uuidString).\(districtID)"
        super.init(name, api: api)
    }

    required init?(coder: NSCoder) { nil }

    func safetyDidChange() {
        guideButton?.isHidden = guide.map(api.isHidden) ?? true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeSafetyChanges()
        body.addArrangedSubview(Theme.label(overview, color: Theme.secondary))
        body.addArrangedSubview(progress)
        map.heightAnchor.constraint(equalTo: map.widthAnchor, multiplier: 0.66).isActive = true
        body.addArrangedSubview(map)
        body.addArrangedSubview(Theme.label("Tap a number on the map or choose a place below.", size: 15, color: Theme.secondary))
        body.addArrangedSubview(list)
        enableRefresh { [weak self] in
            self?.renderVisits()
            self?.pageRefresh.finish()
        }
        if let guide {
            let button = Theme.button("Read the district guide") { [weak self] in
                guard let self else { return }
                self.push(CatalogDetail(items: [guide], index: 0, api: self.api))
            }
            body.addArrangedSubview(button)
            guideButton = button
            safetyDidChange()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        renderVisits()
    }

    private func renderVisits() {
        let visited = visits
        let count = places.filter { visited.contains($0.id) }.count
        progress.text = count == places.count ? "District explored · \(count) of \(places.count) visited"
            : "\(count) of \(places.count) places visited"
        map.showVisits(visited)
        list.clear()
        for kind in DistrictPlaceKind.allCases {
            let title = Theme.label(kind.plural, size: 23, color: kind.tint, display: true)
            title.accessibilityTraits.insert(.header)
            let entries: [UIView] = places.enumerated().filter { $0.element.kind == kind }.map { index, place in
                let label = "\(index + 1). \(place.name)"
                let button = Theme.textAction(label) { [weak self] in self?.openPlace(place) }
                button.accessibilityValue = visited.contains(place.id) ? "Visited" : "Not visited"
                let state = Theme.label(visited.contains(place.id) ? "Visited" : "Explore", size: 13, color: kind.tint)
                state.isAccessibilityElement = false
                state.setContentHuggingPriority(.required, for: .horizontal)
                let row = Theme.stack([button, state], spacing: 4, axis: .horizontal)
                row.alignment = .center
                return row
            }
            list.addArrangedSubview(Theme.card([title] + entries, spacing: 3))
        }
    }

    private var visits: Set<String> { Set(UserDefaults.standard.stringArray(forKey: visitsKey) ?? []) }

    private func openPlace(_ place: DistrictPlace, replacingCurrent: Bool = false) {
        let nextStop = places.firstIndex { $0.id == place.id }.flatMap { index -> DistrictPlace? in
            guard index + 1 < places.count else { return nil }
            return places[index + 1]
        }
        let page = DistrictPlacePage(place: place, nextStop: nextStop, districtName: heading, visited: { [weak self] in
            self?.visits.contains(place.id) == true
        }, markVisited: { [weak self] in
            guard let self else { return }
            let updated = self.visits.union([place.id])
            UserDefaults.standard.set(updated.sorted(), forKey: self.visitsKey)
        }, continueToNext: { [weak self] in
            guard let self, let nextStop else { return }
            self.openPlace(nextStop, replacingCurrent: true)
        }, api: api)
        if replacingCurrent, let navigationController, navigationController.topViewController is DistrictPlacePage {
            navigationController.setViewControllers(Array(navigationController.viewControllers.dropLast()) + [page], animated: true)
        } else {
            push(page)
        }
    }
}

private final class DistrictPlacePage: CityPage {
    private let place: DistrictPlace
    private let nextStop: DistrictPlace?
    private let districtName: String
    private let visited: () -> Bool
    private let markVisited: () -> Void
    private let continueToNext: () -> Void
    private let visitAction = Theme.stack()

    init(place: DistrictPlace, nextStop: DistrictPlace?, districtName: String, visited: @escaping () -> Bool,
         markVisited: @escaping () -> Void, continueToNext: @escaping () -> Void, api: CommunityAPI) {
        self.place = place
        self.nextStop = nextStop
        self.districtName = districtName
        self.visited = visited
        self.markVisited = markVisited
        self.continueToNext = continueToNext
        super.init(place.name, api: api)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        let type = Theme.label("\(place.kind.title) · \(districtName)", size: 16, color: place.kind.tint, display: true)
        body.addArrangedSubview(Theme.card([type, Theme.label(place.description, size: 19), visitAction]))
        if let nextStop {
            body.addArrangedSubview(Theme.button("Next stop: \(nextStop.name)", action: continueToNext))
        }
        body.addArrangedSubview(Theme.textAction("Back to district map") { [weak self] in
            self?.navigationController?.popViewController(animated: true)
        })
        updateVisitAction()
        enableRefresh { [weak self] in
            self?.updateVisitAction()
            self?.pageRefresh.finish()
        }
    }

    private func updateVisitAction() {
        visitAction.clear()
        if visited() {
            visitAction.addArrangedSubview(Theme.label("Visited", color: Theme.mint, display: true))
        } else {
            visitAction.addArrangedSubview(Theme.button("Mark as visited", accent: true) { [weak self] in
                self?.markVisited()
                self?.updateVisitAction()
            })
        }
    }
}
