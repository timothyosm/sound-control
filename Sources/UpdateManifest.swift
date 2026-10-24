import Foundation
import CryptoKit

struct UpdateManifest: Codable, Equatable {
    let version: String
    let build: Int
    let minimumSystemVersion: String
    let url: String
    let sha256: String
    let size: Int

    static let repository = "timothyosm/sound-control"
    static let feed = URL(string: "https://github.com/\(repository)/releases/latest/download/update.json")!
    static let maximumArchiveSize = 100_000_000

    static func verified(_ envelope: Data, publicKey: String) throws -> UpdateManifest {
        struct Envelope: Decodable { let payload: String; let signature: String }
        guard envelope.count <= 65_536,
              let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let signed = try? JSONDecoder().decode(Envelope.self, from: envelope),
              let payload = Data(base64Encoded: signed.payload),
              let signature = Data(base64Encoded: signed.signature),
              key.isValidSignature(signature, for: payload),
              let manifest = try? JSONDecoder().decode(Self.self, from: payload),
              manifest.build > 0, manifest.size > 0, manifest.size <= maximumArchiveSize,
              manifest.sha256.count == 64, manifest.sha256.allSatisfy({ "0123456789abcdef".contains($0) }),
              manifest.version.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil,
              manifest.minimumSystemVersion.range(of: #"^[0-9]+\.[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
              manifest.url == "https://github.com/\(repository)/releases/download/v\(manifest.version)/SoundControl.zip"
        else { throw UpdateFailure.invalidRelease }
        return manifest
    }

    func supports(system: String) -> Bool {
        system.compare(minimumSystemVersion, options: .numeric) != .orderedAscending
    }
    func verifyArchive(_ data: Data) throws {
        guard data.count == size,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sha256
        else { throw UpdateFailure.invalidRelease }
    }
}

enum UpdateFailure: LocalizedError {
    case invalidRelease, download, installation, permissions, timeout
    var errorDescription: String? {
        switch self {
        case .invalidRelease: return "The update could not be verified. Your installed app has not changed. Try checking again later."
        case .download: return "The update could not be downloaded. Check your internet connection and try again."
        case .installation: return "The update could not be installed. Reopen Sound Control and try again."
        case .permissions: return "Sound Control cannot replace this copy of the app. Move it to an Applications folder you can write to, then try again."
        case .timeout: return "Sound Control did not close in time. Reopen the app and try again."
        }
    }
}
