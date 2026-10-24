import Foundation
import CryptoKit

@main struct UpdateTests {
    static func main() throws {
        var count = 0
        func check(_ condition: Bool, _ message: String) { precondition(condition, message); count += 1 }
        func rejects(_ body: () throws -> Void) { do { try body(); preconditionFailure("Invalid update accepted") } catch { count += 1 } }
        let key = Curve25519.Signing.PrivateKey()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let archive = Data("test archive".utf8)
        let digest = SHA256.hash(data: archive).map { String(format: "%02x", $0) }.joined()
        var fields: [String: Any] = ["version":"0.6.0", "build":8, "minimumSystemVersion":"13.0", "url":"https://github.com/timothyosm/sound-control/releases/download/v0.6.0/SoundControl.zip", "sha256":digest, "size":archive.count]
        func sign(_ fields: [String: Any]) throws -> Data {
            let payload = try JSONSerialization.data(withJSONObject: fields)
            return try JSONEncoder().encode(["payload": payload.base64EncodedString(), "signature": key.signature(for: payload).base64EncodedString()])
        }
        let signed = try sign(fields)
        let manifest = try UpdateManifest.verified(signed, publicKey: publicKey)
        check(manifest.build == 8, "Authenticated build")
        check(manifest.supports(system: "13.0") && manifest.supports(system: "26.0") && !manifest.supports(system: "12.9"), "Numeric OS comparison")
        try manifest.verifyArchive(archive); count += 1
        rejects { try manifest.verifyArchive(Data("test archivE".utf8)) }
        rejects { try manifest.verifyArchive(archive + Data([0])) }
        rejects { _ = try UpdateManifest.verified(signed, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()) }
        rejects { _ = try UpdateManifest.verified(Data(repeating: 0, count: 65_537), publicKey: publicKey) }
        rejects { _ = try UpdateManifest.verified(signed, publicKey: "invalid") }
        for length in [0,1,signed.count / 2,signed.count-1] {
            rejects { _ = try UpdateManifest.verified(signed.prefix(length), publicKey: publicKey) }
        }
        var tampered = try JSONSerialization.jsonObject(with: signed) as! [String: String]
        fields["build"] = 999
        tampered["payload"] = try JSONSerialization.data(withJSONObject: fields).base64EncodedString()
        rejects { _ = try UpdateManifest.verified(JSONEncoder().encode(tampered), publicKey: publicKey) }
        fields["build"] = 8
        let invalid: [(String,Any)] = [("build",0),("size",0),("size",100_000_001),("sha256","bad"),("version","../evil"),("minimumSystemVersion","macOS 13"),("url","http://github.com/timothyosm/sound-control/releases/download/v0.6.0/SoundControl.zip"),("url","https://github.com/attacker/release.zip")]
        for (field,value) in invalid {
            var modified = fields; modified[field] = value
            rejects { _ = try UpdateManifest.verified(sign(modified), publicKey: publicKey) }
        }
        print("PASS: \(count) update verification assertions")
    }
}
