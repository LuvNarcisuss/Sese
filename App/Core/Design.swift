import UIKit
import CoreText
import AVFoundation
import SafariServices

@MainActor
enum Theme {
    static let iconSize: CGFloat = 40
    static let iconTouchSize: CGFloat = 48
    static let ink = UIColor(red: 0.052, green: 0.043, blue: 0.102, alpha: 1)
    static let panel = UIColor(red: 0.115, green: 0.092, blue: 0.192, alpha: 1)
    static let line = UIColor(red: 0.27, green: 0.23, blue: 0.37, alpha: 1)
    static let paper = UIColor(red: 0.99, green: 0.956, blue: 0.875, alpha: 1)
    static let secondary = UIColor(red: 0.76, green: 0.71, blue: 0.83, alpha: 1)
    static let mint = UIColor(red: 0.64, green: 0.97, blue: 0.81, alpha: 1)
    static let gold = UIColor(red: 1, green: 0.78, blue: 0.48, alpha: 1)
    static let coral = UIColor(red: 1, green: 0.59, blue: 0.60, alpha: 1)

    private static let fonts: [Bool: String] = {
        let files = [true: "Fredoka-Variable.ttf", false: "ComicNeue-Regular.ttf"]
        return files.compactMapValues { file in
            let url = Resources.url("Fonts/\(file)") as CFURL
            CTFontManagerRegisterFontsForURL(url, .process, nil)
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor],
                  let descriptor = descriptors.first else { return nil }
            let font = CTFontCreateWithFontDescriptor(descriptor, 16, nil)
            return CTFontCopyPostScriptName(font) as String
        }
    }()

    static func font(_ size: CGFloat, display: Bool = false, textStyle: UIFont.TextStyle = .body) -> UIFont {
        let name = fonts[display] ?? fonts[!display] ?? "Georgia"
        let face = UIFont(name: name, size: size) ?? UIFont(descriptor: UIFontDescriptor(name: "Georgia", size: size), size: size)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: face)
    }

    static func label(_ text: String, size: CGFloat = 17, color: UIColor = paper, display: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = font(size, display: display, textStyle: display ? .headline : .body)
        label.textColor = color
        label.numberOfLines = 0
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    static func button(_ text: String, icon: String? = nil, accent: Bool = false, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.filled()
        var attributes = AttributeContainer()
        attributes.font = font(17, display: true)
        config.attributedTitle = AttributedString(text, attributes: attributes)
        config.baseForegroundColor = accent ? ink : paper
        config.baseBackgroundColor = accent ? mint : panel
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        config.imagePadding = 8
        if icon != nil { config.imagePlacement = .top }
        config.titleLineBreakMode = .byWordWrapping
        let button = UIButton(configuration: config, primaryAction: UIAction { _ in action() })
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        if let icon {
            Task { [weak button] in
                guard let image = await Artwork.image(icon) else { return }
                button?.configuration?.image = image
            }
        }
        return button
    }

    static func icon(_ name: String, label: String, action: @escaping () -> Void) -> UIButton {
        let button = iconTarget(label, action: action)
        Task { [weak button] in
            let image = await Artwork.image(name)
            guard let button else { return }
            if let image {
                button.setImage(image, for: .normal)
            } else {
                button.setTitle(label, for: .normal)
                button.titleLabel?.font = font(12, display: true)
                button.titleLabel?.numberOfLines = 2
            }
        }
        return button
    }

    static func textAction(_ text: String, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.plain()
        var attributes = AttributeContainer()
        attributes.font = font(17, display: true)
        config.attributedTitle = AttributedString(text, attributes: attributes)
        config.baseForegroundColor = paper
        config.contentInsets = .zero
        let button = UIButton(configuration: config, primaryAction: UIAction { _ in action() })
        button.contentHorizontalAlignment = .leading
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return button
    }

    static func moreIcon(label: String, action: @escaping () -> Void) -> UIButton {
        icon("settings", label: label, action: action)
    }

    private static func iconTarget(_ label: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .custom)
        button.setTitleColor(paper, for: .normal)
        button.setTitleColor(secondary, for: .highlighted)
        button.accessibilityLabel = label
        button.widthAnchor.constraint(equalToConstant: iconTouchSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: iconTouchSize).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    static func field(_ placeholder: String) -> UITextField {
        let field = UITextField()
        field.font = font(17)
        field.textColor = paper
        field.attributedPlaceholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: secondary])
        field.accessibilityLabel = placeholder
        field.backgroundColor = panel
        field.layer.cornerRadius = 12
        field.layer.borderColor = line.cgColor
        field.layer.borderWidth = 1
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 44))
        field.leftViewMode = .always
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 46).isActive = true
        field.clearButtonMode = .never
        return field
    }

    static func stack(_ views: [UIView] = [], spacing: CGFloat = 12, axis: NSLayoutConstraint.Axis = .vertical) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = axis
        stack.spacing = spacing
        return stack
    }

    static func card(_ views: [UIView], spacing: CGFloat = 10) -> UIStackView {
        let stack = stack(views, spacing: spacing)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        stack.backgroundColor = panel
        stack.layer.cornerRadius = 22
        stack.layer.borderColor = line.cgColor
        stack.layer.borderWidth = 1
        return stack
    }

    static func empty(_ title: String, _ detail: String) -> UIStackView {
        card([label(title, size: 23, display: true), label(detail, color: secondary)])
    }

    static func artwork(_ name: String, mode: UIView.ContentMode = .scaleAspectFill) -> UIImageView {
        let view = UIImageView()
        view.contentMode = mode
        view.clipsToBounds = true
        view.accessibilityIgnoresInvertColors = true
        Task { [weak view] in view?.image = await Artwork.image(name) }
        return view
    }
}

extension UIImage {
    @MainActor func scaled(to size: CGFloat) -> UIImage {
        let dimension = max(self.size.width, self.size.height)
        guard dimension > 0 else { return self }
        let target = CGSize(width: self.size.width * size / dimension, height: self.size.height * size / dimension)
        return UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
            .withRenderingMode(.alwaysOriginal)
    }
}

extension UIStackView {
    func clear() { arrangedSubviews.forEach { removeArrangedSubview($0); $0.removeFromSuperview() } }
}

@MainActor
enum Artwork {
    private static let storage = (try? Resources.decode(BackendConfiguration.self, "Backend.json"))?.url
        .appendingPathComponent("storage/v1/object/public/editorial", isDirectory: true)
    private static let cache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()
    private static var downloads: [URL: Task<UIImage?, Never>] = [:]
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }()

    static let expoPortrait = storage?.appendingPathComponent("944f77db-dbc1-4293-976a-e6bc0dc71f39/expo-duo.jpg")
    static let fanPortrait = storage?.appendingPathComponent("sese-media-v1/fan-duo.jpg")

    private static let iconImages: [String: UIImage] = {
        guard let data = try? Data(contentsOf: Resources.url("IconArtwork.plist")),
              let images = try? PropertyListDecoder().decode([String: Data].self, from: data) else { return [:] }
        // Match the visible shapes, not the differently padded ImageGen canvases.
        let bounds: [String: CGRect] = [
            "like": CGRect(x: 32, y: 14, width: 79, height: 69),
            "like-outline": CGRect(x: 11, y: 20, width: 121, height: 111),
            "save": CGRect(x: 36, y: 14, width: 72, height: 116),
            "save-outline": CGRect(x: 31, y: 8, width: 82, height: 126),
            "comments": CGRect(x: 23, y: 22, width: 108, height: 114),
            "share": CGRect(x: 37, y: 11, width: 81, height: 82),
            "shorts": CGRect(x: 22, y: 15, width: 110, height: 125),
            "districts": CGRect(x: 23, y: 31, width: 109, height: 94),
            "cosplay": CGRect(x: 24, y: 11, width: 108, height: 132),
            "chats": CGRect(x: 36, y: 16, width: 82, height: 74),
            "profile": CGRect(x: 21, y: 13, width: 113, height: 129),
            "settings": CGRect(x: 17, y: 14, width: 122, height: 127),
            "search": CGRect(x: 38, y: 8, width: 80, height: 89),
            "wallet": CGRect(x: 46, y: 14, width: 64, height: 73),
            "back": CGRect(x: 42, y: 21, width: 74, height: 112),
            "filter": CGRect(x: 36, y: 11, width: 81, height: 82),
            "consent-unchecked": CGRect(x: 20, y: 23, width: 87, height: 84),
            "consent-checked": CGRect(x: 21, y: 24, width: 86, height: 83),
            "diamond": CGRect(x: 46, y: 65, width: 161, height: 132)
        ]
        let presentationSize = CGSize(width: Theme.iconSize, height: Theme.iconSize)
        return images.reduce(into: [:]) { result, entry in
            guard let source = UIImage(data: entry.value), let contentBounds = bounds[entry.key],
                  let shape = source.cgImage?.cropping(to: contentBounds) else { return }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            format.opaque = false
            let artwork = entry.key == "like" ? removingFaintBackdrop(from: shape) : shape
            result[entry.key] = UIGraphicsImageRenderer(size: presentationSize, format: format).image { _ in
                UIImage(cgImage: artwork).draw(in: CGRect(origin: .zero, size: presentationSize))
            }.withRenderingMode(.alwaysOriginal)
        }
    }()

    private static func removingFaintBackdrop(from image: CGImage) -> CGImage {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return image }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let bytes = buffer.bindMemory(to: UInt8.self)
            for offset in stride(from: 0, to: bytes.count, by: 4) where bytes[offset + 3] < 128 {
                bytes[offset] = 0
                bytes[offset + 1] = 0
                bytes[offset + 2] = 0
                bytes[offset + 3] = 0
            }
            return context.makeImage() ?? image
        }
    }

    static func iconImage(_ name: String) -> UIImage? { iconImages[name] }

    static func image(_ name: String) async -> UIImage? {
        if let icon = iconImage(name) { return icon }
        let object: String
        switch name {
        case "diamond": object = "exploration/34acd192-a548-49e8-a9ff-8fa39b51e916/diamond.png"
        case "like-outline", "save-outline": object = "shorts/ui/25cfb986-9b53-4dbe-b40d-f6f63f0171b5/\(name).png"
        case "city-map": object = "exploration/6815e1a4-202e-48c4-9468-23c68d6151c5/city-map.jpg"
        default: object = "sese-media-v1/\(name).png"
        }
        return await image(at: storage?.appendingPathComponent(object))
    }

    static func image(at url: URL?) async -> UIImage? {
        guard let url, url.scheme == "https" else { return nil }
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if let pending = downloads[url] { return await pending.value }
        let task = Task { () -> UIImage? in
            guard let (data, response) = try? await session.data(from: url),
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.count <= 12_000_000, let image = UIImage(data: data) else { return nil }
            return image.withRenderingMode(.alwaysOriginal)
        }
        downloads[url] = task
        defer { downloads[url] = nil }
        let image = await task.value
        if let image, let pixels = image.cgImage {
            cache.setObject(image, forKey: url as NSURL, cost: pixels.bytesPerRow * pixels.height)
        }
        return image
    }
}

final class EditorialImage: UIImageView {
    private var loadTask: Task<Void, Never>?

    convenience init(item: CatalogItem) {
        self.init(coverURL: item.imageUrl)
    }

    init(coverURL: URL?, videoURL: URL? = nil) {
        super.init(image: nil)
        contentMode = .scaleAspectFill
        clipsToBounds = true
        backgroundColor = Theme.panel
        layer.cornerRadius = 14
        loadTask = Task { [weak self] in
            var cover = await Artwork.image(at: coverURL)
            if cover == nil, let videoURL, !Task.isCancelled {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 480, height: 480)
                if let frame = try? await generator.image(at: .zero) {
                    cover = UIImage(cgImage: frame.image)
                }
            }
            if cover == nil { cover = await Artwork.image("background") }
            guard !Task.isCancelled else { return }
            self?.image = cover
        }
    }

    deinit { loadTask?.cancel() }

    required init?(coder: NSCoder) { return nil }
}

final class ContentScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool {
        // A drag over a card, avatar, or action must still scroll the page.
        if view is UIButton { return true }
        return super.touchesShouldCancel(in: view)
    }
}

@MainActor
final class PageRefresh: NSObject {
    let control = UIRefreshControl()
    let feedback = Theme.label("", size: 14, color: Theme.secondary)
    private var action: (() -> Void)?
    private weak var attachedScroll: UIScrollView?
    private var deadline: Task<Void, Never>?
    private(set) var isRefreshing = false
    private var sequence = 0

    override init() {
        super.init()
        feedback.isHidden = true
        feedback.accessibilityIdentifier = "refresh.status"
        control.tintColor = Theme.mint
        control.accessibilityLabel = "Refresh content"
        control.addAction(UIAction { [weak self] _ in self?.begin() }, for: .valueChanged)
    }

    func install(on scroll: UIScrollView, action: @escaping () -> Void) {
        self.action = action
        attachedScroll = scroll
        scroll.alwaysBounceVertical = true
        scroll.refreshControl = control
    }

    func begin() {
        guard !isRefreshing, let action else { return }
        sequence += 1
        isRefreshing = true
        if attachedScroll?.isHidden == false && !control.isRefreshing { control.beginRefreshing() }
        feedback.text = "Updating…"
        feedback.accessibilityValue = "loading:\(sequence)"
        feedback.isHidden = false
        deadline?.cancel()
        deadline = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 35_000_000_000)
            guard !Task.isCancelled else { return }
            self?.finish(error: "The update took too long. Pull down to try again.")
        }
        action()
    }

    func finish(error: String? = nil) {
        guard isRefreshing else { return }
        deadline?.cancel()
        deadline = nil
        isRefreshing = false
        control.endRefreshing()
        feedback.text = error ?? "Updated just now"
        feedback.accessibilityValue = "\(error == nil ? "success" : "failure"):\(sequence)"
        UIAccessibility.post(notification: .announcement, argument: feedback.text)
    }

    func cancel() {
        deadline?.cancel()
        deadline = nil
        isRefreshing = false
        control.endRefreshing()
        feedback.isHidden = true
    }
}

@MainActor
class CityPage: UIViewController {
    let api: CommunityAPI
    let heading: String
    let body = Theme.stack(spacing: 14)
    let actions = Theme.stack(spacing: 8, axis: .horizontal)
    let scroll = ContentScrollView()
    let pageRefresh = PageRefresh()
    private let status = Theme.label("", size: 15, color: Theme.secondary)

    init(_ heading: String, api: CommunityAPI) {
        self.api = api
        self.heading = heading
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.ink
        let art = Theme.artwork("background")
        art.alpha = 0.34
        let title = Theme.label(heading, size: 34, display: true)
        title.accessibilityTraits.insert(.header)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let header = Theme.stack(spacing: 10, axis: .horizontal)
        header.alignment = .center
        if navigationController?.viewControllers.first !== self {
            header.addArrangedSubview(Theme.icon("back", label: "Back") { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            })
        }
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)
        actions.setContentHuggingPriority(.required, for: .horizontal)
        actions.setContentCompressionResistancePriority(.required, for: .horizontal)
        header.addArrangedSubview(title)
        header.addArrangedSubview(actions)
        status.isHidden = true
        let column = Theme.stack([header, status, pageRefresh.feedback, scroll], spacing: 10)
        scroll.accessibilityIdentifier = "page.scroll"
        scroll.keyboardDismissMode = .interactive
        for subview in [art, column, body] { subview.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(art)
        view.addSubview(column)
        scroll.addSubview(body)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            art.topAnchor.constraint(equalTo: view.topAnchor), art.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            art.leadingAnchor.constraint(equalTo: view.leadingAnchor), art.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            column.topAnchor.constraint(equalTo: safe.topAnchor, constant: 10),
            column.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -4),
            column.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            column.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            body.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            body.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -14),
            body.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            body.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pageRefresh.cancel()
    }

    func enableRefresh(_ action: @escaping () -> Void) {
        pageRefresh.install(on: scroll, action: action)
    }

    func push(_ page: UIViewController) { navigationController?.pushViewController(page, animated: true) }

    func showStatus(_ text: String?) {
        status.text = text
        status.isHidden = text == nil
    }

    func alert(_ text: String) {
        guard view.window != nil, presentedViewController == nil else { return }
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    func open(_ url: URL) {
        guard url.scheme == "https" else { return }
        present(SFSafariViewController(url: url), animated: true)
    }

    func menu(_ title: String, choices: [(String, UIAlertAction.Style, () -> Void)]) {
        let menu = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        choices.forEach { text, style, action in menu.addAction(UIAlertAction(title: text, style: style) { _ in action() }) }
        menu.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(menu, animated: true)
    }

    func report(_ target: [String: String], video: Bool = true) {
        let reasons = ["Harassment", "Spam", "Inappropriate content", "Other"]
        menu("Report", choices: reasons.map { reason in
            (reason, .default, { [weak self] in
                guard let self else { return }
                Task {
                    do {
                        try await self.api.report(target, reason: reason, video: video)
                        UIAccessibility.post(notification: .announcement, argument: "Report submitted.")
                    } catch { self.alert(error.localizedDescription) }
                }
            })
        })
    }

    func search(_ field: UITextField, into parent: UIStackView, change: @escaping (String) -> Void) {
        parent.addArrangedSubview(field)
        field.addAction(UIAction { [weak field] _ in change(field?.text ?? "") }, for: .editingChanged)
    }
}
