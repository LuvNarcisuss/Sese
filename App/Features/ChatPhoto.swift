import Foundation
import ImageIO
import UIKit
import PhotosUI
import UniformTypeIdentifiers

enum ChatPhoto {
    static let maximumBytes = 2_097_152

    static func pick(from provider: NSItemProvider) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = thumbnail(from: source) else {
                    continuation.resume(throwing: CommunityError.invalidInput("This photo could not be opened."))
                    return
                }
                for quality in [0.84, 0.68, 0.50] {
                    if let data = jpeg(image, quality: quality), data.count <= maximumBytes {
                        continuation.resume(returning: data)
                        return
                    }
                }
                continuation.resume(throwing: CommunityError.invalidInput("This photo is too large to send."))
            }
        }
    }

    static func decode(_ data: Data, maximumPixelSize: Int = 1600) -> CGImage? {
        guard data.count <= maximumBytes, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source), type as String == UTType.jpeg.identifier else { return nil }
        return thumbnail(from: source, maximumPixelSize: maximumPixelSize)
    }

    private static func thumbnail(from source: CGImageSource, maximumPixelSize: Int = 1600) -> CGImage? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int,
              (1...30_000).contains(width), (1...30_000).contains(height), width * height <= 150_000_000 else { return nil }
        let options: [String: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways as String: true,
            kCGImageSourceCreateThumbnailWithTransform as String: true,
            kCGImageSourceThumbnailMaxPixelSize as String: maximumPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes as CFMutableData, UTType.jpeg.identifier as CFString,
                                                                 1, nil) else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality as String: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        return CGImageDestinationFinalize(destination) ? bytes as Data : nil
    }
}

final class ChatPhotoPage: CityPage, SafetyObserving {
    private let message: Message
    private var loadTask: Task<Void, Never>?

    init(message: Message, api: CommunityAPI) {
        self.message = message
        super.init("Photo", api: api)
    }

    required init?(coder: NSCoder) { return nil }

    func safetyDidChange() {
        if api.isBlocked(message.senderId) || api.isBlocked(message.recipientId) {
            loadTask?.cancel()
            closeHiddenContent()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeSafetyChanges()
        enableRefresh { [weak self] in self?.loadPhoto() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadPhoto()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        loadTask?.cancel()
        body.clear()
    }

    private func loadPhoto() {
        loadTask?.cancel()
        showStatus("Loading photo…")
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await self.api.chatPhoto(for: self.message)
                let image = await Task.detached(priority: .userInitiated) { ChatPhoto.decode(data) }.value
                guard !Task.isCancelled else { return }
                guard let image else { throw CommunityError.unavailable }
                let view = UIImageView(image: UIImage(cgImage: image))
                view.contentMode = .scaleAspectFit
                view.isAccessibilityElement = true
                view.accessibilityLabel = "Photo attachment"
                view.heightAnchor.constraint(equalToConstant: 440).isActive = true
                self.body.clear()
                self.body.addArrangedSubview(view)
                self.showStatus(nil)
                self.pageRefresh.finish()
            } catch {
                guard !Task.isCancelled else { return }
                self.showStatus("This photo could not be loaded.")
                self.pageRefresh.finish(error: "This photo could not be updated. Pull down to try again.")
                if self.body.arrangedSubviews.isEmpty {
                    self.body.addArrangedSubview(Theme.button("Retry") { [weak self] in self?.loadPhoto() })
                }
            }
        }
    }
}
