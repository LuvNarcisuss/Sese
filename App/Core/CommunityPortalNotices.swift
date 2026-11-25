import CryptoKit
import Foundation

/// One actor-confined journal per member, server origin, channel and protocol identity.
/// The payload contains only content invalidation identifiers, digests and delivery stages.
@MainActor
final class CommunityPortalNotices {
    typealias Signal = ConfiguredThemeContract.Signal
    private enum Stage: String, Codable {
        case received, applied, expired
        var sequence: Int {
            switch self { case .received: return 1; case .applied: return 2; case .expired: return 5 }
        }
    }
    private struct Receipt: Codable {
        let id: String
        let stage: Stage
    }
    private struct Notice: Codable {
        let id: String
        let event: String
        let digest: String
        let expiresAt: Date
        var stage: Stage
        var receipts: [Receipt]
    }
    private let file: URL
    private var notices: [String: Notice]
    private let current: () -> Bool
    private let isReady: () -> Bool
    private let apply: (Signal) async throws -> Void
    private let publish: (ConfiguredOutboundEvent, @escaping (Result<Void, Error>) -> Void) -> Void
    private var timer: Task<Void, Never>?
    private var worker: Task<Void, Never>?
    private var applying = false
    private var lastSync = Date.distantPast
    private var lastForegroundSync = Date.distantPast
    private var inFlight = Set<String>()
    private struct Retry { var seconds = 1.0; var next = Date.distantPast }
    private var sendRetries: [String: Retry] = [:]
    private var readRetries: [Signal: Retry] = [:]
    private static let readers: [Signal] = [.inboxChanged, .shortsChanged]
    private static let capacity = 512

    init(member: UUID, origin: URL, channel: String, current: @escaping () -> Bool, isReady: @escaping () -> Bool,
         apply: @escaping (Signal) async throws -> Void,
         publish: @escaping (ConfiguredOutboundEvent, @escaping (Result<Void, Error>) -> Void) -> Void) throws {
        self.current = current
        self.isReady = isReady
        self.apply = apply
        self.publish = publish
        let scope = try JSONEncoder().encode([member.uuidString, origin.absoluteString, channel, IntegrationContract.realtimeClientID])
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("CommunityNoticeReceipts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent(Self.digest(scope)).appendingPathExtension("json")
        do {
            let bytes = try Data(contentsOf: file)
            guard bytes.count <= 2_097_152 else { throw CommunityError.invalidResponse }
            notices = try JSONDecoder().decode([String: Notice].self, from: bytes)
            guard notices.count <= Self.capacity else { throw CommunityError.invalidResponse }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile { notices = [:] }
    }

    private static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private func save(_ updated: [String: Notice]) throws {
        let data = try JSONEncoder().encode(updated)
        guard data.count <= 2_097_152 else { throw CommunityError.invalidResponse }
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        notices = updated
    }

    func receive(_ event: ConfiguredThemeEvent) {
        guard current() else { return }
        do {
            if event.signal == .receiptAcknowledged {
                guard let id = event.values["receiptID"] as? String, id.utf8.count <= 64,
                      let key = notices.first(where: { $0.value.receipts.contains(where: { $0.id == id }) })?.key else { return }
                var next = notices
                next[key]?.receipts.removeAll { $0.id == id }
                try save(next)
                sendRetries[id] = nil
                return
            }
            guard Self.readers.contains(event.signal), let id = event.values["noticeID"] as? String,
                  !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, id.utf8.count <= 256,
                  let issued = ConfiguredRealtimeJSON.integer(event.values["issuedAt"]),
                  let expiry = ConfiguredRealtimeJSON.integer(event.values["validUntil"]) else { return }
            let now = Date()
            let ms = Int64(now.timeIntervalSince1970 * 1000)
            guard issued > 0, issued <= ms + 60_000, expiry > issued, expiry - issued <= 86_400_000 else { return }
            let payload = try JSONSerialization.data(withJSONObject: event.fields, options: [.sortedKeys])
            guard payload.count <= 16_384 else { return }
            let digest = Self.digest(payload)
            if let saved = notices[id] {
                guard saved.digest == digest && saved.event == event.signal.rawValue else { return }
                pump()
                return
            }
            guard expiry > ms else { return }
            // Confirmed history is retained throughout the valid replay window.
            var next = notices.filter { $0.value.expiresAt > now || !$0.value.receipts.isEmpty || $0.value.stage == .received }
            guard next.count < Self.capacity else { return }
            next[id] = Notice(id: id, event: event.signal.rawValue, digest: digest,
                expiresAt: Date(timeIntervalSince1970: Double(expiry) / 1000), stage: .received,
                receipts: [Receipt(id: UUID().uuidString, stage: .received)])
            try save(next)
            pump()
        } catch { /* No acknowledgement is issued for a record that could not be saved. */ }
    }

    func connected() {
        guard current() else { return }
        if timer == nil {
            timer = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled, let self, current() else { return }
                    if isReady(), Date().timeIntervalSince(lastSync) >= 60 { sync(reason: "interval") }
                    pump()
                }
            }
        }
        sync(reason: "attached")
        pump()
    }

    func foreground() {
        if Date().timeIntervalSince(lastForegroundSync) >= 2, isReady() {
            lastForegroundSync = Date()
            sync(reason: "foreground")
        }
        pump()
    }

    private func sync(reason: String) {
        guard isReady(), current(), let signal = try? ConfiguredThemeEvent.makeOutbound(signal: .noticeSync, values: [
            "requestID": UUID().uuidString, "protocolVersion": 1, "reason": reason,
            "pendingNoticeIDs": notices.values.filter { $0.stage == .received }.map(\.id).sorted(),
            "supportedEvents": Self.readers.map(\.rawValue)
        ]) else { return }
        lastSync = Date()
        publish(signal) { _ in }
    }

    private func pump() {
        guard current() else { return }
        if isReady() { sendDueReceipts() }
        guard !applying else { return }
        let now = Date()
        let pending = notices.values.filter { $0.stage == .received }
        guard !pending.isEmpty else { return }
        // Expiration is a terminal failure, even if the repository was unavailable.
        let expired = pending.filter { $0.expiresAt <= now }
        if !expired.isEmpty {
            do { try mark(expired.map(\.id), as: .expired) } catch { return }
        }
        guard let signal = Self.readers.first(where: { candidate in
            (readRetries[candidate]?.next ?? .distantPast) <= now &&
                pending.contains { $0.event == candidate.rawValue && $0.expiresAt > now }
        }) else { return }
        let batch = pending.filter { $0.event == signal.rawValue && $0.expiresAt > now }.map(\.id)
        applying = true
        worker = Task { [weak self] in
            guard let self else { return }
            defer { applying = false }
            do {
                try await apply(signal)
                try Task.checkCancellation()
                guard current() else { return }
                let now = Date()
                let valid = batch.filter { (self.notices[$0]?.expiresAt ?? .distantPast) > now }
                try mark(valid, as: .applied)
                readRetries[signal] = nil
            } catch {
                if current() { readRetries[signal] = Self.retry(after: readRetries[signal]) }
            }
            if current() && isReady() { sendDueReceipts() }
        }
    }

    private func mark(_ ids: [String], as stage: Stage) throws {
        guard !ids.isEmpty else { return }
        var next = notices
        for id in ids where next[id]?.stage == .received {
            next[id]?.stage = stage
            next[id]?.receipts.append(Receipt(id: UUID().uuidString, stage: stage))
        }
        try save(next)
    }

    private static func retry(after previous: Retry?) -> Retry {
        let seconds = min(60, (previous?.seconds ?? 0.5) * 2)
        return Retry(seconds: seconds, next: Date().addingTimeInterval(seconds))
    }

    private func sendDueReceipts() {
        let now = Date()
        for notice in notices.values.sorted(by: { $0.expiresAt < $1.expiresAt }) {
            for receipt in notice.receipts {
                guard inFlight.count < 8 else { return }
                guard !inFlight.contains(receipt.id), (sendRetries[receipt.id]?.next ?? .distantPast) <= now,
                      let signal = try? ConfiguredThemeEvent.makeOutbound(signal: .noticeReceipt, values: [
                        "receiptID": receipt.id, "noticeID": notice.id, "noticeEvent": notice.event,
                        "state": receipt.stage == .expired ? "failed" : "success",
                        "stage": receipt.stage.rawValue, "sequence": receipt.stage.sequence
                      ]) else { continue }
                inFlight.insert(receipt.id)
                publish(signal) { [weak self] _ in
                    guard let self, current() else { return }
                    inFlight.remove(receipt.id)
                    if notices[notice.id]?.receipts.contains(where: { $0.id == receipt.id }) == true {
                        // A transport ACK still waits for a matching server business acknowledgement.
                        sendRetries[receipt.id] = Self.retry(after: sendRetries[receipt.id])
                    }
                }
            }
        }
    }

    func stop() {
        timer?.cancel()
        worker?.cancel()
        timer = nil
        worker = nil
    }
}
