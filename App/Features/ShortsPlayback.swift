import AVFoundation
import UIKit

private final class ShortsPlayerSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var togglePlayback: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        guard let togglePlayback else { return false }
        togglePlayback()
        return true
    }
}

final class ShortsPlaybackView: UIView {
    var progressChanged: ((Float) -> Void)?

    private let videoURL: URL
    private let surface = ShortsPlayerSurface()
    private let poster = UIImageView()
    private let loading = UIActivityIndicatorView(style: .large)
    private lazy var playButton = Theme.button("Play", accent: true) { [weak self] in
        self?.togglePlayback()
    }
    private lazy var failure = Theme.card([
        Theme.label("This short could not start.", color: Theme.secondary),
        Theme.button("Retry playback", accent: true) { [weak self] in self?.retry() }
    ], spacing: 12)
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var displayObservation: NSKeyValueObservation?
    private var playerObservation: NSKeyValueObservation?
    private var progressObserver: Any?
    private var timeout: Task<Void, Never>?
    private var active = false
    private var wantsPlayback = true
    private var ready = false

    init(videoURL: URL, posterURL: URL?) {
        self.videoURL = videoURL
        super.init(frame: .zero)
        backgroundColor = .black
        surface.playerLayer.videoGravity = .resizeAspectFill
        surface.isAccessibilityElement = true
        surface.accessibilityTraits = .button
        surface.accessibilityLabel = "Pause video"
        surface.togglePlayback = { [weak self] in self?.togglePlayback() }
        surface.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(togglePlayback)))

        poster.contentMode = .scaleAspectFill
        poster.clipsToBounds = true
        poster.isUserInteractionEnabled = false
        poster.isAccessibilityElement = false
        loading.color = Theme.paper
        playButton.accessibilityLabel = "Play video"
        playButton.isHidden = true
        failure.alignment = .center
        failure.isHidden = true

        for child in [surface, poster, loading, playButton, failure] as [UIView] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        for child in [surface, poster] as [UIView] {
            NSLayoutConstraint.activate([
                child.leadingAnchor.constraint(equalTo: leadingAnchor),
                child.trailingAnchor.constraint(equalTo: trailingAnchor),
                child.topAnchor.constraint(equalTo: topAnchor),
                child.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        for child in [loading, playButton, failure] as [UIView] {
            NSLayoutConstraint.activate([
                child.centerXAnchor.constraint(equalTo: centerXAnchor),
                child.centerYAnchor.constraint(equalTo: centerYAnchor),
                child.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
                child.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16)
            ])
        }
        if let posterURL {
            Task { [weak self] in
                let image = await Artwork.image(at: posterURL)
                self?.poster.image = image
            }
        }
    }

    required init?(coder: NSCoder) { nil }

    func setActive(_ active: Bool) {
        guard self.active != active else { return }
        self.active = active
        updatePlayback()
    }

    func releasePlayback() {
        active = false
        wantsPlayback = true
        resetPlayer()
        failure.isHidden = true
        playButton.isHidden = true
        surface.isAccessibilityElement = true
    }

    private func preparePlayer() {
        let queue = AVQueuePlayer()
        let layer = surface.playerLayer
        player = queue
        layer.player = queue
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: videoURL))
        displayObservation = layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self, weak queue] layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor [weak self, weak queue] in
                guard let self, let queue, self.player === queue else { return }
                self.ready = true
                self.poster.isHidden = true
                self.loading.stopAnimating()
                self.timeout?.cancel()
            }
        }
        playerObservation = queue.observe(\.timeControlStatus, options: [.new]) { [weak self, weak queue] _, _ in
            Task { @MainActor [weak self, weak queue] in
                guard let self, let queue, self.player === queue else { return }
                if queue.status == .failed || queue.currentItem?.status == .failed {
                    self.showFailure()
                }
            }
        }
        progressObserver = queue.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 10), queue: .main
        ) { [weak self, weak queue] time in
            Task { @MainActor [weak self, weak queue] in
                guard let self, let queue, self.player === queue,
                      let duration = queue.currentItem?.duration.seconds, duration.isFinite, duration > 0,
                      time.seconds.isFinite else { return }
                self.progressChanged?(Float(max(0, min(time.seconds / duration, 1))))
            }
        }
    }

    private func updatePlayback() {
        timeout?.cancel()
        guard active, wantsPlayback, failure.isHidden else {
            player?.pause()
            loading.stopAnimating()
            return
        }
        if player == nil { preparePlayer() }
        player?.play()
        guard !ready else { return }
        loading.startAnimating()
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            self?.showFailure()
        }
    }

    @objc private func togglePlayback() {
        guard active, failure.isHidden else { return }
        wantsPlayback.toggle()
        surface.isAccessibilityElement = wantsPlayback
        playButton.isHidden = wantsPlayback
        updatePlayback()
    }

    private func retry() {
        guard active else { return }
        wantsPlayback = true
        failure.isHidden = true
        surface.isAccessibilityElement = true
        updatePlayback()
    }

    private func showFailure() {
        resetPlayer()
        surface.isAccessibilityElement = false
        playButton.isHidden = true
        failure.isHidden = false
    }

    private func resetPlayer() {
        ready = false
        timeout?.cancel()
        timeout = nil
        displayObservation = nil
        playerObservation = nil
        if let progressObserver { player?.removeTimeObserver(progressObserver) }
        progressObserver = nil
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player?.removeAllItems()
        surface.playerLayer.player = nil
        player = nil
        poster.isHidden = false
        loading.stopAnimating()
        progressChanged?(0)
    }

    deinit {
        timeout?.cancel()
        if let progressObserver { player?.removeTimeObserver(progressObserver) }
    }
}
