import UIKit

final class ThemedDialog: UIViewController {
    private typealias Choice = (title: String, style: UIAlertAction.Style, handler: (() -> Void)?)
    private var choices: [Choice] = []
    private let message: String?
    private let sheet: Bool
    private var closing = false

    init(title: String?, message: String?, preferredStyle: UIAlertController.Style) {
        self.message = message
        sheet = preferredStyle == .actionSheet
        super.init(nibName: nil, bundle: nil)
        self.title = title
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) { nil }

    func addChoice(_ title: String, style: UIAlertAction.Style, handler: (() -> Void)? = nil) {
        choices.append((title, style, handler))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.ink.withAlphaComponent(0.76)
        view.accessibilityViewIsModal = true
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = Theme.panel
        card.layer.cornerRadius = 24
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1.25
        card.layer.borderColor = Theme.gold.withAlphaComponent(0.75).cgColor
        card.clipsToBounds = true
        card.accessibilityIdentifier = "dialog." + (title ?? "Notice")
        card.accessibilityContainerType = .semanticGroup
        view.addSubview(card)

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = false
        card.addSubview(scroll)
        let skyline = UIImageView(image: Artwork.dialogSkyline)
        skyline.contentMode = .scaleAspectFill
        skyline.clipsToBounds = true
        skyline.isAccessibilityElement = false
        let content = Theme.stack(spacing: 10)
        content.isLayoutMarginsRelativeArrangement = true
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 4, leading: 18, bottom: 18, trailing: 18)
        if let title {
            let heading = Theme.label(title, size: 24, color: Theme.paper, display: true)
            heading.setContentCompressionResistancePriority(.required, for: .vertical)
            heading.accessibilityTraits.insert(.header)
            content.addArrangedSubview(heading)
        }
        if let message, !message.isEmpty {
            let body = Theme.label(message, color: Theme.paper)
            body.setContentCompressionResistancePriority(.required, for: .vertical)
            content.addArrangedSubview(body)
        }
        let ordered = choices.filter { $0.style != .cancel } + choices.filter { $0.style == .cancel }
        for choice in ordered {
            let button = Theme.button(choice.title) { [weak self] in self?.finish(choice.handler) }
            let cancel = choice.style == .cancel && choices.count > 1
            let destructive = choice.style == .destructive
            button.configuration?.baseForegroundColor = cancel ? Theme.secondary : (destructive ? Theme.coral : Theme.mint)
            button.configuration?.baseBackgroundColor = cancel ? .clear : Theme.ink.withAlphaComponent(0.72)
            button.configuration?.background.strokeColor = cancel ? .clear : Theme.line
            button.configuration?.background.strokeWidth = cancel ? 0 : 1
            button.setContentCompressionResistancePriority(.required, for: .vertical)
            content.addArrangedSubview(button)
        }

        let column = Theme.stack([skyline, content], spacing: 0)
        column.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(column)
        let safe = view.safeAreaLayoutGuide
        let width = card.widthAnchor.constraint(equalTo: safe.widthAnchor, constant: -32)
        width.priority = .defaultHigh
        let fit = card.heightAnchor.constraint(equalTo: column.heightAnchor)
        fit.priority = .defaultHigh
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: safe.centerXAnchor), width, fit,
            card.widthAnchor.constraint(lessThanOrEqualTo: safe.widthAnchor, constant: -32),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 400),
            card.heightAnchor.constraint(lessThanOrEqualTo: safe.heightAnchor, constant: -24),
            sheet ? card.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -10)
                  : card.centerYAnchor.constraint(equalTo: safe.centerYAnchor),
            scroll.topAnchor.constraint(equalTo: card.topAnchor), scroll.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            column.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            column.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            column.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            skyline.heightAnchor.constraint(equalTo: column.widthAnchor, multiplier: 0.22)
        ])
    }

    private func finish(_ handler: (() -> Void)?) {
        guard !closing else { return }
        closing = true
        view.isUserInteractionEnabled = false
        dismiss(animated: !UIAccessibility.isReduceMotionEnabled, completion: handler)
    }

    override func accessibilityPerformEscape() -> Bool {
        guard let cancel = choices.first(where: { $0.style == .cancel }) else { return false }
        finish(cancel.handler)
        return true
    }
}
