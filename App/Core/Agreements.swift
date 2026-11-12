import CryptoKit
import Foundation

enum AgreementKind: String {
    case terms
    case privacy

    var title: String {
        switch self {
        case .terms: return "Terms of Service"
        case .privacy: return "Privacy Policy"
        }
    }

    var filename: String {
        switch self {
        case .terms: return "Terms.pdf"
        case .privacy: return "Privacy.pdf"
        }
    }

    func bundledData() -> Data? {
        guard let data = try? Data(contentsOf: Resources.url(filename)),
              data.count <= 1_048_576, data.starts(with: Data("%PDF-".utf8)) else { return nil }
        return data
    }
}

struct AgreementDocument {
    let kind: AgreementKind
    let url: URL
    let data: Data

    var revisionComponent: String {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "\(kind.rawValue)\n\(url.absoluteString)\n\(digest)\n"
    }

    func publishedData() async -> Data? {
        let request = URLRequest(url: url, timeoutInterval: 10)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url == url, http.mimeType == "application/pdf", data == self.data else { return nil }
        return data
    }
}

struct AgreementSet {
    let terms: AgreementDocument
    let privacy: AgreementDocument
    let revision: String

    init?(configuration: BackendConfiguration) {
        guard let terms = Self.document(.terms, at: configuration.termsURL, host: configuration.url.host),
              let privacy = Self.document(.privacy, at: configuration.privacyURL, host: configuration.url.host),
              terms.url != privacy.url, terms.url.deletingLastPathComponent() == privacy.url.deletingLastPathComponent() else { return nil }
        let fingerprint = "agreements-v1\n" + terms.revisionComponent + privacy.revisionComponent
        let digest = SHA256.hash(data: Data(fingerprint.utf8)).map { String(format: "%02x", $0) }.joined()
        let revision = "sha256:" + digest
        guard revision == configuration.agreementRevision else { return nil }
        self.terms = terms
        self.privacy = privacy
        self.revision = revision
    }

    func document(_ kind: AgreementKind) -> AgreementDocument {
        kind == .terms ? terms : privacy
    }

    private static func document(_ kind: AgreementKind, at address: String, host: String?) -> AgreementDocument? {
        guard let parts = URLComponents(string: address),
              parts.scheme == "https", let host, parts.host == host, parts.user == nil, parts.password == nil,
              parts.port == nil, parts.query == nil, parts.fragment == nil, let url = parts.url,
              url.absoluteString == address else { return nil }
        let path = parts.percentEncodedPath.split(separator: "/", omittingEmptySubsequences: false)
        guard path.count == 8, Array(path.prefix(6)) == ["", "storage", "v1", "object", "public", "agreements"],
              path[6].range(of: "^[A-Za-z0-9][A-Za-z0-9_-]*$", options: .regularExpression) != nil,
              path[7].range(of: "^[A-Za-z0-9][A-Za-z0-9_-]*[.]pdf$", options: .regularExpression) != nil,
              let data = kind.bundledData() else { return nil }
        return AgreementDocument(kind: kind, url: url, data: data)
    }
}
