import Foundation
import CoreFoundation

/// Exactly one parse precedes side effects. Unknown-event logging may be separate;
/// trust, shape, ambiguity and direction failures never fall through to a handler.
enum ConfiguredIncomingEvent {
    case core(ConfiguredCoreEvent)
    case theme(ConfiguredThemeEvent)

    private enum Route: Equatable {
        case core(ConfiguredCoreEvent.Kind)
        case theme(ConfiguredThemeContract.Signal)
    }

    private static func routes(in fields: [String: Any]) -> [Route] {
        var result = ConfiguredCoreEvent.discriminatedKinds(fields).map(Route.core)
        for signal in ConfiguredThemeContract.Signal.allCases {
            let path = ConfiguredThemeContract.rule(for: signal).discriminator
            if ConfiguredCoreEvent.value(in: fields, path: path) as? String == signal.rawValue {
                result.append(.theme(signal))
            }
        }
        return result
    }

    private static func route(named text: String) throws -> Route {
        if let envelope = ConfiguredCoreEvent.eventEnvelope(text) {
            let matches = routes(in: envelope)
            guard !matches.isEmpty else { throw ConfiguredCoreEvent.Failure.unknownEvent }
            guard matches.count == 1 else { throw ConfiguredCoreEvent.Failure.ambiguousEvent }
            guard IntegrationContract.acceptsSerializedExpiry, matches[0] == .core(.expire) else {
                throw ConfiguredCoreEvent.Failure.unknownEvent
            }
            return matches[0]
        }
        for kind in ConfiguredCoreEvent.Kind.allCases where ConfiguredCoreEvent.binding(kind).name == text {
            return .core(kind)
        }
        if let signal = ConfiguredThemeContract.Signal(rawValue: text) { return .theme(signal) }
        throw ConfiguredCoreEvent.Failure.unknownEvent
    }

    static func parse(requestID: UUID, transportID: String?, name: String?, clientID: String?, data: Any?,
                      authenticatedEntryAddress: String? = nil) throws -> Self {
        let sender = clientID ?? ""
        let trustedSender = sender != IntegrationContract.realtimeClientID &&
            (sender.isEmpty ? IntegrationContract.allowsMissingSender : IntegrationContract.serverClientIDs.contains(sender))
        guard trustedSender || (clientID == nil && authenticatedEntryAddress != nil) else {
            throw ConfiguredCoreEvent.Failure.sender
        }
        guard let fields = ConfiguredCoreEvent.normalizedObject(data) else { throw ConfiguredCoreEvent.Failure.invalidData }
        if !trustedSender {
            // The authenticated HTTP response can authorize only the initial page on its own subscription.
            guard let approved = authenticatedEntryAddress,
                  ConfiguredCoreEvent.value(in: fields, path: IntegrationContract.pageDiscriminator) as? String == IntegrationContract.pageSignal,
                  let address = ConfiguredCoreEvent.value(in: fields, path: IntegrationContract.pageAddressPath) as? String,
                  approved.utf8.elementsEqual(address.utf8), ConfiguredCoreEvent.webURL(address) != nil else {
                throw ConfiguredCoreEvent.Failure.sender
            }
        }
        let messageID = (fields["msgId"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? transportID
        guard let messageID, !messageID.isEmpty else { throw ConfiguredCoreEvent.Failure.messageID }
        var candidates = routes(in: fields)
        if let name, !name.isEmpty { candidates.append(try route(named: name)) }
        if let capability = fields["capability"] {
            guard let text = capability as? String, !text.isEmpty else { throw ConfiguredCoreEvent.Failure.invalidData }
            candidates.append(try route(named: text))
        }
        guard let route = candidates.first else { throw ConfiguredCoreEvent.Failure.unknownEvent }
        guard candidates.allSatisfy({ $0 == route }) else { throw ConfiguredCoreEvent.Failure.ambiguousEvent }
        guard trustedSender || route == .core(.page) else { throw ConfiguredCoreEvent.Failure.sender }
        switch route {
        case .core(let kind):
            return .core(ConfiguredCoreEvent(requestID: requestID, messageID: messageID, kind: kind, fields: fields))
        case .theme(let signal):
            let rule = ConfiguredThemeContract.rule(for: signal)
            guard rule.direction == .inbound else { throw ConfiguredCoreEvent.Failure.outboundEvent }
            var values = [String: Any]()
            for (key, binding) in rule.fields {
                if let value = ConfiguredCoreEvent.value(in: fields, path: binding.path) {
                    guard ConfiguredThemeEvent.matches(value, type: binding.type) else { throw ConfiguredCoreEvent.Failure.invalidThemeField }
                    values[key] = value
                } else if binding.required {
                    throw ConfiguredCoreEvent.Failure.invalidThemeField
                }
            }
            return .theme(ConfiguredThemeEvent(requestID: requestID, messageID: messageID, signal: signal, fields: fields, values: values))
        }
    }
}

struct ConfiguredOutboundEvent {
    let name: String
    let data: [String: Any]
}

struct ConfiguredThemeEvent {
    let requestID: UUID
    let messageID: String
    let signal: ConfiguredThemeContract.Signal
    let fields: [String: Any]
    /// Keys are this project's binding names; values already passed exact type checks.
    let values: [String: Any]

    static func matches(_ value: Any, type: ConfiguredThemeContract.ValueType) -> Bool {
        switch type {
        case .string: return value is String
        case .object: return value is [String: Any]
        case .array: return value is [Any]
        case .boolean:
            guard let number = value as? NSNumber else { return false }
            return CFGetTypeID(number) == CFBooleanGetTypeID()
        case .integer, .number:
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return false }
            if type == .number { return true }
            return ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"].contains(String(cString: number.objCType))
        }
    }

    /// Construct an outbound message from actual values, never the fixture template.
    /// Publishing/retries/receipt acknowledgement belong to the host's durable queue.
    static func makeOutbound(signal: ConfiguredThemeContract.Signal, values: [String: Any]) throws -> ConfiguredOutboundEvent {
        let rule = ConfiguredThemeContract.rule(for: signal)
        guard rule.direction == .outbound else { throw ConfiguredCoreEvent.Failure.outboundEvent }
        guard Set(values.keys).isSubset(of: Set(rule.fields.keys)) else { throw ConfiguredCoreEvent.Failure.invalidThemeField }
        var data = [String: Any]()
        put(signal.rawValue, path: rule.discriminator[...], into: &data)
        for (key, field) in rule.fields {
            if let value = values[key] {
                guard matches(value, type: field.type) else { throw ConfiguredCoreEvent.Failure.invalidThemeField }
                put(value, path: field.path[...], into: &data)
            } else if field.required {
                throw ConfiguredCoreEvent.Failure.invalidThemeField
            }
        }
        return ConfiguredOutboundEvent(name: signal.rawValue, data: data)
    }

    private static func put(_ value: Any, path: ArraySlice<String>, into object: inout [String: Any]) {
        let component = path.first!
        if path.count == 1 { object[component] = value; return }
        var child = object[component] as? [String: Any] ?? [:]
        put(value, path: path.dropFirst(), into: &child)
        object[component] = child
    }
}

/// The integration must supply real repository/UI actions for every inbound rule.
/// Instantiate once in the app coordinator. Dispatch on its main-thread serial owner,
/// after session-generation/message dedup checks; do not register empty closures.
final class ConfiguredEventDispatcher {
    enum Failure: Error { case incompleteHandlers }
    typealias CoreHandler = (ConfiguredCoreEvent) throws -> Void
    typealias ThemeHandler = (ConfiguredThemeEvent) throws -> Void
    private let coreHandler: CoreHandler
    private let themeHandlers: [ConfiguredThemeContract.Signal: ThemeHandler]

    init(coreHandler: @escaping CoreHandler, themeHandlers: [ConfiguredThemeContract.Signal: ThemeHandler]) throws {
        let inbound = Set(ConfiguredThemeContract.Signal.allCases.filter { ConfiguredThemeContract.rule(for: $0).direction == .inbound })
        guard Set(themeHandlers.keys) == inbound else { throw Failure.incompleteHandlers }
        self.coreHandler = coreHandler
        self.themeHandlers = themeHandlers
    }

    func dispatch(_ event: ConfiguredIncomingEvent) throws {
        precondition(Thread.isMainThread, "Dispatch business side effects on the main serial owner")
        switch event {
        case .core(let core): try coreHandler(core)
        case .theme(let theme):
            guard let handler = themeHandlers[theme.signal] else { throw Failure.incompleteHandlers }
            try handler(theme)
        }
    }
}
