import Foundation
import Supabase

struct BackendConfiguration: Decodable {
    let url: URL
    let publishableKey: String
    let agreementRevision: String
    let termsURL: String
    let privacyURL: String
}

enum Resources {
    static func url(_ path: String) -> URL {
        Bundle.main.bundleURL.appendingPathComponent("CommunityContent", isDirectory: true).appendingPathComponent(path)
    }

    static func decode<T: Decodable>(_ type: T.Type, _ path: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: url(path)))
    }
}

enum CommunityError: LocalizedError {
    case configuration, agreements, credentialStorage, invalidResponse, unavailable, request(Int), invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .configuration: return "The community service is unavailable."
        case .agreements: return "The current agreements are unavailable. Please try again later."
        case .credentialStorage: return "This iPhone could not open its sign-in credential. Please try again."
        case .invalidResponse: return "The service returned an unexpected response."
        case .unavailable: return "This item is no longer available."
        case .request(let status):
            return status == 403 ? "This action is unavailable for your account." : "The request could not be completed. Please try again."
        case .invalidInput(let message): return message
        }
    }
}

struct CatalogItem: Decodable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let description: String
    let credit: String
    let sourceUrl: URL
    let imageUrl: URL?
    let mediaUrl: URL?
    var isVideo: Bool { kind == "Film Clip" || kind == "Cosplay Video" }
}

struct MemberWork: Decodable, Identifiable {
    let id: UUID
    let ownerId: UUID
    let title: String
    let caption: String
    let sourceUrl: URL
    let status: String
    let author: Member?
}

struct Member: Decodable, Identifiable {
    let id: UUID
    let displayName: String
    let bio: String
    let avatar: String?
    let discoverable: Bool
}

struct MemberCounts: Decodable {
    let followers: Int
    let following: Int
    let friends: Int
}

struct Reaction: Decodable {
    let catalogId: String
    let kind: String
}

struct Comment: Decodable {
    let id: UUID
    let authorId: UUID
    let body: String
    let author: Member?
}

struct Follow: Decodable {
    let followerId: UUID
    let targetId: UUID
}

struct Block: Decodable {
    let targetId: UUID
}

struct Message: Decodable {
    let id: UUID
    let senderId: UUID
    let recipientId: UUID
    let body: String
    let createdAt: String
    let photoPath: String?
}

struct InboxItem: Decodable {
    let peerId: UUID
    let displayName: String
    let avatar: String?
    let body: String
    let createdAt: String
    let pinned: Bool
    let muted: Bool
    let archived: Bool
    let unread: Bool
}

@MainActor
final class CommunityAPI {
    let configuration: BackendConfiguration
    let client: SupabaseClient
    let agreements: AgreementSet?
    private(set) var memberID: UUID?
    private static let chatPhotoBucket = "chat-photos"

    init() throws {
        let configuration = try Resources.decode(BackendConfiguration.self, "Backend.json")
        guard configuration.url.scheme == "https", !configuration.publishableKey.isEmpty else {
            throw CommunityError.configuration
        }
        self.configuration = configuration
        agreements = AgreementSet(configuration: configuration)
        client = SupabaseClient(supabaseURL: configuration.url, supabaseKey: configuration.publishableKey)
    }

    func signIn() async throws {
        guard let agreements else { throw CommunityError.agreements }
        let credential = try DeviceCredential.loadOrCreate()
        let session: Session
        do {
            session = try await client.auth.signIn(email: credential.email, password: credential.password)
        } catch let error as AuthError where error.errorCode == .invalidCredentials {
            try await provisionDeviceAccount(credential, agreementRevision: agreements.revision)
            session = try await client.auth.signIn(email: credential.email, password: credential.password)
        }

        do {
            guard session.user.isAnonymous == false, session.user.email == credential.email else {
                throw CommunityError.invalidResponse
            }
            struct Bootstrap: Decodable { let code: Int; let data: [String: String] }
            let result: Bootstrap = try await read("rpc/bootstrap", method: "POST",
                                                   body: ["agreement_revision": agreements.revision])
            guard result.code == 0, result.data.isEmpty else { throw CommunityError.invalidResponse }
            memberID = session.user.id
        } catch {
            try? await client.auth.signOut(scope: .local)
            throw error
        }
    }

    private func provisionDeviceAccount(_ credential: DeviceCredential, agreementRevision: String) async throws {
        let endpoint = configuration.url.appendingPathComponent("functions/v1/device-sign-in")
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "credential": credential.password,
            "agreement_revision": agreementRevision
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CommunityError.invalidResponse }
        switch response.statusCode {
        case 204: return
        case 409: throw CommunityError.agreements
        case 429: throw CommunityError.invalidInput("Too many sign-in attempts. Please try again shortly.")
        default: throw CommunityError.request(response.statusCode)
        }
    }

    func signOut() async throws {
        try await client.auth.signOut(scope: .local)
        memberID = nil
    }

    func deleteAccount() async throws {
        var lastBatch: [String] = []
        while true {
            let paths: [String] = try await read("rpc/begin_account_photo_cleanup", method: "POST", body: [:])
            if paths.isEmpty { break }
            guard paths != lastBatch else {
                throw CommunityError.invalidInput("Photo cleanup could not finish. Try deleting your account again.")
            }
            _ = try await client.storage.from(Self.chatPhotoBucket).remove(paths: paths)
            lastBatch = paths
        }
        try await write("rpc/delete_my_account", method: "POST", body: [:])
        memberID = nil
        try? await client.auth.signOut(scope: .local)
        DeviceCredential.remove()
    }

    func catalog() async throws -> [CatalogItem] {
        try await read("catalog", query: ["order": "position.asc", "limit": "100"])
    }

    func works(owner: UUID? = nil) async throws -> [MemberWork] {
        var filters = ["order": "created_at.desc,id.desc", "limit": "100",
                       "select": "*,author:profiles!works_owner_id_fkey(*)"]
        if let owner {
            filters["owner_id"] = "eq.\(owner.uuidString)"
        } else {
            filters["status"] = "eq.approved"
        }
        return try await read("works", query: filters)
    }

    func submitWork(title: String, caption: String, url: URL) async throws {
        try await write("works", method: "POST", body: [
            "title": title, "caption": caption, "source_url": url.absoluteString
        ])
    }

    func removeWork(_ id: UUID) async throws {
        try await write("works", method: "DELETE", query: ["id": "eq.\(id.uuidString)"])
    }

    func member(_ id: UUID) async throws -> Member {
        let members: [Member] = try await read("profiles", query: ["id": "eq.\(id.uuidString)"])
        guard let member = members.first else { throw CommunityError.unavailable }
        return member
    }

    func members() async throws -> [Member] {
        try await read("profiles", query: ["discoverable": "eq.true", "order": "display_name.asc,id.asc", "limit": "100"])
    }

    func counts(_ id: UUID) async throws -> MemberCounts {
        try await read("rpc/member_counts", method: "POST", body: ["member": id.uuidString])
    }

    func updateProfile(_ id: UUID, name: String, bio: String, avatar: String?, discoverable: Bool) async throws {
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...30).contains(displayName.count), bio.count <= 160 else {
            throw CommunityError.invalidInput("Use a name of 1–30 characters and a bio of at most 160 characters.")
        }
        try await write("profiles", method: "PATCH", query: ["id": "eq.\(id.uuidString)"],
                        body: ["display_name": displayName, "bio": bio, "avatar": avatar.map { $0 as Any } ?? NSNull(),
                               "discoverable": discoverable])
    }

    func reactions() async throws -> [Reaction] { try await read("reactions", query: ["limit": "200"]) }

    func setReaction(_ kind: String, item: String, enabled: Bool) async throws {
        if enabled {
            try await write("reactions", method: "POST", body: ["catalog_id": item, "kind": kind], prefer: "resolution=ignore-duplicates")
        } else {
            try await write("reactions", method: "DELETE", query: ["catalog_id": "eq.\(item)", "kind": "eq.\(kind)"])
        }
    }

    func comments(_ item: String) async throws -> [Comment] {
        try await read("comments", query: ["catalog_id": "eq.\(item)", "order": "created_at.desc", "limit": "100",
                                          "select": "id,author_id,body,author:profiles!comments_author_id_fkey(*)"])
    }

    func addComment(_ item: String, text: String) async throws {
        try await write("comments", method: "POST", body: ["catalog_id": item, "body": text])
    }

    func removeComment(_ id: UUID) async throws {
        try await write("comments", method: "DELETE", query: ["id": "eq.\(id.uuidString)"])
    }

    func follows() async throws -> [Follow] { try await read("follows", query: ["limit": "200"]) }
    func blocks() async throws -> [Block] { try await read("blocks", query: ["limit": "200"]) }

    func setRelationship(_ table: String, peer: UUID, enabled: Bool) async throws {
        if enabled {
            try await write(table, method: "POST", body: ["target_id": peer.uuidString], prefer: "resolution=ignore-duplicates")
        } else {
            try await write(table, method: "DELETE", query: ["target_id": "eq.\(peer.uuidString)"])
        }
    }

    func report(_ target: [String: String], reason: String) async throws {
        try await write("reports", method: "POST", body: target.merging(["reason": reason]) { _, new in new })
    }

    func inbox() async throws -> [InboxItem] { try await read("rpc/inbox", method: "POST", body: [:]) }

    func thread(_ peer: UUID, before: String? = nil) async throws -> [Message] {
        let other = peer.uuidString
        var query = ["or": "(sender_id.eq.\(other),recipient_id.eq.\(other))",
                     "order": "created_at.desc,id.desc", "limit": "50"]
        if let before { query["created_at"] = "lt.\(before)" }
        return try await read("messages", query: query)
    }

    func send(_ text: String, to peer: UUID, id: UUID) async throws {
        try await write("messages", method: "POST",
                        body: ["id": id.uuidString, "recipient_id": peer.uuidString, "body": text],
                        prefer: "resolution=ignore-duplicates")
    }

    func sendPhoto(_ data: Data, to peer: UUID, id: UUID) async throws {
        guard let sender = memberID, sender != peer, (1...ChatPhoto.maximumBytes).contains(data.count) else {
            throw CommunityError.invalidInput("Choose a valid photo and recipient.")
        }
        let path = Self.chatPhotoPath(sender: sender, peer: peer, id: id)
        let storage = client.storage.from(Self.chatPhotoBucket)
        do {
            try await storage.upload(path, data: data, options: FileOptions(cacheControl: "0", contentType: "image/jpeg", upsert: false))
        } catch {
            let uploadError = error
            guard let existing = try? await storage.download(path: path, cacheNonce: UUID().uuidString),
                  existing == data else { throw uploadError }
        }
        guard memberID == sender else { throw CommunityError.unavailable }
        try await write("rpc/send_chat_photo", method: "POST", body: ["message_id": id.uuidString, "peer_id": peer.uuidString])
    }

    func chatPhoto(for message: Message) async throws -> Data {
        guard let viewer = memberID, viewer == message.senderId || viewer == message.recipientId,
              let path = message.photoPath,
              path == Self.chatPhotoPath(sender: message.senderId, peer: message.recipientId, id: message.id) else {
            throw CommunityError.unavailable
        }
        let data = try await client.storage.from(Self.chatPhotoBucket).download(path: path, cacheNonce: UUID().uuidString)
        guard memberID == viewer, (1...ChatPhoto.maximumBytes).contains(data.count) else { throw CommunityError.unavailable }
        return data
    }

    private static func chatPhotoPath(sender: UUID, peer: UUID, id: UUID) -> String {
        "\(sender.uuidString.lowercased())/\(peer.uuidString.lowercased())/\(id.uuidString.lowercased()).jpg"
    }

    func setPreference(_ fields: [String: Any], peer: UUID) async throws {
        guard let memberID else { throw CommunityError.configuration }
        var payload = fields
        payload["member_id"] = memberID.uuidString
        payload["peer_id"] = peer.uuidString
        try await write("inbox_preferences", method: "POST", body: payload, prefer: "resolution=merge-duplicates")
    }

    func watchMessages(_ onChange: @escaping @MainActor () -> Void) async {
        let channel = client.channel("inbox-\(UUID().uuidString)")
        let changes = channel.postgresChange(InsertAction.self, schema: "public", table: "messages")
        do {
            try await channel.subscribeWithError()
            if !Task.isCancelled { onChange() }
            for await _ in changes {
                if Task.isCancelled { break }
                onChange()
            }
        } catch {
            if !Task.isCancelled { onChange() }
        }
        await client.removeChannel(channel)
    }

    private func read<T: Decodable>(_ path: String, method: String = "GET", query: [String: String] = [:],
                                    body: [String: Any]? = nil) async throws -> T {
        let data = try await request(path, method: method, query: query, body: body, prefer: nil)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    private func write(_ path: String, method: String, query: [String: String] = [:],
                       body: [String: Any]? = nil, prefer: String? = nil) async throws {
        _ = try await request(path, method: method, query: query, body: body, prefer: prefer)
    }

    private func request(_ path: String, method: String, query: [String: String], body: [String: Any]?,
                         prefer: String?) async throws -> Data {
        let session = try await client.auth.session
        let endpoint = configuration.url.appendingPathComponent("rest/v1/\(path)")
        guard var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw CommunityError.configuration }
        if !query.isEmpty { parts.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = parts.url else { throw CommunityError.configuration }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = method
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CommunityError.invalidResponse }
        guard (200...299).contains(response.statusCode) else { throw CommunityError.request(response.statusCode) }
        return data
    }
}
