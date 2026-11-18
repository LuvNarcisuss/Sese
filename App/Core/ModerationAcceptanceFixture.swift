#if DEBUG && targetEnvironment(simulator) && SESE_SAFETY_ACCEPTANCE
import Foundation

/// An in-memory REST adapter for the explicitly enabled simulator acceptance build.
@MainActor
final class ModerationAcceptanceFixture {
    static let shared: ModerationAcceptanceFixture? = ProcessInfo.processInfo.arguments.contains("-ModerationAcceptance")
        ? ModerationAcceptanceFixture() : nil
    let viewer = UUID(uuidString: "15000000-0000-4000-8000-000000000001")!
    let author = "15000000-0000-4000-8000-000000000002"
    let comment = "15000000-0000-4000-8000-000000000003"
    let host = URL(string: "https://moderation.invalid")!
    let clips = [("paper", "Paper costume"), ("plaza", "Plaza dance"), ("mask", "Midnight mask")]
    private var reported = false
    private var blocked = false

    func respond(_ path: String, method: String, query: [String: String], body: [String: Any]?) throws -> (Data, HTTPURLResponse) {
        let payload: Any
        switch (method, path) {
        case ("GET", "catalog"):
            payload = clips.filter { clip in
                (clip.0 != "paper" || !reported) && (clip.0 == "plaza" || !blocked)
            }.map { clip -> [String: Any] in
                ["id": clip.0, "kind": "Film Clip", "title": clip.1,
                 "description": "A costume performance.", "credit": "City festivals",
                 "source_url": host.absoluteString, "media_url": host.absoluteString + "/storage/v1/object/public/editorial/shorts/" + clip.0 + ".mp4",
                 "publisher_id": clip.0 == "plaza" ? NSNull() as Any : author]
            }
        case ("GET", "comments"):
            payload = query["catalog_id"] == "eq.plaza" && !blocked
                ? [["id": comment, "author_id": author, "body": "Midnight costume rehearsal."]] : []
        case ("GET", "profiles"):
            payload = [["id": viewer.uuidString, "display_name": "Festival visitor", "bio": "", "discoverable": false] as [String: Any]]
        case ("POST", "rpc/member_counts"):
            payload = ["followers": 0, "following": 0, "friends": 0]
        case ("GET", "reactions"), ("GET", "follows"), ("GET", "cosplay_posts"), ("GET", "works"),
             ("GET", "work_reactions"), ("GET", "cosplay_video_reactions"):
            payload = []
        case ("POST", "rpc/short_counts"):
            payload = (body?["items"] as? [String] ?? []).map { id -> [String: Any] in
                ["catalog_id": id, "likes": 0, "saves": 0, "shares": 0, "comments": id == "plaza" && !blocked ? 1 : 0,
                 "editorial_baseline": false]
            }
        case ("POST", "rpc/submit_video_report"):
            guard body?["target_kind"] as? String == "catalog", body?["item_key"] as? String == "paper",
                  body?["report_reason"] as? String == "Harassment" else { throw CommunityError.invalidResponse }
            reported = true
            payload = NSNull()
        case ("POST", "rpc/block_member"):
            guard (body?["peer"] as? String)?.lowercased() == author,
                  (body?["comment"] as? String)?.lowercased() == comment else { throw CommunityError.invalidResponse }
            blocked = true
            payload = NSNull()
        case ("POST", "rpc/safety_history"), ("POST", "rpc/reported_video_history"):
            let entries: [[String: String]]
            if path == "rpc/reported_video_history" || body?["entry_kind"] as? String == "report" {
                entries = reported ? [["target_key": "catalog:paper", "label": "Paper costume", "detail": "Harassment · catalog:paper"]] : []
            } else {
                entries = blocked ? [["target_key": author, "label": "City Resident", "detail": "Member " + author]] : []
            }
            payload = body?["page_offset"] as? Int == 0 ? entries : []
        case ("POST", "rpc/withdraw_video_report"):
            guard body?["entry_key"] as? String == "catalog:paper" else { throw CommunityError.invalidResponse }
            reported = false
            payload = NSNull()
        case ("DELETE", "blocks"):
            guard query["target_id"]?.lowercased() == "eq." + author else { throw CommunityError.invalidResponse }
            blocked = false
            payload = NSNull()
        default:
            throw CommunityError.unavailable
        }
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed])
        return (data, HTTPURLResponse(url: host, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}
#endif
