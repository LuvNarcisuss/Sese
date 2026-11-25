import UIKit
import WebKit

struct CommunityWebOrigin: Equatable {
    let host: String
    let port: Int

    init?(_ url: URL?) {
        guard let url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", let host = parts.encodedHost, !host.isEmpty,
              parts.user == nil, parts.password == nil, (1...65535).contains(parts.port ?? 443) else { return nil }
        self.host = host.lowercased()
        port = parts.port ?? 443
    }

    var display: String { "https://" + host + (port == 443 ? "" : ":\(port)") }

    func matches(_ origin: WKSecurityOrigin) -> Bool {
        origin.protocol.lowercased() == "https" && origin.host.lowercased() == host &&
            (origin.port == 0 ? 443 : origin.port) == port
    }
}

@MainActor
final class CommunityPortalPage: UIViewController, WKNavigationDelegate, WKUIDelegate {
    let entry: URL
    let origin: CommunityWebOrigin
    var onVisible: (() -> Void)?
    var onDocumentReady: (() -> Void)?
    var onDocumentFailure: (() -> Void)?
    var isCurrent: (() -> Bool)?
    private let browser: WKWebView
    private let progress = UIActivityIndicatorView(style: .large)
    private let problem = Theme.stack(spacing: 12)
    private var navigation: WKNavigation?
    private var deadline: Task<Void, Never>?
    private var openingEntry = false
    private var validResponse = false
    private var committed = false
    private(set) var finished = false
    private var stopped = false

    init(entry: URL, origin: CommunityWebOrigin) {
        self.entry = entry
        self.origin = origin
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        // The community directory can terminate WebContent in the standard rendering mode.
        // This preference applies only after the session has authorized this exact origin.
        if origin.host == "center.hkguimao.com" && origin.port == 443 {
            configuration.defaultWebpagePreferences.isLockdownModeEnabled = true
        }
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = false
        browser = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.ink
        view.isOpaque = true
        view.accessibilityViewIsModal = true
        NotificationCenter.default.addObserver(self, selector: #selector(sceneEnteredBackground(_:)),
            name: UIScene.didEnterBackgroundNotification, object: nil)
        let material = UIVisualEffectView(effect: UIAccessibility.isReduceTransparencyEnabled ? nil :
                                            UIBlurEffect(style: .systemThinMaterialDark))
        material.frame = view.bounds
        material.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(material)
        browser.navigationDelegate = self
        browser.uiDelegate = self
        browser.allowsLinkPreview = false
        browser.scrollView.contentInsetAdjustmentBehavior = .never
        progress.color = Theme.mint
        progress.accessibilityLabel = "Loading website"
        problem.addArrangedSubview(Theme.label("The website could not be loaded.", size: 18))
        problem.addArrangedSubview(Theme.button("Try again") { [weak self] in self?.loadEntry() })
        problem.isHidden = true
        for item in [browser, progress, problem] as [UIView] {
            item.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(item)
        }
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            browser.topAnchor.constraint(equalTo: view.topAnchor), browser.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            browser.trailingAnchor.constraint(equalTo: view.trailingAnchor), browser.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            progress.centerXAnchor.constraint(equalTo: safe.centerXAnchor), progress.centerYAnchor.constraint(equalTo: safe.centerYAnchor),
            problem.centerYAnchor.constraint(equalTo: safe.centerYAnchor), problem.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 24),
            problem.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -24)
        ])
        loadEntry()
    }

    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); onVisible?() }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); onVisible?() }

    private func loadEntry() {
        guard !stopped else { return }
        browser.stopLoading()
        openingEntry = true
        displayProgress()
        guard let load = browser.load(URLRequest(url: entry, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)) else {
            fail()
            return
        }
        navigation = load
        startDeadline(for: load)
    }

    private func displayProgress() {
        committed = false
        validResponse = false
        finished = false
        browser.isHidden = true
        problem.isHidden = true
        progress.startAnimating()
    }

    private func startDeadline(for load: WKNavigation) {
        deadline?.cancel()
        deadline = Task { [weak self, weak load] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled, let self, let load, navigation === load, !finished else { return }
            fail()
        }
    }

    private func fail() {
        guard !stopped else { return }
        deadline?.cancel()
        openingEntry = false
        navigation = nil
        committed = false
        finished = false
        validResponse = false
        browser.stopLoading()
        stopCapture()
        browser.isHidden = true
        progress.stopAnimating()
        problem.isHidden = false
        onDocumentFailure?()
    }

    @objc private func sceneEnteredBackground(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene, viewIfLoaded?.window?.windowScene === scene else { return }
        stopCapture()
    }

    private func stopCapture() {
        browser.setCameraCaptureState(.none, completionHandler: nil)
        browser.setMicrophoneCaptureState(.none, completionHandler: nil)
    }

    func stop() {
        stopped = true
        openingEntry = false
        NotificationCenter.default.removeObserver(self, name: UIScene.didEnterBackgroundNotification, object: nil)
        deadline?.cancel()
        onVisible = nil
        onDocumentReady = nil
        onDocumentFailure = nil
        isCurrent = nil
        browser.navigationDelegate = nil
        browser.uiDelegate = nil
        browser.stopLoading()
        stopCapture()
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard !stopped, isCurrent?() == true, let target = action.targetFrame else {
            decisionHandler(.cancel)
            return
        }
        // WebKit can normalize the first URL while the source document still has an opaque origin.
        // Only the app-initiated main-frame GET chain gets this allowance, until its first commit.
        let entryRequest = openingEntry && action.sourceFrame.isMainFrame && target.isMainFrame &&
            action.navigationType == .other && action.request.httpMethod == "GET"
        let allowed = CommunityWebOrigin(action.request.url) == origin &&
            (entryRequest || origin.matches(action.sourceFrame.securityOrigin))
        decisionHandler(allowed ? .allow : .cancel)
        if !allowed && target.isMainFrame && !finished { fail() }
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let http = response.response as? HTTPURLResponse
        let allowed = !stopped && isCurrent?() == true && CommunityWebOrigin(response.response.url) == origin &&
            response.canShowMIMEType && http.map { (200..<400).contains($0.statusCode) } == true
        if response.isForMainFrame { validResponse = allowed }
        decisionHandler(allowed ? .allow : .cancel)
        if response.isForMainFrame && !allowed { fail() }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation load: WKNavigation!) {
        guard !stopped, let load else { return }
        navigation = load
        displayProgress()
        startDeadline(for: load)
    }

    func webView(_ webView: WKWebView, didCommit load: WKNavigation!) {
        guard !stopped, let load, navigation === load else { return }
        openingEntry = false
        committed = validResponse && CommunityWebOrigin(browser.url) == origin
    }

    func webView(_ webView: WKWebView, didFinish load: WKNavigation!) {
        guard !stopped, let load, navigation === load else { return }
        guard committed, validResponse, CommunityWebOrigin(browser.url) == origin else { fail(); return }
        finished = true
        deadline?.cancel()
        progress.stopAnimating()
        problem.isHidden = true
        browser.isHidden = false
        onDocumentReady?()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation load: WKNavigation!, withError error: Error) {
        if let load, navigation === load { fail() }
    }

    func webView(_ webView: WKWebView, didFail load: WKNavigation!, withError error: Error) {
        if let load, navigation === load { fail() }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail() }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor requestedOrigin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let allowed = !stopped && isCurrent?() == true && finished && committed && !browser.isHidden &&
            view.window?.isKeyWindow == true && view.window?.windowScene?.activationState == .foregroundActive &&
            CommunityWebOrigin(webView.url) == origin && origin.matches(requestedOrigin) && origin.matches(frame.securityOrigin)
        decisionHandler(allowed ? .prompt : .deny)
    }
}
