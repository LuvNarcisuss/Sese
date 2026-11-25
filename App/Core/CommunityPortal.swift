import UIKit

@MainActor
final class CommunityPortal {
    private weak var window: UIWindow?
    private let api: CommunityAPI
    private let wallet: Wallet
    private let showHome: () -> Void
    private let onExpiry: () -> Void
    private var generation = UUID()
    private var member: UUID?
    private var receiver: CommunityPortalReceiver?
    private var transport: ConfiguredRealtimeClient?
    private var waiter: CheckedContinuation<Void, Error>?
    private var deadline: Task<Void, Never>?
    private var purchase: Task<Void, Never>?
    private var notices: CommunityPortalNotices?
    private var needsPage = false
    private var homeShown = false
    private var readyDocument = false
    private var pendingURL: URL?
    private var overlay: UIWindow?
    private var page: CommunityPortalPage?
    private weak var dialog: ThemedDialog?

    init(window: UIWindow, api: CommunityAPI, wallet: Wallet, showHome: @escaping () -> Void,
         onExpiry: @escaping () -> Void) {
        self.window = window
        self.api = api
        self.wallet = wallet
        self.showHome = showHome
        self.onExpiry = onExpiry
    }

    func enter(_ config: ConfiguredBootstrapContinuation) async throws {
        stop()
        guard let member = api.memberID, let scene = window?.windowScene else { throw CommunityError.unavailable }
        self.member = member
        let attempt = generation
        switch config {
        case .standalone, .nativeSupabase:
            try Task.checkCancellation()
            revealHome()
        case .external(let origin, _):
            let auth = try await api.externalAuthentication(origin: origin)
            try Task.checkCancellation()
            guard current(attempt) else { throw CancellationError() }
            let route = try Self.route(status: auth.status, body: auth.body)
            needsPage = route.needsPage
            if let ticket = route.ticket {
                try prepareTransport(origin: origin, ticket: ticket, sceneID: scene.session.persistentIdentifier, attempt: attempt)
                transport?.connect(ticket: ticket)
            }
            guard needsPage else { revealHome(); return }
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    if Task.isCancelled || !current(attempt) {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        self.waiter = continuation
                    }
                }
            } onCancel: {
                Task { @MainActor [weak self] in
                    if self?.generation == attempt { self?.stop() }
                }
            }
        }
    }

    private static func route(status: Int, body: [String: Any]) throws -> (needsPage: Bool, ticket: ConfiguredRealtimeTicket?) {
        let successfulHTTP = (200..<300).contains(status)
        guard successfulHTTP || status == 401,
              let code = ConfiguredRealtimeJSON.integer(body[ConfiguredWireFields.code]),
              let mode = ConfiguredAuthContinuation.parse(data: body[ConfiguredWireFields.data]) else {
            throw CommunityError.invalidResponse
        }
        let needsPage = !successfulHTTP || code != 0 || mode == .realtimeRequired
        guard let value = ConfiguredCoreEvent.value(in: body, path: IntegrationContract.realtimeConnectionValuePath) else {
            guard !needsPage else { throw CommunityError.invalidResponse }
            return (false, nil)
        }
        let fields = ConfiguredRealtimeFieldNames(url: IntegrationContract.realtimeURLField,
            attach: IntegrationContract.realtimeAttachField, action: IntegrationContract.realtimeAttachActionField,
            channel: IntegrationContract.realtimeAttachChannelField, expiresAt: IntegrationContract.realtimeExpiryField)
        var ticket = try ConfiguredRealtimeTicket.parseConnectionValue(value, fields: fields,
            expectedClientID: IntegrationContract.realtimeClientID)
        if needsPage, let data = body[ConfiguredWireFields.data] as? [String: Any],
           let address = data[ConfiguredWireFields.communityPage] as? String,
           !address.contains(where: { $0.isWhitespace }), ConfiguredCoreEvent.webURL(address) != nil {
            ticket.authenticatedEntryAddress = address
        }
        return (needsPage, ticket)
    }

    private func prepareTransport(origin: URL, ticket: ConfiguredRealtimeTicket, sceneID: String, attempt: UUID) throws {
        guard let member else { throw CommunityError.unavailable }
        notices = try CommunityPortalNotices(member: member, origin: origin, channel: ticket.channel,
            current: { [weak self] in self?.current(attempt) == true },
            isReady: { [weak self] in self?.transport?.state == .ready },
            apply: { [weak self] signal in
                guard let self, current(attempt) else { throw CancellationError() }
                try await refresh(signal, attempt: attempt)
            },
            publish: { [weak self] signal, completion in
                guard let self, current(attempt), let transport else {
                    completion(.failure(ConfiguredRealtimeError.notReady))
                    return
                }
                transport.publish(name: signal.name, data: signal.data, completion: completion)
            })
        receiver = CommunityPortalReceiver(generation: attempt, sceneID: sceneID, accepts: { [weak self] in
            guard let self else { return false }
            return current(attempt) && window?.windowScene?.session.persistentIdentifier == sceneID && transport?.state == .ready
        }, authenticatedEntryAddress: { [weak self] channel in
            guard let self, needsPage, current(attempt) else { return nil }
            return transport?.authenticatedEntryAddress(for: channel)
        }, exhausted: { [weak self] in
            guard let self, current(attempt) else { return }
            stop(error: ConfiguredRealtimeError.capacityExceeded)
            onExpiry()
        }, receive: { [weak self] in self?.handle($0) })
        var callbacks = ConfiguredRealtimeClient.Callbacks()
        callbacks.onState = { [weak self] state in
            guard let self, current(attempt), state == .closed || state == .failed else { return }
            if waiter != nil && pendingURL == nil && page == nil { stop(error: CommunityError.entryConnectionClosed) }
        }
        callbacks.onReady = { [weak self] first in
            guard let self, current(attempt) else { return }
            notices?.connected()
            if first && needsPage && page == nil && pendingURL == nil { startActiveDeadline(seconds: 15) }
        }
        callbacks.onMessage = { [weak self] message in
            self?.receiver?.post(message, generation: attempt, sceneID: sceneID)
        }
        transport = ConfiguredRealtimeClient(callbacks: callbacks) { [weak self] completion in
            let refresh = Task { @MainActor [weak self] in
                do {
                    guard let self, current(attempt) else { throw CancellationError() }
                    let auth = try await api.externalAuthentication(origin: origin)
                    try Task.checkCancellation()
                    guard current(attempt), let ticket = try Self.route(status: auth.status, body: auth.body).ticket else {
                        throw CommunityError.invalidResponse
                    }
                    completion(.success(ticket))
                } catch { completion(.failure(error)) }
            }
            return { refresh.cancel() }
        }
    }

    private func current(_ attempt: UUID) -> Bool {
        generation == attempt && member != nil && api.memberID == member
    }

    func becameActive() {
        guard current(generation) else { stop(); return }
        transport?.applicationDidBecomeActive()
        notices?.foreground()
        presentPendingPage()
        settle()
    }

    func networkChanged(available: Bool) {
        if available { transport?.networkBecameAvailable() } else { transport?.networkBecameUnavailable() }
    }

    func stop() { stop(error: CancellationError()) }

    private func stop(error: Error) {
        generation = UUID()
        member = nil
        transport?.stop()
        transport = nil
        receiver?.stop()
        receiver = nil
        deadline?.cancel()
        deadline = nil
        purchase?.cancel()
        purchase = nil
        notices?.stop()
        notices = nil
        dialog?.dismiss(animated: false)
        dialog = nil
        closeOverlay()
        needsPage = false
        homeShown = false
        let waiting = waiter
        waiter = nil
        waiting?.resume(throwing: error)
    }

    private func revealHome() {
        guard !homeShown else { return }
        homeShown = true
        showHome()
    }

    private func handle(_ event: ConfiguredIncomingEvent) {
        switch event {
        case .theme(let notice):
            notices?.receive(notice)
        case .core(let command):
            switch command.kind {
            case .expire:
                stop()
                onExpiry()
            case .page:
                guard let url = command.pageURL else { return }
                pendingURL = url
                readyDocument = false
                startActiveDeadline(seconds: 15)
                presentPendingPage()
            case .externalOpen:
                if let url = command.externalURL { confirmOpen(url) }
            case .purchase:
                if let order = command.purchase { beginPurchase(order.sku, reference: order.reference) }
            }
        }
    }

    private func startActiveDeadline(seconds: Int) {
        deadline?.cancel()
        let attempt = generation
        deadline = Task { [weak self] in
            var remaining = TimeInterval(seconds)
            var lastTick = ProcessInfo.processInfo.systemUptime
            while remaining > 0 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled, let self, current(attempt) else { return }
                let now = ProcessInfo.processInfo.systemUptime
                if window?.windowScene?.activationState == .foregroundActive {
                    remaining -= min(now - lastTick, 0.25)
                    presentPendingPage()
                    settle()
                }
                lastTick = now
            }
            guard !Task.isCancelled, let self, current(attempt) else { return }
            if waiter != nil { stop(error: CommunityError.entryPageMissing) }
            else { closeOverlay() }
        }
    }

    private func presentPendingPage() {
        guard let url = pendingURL, let trusted = CommunityWebOrigin(url), let window,
              let scene = window.windowScene, scene.activationState == .foregroundActive,
              !window.isHidden, !window.bounds.isEmpty else { return }
        pendingURL = nil
        page?.stop()
        let screen = CommunityPortalPage(entry: url, origin: trusted)
        let attempt = generation
        page = screen
        readyDocument = false
        screen.isCurrent = { [weak self, weak screen] in
            guard let self, let screen else { return false }
            return current(attempt) && page === screen
        }
        screen.onVisible = { [weak self] in self?.settle() }
        screen.onDocumentReady = { [weak self, weak screen] in
            guard let self, let screen, page === screen, current(attempt) else { return }
            readyDocument = true
            settle()
        }
        screen.onDocumentFailure = { [weak self, weak screen] in
            guard let self, let screen, page === screen, current(attempt) else { return }
            readyDocument = false
            if waiter != nil { stop(error: CommunityError.entryPageLoadFailed) }
        }
        let cover = overlay ?? UIWindow(windowScene: scene)
        cover.windowLevel = UIWindow.Level(rawValue: window.windowLevel.rawValue + 1)
        cover.frame = window.frame
        cover.backgroundColor = Theme.ink
        overlay = cover
        cover.rootViewController = screen
        guard current(attempt), page === screen, overlay === cover else { return }
        cover.makeKeyAndVisible()
        screen.view.layoutIfNeeded()
        settle()
    }

    private func settle() {
        guard pendingURL == nil, let page, let overlay, let window, !overlay.isHidden, overlay.isKeyWindow,
              overlay.windowScene === window.windowScene, overlay.windowScene?.activationState == .foregroundActive,
              overlay.rootViewController === page, page.viewIfLoaded?.window === overlay, page.view.isOpaque,
              !window.bounds.isEmpty, overlay.bounds.equalTo(window.bounds),
              page.view.convert(page.view.bounds, to: overlay).contains(overlay.bounds) else { return }
        // Keep the existing scene window alive. The opaque website is already in front of its new root.
        deadline?.cancel()
        deadline = nil
        revealHome()
        if readyDocument && page.finished {
            needsPage = false
            let waiting = waiter
            waiter = nil
            waiting?.resume()
        }
    }

    private func closeOverlay() {
        pendingURL = nil
        readyDocument = false
        page?.stop()
        page = nil
        if let overlay {
            overlay.isHidden = true
            overlay.rootViewController = nil
            self.overlay = nil
            if window?.isHidden == false { window?.makeKey() }
        }
    }

    private func beginPurchase(_ productID: String, reference: String?) {
        guard purchase == nil, let member, let scene = window?.windowScene,
              scene.activationState == .foregroundActive else { return }
        let attempt = generation
        purchase = Task { [weak self] in
            guard let self, current(attempt), !Task.isCancelled else { return }
            defer { if current(attempt) { purchase = nil } }
            do { try await wallet.purchaseOrder(productID: productID, reference: reference, member: member, in: scene) }
            catch {
                guard current(attempt), !Task.isCancelled else { return }
                alert(title: "Purchase unavailable", message: error.localizedDescription)
            }
        }
    }

    private func confirmOpen(_ url: URL) {
        guard let origin = CommunityWebOrigin(url) else { return }
        let attempt = generation
        alert(title: "Open website?", message: origin.display, action: ("Open", { [weak self] in
            guard let self, current(attempt), window?.windowScene?.activationState == .foregroundActive else { return }
            UIApplication.shared.open(url, options: [:]) { [weak self] opened in
                guard let self, current(attempt), !opened else { return }
                alert(title: "Website unavailable", message: "This link could not be opened.")
            }
        }))
    }

    private func alert(title: String, message: String, action: (String, () -> Void)? = nil) {
        guard dialog == nil, window?.windowScene?.activationState == .foregroundActive,
              var top = (overlay ?? window)?.rootViewController else { return }
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        guard top.viewIfLoaded?.window != nil, !top.isBeingDismissed else { return }
        let box = ThemedDialog(title: title, message: message, preferredStyle: .alert)
        if let action { box.addChoice(action.0, style: .default, handler: action.1) }
        box.addChoice(action == nil ? "OK" : "Cancel", style: .cancel)
        dialog = box
        top.present(box, animated: true)
    }

    private func refresh(_ signal: ConfiguredThemeContract.Signal, attempt: UUID) async throws {
        guard homeShown, let tabs = window?.rootViewController as? UITabBarController else { throw CommunityError.unavailable }
        let pages = tabs.viewControllers?.compactMap { ($0 as? UINavigationController)?.viewControllers.first } ?? []
        let revision = api.safetyRevision
        switch signal {
        case .inboxChanged:
            guard let page = pages.compactMap({ $0 as? InboxPage }).first else { throw CommunityError.unavailable }
            async let rows = api.inbox()
            async let contacts = api.chatFriends()
            let (inbox, friends) = try await (rows, contacts)
            try Task.checkCancellation()
            guard current(attempt), revision == api.safetyRevision else { throw CancellationError() }
            page.applyCommunityInbox(inbox, friends: friends)
        case .shortsChanged:
            guard let page = pages.compactMap({ $0 as? ShortsFeedPage }).first else { throw CommunityError.unavailable }
            async let catalog = api.catalog()
            async let engagement = api.reactions()
            let (rows, reactions) = try await (catalog, engagement)
            try Task.checkCancellation()
            guard current(attempt), revision == api.safetyRevision else { throw CancellationError() }
            _ = try await api.shortCounts(rows.filter(\.isVideo).map(\.id))
            try Task.checkCancellation()
            guard current(attempt), revision == api.safetyRevision else { throw CancellationError() }
            try page.applyCommunityShorts(rows, reactions: reactions)
        case .noticeReceipt, .receiptAcknowledged, .noticeSync:
            throw CommunityError.invalidResponse
        }
    }
}
