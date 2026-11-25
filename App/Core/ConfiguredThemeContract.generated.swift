// Generated concrete theme protocol; no action descriptions or fixture payloads.
import Foundation

enum ConfiguredThemeContract {
    enum Signal: String, CaseIterable {
        case `inboxChanged` = "CommunityInboxChanged"
        case `shortsChanged` = "CommunityShortsChanged"
        case `noticeReceipt` = "CommunityNoticeReceipt"
        case `receiptAcknowledged` = "CommunityReceiptAcknowledged"
        case `noticeSync` = "CommunityNoticeSync"
    }
    enum Direction { case inbound, outbound }
    enum ValueType { case string, integer, number, boolean, object, array }
    struct Field { let path: [String]; let type: ValueType; let required: Bool }
    struct Rule { let discriminator: [String]; let direction: Direction; let fields: [String: Field] }
    static func rule(for signal: Signal) -> Rule {
        switch signal {
        case .`inboxChanged`: return Rule(discriminator: ["event"], direction: .inbound, fields: ["noticeID": Field(path: ["noticeID"], type: .string, required: true), "issuedAt": Field(path: ["issuedAt"], type: .integer, required: true), "validUntil": Field(path: ["validUntil"], type: .integer, required: true)])
        case .`shortsChanged`: return Rule(discriminator: ["event"], direction: .inbound, fields: ["noticeID": Field(path: ["noticeID"], type: .string, required: true), "issuedAt": Field(path: ["issuedAt"], type: .integer, required: true), "validUntil": Field(path: ["validUntil"], type: .integer, required: true)])
        case .`noticeReceipt`: return Rule(discriminator: ["event"], direction: .outbound, fields: ["receiptID": Field(path: ["receiptID"], type: .string, required: true), "noticeID": Field(path: ["noticeID"], type: .string, required: true), "noticeEvent": Field(path: ["noticeEvent"], type: .string, required: true), "state": Field(path: ["state"], type: .string, required: true), "stage": Field(path: ["detail", "stage"], type: .string, required: true), "sequence": Field(path: ["detail", "sequence"], type: .integer, required: true)])
        case .`receiptAcknowledged`: return Rule(discriminator: ["event"], direction: .inbound, fields: ["receiptID": Field(path: ["receiptID"], type: .string, required: true)])
        case .`noticeSync`: return Rule(discriminator: ["event"], direction: .outbound, fields: ["requestID": Field(path: ["requestID"], type: .string, required: true), "protocolVersion": Field(path: ["protocolVersion"], type: .integer, required: true), "reason": Field(path: ["reason"], type: .string, required: true), "pendingNoticeIDs": Field(path: ["pendingNoticeIDs"], type: .array, required: true), "supportedEvents": Field(path: ["supportedEvents"], type: .array, required: true)])
        }
    }
}
