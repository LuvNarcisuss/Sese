import AVFoundation
import AVKit
import PhotosUI
import UIKit
import UniformTypeIdentifiers

private enum CosplayMedia {
    static func prepare(_ kind: CosplayMediaKind, from provider: NSItemProvider) async throws -> Data {
        switch kind {
        case .photo:
            return try await ChatPhoto.pick(from: provider)
        case .video:
            let input = try await copyVideo(from: provider)
            defer { try? FileManager.default.removeItem(at: input) }
            let asset = AVURLAsset(url: input)
            let duration = try await asset.load(.duration).seconds
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard duration.isFinite, duration > 0, duration <= 30, !tracks.isEmpty else {
                throw CommunityError.invalidInput("Choose a video up to 30 seconds long.")
            }
            let output = temporaryVideoURL()
            defer { try? FileManager.default.removeItem(at: output) }
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset640x480),
                  exporter.supportedFileTypes.contains(.mp4) else {
                throw CommunityError.invalidInput("This video could not be converted to MP4.")
            }
            exporter.outputURL = output
            exporter.outputFileType = .mp4
            exporter.fileLengthLimit = Int64(CommunityAPI.maximumCosplayMediaBytes)
            exporter.shouldOptimizeForNetworkUse = true
            exporter.metadata = []
            let complete: Bool = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    exporter.exportAsynchronously {
                        continuation.resume(returning: exporter.status == .completed)
                    }
                }
            } onCancel: {
                exporter.cancelExport()
            }
            try Task.checkCancellation()
            guard complete,
                  let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  (1...CommunityAPI.maximumCosplayMediaBytes).contains(size) else {
                throw CommunityError.invalidInput("This video is too large to post. Choose a shorter clip.")
            }
            return try Data(contentsOf: output)
        }
    }

    static func temporaryVideoURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
    }

    private static func copyVideo(from provider: NSItemProvider) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                guard let url else {
                    continuation.resume(throwing: CommunityError.invalidInput("This video could not be opened."))
                    return
                }
                let allowedExtensions = ["mov", "mp4", "m4v"]
                let sourceExtension = url.pathExtension.lowercased()
                let fileExtension = allowedExtensions.contains(sourceExtension) ? sourceExtension : "mov"
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension)
                do {
                    guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                          (1...120_000_000).contains(size) else {
                        throw CommunityError.invalidInput("Choose a smaller source video.")
                    }
                    try FileManager.default.copyItem(at: url, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    try? FileManager.default.removeItem(at: destination)
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    @MainActor
    static func play(_ data: Data, from page: UIViewController, temporaryFile: inout URL?) throws {
        if let temporaryFile { try? FileManager.default.removeItem(at: temporaryFile) }
        let file = temporaryVideoURL()
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        temporaryFile = file
        let player = AVPlayerViewController()
        player.player = AVPlayer(url: file)
        page.present(player, animated: true) { player.player?.play() }
    }
}

final class ComposeCosplayPage: CityPage, PHPickerViewControllerDelegate {
    private struct Attachment {
        let id = UUID()
        let kind: CosplayMediaKind
        let data: Data
    }

    private let titleField = Theme.field("Title")
    private let captionField = Theme.field("Caption")
    private let preview = Theme.stack()
    private let permission = UISwitch()
    private let onSubmitted: () -> Void
    private var attachment: Attachment?
    private var chosenKind = CosplayMediaKind.photo
    private var prepareTask: Task<Void, Never>?
    private var submitButton: UIButton?
    private var temporaryVideo: URL?
    private var isSubmitting = false
    private var attempted = false

    init(api: CommunityAPI, onSubmitted: @escaping () -> Void) {
        self.onSubmitted = onSubmitted
        super.init("Post cosplay", api: api)
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        prepareTask?.cancel()
        if let temporaryVideo { try? FileManager.default.removeItem(at: temporaryVideo) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let photos = Theme.button("Choose photo") { [weak self] in self?.choose(.photo) }
        let videos = Theme.button("Choose video") { [weak self] in self?.choose(.video) }
        let choices = Theme.stack([photos, videos], spacing: 8, axis: .horizontal)
        choices.distribution = .fillEqually
        body.addArrangedSubview(choices)
        body.addArrangedSubview(Theme.label("Choose one photo or a video up to 30 seconds. Prepared videos must fit within 6 MB.", size: 15, color: Theme.secondary))
        body.addArrangedSubview(preview)
        body.addArrangedSubview(titleField)
        body.addArrangedSubview(captionField)
        permission.setContentHuggingPriority(.required, for: .horizontal)
        permission.setContentCompressionResistancePriority(.required, for: .horizontal)
        permission.accessibilityLabel = "I have permission to share this media"
        permission.addAction(UIAction { [weak self] _ in self?.updateSubmit() }, for: .valueChanged)
        let permissionRow = Theme.stack([Theme.label("I have permission to share this media."), permission], axis: .horizontal)
        permissionRow.alignment = .center
        body.addArrangedSubview(permissionRow)
        body.addArrangedSubview(Theme.label("Anyone with the file link can view it once it is uploaded. Approved posts appear in the community gallery.", size: 15, color: Theme.secondary))
        let submit = Theme.button("Submit for review", accent: true) { [weak self] in self?.submit() }
        submitButton = submit
        body.addArrangedSubview(submit)
        updateSubmit()
    }

    private func choose(_ kind: CosplayMediaKind) {
        guard !isSubmitting, prepareTask == nil else { return }
        chosenKind = kind
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = kind == .photo ? .images : .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        let kind = chosenKind
        showStatus("Preparing \(kind.title.lowercased())…")
        prepareTask = Task { [weak self] in
            do {
                let data = try await CosplayMedia.prepare(kind, from: provider)
                guard let self, !Task.isCancelled else { return }
                self.attachment = Attachment(kind: kind, data: data)
                self.attempted = false
                self.permission.isOn = false
                self.titleField.isEnabled = true
                self.captionField.isEnabled = true
                self.showStatus(nil)
                self.renderPreview()
            } catch {
                guard !Task.isCancelled else { return }
                self?.showStatus(error.localizedDescription)
            }
            self?.prepareTask = nil
            self?.updateSubmit()
        }
        updateSubmit()
    }

    private func renderPreview() {
        preview.clear()
        guard let attachment else { return }
        if attachment.kind == .photo, let picture = ChatPhoto.decode(attachment.data) {
            let image = UIImageView(image: UIImage(cgImage: picture))
            image.contentMode = .scaleAspectFit
            image.heightAnchor.constraint(equalToConstant: 220).isActive = true
            image.accessibilityLabel = "Selected photo"
            image.isAccessibilityElement = true
            preview.addArrangedSubview(image)
        } else if attachment.kind == .video {
            preview.addArrangedSubview(Theme.button("Preview video") { [weak self] in
                guard let self else { return }
                do { try CosplayMedia.play(attachment.data, from: self, temporaryFile: &self.temporaryVideo) }
                catch { self.alert(error.localizedDescription) }
            })
        }
    }

    private func updateSubmit() {
        submitButton?.isEnabled = attachment != nil && permission.isOn && !isSubmitting && prepareTask == nil
    }

    private func submit() {
        guard !isSubmitting, let attachment, permission.isOn, prepareTask == nil else { return }
        let title = (titleField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let caption = captionField.text ?? ""
        guard (1...80).contains(title.count), caption.count <= 350 else {
            alert("Use a title of 1–80 characters and a caption of at most 350 characters.")
            return
        }
        isSubmitting = true
        if !attempted {
            titleField.isEnabled = false
            captionField.isEnabled = false
            attempted = true
        }
        updateSubmit()
        view.endEditing(true)
        showStatus("Uploading \(attachment.kind.title.lowercased())…")
        Task {
            defer {
                isSubmitting = false
                updateSubmit()
            }
            do {
                try await api.submitCosplay(id: attachment.id, title: title, caption: caption, kind: attachment.kind,
                                            bytes: attachment.data)
                self.attachment = nil
                guard navigationController?.topViewController === self else { return }
                onSubmitted()
                navigationController?.popViewController(animated: true)
            } catch {
                showStatus("The post could not be submitted. Try again or choose another file.")
            }
        }
    }
}

@MainActor
enum CosplayPostCard {
    static func make(_ post: CosplayPost, api: CommunityAPI, open: @escaping () -> Void,
                     openAuthor: ((UUID) -> Void)? = nil) -> UIView {
        let card = Theme.card([], spacing: 6)
        if post.mediaKind == .photo && post.status != "removed" {
            let preview = CosplayPhotoThumbnail(post: post, api: api)
            preview.heightAnchor.constraint(equalToConstant: 126).isActive = true
            preview.addAction(UIAction { _ in open() }, for: .touchUpInside)
            card.addArrangedSubview(preview)
        }
        if let openAuthor, let author = post.author {
            let avatar = MemberAvatar.button(author.avatar, size: Theme.iconSize, label: "Open \(author.displayName)’s profile",
                                             memberID: author.id) { openAuthor(author.id) }
            let identity = Theme.stack([avatar, Theme.label(author.displayName, size: 15)], spacing: 8, axis: .horizontal)
            identity.alignment = .center
            card.addArrangedSubview(identity)
        }
        card.addArrangedSubview(Theme.textAction(post.title, action: open))
        let status = post.ownerId == api.memberID ? " · \(post.statusTitle)" : ""
        card.addArrangedSubview(Theme.label("\(post.mediaKind.title)\(status)", size: 14, color: Theme.secondary))
        return card
    }
}

private final class CosplayPhotoThumbnail: UIButton {
    private let picture = UIImageView()
    private var loadTask: Task<Void, Never>?

    init(post: CosplayPost, api: CommunityAPI) {
        super.init(frame: .zero)
        accessibilityLabel = "Open \(post.title)"
        picture.contentMode = .scaleAspectFill
        picture.clipsToBounds = true
        picture.layer.cornerRadius = 12
        picture.backgroundColor = Theme.ink
        picture.isUserInteractionEnabled = false
        picture.translatesAutoresizingMaskIntoConstraints = false
        addSubview(picture)
        NSLayoutConstraint.activate([
            picture.leadingAnchor.constraint(equalTo: leadingAnchor),
            picture.trailingAnchor.constraint(equalTo: trailingAnchor),
            picture.topAnchor.constraint(equalTo: topAnchor),
            picture.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        loadTask = Task { [weak self] in
            guard let data = try? await api.cosplayMedia(post), !Task.isCancelled else { return }
            let image = await Task.detached { ChatPhoto.decode(data, maximumPixelSize: 480) }.value
            guard !Task.isCancelled, let image else { return }
            self?.picture.image = UIImage(cgImage: image)
        }
    }

    required init?(coder: NSCoder) { nil }

    deinit { loadTask?.cancel() }
}

final class CosplayPostPage: CityPage {
    private var post: CosplayPost
    private var refreshTask: Task<Void, Never>?
    private let media = Theme.stack()
    private var temporaryVideo: URL?
    private var loading = false
    private var engagement: PublicationReactionBar?

    init(post: CosplayPost, api: CommunityAPI) {
        self.post = post
        super.init("Cosplay post", api: api)
    }

    required init?(coder: NSCoder) { nil }

    deinit { if let temporaryVideo { try? FileManager.default.removeItem(at: temporaryVideo) } }

    override func viewDidLoad() {
        super.viewDidLoad()
        enableRefresh { [weak self] in self?.reloadPost() }
        renderPost()
    }

    private func renderPost() {
        body.clear()
        actions.clear()
        media.clear()
        engagement = nil
        body.addArrangedSubview(Theme.label(post.title, size: 28, display: true))
        if !post.caption.isEmpty { body.addArrangedSubview(Theme.label(post.caption, color: Theme.secondary)) }
        if let author = post.author {
            let avatar = MemberAvatar.button(author.avatar, size: Theme.iconSize, label: "Open \(author.displayName)’s profile",
                                             memberID: author.id) { [weak self] in
                guard let self else { return }
                self.push(ProfilePage(memberID: author.id, api: self.api))
            }
            let identity = Theme.stack([avatar, Theme.label(author.displayName)], spacing: 8, axis: .horizontal)
            identity.alignment = .center
            body.addArrangedSubview(identity)
        }
        body.addArrangedSubview(media)
        if post.ownerId == api.memberID {
            body.addArrangedSubview(Theme.label(post.statusTitle, color: Theme.secondary))
            body.addArrangedSubview(Theme.button("Remove post") { [weak self] in self?.confirmRemoval() })
        } else {
            actions.addArrangedSubview(Theme.moreIcon(label: "Post options") { [weak self] in
                guard let self else { return }
                let id = self.post.id.uuidString
                self.menu("Post options", choices: [
                    ("Report post", .destructive, { [weak self] in self?.report(["cosplay_post_id": id]) })
                ])
            })
        }
        guard post.status != "removed" else { return }
        body.addArrangedSubview(Theme.textAction("Share media link") { [weak self] in
            guard let self, let url = try? self.api.cosplayMediaURL(self.post) else { return }
            self.present(UIActivityViewController(activityItems: [url], applicationActivities: nil), animated: true)
        })
        if post.mediaKind == .video {
            if post.status == "approved" {
                let bar = PublicationReactionBar(api: api, source: .cosplay, item: post.id)
                body.addArrangedSubview(bar.view)
                engagement = bar
            }
            media.addArrangedSubview(Theme.button("Play video", accent: true) { [weak self] in self?.loadMedia() })
        }
    }

    private func reloadPost() {
        guard !loading else {
            pageRefresh.finish(error: "Wait for the media to load, then pull down again.")
            return
        }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let rows = try await api.cosplayPosts(owner: post.ownerId, ids: [post.id])
                try Task.checkCancellation()
                guard let updated = rows.first else { throw CommunityError.unavailable }
                post = updated
                renderPost()
                if post.mediaKind == .photo && post.status != "removed" {
                    loadMedia { [weak self] error in self?.pageRefresh.finish(error: error) }
                } else if let engagement {
                    engagement.load { [weak self] error in self?.pageRefresh.finish(error: error) }
                } else {
                    pageRefresh.finish()
                }
            } catch {
                guard !Task.isCancelled else { return }
                pageRefresh.finish(error: "This post could not be updated. Pull down to try again.")
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        engagement?.load()
        if post.mediaKind == .photo, post.status != "removed", media.arrangedSubviews.isEmpty { loadMedia() }
    }

    private func loadMedia(completion: ((String?) -> Void)? = nil) {
        guard !loading else {
            completion?("Wait for the media to load, then pull down again.")
            return
        }
        loading = true
        showStatus("Loading \(post.mediaKind.title.lowercased())…")
        Task {
            defer { loading = false }
            do {
                let data = try await api.cosplayMedia(post)
                if post.mediaKind == .photo {
                    guard let image = await Task.detached(operation: { ChatPhoto.decode(data) }).value else {
                        throw CommunityError.unavailable
                    }
                    let picture = UIImageView(image: UIImage(cgImage: image))
                    picture.contentMode = .scaleAspectFit
                    picture.heightAnchor.constraint(equalToConstant: 330).isActive = true
                    picture.accessibilityLabel = post.title
                    picture.isAccessibilityElement = true
                    media.clear()
                    media.addArrangedSubview(picture)
                } else {
                    guard view.window != nil, navigationController?.topViewController === self else { return }
                    try CosplayMedia.play(data, from: self, temporaryFile: &temporaryVideo)
                }
                showStatus(nil)
                completion?(nil)
            } catch {
                completion?("This media could not be updated. Pull down to try again.")
                showStatus("This media could not be loaded.")
                if post.mediaKind == .photo, media.arrangedSubviews.isEmpty {
                    media.addArrangedSubview(Theme.button("Retry") { [weak self] in self?.loadMedia() })
                }
            }
        }
    }

    private func confirmRemoval() {
        let alert = UIAlertController(title: "Remove this post?",
                                      message: "The post and its uploaded file will be removed.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Remove", style: .destructive) { [weak self] _ in
            guard let self else { return }
            Task {
                do {
                    try await self.api.removeCosplay(self.post)
                    self.navigationController?.popViewController(animated: true)
                } catch { self.showStatus("Removal could not finish. Try again.") }
            }
        })
        present(alert, animated: true)
    }
}
