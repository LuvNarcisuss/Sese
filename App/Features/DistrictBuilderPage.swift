import UIKit

final class DistrictBuilderPage: CityPage {
    private let memberID: UUID
    private let wallet: Wallet
    private let didBuild: (BuiltDistrict) -> Void
    private let buildID = UUID()
    private let nameField = Theme.field("District name")
    private let balance = Theme.label("", size: 16, color: Theme.gold, display: true)
    private let stylePreview = Theme.stack()
    private let layoutChoices = Theme.stack()
    private var style = DistrictStyle.desert
    private var plan = DistrictPlan()

    init(memberID: UUID, wallet: Wallet, api: CommunityAPI, didBuild: @escaping (BuiltDistrict) -> Void) {
        self.memberID = memberID
        self.wallet = wallet
        self.didBuild = didBuild
        super.init("Build a district", api: api)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        body.addArrangedSubview(Theme.label("Name your district and choose the streets, buildings, and attractions that go on its map.", color: Theme.secondary))
        nameField.autocapitalizationType = .words
        nameField.returnKeyType = .done
        nameField.addAction(UIAction { [weak self] _ in self?.nameField.resignFirstResponder() }, for: .editingDidEndOnExit)
        body.addArrangedSubview(Theme.card([
            Theme.label("Name", size: 20, display: true), nameField,
            Theme.label("Up to 30 characters", size: 14, color: Theme.secondary)
        ]))
        body.addArrangedSubview(stylePreview)
        body.addArrangedSubview(layoutChoices)
        body.addArrangedSubview(Theme.card([
            balance,
            Theme.button("Build for \(BuiltDistrict.price.formatted()) diamonds", icon: "diamond", accent: true) { [weak self] in
                self?.confirmBuild()
            },
            Theme.textAction("Open wallet") { [weak self] in self?.showWallet() }
        ]))
        renderPlan(refreshStyle: true)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshBalance), name: Wallet.didChange, object: wallet)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshBalance()
    }

    @objc private func refreshBalance() {
        balance.text = (try? wallet.ledger(for: memberID)).map { "\($0.balance.formatted()) diamonds available" }
            ?? "Wallet balance unavailable"
    }

    private func renderPlan(refreshStyle: Bool = false) {
        if refreshStyle {
            stylePreview.clear()
            let art = Theme.artwork(style.artwork)
            art.layer.cornerRadius = 12
            art.heightAnchor.constraint(equalTo: art.widthAnchor, multiplier: 0.45).isActive = true
            stylePreview.addArrangedSubview(Theme.card([
                Theme.label("Theme: \(style.title)", size: 21, display: true), art,
                Theme.textAction("Change theme") { [weak self] in self?.chooseStyle() }
            ]))
        }
        layoutChoices.clear()
        let places = style.places(for: plan)
        for kind in DistrictPlaceKind.allCases {
            let selection = places.filter { $0.kind == kind }
            let title = Theme.label(kind.plural, size: 20, display: true)
            title.accessibilityTraits.insert(.header)
            layoutChoices.addArrangedSubview(Theme.card([
                title,
                Theme.label(selection.map(\.name).joined(separator: " · "), color: Theme.secondary),
                Theme.textAction("Choose \(kind.plural.lowercased())") { [weak self] in self?.choosePlaces(kind) }
            ]))
        }
    }

    private func chooseStyle() {
        view.endEditing(true)
        let choices = DistrictStyle.allCases.map { option in
            (option.title, UIAlertAction.Style.default, { [weak self] in
                guard let self else { return }
                self.style = option
                self.renderPlan(refreshStyle: true)
            })
        }
        menu("District theme", choices: choices)
    }

    private func choosePlaces(_ kind: DistrictPlaceKind) {
        view.endEditing(true)
        let choices = DistrictPlaceChoice.allCases.map { option in
            var proposed = plan
            proposed.select(option, for: kind)
            let names = style.places(for: proposed).filter { $0.kind == kind }.map(\.name)
            let label = option == .both ? "Build both" : names.joined()
            return (label, UIAlertAction.Style.default, { [weak self] in
                self?.plan.select(option, for: kind)
                self?.renderPlan()
            })
        }
        menu(kind.plural, choices: choices)
    }

    private func confirmBuild() {
        view.endEditing(true)
        guard let name = BuiltDistrict.validName(nameField.text ?? "") else {
            alert(WalletError.invalidDistrictName.localizedDescription)
            return
        }
        let price = BuiltDistrict.price.formatted()
        let selectedStyle = style
        let selectedPlan = plan
        let count = selectedStyle.places(for: selectedPlan).count
        let alert = ThemedDialog(title: "Build \(name)?",
                                      message: "Spend \(price) diamonds to build this district with \(count) places to explore.", preferredStyle: .alert)
        alert.addChoice("Cancel", style: .cancel)
        alert.addChoice("Build district", style: .default) { [weak self] in
            guard let self else { return }
            Task {
                do {
                    let district = try await self.wallet.buildDistrict(id: self.buildID, name: name, style: selectedStyle,
                                                                      plan: selectedPlan, for: self.memberID)
                    guard self.viewIfLoaded?.window != nil else { return }
                    self.didBuild(district)
                } catch {
                    self.showStatus(self.wallet.message(for: error))
                    self.refreshBalance()
                }
            }
        }
        present(alert, animated: true)
    }

    private func showWallet() { push(WalletPage(memberID: memberID, wallet: wallet, api: api)) }
}
