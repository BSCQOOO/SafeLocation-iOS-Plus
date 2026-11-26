import Foundation

// Synthetic profile data only; never use a real device's credentials.
func der(_ tag: UInt8, _ body: Data) -> Data {
    var result = Data([tag])
    if body.count < 128 { result.append(UInt8(body.count)) }
    else {
        var count = body.count
        var length: [UInt8] = []
        while count > 0 { length.insert(UInt8(count & 255), at: 0); count >>= 8 }
        result.append(0x80 | UInt8(length.count))
        result.append(contentsOf: length)
    }
    result.append(body)
    return result
}
let expiry = Date(timeIntervalSince1970: 2_000_000_000)
let payload = try PropertyListSerialization.data(fromPropertyList: ["ExpirationDate": expiry, "TeamIdentifier": ["TESTTEAM"]], format: .xml, options: 0)
let signedOID = der(0x06, Data([0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x07,0x02]))
let dataOID = der(0x06, Data([0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x07,0x01]))
let encap = der(0x30, dataOID + der(0xa0, der(0x04, payload)))
let fakeCMS = der(0x30, signedOID + der(0xa0, der(0x30, der(0x02, Data([1])) + der(0x31, Data()) + encap)))
precondition(ProfileMetadata.parseCMS(fakeCMS)?.expiration == expiry)
precondition(ProfileMetadata.parseCMS(fakeCMS)?.teamIdentifier == "TESTTEAM")
precondition(ProfileMetadata.parseCMS(Data(fakeCMS.dropLast())) == nil)
precondition(ProfileMetadata.parseCMS(payload) == nil)
precondition(ProfileMetadata.parsePlist(Data()) == nil)
precondition(ReleaseCatalog.isNewer("v3.0.10", than: "3.0.2") == true)
precondition(ReleaseCatalog.isNewer("v2.9.9", than: "3.0.0") == false)
precondition(ReleaseCatalog.isNewer("v3.0.0-beta.1", than: "3.0.0") == nil)

let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let source = root.appendingPathComponent("sample.ipa")
// Tests staging only, not ZIP validity.
try Data([0x50,0x4b,0x03,0x04,0x41]).write(to: source)
let vault = PackageVault(root: root.appendingPathComponent("vault"))
let staged = try await vault.stage(source)
let repeated = try await vault.stage(source)
precondition(staged.id == repeated.id && staged.sha256.count == 64 && staged.bytes == 5)
let before = try await vault.list()
precondition(before.count == 1)
try await vault.remove(staged.id)
let after = try await vault.list()
precondition(after.isEmpty)
let invalid = root.appendingPathComponent("bad.ipa")
try Data("invalid".utf8).write(to: invalid)
do { _ = try await vault.stage(invalid); preconditionFailure("Accepted invalid magic") }
catch PackageVault.VaultError.invalid {}
print("Signing foundation regression checks passed (metadata only; no real signing).")
