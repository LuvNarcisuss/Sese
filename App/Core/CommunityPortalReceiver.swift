import Foundation

/// Each scene owns its own center. The only publisher is its current authenticated transport.
@MainActor
final class CommunityPortalReceiver: NSObject {
    private static let arrival = Notification.Name("SeseCommunitySocketMessage")
    private let center = NotificationCenter()
    private let publisher = NSObject()
    private let generation: UUID
    private let sceneID: String
    private let accepts: () -> Bool
    private let authenticatedEntryAddress: (String) -> String?
    private var receivedFirstPage = false
    private let exhausted: () -> Void
    private let receive: (ConfiguredIncomingEvent) -> Void
    private var seen = Set<String>()
    private var active = true

    init(generation: UUID, sceneID: String, accepts: @escaping () -> Bool,
         authenticatedEntryAddress: @escaping (String) -> String?,
         exhausted: @escaping () -> Void, receive: @escaping (ConfiguredIncomingEvent) -> Void) {
        self.generation = generation
        self.sceneID = sceneID
        self.accepts = accepts
        self.authenticatedEntryAddress = authenticatedEntryAddress
        self.receive = receive
        self.exhausted = exhausted
        super.init()
        center.addObserver(self, selector: #selector(deliver(_:)), name: Self.arrival, object: publisher)
    }

    func post(_ message: ConfiguredRealtimeMessage, generation: UUID, sceneID: String) {
        guard active else { return }
        center.post(name: Self.arrival, object: publisher, userInfo: [
            "generation": generation, "scene": sceneID, "message": message
        ])
    }

    @objc private func deliver(_ notification: Notification) {
        guard active, accepts(), (notification.object as? NSObject) === publisher,
              notification.userInfo?["generation"] as? UUID == generation,
              notification.userInfo?["scene"] as? String == sceneID,
              let message = notification.userInfo?["message"] as? ConfiguredRealtimeMessage else { return }
        let address = receivedFirstPage || message.clientID != nil ? nil : authenticatedEntryAddress(message.channel)
        guard let event = try? ConfiguredIncomingEvent.parse(requestID: generation, transportID: message.id,
                  name: message.name, clientID: message.clientID, data: message.data, authenticatedEntryAddress: address) else { return }
        // Theme identity is journaled with its business action and has its own retry rules.
        guard case .core(let item) = event else { receive(event); return }
        switch item.kind {
        case .page: guard CommunityWebOrigin(item.pageURL) != nil else { return }
        case .externalOpen: guard CommunityWebOrigin(item.externalURL) != nil else { return }
        case .purchase: guard item.purchase != nil else { return }
        case .expire: break
        }
        let id = item.messageID
        guard !id.isEmpty, id.utf8.count <= 512, !seen.contains(id) else { return }
        // Fail closed at capacity without evicting purchase IDs or losing a sign-out.
        guard seen.count < 8192 || item.kind == .expire else { exhausted(); return }
        seen.insert(id)
        if item.kind == .page { receivedFirstPage = true }
        receive(event)
    }

    func stop() {
        active = false
        center.removeObserver(self)
        seen.removeAll()
    }
}
