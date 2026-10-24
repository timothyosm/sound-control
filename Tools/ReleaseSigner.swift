import Foundation
import CryptoKit
import Security

@main struct ReleaseSigner {
    static func key(create: Bool) throws -> Curve25519.Signing.PrivateKey {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.timothyosmond.SoundControl.release-signing",
            kSecAttrAccount as String: "ed25519-v1"]
        var read = query; read[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return try .init(rawRepresentation: data) }
        guard status == errSecItemNotFound, create else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        let key = Curve25519.Signing.PrivateKey()
        var write = query
        write[kSecValueData as String] = key.rawRepresentation
        write[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let added = SecItemAdd(write as CFDictionary, nil)
        guard added == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(added)) }
        return key
    }
    static func main() throws {
        let args = CommandLine.arguments
        if args.count == 2, args[1] == "public-key" {
            print(try key(create: true).publicKey.rawRepresentation.base64EncodedString()); return
        }
        guard args.count == 6, let build = Int(args[3]) else {
            fputs("Usage: ReleaseSigner public-key | archive.zip version build minimum-macOS output.json\n", stderr); exit(2)
        }
        let archive = try Data(contentsOf: URL(fileURLWithPath: args[1]))
        let manifest = UpdateManifest(version: args[2], build: build, minimumSystemVersion: args[4],
            url: "https://github.com/\(UpdateManifest.repository)/releases/download/v\(args[2])/SoundControl.zip",
            sha256: SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined(), size: archive.count)
        let key = try key(create: false)
        let payload = try JSONEncoder().encode(manifest)
        let envelope = ["payload": payload.base64EncodedString(), "signature": try key.signature(for: payload).base64EncodedString()]
        let data = try JSONEncoder().encode(envelope)
        _ = try UpdateManifest.verified(data, publicKey: key.publicKey.rawRepresentation.base64EncodedString())
        try data.write(to: URL(fileURLWithPath: args[5]), options: .atomic)
    }
}
