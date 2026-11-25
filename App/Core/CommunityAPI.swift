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
    case entryConnectionClosed, entryPageMissing, entryPageLoadFailed

    var errorDescription: String? {
        switch self {
        case .configuration: return "The community service is unavailable."
        case .agreements: return "The current agreements are unavailable. Please try again later."
        case .credentialStorage: return "This iPhone could not open its sign-in credential. Please try again."
        case .invalidResponse: return "The service returned an unexpected response."
        case .unavailable: return "This item is no longer available."
        case .entryConnectionClosed: return "The sign-in connection closed. Please try again."
        case .entryPageMissing: return "The sign-in service did not send a verified page. Please try again later."
        case .entryPageLoadFailed: return "The sign-in page could not be loaded. Please try again."
        case .request(let status):
            return status == 403 ? "This action is unavailable for your account." : "The request could not be completed. Please try again."
        case .invalidInput(let message): return message
        }
    }
}

struct CatalogItem: Decodable, Identifiable, Equatable {
    let id: String
    let kind: String
    let title: String
    let description: String
    let credit: String
    let sourceUrl: URL
    let imageUrl: URL?
    let mediaUrl: URL?
    let publisherId: UUID?
    let publisher: Member?
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

enum CosplayMediaKind: String, Decodable {
    case photo, video

    var title: String { self == .photo ? "Photo" : "Video" }
    var fileExtension: String { self == .photo ? "jpg" : "mp4" }
    var mimeType: String { self == .photo ? "image/jpeg" : "video/mp4" }
}

struct CosplayPost: Decodable, Identifiable {
    let id: UUID
    let ownerId: UUID
    let title: String
    let caption: String
    let mediaKind: CosplayMediaKind
    let mediaPath: String
    let status: String
    let author: Member?

    var statusTitle: String {
        switch status {
        case "pending": return "Pending review"
        case "removed": return "Removal pending"
        default: return status.capitalized
        }
    }
}

struct Member: Decodable, Identifiable, Equatable {
    let id: UUID
    let displayName: String
    let bio: String
    private let memberAvatar: String?
    private let editorialPortrait: String?
    var avatar: String? { editorialPortrait ?? memberAvatar }
    let discoverable: Bool

    private enum CodingKeys: String, CodingKey {
        case id, displayName, bio, discoverable, editorialPortrait
        case memberAvatar = "avatar"
    }
}

struct MemberCounts: Decodable {
    let followers: Int
    let following: Int
    let friends: Int
    let likes: Int?
    let saves: Int?
}

struct ShortCounts: Decodable {
    let catalogId: String
    let likes: Int
    let comments: Int
    let saves: Int
    let shares: Int
    let editorialBaseline: Bool
    let isLimited: Bool?
}

enum PublicationSource: String {
    case work, cosplay

    var reactionTable: String { self == .work ? "work_reactions" : "cosplay_video_reactions" }
    var key: String { self == .work ? "work_id" : "post_id" }
}

struct PublicationReaction: Decodable {
    let item: UUID
    let kind: String
}

struct PublicationCounts: Decodable {
    let likes: Int
    let saves: Int
}

struct Reaction: Decodable {
    let catalogId: String
    let kind: String
}

struct Comment: Decodable {
    let id: UUID
    let authorId: UUID?
    let editorialKey: String?
    let body: String
    let author: Member?
}

struct Follow: Decodable {
    let followerId: UUID
    let targetId: UUID
}

struct SafetyEntry: Decodable {
    let targetKey: String
    let label: String
    let detail: String
    let coverUrl: URL?
    let previewPath: String?
}

struct Message: Decodable {
    let id: UUID
    let senderId: UUID
    let recipientId: UUID
    let body: String
    let createdAt: String
    let photoPath: String?
}

struct ChatFriend: Identifiable {
    let id: UUID
    let profile: Member?
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
    static let safetyChanged = Notification.Name("SeseSafetyChanged")
    private(set) var safetyRevision = 0
    // RLS owns persistent visibility. These session deltas also filter responses started before a write.
    private var hiddenVideos = Set<String>()
    private var hiddenComments = Set<String>()
    private var blockedPeers = Set<UUID>()
    private var safetyWrites = Set<String>()
    let configuration: BackendConfiguration
    let client: SupabaseClient
    let agreements: AgreementSet?
    private(set) var memberID: UUID?
    private var shortCountCache: [String: ShortCounts] = [:]
    private static let chatPhotoBucket = "chat-photos"
    private static let cosplayBucket = "cosplay-media"
    nonisolated static let maximumCosplayMediaBytes = 6_291_456

    init() throws {
        let configuration = try Resources.decode(BackendConfiguration.self, "Backend.json")
        guard configuration.url.scheme == "https", !configuration.publishableKey.isEmpty else {
            throw CommunityError.configuration
        }
        agreements = AgreementSet(configuration: configuration)
#if DEBUG && targetEnvironment(simulator) && SESE_SAFETY_ACCEPTANCE
        if let fixture = ModerationAcceptanceFixture.shared {
            self.configuration = BackendConfiguration(url: fixture.host, publishableKey: "local-acceptance",
                agreementRevision: configuration.agreementRevision, termsURL: configuration.termsURL, privacyURL: configuration.privacyURL)
            client = SupabaseClient(supabaseURL: fixture.host, supabaseKey: "local-acceptance")
            return
        }
#endif
        self.configuration = configuration
        client = SupabaseClient(supabaseURL: configuration.url, supabaseKey: configuration.publishableKey)
    }

    func signIn() async throws -> ConfiguredBootstrapContinuation {
        guard let agreements else { throw CommunityError.agreements }
#if DEBUG && targetEnvironment(simulator) && SESE_SAFETY_ACCEPTANCE
        if let fixture = ModerationAcceptanceFixture.shared {
            memberID = fixture.viewer
            return .standalone
        }
#endif
        guard configuration.url.absoluteString == SupabaseIntegrationContract.projectURLString else {
            throw CommunityError.configuration
        }
        try await EntryConnection.shared.wait(for: configuration.url)
        let credential = try DeviceCredential.loadOrCreate()
        let session: Session
        if client.auth.currentSession?.user.email == credential.email {
            do {
                session = try await client.auth.session
            } catch let error as AuthError where [.sessionExpired, .sessionNotFound, .refreshTokenNotFound, .refreshTokenAlreadyUsed].contains(error.errorCode) {
                session = try await client.auth.signIn(email: credential.email, password: credential.password)
            }
        } else {
            do {
                session = try await client.auth.signIn(email: credential.email, password: credential.password)
            } catch let error as AuthError where error.errorCode == .invalidCredentials {
                try await provisionDeviceAccount(credential, agreementRevision: agreements.revision)
                session = try await client.auth.signIn(email: credential.email, password: credential.password)
            }
        }
        guard !session.user.isAnonymous, session.user.email == credential.email else { throw CommunityError.invalidResponse }
        let configuration = try await bootstrapEntry(account: session.user.id, revision: agreements.revision)
        try Task.checkCancellation()
        if memberID != session.user.id {
            resetSafety()
            shortCountCache.removeAll()
        }
        memberID = session.user.id
        return configuration
    }

    func endExternalSession() {
        memberID = nil
        resetSafety()
        shortCountCache.removeAll()
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
        resetSafety()
        shortCountCache.removeAll()
    }

    func deleteAccount() async throws {
        try await removeAccountMedia(rpc: "begin_account_photo_cleanup", bucket: Self.chatPhotoBucket)
        do {
            try await removeAccountMedia(rpc: "begin_account_cosplay_cleanup", bucket: Self.cosplayBucket)
        } catch CommunityError.request(404) {
            // The earlier backend has no Cosplay uploads to remove.
        }
        try await write("rpc/delete_my_account", method: "POST", body: [:])
        memberID = nil
        resetSafety()
        shortCountCache.removeAll()
        try? await client.auth.signOut(scope: .local)
        DeviceCredential.remove()
    }

    private func removeAccountMedia(rpc: String, bucket: String) async throws {
        var lastBatch: [String] = []
        while true {
            let paths: [String] = try await read("rpc/\(rpc)", method: "POST", body: [:])
            if paths.isEmpty { return }
            guard paths != lastBatch else {
                throw CommunityError.invalidInput("Media cleanup could not finish. Try deleting your account again.")
            }
            _ = try await client.storage.from(bucket).remove(paths: paths)
            lastBatch = paths
        }
    }

    func cosplayPosts(owner: UUID? = nil, ids: Set<UUID>? = nil) async throws -> [CosplayPost] {
        var filters = ["order": "created_at.desc,id.desc", "limit": "60",
                       "select": "*,author:profiles!cosplay_posts_owner_id_fkey(*)"]
        if let owner {
            filters["owner_id"] = "eq.\(owner.uuidString)"
        }
        if owner == nil || owner != memberID {
            filters["status"] = "eq.approved"
        }
        let posts: [CosplayPost]
        if owner == nil, ids == nil {
            posts = try await read("cosplay_posts", query: filters)
        } else {
            filters.removeValue(forKey: "limit")
            posts = try await readMedia("cosplay_posts", ids: ids, filters: filters)
        }
        return posts.filter { !isHidden($0) }
    }

    func submitCosplay(id: UUID, title: String, caption: String, kind: CosplayMediaKind, bytes: Data) async throws {
        guard let owner = memberID, (1...Self.maximumCosplayMediaBytes).contains(bytes.count) else {
            throw CommunityError.invalidInput("Choose a photo or video within the upload limit.")
        }
        let path = Self.cosplayPath(owner: owner, id: id, kind: kind)
        let storage = client.storage.from(Self.cosplayBucket)
        do {
            try await storage.upload(path, data: bytes, options: FileOptions(cacheControl: "0", contentType: kind.mimeType, upsert: false))
        } catch {
            let uploadError = error
            guard let existing = try? await storage.download(path: path, cacheNonce: UUID().uuidString),
                  existing == bytes else { throw uploadError }
        }
        guard memberID == owner else { throw CommunityError.unavailable }
        try await write("rpc/submit_cosplay_post", method: "POST", body: [
            "post_id": id.uuidString, "post_title": title, "post_caption": caption, "kind": kind.rawValue
        ])
    }

    func cosplayMediaURL(_ post: CosplayPost) throws -> URL {
        guard !isHidden(post), post.status != "removed",
              post.mediaPath == Self.cosplayPath(owner: post.ownerId, id: post.id, kind: post.mediaKind) else {
            throw CommunityError.unavailable
        }
        return try client.storage.from(Self.cosplayBucket).getPublicURL(path: post.mediaPath)
    }

    func cosplayMedia(_ post: CosplayPost) async throws -> Data {
        let viewer = memberID
        let url = try cosplayMediaURL(post)
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url == url, http.mimeType == post.mediaKind.mimeType,
              memberID == viewer, !isHidden(post), (1...Self.maximumCosplayMediaBytes).contains(data.count) else {
            throw CommunityError.unavailable
        }
        return data
    }

    func removeCosplay(_ post: CosplayPost) async throws {
        guard let owner = memberID, owner == post.ownerId,
              post.mediaPath == Self.cosplayPath(owner: owner, id: post.id, kind: post.mediaKind) else {
            throw CommunityError.unavailable
        }
        let payload = ["post_id": post.id.uuidString]
        try await write("rpc/hide_cosplay_post", method: "POST", body: payload)
        _ = try await client.storage.from(Self.cosplayBucket).remove(paths: [post.mediaPath])
        guard memberID == owner else { throw CommunityError.unavailable }
        try await write("rpc/finish_cosplay_post_removal", method: "POST", body: payload)
    }

    private static func cosplayPath(owner: UUID, id: UUID, kind: CosplayMediaKind) -> String {
        "\(owner.uuidString.lowercased())/\(id.uuidString.lowercased()).\(kind.fileExtension)"
    }

    func catalog() async throws -> [CatalogItem] {
        let items: [CatalogItem] = try await read("catalog", query: [
            "select": "*,publisher:profiles!catalog_publisher_id_fkey(*)", "order": "position.asc", "limit": "100"
        ])
        return items.filter { !isHidden($0) }
    }

    func works(owner: UUID? = nil, ids: Set<UUID>? = nil) async throws -> [MemberWork] {
        var filters = ["order": "created_at.desc,id.desc",
                       "select": "*,author:profiles!works_owner_id_fkey(*)"]
        if let owner {
            filters["owner_id"] = "eq.\(owner.uuidString)"
        } else {
            filters["status"] = "eq.approved"
        }
        let works: [MemberWork]
        if owner == nil, ids == nil {
            filters["limit"] = "100"
            works = try await read("works", query: filters)
        } else {
            works = try await readMedia("works", ids: ids, filters: filters)
        }
        return works.filter { !isHidden($0) }
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
        guard let member = try await visibleMember(id) else { throw CommunityError.unavailable }
        return member
    }

    func visibleMember(_ id: UUID) async throws -> Member? {
        let members: [Member] = try await read("profiles", query: ["id": "eq.\(id.uuidString)"])
        return members.first
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

    func reactions() async throws -> [Reaction] {
        try await readPages("reactions", query: ["order": "catalog_id.asc,kind.asc"])
    }

    func cachedShortCount(_ id: String) -> ShortCounts? {
        shortCountCache[id]
    }

    func shortCounts(_ ids: [String]) async throws -> [ShortCounts] {
        guard !ids.isEmpty else { return [] }
        guard let account = memberID else { throw CommunityError.unavailable }
        let revision = safetyRevision
        let rows: [ShortCounts]
        do {
            let initial: [ShortCounts] = try await read("rpc/short_counts", method: "POST", body: ["items": ids])
            let visible = Set(initial.map(\.catalogId))
            let pending = pendingShortShares(for: account).filter { visible.contains($0.key) }
            if pending.isEmpty {
                rows = initial
            } else {
                for (id, events) in pending {
                    for event in events {
                        try Task.checkCancellation()
                        try await submitShortShare(id, event: event)
                        updatePendingShortShare(id, event: event, account: account, add: false)
                    }
                }
                rows = try await read("rpc/short_counts", method: "POST", body: ["items": ids])
            }
        } catch {
            if account == memberID && revision == safetyRevision && !Task.isCancelled {
                for id in ids { shortCountCache.removeValue(forKey: id) }
            }
            throw error
        }
        try Task.checkCancellation()
        guard memberID == account else { throw CommunityError.unavailable }
        guard revision == safetyRevision else { throw CancellationError() }
        for row in rows { shortCountCache[row.catalogId] = row }
        return rows
    }

    func recordShortShare(_ id: String, event: UUID) async throws {
        guard let account = memberID else { throw CommunityError.unavailable }
        do {
            try await submitShortShare(id, event: event)
        } catch CommunityError.request(404) {
            guard memberID == account else { throw CommunityError.unavailable }
            updatePendingShortShare(id, event: event, account: account, add: true)
            throw CommunityError.request(404)
        }
    }

    private func submitShortShare(_ id: String, event: UUID) async throws {
        try await write("rpc/record_short_share", method: "POST", body: ["item": id, "event": event.uuidString])
    }

    private func pendingShortShares(for account: UUID) -> [String: [UUID]] {
        let key = "SesePendingShortShares.\(account.uuidString)"
        let entries = UserDefaults.standard.dictionary(forKey: key) as? [String: [String]] ?? [:]
        return entries.mapValues { $0.compactMap(UUID.init(uuidString:)) }
    }

    private func updatePendingShortShare(_ id: String, event: UUID, account: UUID, add: Bool) {
        let key = "SesePendingShortShares.\(account.uuidString)"
        var entries = pendingShortShares(for: account)
        var events = Set(entries[id] ?? [])
        if add { events.insert(event) } else { events.remove(event) }
        entries[id] = events.isEmpty ? nil : Array(events)
        UserDefaults.standard.set(entries.mapValues { $0.map(\.uuidString).sorted() }, forKey: key)
    }

    func publicationReactions(_ source: PublicationSource, item: UUID? = nil) async throws -> [PublicationReaction] {
        var filters = ["select": "item:\(source.key),kind", "order": "\(source.key).asc,kind.asc"]
        if let item { filters[source.key] = "eq.\(item.uuidString)" }
        do {
            return try await readPages(source.reactionTable, query: filters)
        } catch CommunityError.request(404) {
            // The earlier backend cannot accept reactions on member publications.
            return []
        }
    }

    func publicationCounts(_ source: PublicationSource, item: UUID) async throws -> PublicationCounts {
        try await read("rpc/publication_counts", method: "POST", body: ["item": item.uuidString, "source": source.rawValue])
    }

    func setPublicationReaction(_ kind: String, source: PublicationSource, item: UUID, enabled: Bool) async throws {
        if enabled {
            try await write(source.reactionTable, method: "POST", body: [source.key: item.uuidString, "kind": kind],
                            prefer: "resolution=ignore-duplicates")
        } else {
            try await write(source.reactionTable, method: "DELETE", query: [source.key: "eq.\(item.uuidString)", "kind": "eq.\(kind)"])
        }
    }

    func setReaction(_ kind: String, item: String, enabled: Bool) async throws {
        let account = memberID
        if enabled {
            try await write("reactions", method: "POST", body: ["catalog_id": item, "kind": kind], prefer: "resolution=ignore-duplicates")
        } else {
            try await write("reactions", method: "DELETE", query: ["catalog_id": "eq.\(item)", "kind": "eq.\(kind)"])
        }
        guard memberID == account else { throw CommunityError.unavailable }
    }

    func comments(_ item: String) async throws -> [Comment] {
        try await readPages("comments", query: ["catalog_id": "eq.\(item)", "order": "created_at.desc,id.desc",
                                          "select": "id,author_id,editorial_key,body,author:profiles!comments_author_id_fkey(*)"])
    }

    func addComment(_ item: String, text: String) async throws {
        try await write("comments", method: "POST", body: ["catalog_id": item, "body": text])
    }

    func removeComment(_ id: UUID) async throws {
        try await write("comments", method: "DELETE", query: ["id": "eq.\(id.uuidString)"])
    }

    func follows() async throws -> [Follow] {
        let pageSize = 200
        var links: [Follow] = []
        while true {
            let page: [Follow] = try await read("follows", query: [
                "order": "follower_id.asc,target_id.asc",
                "limit": String(pageSize), "offset": String(links.count)
            ])
            links.append(contentsOf: page)
            if page.count < pageSize { break }
        }
        return links
    }
    private func resetSafety() {
        hiddenVideos.removeAll()
        hiddenComments.removeAll()
        blockedPeers.removeAll()
        safetyRevision += 1
    }

    func isBlocked(_ peer: UUID) -> Bool { blockedPeers.contains(peer) }
    func isHidden(_ comment: Comment) -> Bool {
        hiddenComments.contains("comment:" + comment.id.uuidString.lowercased()) || comment.authorId.map(isBlocked) == true
    }
    func isHidden(_ item: CatalogItem) -> Bool {
        item.publisherId.map(isBlocked) == true || hiddenVideos.contains("catalog:\(item.id)")
    }
    func isHidden(_ work: MemberWork) -> Bool {
        isBlocked(work.ownerId) || hiddenVideos.contains("work:\(work.id.uuidString.lowercased())")
    }
    func isHidden(_ post: CosplayPost) -> Bool {
        isBlocked(post.ownerId) || hiddenVideos.contains("cosplay:\(post.id.uuidString.lowercased())")
    }

    private func publishSafetyChange() {
        safetyRevision += 1
        shortCountCache.removeAll()
        NotificationCenter.default.post(name: Self.safetyChanged, object: self)
    }

    private func safetyWriteKey(_ key: String, account: UUID) throws -> String {
        let scoped = "\(account.uuidString)/\(key)"
        guard safetyWrites.insert(scoped).inserted else {
            throw CommunityError.invalidInput("An update is already in progress.")
        }
        return scoped
    }

    func reportedPreviewURL(_ entry: SafetyEntry) -> URL? {
        guard let path = entry.previewPath else { return nil }
        let parts = path.components(separatedBy: "/")
        guard parts.count == 2, let owner = UUID(uuidString: parts[0]),
              entry.targetKey.hasPrefix("cosplay:"), let id = UUID(uuidString: String(entry.targetKey.dropFirst("cosplay:".count))),
              path == Self.cosplayPath(owner: owner, id: id, kind: .video) else { return nil }
        return try? client.storage.from(Self.cosplayBucket).getPublicURL(path: path)
    }

    func safetyHistory(_ kind: String, includeCovers: Bool = false) async throws -> [SafetyEntry] {
        guard let account = memberID, ["report", "block", "comment"].contains(kind) else { throw CommunityError.unavailable }
        var entries: [SafetyEntry] = []
        while true {
            try Task.checkCancellation()
            let page: [SafetyEntry]
            if kind == "comment" {
                page = try await read("rpc/reported_comment_history", method: "POST",
                                      body: ["page_offset": entries.count], account: account)
            } else if includeCovers && kind == "report" {
                page = try await read("rpc/reported_video_history", method: "POST",
                                      body: ["page_offset": entries.count], account: account)
            } else {
                page = try await read("rpc/safety_history", method: "POST",
                                      body: ["entry_kind": kind, "page_offset": entries.count], account: account)
            }
            guard account == memberID else { throw CommunityError.unavailable }
            entries += page
            if page.count < 100 { return entries }
        }
    }

    func reconcileSafety() async {
        guard let account = memberID else { return }
        let revision = safetyRevision
        do {
            async let reports = self.safetyHistory("report")
            async let blocks = self.safetyHistory("block")
            async let comments = self.safetyHistory("comment")
            let (reportRows, blockRows, commentRows) = try await (reports, blocks, comments)
            guard account == memberID, revision == safetyRevision else { return }
            let videos = Set(reportRows.map(\.targetKey))
            let peers = Set(blockRows.compactMap { UUID(uuidString: $0.targetKey) })
            let hidden = Set(commentRows.map(\.targetKey))
            guard videos != hiddenVideos || peers != blockedPeers || hidden != hiddenComments else { return }
            hiddenComments = hidden
            hiddenVideos = videos
            blockedPeers = peers
            publishSafetyChange()
        } catch {
            // A failed reconciliation must never make previously hidden content visible.
        }
    }

    func blockMember(_ peer: UUID, source: String? = nil) async throws {
        guard let account = memberID, peer != account else { throw CommunityError.unavailable }
        let key = try safetyWriteKey("block:\(peer)", account: account)
        defer { safetyWrites.remove(key) }
        let body: [String: Any] = ["peer": peer.uuidString, "source": source.map { $0 as Any } ?? NSNull()]
        try await write("rpc/block_from_source", method: "POST", body: body, account: account)
        guard account == memberID else { throw CommunityError.unavailable }
        blockedPeers.insert(peer)
        publishSafetyChange()
    }

    func setRelationship(_ table: String, peer: UUID, enabled: Bool) async throws {
        guard let account = memberID else { throw CommunityError.unavailable }
        if table == "blocks" {
            if enabled { try await blockMember(peer); return }
            let key = try safetyWriteKey("block:\(peer)", account: account)
            defer { safetyWrites.remove(key) }
            try await write(table, method: "DELETE", query: ["target_id": "eq.\(peer.uuidString)"], account: account)
            guard account == memberID else { throw CommunityError.unavailable }
            blockedPeers.remove(peer)
            publishSafetyChange()
        } else if enabled {
            try await write(table, method: "POST", body: ["target_id": peer.uuidString], prefer: "resolution=ignore-duplicates", account: account)
        } else {
            try await write(table, method: "DELETE", query: ["target_id": "eq.\(peer.uuidString)"], account: account)
        }
    }

    func report(_ target: [String: String], reason: String, video: Bool, requestID: UUID) async throws {
        guard let account = memberID else { throw CommunityError.unavailable }
        if let id = target["comment_id"] {
            let targetKey = "comment:" + id.lowercased()
            let key = try safetyWriteKey(targetKey, account: account)
            defer { safetyWrites.remove(key) }
            try await write("rpc/submit_comment_report", method: "POST", body: ["item": id, "report_reason": reason], account: account)
            guard account == memberID else { throw CommunityError.unavailable }
            hiddenComments.insert(targetKey)
            publishSafetyChange()
        } else if video, let (field, rawID) = target.first, target.count == 1,
           let kind = ["work_id": "work", "catalog_id": "catalog", "cosplay_post_id": "cosplay"][field] {
            let id = kind == "catalog" ? rawID : rawID.lowercased()
            let targetKey = "\(kind):\(id)"
            let key = try safetyWriteKey(targetKey, account: account)
            defer { safetyWrites.remove(key) }
            try await write("rpc/submit_video_report", method: "POST",
                            body: ["target_kind": kind, "item_key": id, "report_reason": reason], account: account)
            guard account == memberID else { throw CommunityError.unavailable }
            hiddenVideos.insert(targetKey)
            publishSafetyChange()
        } else {
            let kinds = ["reported_id": "member", "message_id": "message", "catalog_id": "catalog", "cosplay_post_id": "cosplay"]
            guard let (field, item) = target.first(where: { kinds[$0.key] != nil }), let kind = kinds[field] else {
                throw CommunityError.unavailable
            }
            let body: [String: Any] = ["target_type": kind, "item": item, "report_reason": reason, "request_id": requestID.uuidString,
                                       "source": target["source_key"].map { $0 as Any } ?? NSNull()]
            try await write("rpc/submit_item_report", method: "POST", body: body, account: account)
        }
    }

    func withdrawReport(_ entry: SafetyEntry) async throws {
        guard let account = memberID else { throw CommunityError.unavailable }
        let key = try safetyWriteKey(entry.targetKey, account: account)
        defer { safetyWrites.remove(key) }
        if entry.targetKey.hasPrefix("comment:") {
            let id = String(entry.targetKey.dropFirst("comment:".count))
            try await write("rpc/withdraw_comment_report", method: "POST", body: ["item": id], account: account)
            guard account == memberID else { throw CommunityError.unavailable }
            hiddenComments.remove(entry.targetKey)
            publishSafetyChange()
            return
        }
        try await write("rpc/withdraw_video_report", method: "POST", body: ["entry_key": entry.targetKey], account: account)
        guard account == memberID else { throw CommunityError.unavailable }
        hiddenVideos.remove(entry.targetKey)
        publishSafetyChange()
    }

    func chatFriends() async throws -> [ChatFriend] {
        guard let memberID else { throw CommunityError.unavailable }
        let links = try await follows()
        let following = Set(links.filter { $0.followerId == memberID }.map(\.targetId))
        let followers = Set(links.filter { $0.targetId == memberID }.map(\.followerId))
        let ids = following.intersection(followers).sorted { $0.uuidString < $1.uuidString }
        var profiles: [UUID: Member] = [:]
        for start in stride(from: 0, to: ids.count, by: 50) {
            let batch = ids[start..<min(start + 50, ids.count)].map(\.uuidString).joined(separator: ",")
            let members: [Member] = try await read("profiles", query: ["id": "in.(\(batch))"])
            for member in members { profiles[member.id] = member }
        }
        return ids.map { ChatFriend(id: $0, profile: profiles[$0]) }
    }

    func inbox() async throws -> [InboxItem] { try await read("rpc/inbox", method: "POST", body: [:]) }

    func thread(_ peer: UUID, before: Message? = nil) async throws -> [Message] {
        let other = peer.uuidString
        var query = ["or": "(sender_id.eq.\(other),recipient_id.eq.\(other))",
                     "order": "created_at.desc,id.desc", "limit": "50"]
        if let before {
            query["and"] = "(or(created_at.lt.\(before.createdAt),and(created_at.eq.\(before.createdAt),id.lt.\(before.id.uuidString))))"
        }
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
        guard let owner = memberID else { return }
        let statuses = channel.statusChange
        let subscription = Task {
            for await status in statuses {
                guard !Task.isCancelled, self.memberID == owner else { return }
                if status == .subscribed { onChange() }
            }
        }
        defer { subscription.cancel() }
        do {
            try await channel.subscribeWithError()
            for await _ in changes {
                guard !Task.isCancelled, self.memberID == owner else { break }
                onChange()
            }
        } catch {
            if !Task.isCancelled, memberID == owner { onChange() }
        }
        subscription.cancel()
        await client.removeChannel(channel)
    }

    private func readPages<T: Decodable>(_ path: String, query: [String: String]) async throws -> [T] {
        let limit = 100
        var rows: [T] = []
        var query = query
        query["limit"] = String(limit)
        while true {
            try Task.checkCancellation()
            query["offset"] = String(rows.count)
            let page: [T] = try await read(path, query: query)
            rows.append(contentsOf: page)
            if page.count < limit { return rows }
        }
    }

    private func readMedia<T: Decodable>(_ path: String, ids: Set<UUID>?, filters: [String: String]) async throws -> [T] {
        guard let ids else { return try await readPages(path, query: filters) }
        let keys = ids.map(\.uuidString).sorted()
        var rows: [T] = []
        for start in stride(from: 0, to: keys.count, by: 40) {
            try Task.checkCancellation()
            var query = filters
            query["id"] = "in.(\(keys[start..<min(start + 40, keys.count)].joined(separator: ",")))"
            let page: [T] = try await read(path, query: query)
            rows.append(contentsOf: page)
        }
        return rows
    }

    private func read<T: Decodable>(_ path: String, method: String = "GET", query: [String: String] = [:],
                                    body: [String: Any]? = nil, account: UUID? = nil) async throws -> T {
        let data = try await request(path, method: method, query: query, body: body, prefer: nil, account: account)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    private func write(_ path: String, method: String, query: [String: String] = [:],
                       body: [String: Any]? = nil, prefer: String? = nil, account: UUID? = nil) async throws {
        _ = try await request(path, method: method, query: query, body: body, prefer: prefer, account: account)
    }

    private func request(_ path: String, method: String, query: [String: String], body: [String: Any]?,
                         prefer: String?, account: UUID? = nil) async throws -> Data {
        let (data, _) = try await response(path, method: method, query: query, body: body, prefer: prefer, account: account)
        return data
    }

    private func response(_ path: String, method: String, query: [String: String], body: [String: Any]?,
                          prefer: String?, account: UUID? = nil) async throws -> (Data, HTTPURLResponse) {
#if DEBUG && targetEnvironment(simulator) && SESE_SAFETY_ACCEPTANCE
        if let fixture = ModerationAcceptanceFixture.shared {
            guard memberID == fixture.viewer, account == nil || account == fixture.viewer else { throw CommunityError.unavailable }
            return try fixture.respond(path, method: method, query: query, body: body)
        }
#endif
        let session = try await client.auth.session
        if let account, account != memberID || account != session.user.id { throw CommunityError.unavailable }
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
        return (data, response)
    }
}
