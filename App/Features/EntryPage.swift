import PDFKit
import UIKit

final class EntryPage: UIViewController {
    enum Mode { case welcome, unavailable }
    let mode: Mode
    let api: CommunityAPI?
    let entered: () -> Void
    private let status = Theme.label("", size: 16, color: Theme.coral)
    private weak var consentBox: UIButton?
    private weak var consentText: UIStackView?
    private weak var signInButton: UIButton?

    init(mode: Mode, api: CommunityAPI?, entered: @escaping () -> Void) {
        self.mode = mode
        self.api = api
        self.entered = entered
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.ink
        let artwork = Theme.artwork("background")
        artwork.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(artwork)
        let title = Theme.label(mode == .welcome ? "The city is yours." : "Welcome", size: 39, display: true)
        let subtitle = Theme.label("Short films, costume craft, and a city worth exploring.", color: Theme.secondary)
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Sese"
        let brand = Theme.label(appName, size: 21, color: Theme.mint, display: true)
        let stack = Theme.stack([brand, title, subtitle], spacing: 10)
        if mode == .welcome {
            stack.addArrangedSubview(makeConsentRow())
            let button = Theme.button("One-tap sign in", accent: true) { [weak self] in self?.beginSignIn() }
            button.accessibilityIdentifier = "entry.oneTapSignIn"
#if DEBUG && targetEnvironment(simulator) && SESE_SAFETY_ACCEPTANCE
            if ModerationAcceptanceFixture.shared != nil { button.accessibilityIdentifier = "entry.moderationAcceptance" }
#endif
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
            stack.addArrangedSubview(button)
            signInButton = button
        } else {
            status.text = "The community service is unavailable."
        }
        stack.addArrangedSubview(status)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            artwork.topAnchor.constraint(equalTo: view.topAnchor), artwork.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            artwork.leadingAnchor.constraint(equalTo: view.leadingAnchor), artwork.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(greaterThanOrEqualTo: safe.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -20)
        ])
    }

    private func makeConsentRow() -> UIStackView {
        let box = UIButton(type: .custom)
        box.setTitle("□", for: .normal)
        box.setTitle("☑", for: .selected)
        box.setTitleColor(Theme.mint, for: .normal)
        box.setTitleColor(Theme.mint, for: .selected)
        box.titleLabel?.font = Theme.font(29)
        Task { [weak box] in
            async let uncheckedImage = Artwork.image("consent-unchecked")
            async let checkedImage = Artwork.image("consent-checked")
            let (unchecked, checked) = await (uncheckedImage, checkedImage)
            guard let unchecked, let checked, let box else { return }
            box.setTitle(nil, for: .normal)
            box.setTitle(nil, for: .selected)
            box.setImage(unchecked, for: .normal)
            box.setImage(checked, for: .selected)
        }
        box.accessibilityLabel = "Agree to the agreements"
        box.accessibilityIdentifier = "entry.consent"
        box.accessibilityValue = "Unchecked"
        box.widthAnchor.constraint(equalToConstant: Theme.iconTouchSize).isActive = true
        box.heightAnchor.constraint(equalToConstant: Theme.iconTouchSize).isActive = true
        box.addAction(UIAction { [weak self] _ in
            guard let self, let box = self.consentBox else { return }
            box.isSelected.toggle()
            box.accessibilityValue = box.isSelected ? "Checked" : "Unchecked"
            self.status.text = nil
        }, for: .touchUpInside)
        consentBox = box

        let text = Theme.stack([
            Theme.label("I have read and agree to the", size: 16),
            makeAgreementLinks()
        ], spacing: 0)
        consentText = text
        let row = Theme.stack([box, text], spacing: 5, axis: .horizontal)
        row.alignment = .center
        return row
    }

    private func makeAgreementLinks() -> UIStackView {
        let terms = AgreementLinkLabel(.terms) { [weak self] in self?.openAgreement(.terms) }
        let privacy = AgreementLinkLabel(.privacy) { [weak self] in self?.openAgreement(.privacy) }
        let conjunction = Theme.label("and", size: 16)
        conjunction.setContentCompressionResistancePriority(.required, for: .horizontal)
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let links = Theme.stack([terms, conjunction, privacy, spacer], spacing: 5, axis: .horizontal)
        links.alignment = .firstBaseline
        return links
    }

    private func openAgreement(_ kind: AgreementKind) {
        guard navigationController?.topViewController === self else { return }
        let page = AgreementPage(kind: kind, agreement: api?.agreements?.document(kind))
        navigationController?.pushViewController(page, animated: true)
    }

    private func beginSignIn() {
        guard let api, let button = signInButton, button.isEnabled else { return }
        guard consentBox?.isSelected == true else {
            status.text = "Agree to the Terms of Service and Privacy Policy to continue."
            return
        }
        guard api.agreements != nil else { status.text = CommunityError.agreements.localizedDescription; return }

        let ready = button.configuration
        var busy = ready
        var titleAttributes = AttributeContainer()
        titleAttributes.font = Theme.font(17, display: true)
        busy?.attributedTitle = AttributedString("Signing in…", attributes: titleAttributes)
        busy?.showsActivityIndicator = true
        button.configuration = busy
        button.isEnabled = false
        consentBox?.isEnabled = false
        consentText?.isUserInteractionEnabled = false
        status.text = nil

        Task {
            defer {
                button.configuration = ready
                button.isEnabled = true
                consentBox?.isEnabled = true
                consentText?.isUserInteractionEnabled = true
            }
            do {
                try await api.signIn()
                entered()
            } catch let error as CommunityError {
                status.text = error.localizedDescription
            } catch {
                status.text = "Sign-in is unavailable. Please try again."
            }
        }
    }
}

private final class AgreementLinkLabel: UILabel {
    private let follow: () -> Void

    init(_ kind: AgreementKind, follow: @escaping () -> Void) {
        self.follow = follow
        super.init(frame: .zero)
        attributedText = NSAttributedString(string: kind.title, attributes: [
            .font: Theme.font(16), .foregroundColor: Theme.mint,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ])
        numberOfLines = 1
        adjustsFontSizeToFitWidth = true
        minimumScaleFactor = 0.8
        adjustsFontForContentSizeCategory = true
        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.required, for: .horizontal)
        isUserInteractionEnabled = true
        isAccessibilityElement = true
        accessibilityLabel = kind.title
        accessibilityTraits = .link
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(open)))
    }

    required init?(coder: NSCoder) { return nil }

    @objc private func open() { follow() }

    override func accessibilityActivate() -> Bool {
        follow()
        return true
    }
}

final class AgreementPage: UIViewController {
    private let kind: AgreementKind
    private let agreement: AgreementDocument?

    init(kind: AgreementKind, agreement: AgreementDocument?) {
        self.kind = kind
        self.agreement = agreement
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.ink
        let title = Theme.label(kind.title, size: 27, display: true)
        let back = Theme.icon("back", label: "Back") { [weak self] in self?.navigationController?.popViewController(animated: true) }
        let header = Theme.stack([back, title], axis: .horizontal)
        header.alignment = .center
        let pdf = PDFView()
        pdf.backgroundColor = Theme.panel
        pdf.autoScales = true
        let data = agreement?.data ?? kind.bundledData()
        pdf.document = data.flatMap { PDFDocument(data: $0) }
        let status = Theme.label(pdf.document == nil ? "This document is unavailable." : "", color: Theme.secondary)
        status.isHidden = pdf.document != nil
        let stack = Theme.stack([header, status, pdf])
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -12)
        ])
        if let agreement {
            Task {
                guard let data = await agreement.publishedData(), let document = PDFDocument(data: data) else { return }
                pdf.document = document
                status.isHidden = true
            }
        }
    }
}
