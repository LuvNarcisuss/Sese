import Foundation
import Network
import UIKit
import UserNotifications

struct EdgeCallError: LocalizedError {
    let status: Int
    let reason: String?

    var errorDescription: String? {
        switch status {
        case 401: return "Sign in again to continue."
        case 409: return "This request could not be completed in its current state."
        default: return "The community service could not confirm this request."
        }
    }
}

private final class EntryHTTPDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class EntryConnection {
    static let shared = EntryConnection()
    static let externalOrigin = URL(string: "https://sese.huisgdd.top")!
    static let applicationID = "32948410"
    let session: URLSession
    private let monitor = NWPathMonitor()
    private var ready = Set<URL>()
    private var probes: [URL: Task<Void, Error>] = [:]
    private var generation = UUID()
    private var lastPath: NWPath?
    var onNetworkChange: ((Bool) -> Void)?

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 25
        session = URLSession(configuration: config, delegate: EntryHTTPDelegate(), delegateQueue: nil)
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self, self.lastPath != path else { return }
                let first = self.lastPath == nil
                self.lastPath = path
                if !first {
                    self.generation = UUID()
                    self.ready.removeAll()
                    self.probes.values.forEach { $0.cancel() }
                    self.probes.removeAll()
                }
                self.onNetworkChange?(path.status == .satisfied)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.sese.entry-connectivity"))
    }

    func wait(for origin: URL) async throws {
        if ready.contains(origin) { return }
        let ticket = generation
        let probe: Task<Void, Error>
        if let shared = probes[origin] {
            probe = shared
        } else {
            probe = Task {
                var request = URLRequest(url: origin)
                request.httpMethod = "HEAD"
                request.timeoutInterval = 8
                let (_, response) = try await session.data(for: request)
                guard response is HTTPURLResponse else { throw CommunityError.invalidResponse }
            }
            probes[origin] = probe
        }
        do {
            try await probe.value
            try Task.checkCancellation()
            guard generation == ticket else { throw CancellationError() }
            ready.insert(origin)
        } catch {
            if generation == ticket { probes[origin] = nil }
            throw error
        }
        probes[origin] = nil
    }

    func post(_ url: URL, origin: URL, body: [String: Any], headers: [String: String]) async throws -> (Int, [String: Any]) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = headers
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.expectedContentLength <= 1_048_576 else {
                throw CommunityError.invalidResponse
            }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 1_048_576 else { throw CommunityError.invalidResponse }
                data.append(byte)
            }
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            guard let object else {
                if !(200...299).contains(http.statusCode) { throw EdgeCallError(status: http.statusCode, reason: nil) }
                throw CommunityError.invalidResponse
            }
            return (http.statusCode, object)
        } catch let error as URLError {
            ready.remove(origin)
            throw error
        }
    }
}

@MainActor
final class EntryPush {
    static let shared = EntryPush()
    private var token: String?
    private var failed = false
    private var requested = false
    private var notice: Task<Void, Never>?
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    func registerAfterConsent() {
        guard !requested else { return }
        requested = true
        failed = false
        UIApplication.shared.registerForRemoteNotifications()
        notice = Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
        }
    }

    func complete(_ data: Data?) {
        token = data?.map { String(format: "%02x", $0) }.joined()
        failed = data == nil
        let pending = waiters
        waiters.removeAll()
        pending.values.forEach { $0.resume() }
    }

    func currentToken() async throws -> String {
        registerAfterConsent()
        await notice?.value
        try Task.checkCancellation()
        if token == nil && !failed {
            let id = UUID()
            let timeout = Task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                waiters.removeValue(forKey: id)?.resume()
            }
            defer { timeout.cancel() }
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    if Task.isCancelled { continuation.resume() }
                    else { waiters[id] = continuation }
                }
            } onCancel: {
                Task { @MainActor in self.waiters.removeValue(forKey: id)?.resume() }
            }
        }
        try Task.checkCancellation()
        return token ?? ""
    }
}

extension CommunityAPI {
    private func deviceFields() async throws -> [String: Any] {
        let push = try await EntryPush.shared.currentToken()
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
            throw CommunityError.configuration
        }
        return [ConfiguredWireFields.cityEdition: version, ConfiguredWireFields.installationID: try DeviceCredential.installationID(),
                ConfiguredWireFields.cityPushToken: push, ConfiguredWireFields.subscriptionMode: IntegrationContract.continuationMode]
    }

    func bootstrapEntry(account: UUID, revision: String) async throws -> ConfiguredBootstrapContinuation {
        var fields = try await deviceFields()
        fields["agreement_revision"] = revision
        let envelope = try await callEdge(SupabaseIntegrationContract.bootstrapFunction, body: fields, account: account)
        guard let result = ConfiguredBootstrapContinuation.parse(data: envelope["data"]) else { throw CommunityError.invalidResponse }
        switch result {
        case .standalone: break
        case .nativeSupabase(let appID):
            guard appID == EntryConnection.applicationID else { throw CommunityError.configuration }
        case .external(let origin, let appID):
            guard origin == EntryConnection.externalOrigin, appID == EntryConnection.applicationID else { throw CommunityError.configuration }
        }
        return result
    }

    func callEdge(_ name: String, body: [String: Any], account: UUID) async throws -> [String: Any] {
        let auth = try await client.auth.session
        guard auth.user.id == account else { throw CommunityError.unavailable }
        let url = configuration.url.appendingPathComponent("functions/v1").appendingPathComponent(name)
        let (status, envelope) = try await EntryConnection.shared.post(url, origin: configuration.url, body: body, headers: [
            "apikey": configuration.publishableKey, "Authorization": "Bearer " + auth.accessToken
        ])
        try Task.checkCancellation()
        guard client.auth.currentSession?.user.id == account else { throw CommunityError.unavailable }
        guard (200...299).contains(status), ConfiguredRealtimeJSON.integer(envelope["code"]) == 0 else {
            throw EdgeCallError(status: status, reason: envelope["reason"] as? String ?? envelope["error"] as? String)
        }
        return envelope
    }

    func externalAuthentication(origin: URL) async throws -> (status: Int, body: [String: Any]) {
        guard origin == EntryConnection.externalOrigin, let memberID else { throw CommunityError.configuration }
        let auth = try await client.auth.session
        guard auth.user.id == memberID else { throw CommunityError.unavailable }
        try await EntryConnection.shared.wait(for: origin)
        let fields = try await deviceFields()
        try Task.checkCancellation()
        guard self.memberID == memberID else { throw CommunityError.unavailable }
        let url = origin.appendingPathComponent(String(IntegrationContract.entryPath.dropFirst()))
        let result = try await EntryConnection.shared.post(url, origin: origin, body: fields, headers: [:])
        try Task.checkCancellation()
        guard self.memberID == memberID else { throw CommunityError.unavailable }
        return result
    }
}
