import Foundation

/// Parses the encapsulated plist in a DER CMS SignedData profile.
/// This reads metadata only; it does NOT authenticate the CMS signature.
struct ProfileMetadata: Equatable {
    let expiration: Date
    let creation: Date?
    let applicationIdentifier: String?
    let teamIdentifier: String?

    static func current(bundle: Bundle = .main) -> Self? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let bytes = try? Data(contentsOf: url) else { return nil }
        return parseCMS(bytes)
    }

    static func parseCMS(_ data: Data) -> Self? {
        guard data.count <= 4 * 1024 * 1024 else { return nil }
        let bytes = Array(data)
        var cursor = 0
        guard let outer = read(bytes, &cursor, limit: bytes.count), outer.tag == 0x30,
              cursor == bytes.count else { return nil }
        cursor = outer.range.lowerBound
        guard let oid = read(bytes, &cursor, limit: outer.range.upperBound), oid.tag == 0x06,
              Array(bytes[oid.range]) == [0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x07,0x02],
              let wrapped = read(bytes, &cursor, limit: outer.range.upperBound), wrapped.tag == 0xa0,
              cursor == outer.range.upperBound else { return nil }
        cursor = wrapped.range.lowerBound
        guard let signed = read(bytes, &cursor, limit: wrapped.range.upperBound), signed.tag == 0x30,
              cursor == wrapped.range.upperBound else { return nil }
        cursor = signed.range.lowerBound
        guard let version = read(bytes, &cursor, limit: signed.range.upperBound), version.tag == 0x02,
              let digests = read(bytes, &cursor, limit: signed.range.upperBound), digests.tag == 0x31,
              let content = read(bytes, &cursor, limit: signed.range.upperBound), content.tag == 0x30 else { return nil }
        cursor = content.range.lowerBound
        guard let contentOID = read(bytes, &cursor, limit: content.range.upperBound), contentOID.tag == 0x06,
              Array(bytes[contentOID.range]) == [0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x07,0x01],
              let body = read(bytes, &cursor, limit: content.range.upperBound), body.tag == 0xa0,
              cursor == content.range.upperBound else { return nil }
        cursor = body.range.lowerBound
        guard let octets = read(bytes, &cursor, limit: body.range.upperBound), octets.tag == 0x04,
              cursor == body.range.upperBound else { return nil }
        return parsePlist(Data(bytes[octets.range]))
    }

    static func parsePlist(_ data: Data) -> Self? {
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = object as? [String: Any], let expiration = dict["ExpirationDate"] as? Date else { return nil }
        let entitlements = dict["Entitlements"] as? [String: Any]
        return Self(expiration: expiration, creation: dict["CreationDate"] as? Date,
                    applicationIdentifier: entitlements?["application-identifier"] as? String,
                    teamIdentifier: (dict["TeamIdentifier"] as? [String])?.first)
    }

    private static func read(_ bytes: [UInt8], _ cursor: inout Int, limit: Int) -> (tag: UInt8, range: Range<Int>)? {
        guard cursor >= 0, cursor < limit, limit <= bytes.count, limit - cursor >= 2 else { return nil }
        let tag = bytes[cursor]
        cursor += 1
        guard tag & 0x1f != 0x1f else { return nil }
        let first = Int(bytes[cursor])
        cursor += 1
        var length = first
        if first >= 128 {
            let count = first & 127
            guard (1...4).contains(count), count <= limit - cursor else { return nil }
            length = 0
            for _ in 0..<count {
                length = length * 256 + Int(bytes[cursor])
                cursor += 1
            }
        }
        guard length <= limit - cursor else { return nil }
        let range = cursor..<(cursor + length)
        cursor += length
        return (tag, range)
    }
}
