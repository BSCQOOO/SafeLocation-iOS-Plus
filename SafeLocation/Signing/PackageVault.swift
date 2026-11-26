import Foundation
import CryptoKit

struct StagedPackage: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let bytes: Int64
    let sha256: String
    let importedAt: Date
}

/// Local staging only: ZIP magic and a content hash are not code-signing validation.
/// The package is never extracted or executed here.
actor PackageVault {
    static let shared = PackageVault()
    static let limit: Int64 = 512 * 1024 * 1024
    private let root: URL
    private let fm = FileManager.default

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SigningStaging", isDirectory: true)
    }
    private var index: URL { root.appendingPathComponent("index.json") }

    enum VaultError: LocalizedError {
        case invalid, tooLarge, full
        var errorDescription: String? {
            switch self {
            case .invalid: return "请选择非空的 IPA ZIP 文件。"
            case .tooLarge: return "单个 IPA 不能超过 512 MB。"
            case .full: return "暂存区已满，请先清理旧包。"
            }
        }
    }

    func list() throws -> [StagedPackage] {
        guard fm.fileExists(atPath: index.path) else { return [] }
        return try JSONDecoder().decode([StagedPackage].self, from: Data(contentsOf: index))
    }

    private func save(_ items: [StagedPackage]) throws {
        try JSONEncoder().encode(items).write(to: index, options: .atomic)
    }

    func stage(_ source: URL) throws -> StagedPackage {
        guard source.pathExtension.lowercased() == "ipa" else { throw VaultError.invalid }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let fileSize = values.fileSize, fileSize > 4 else { throw VaultError.invalid }
        guard Int64(fileSize) <= Self.limit else { throw VaultError.tooLarge }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        var items = try list()
        guard items.count < 4, items.reduce(Int64(fileSize), { $0 + $1.bytes }) <= 1024 * 1024 * 1024 else { throw VaultError.full }
        let id = UUID()
        let dest = root.appendingPathComponent(id.uuidString + ".ipa")
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        guard let magic = try input.read(upToCount: 4), Array(magic) == [0x50,0x4b,0x03,0x04] else { throw VaultError.invalid }
        try input.seek(toOffset: 0)
        guard fm.createFile(atPath: dest.path, contents: nil) else { throw VaultError.invalid }
        do {
            let output = try FileHandle(forWritingTo: dest)
            defer { try? output.close() }
            var hash = SHA256()
            var count: Int64 = 0
            while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty {
                try Task.checkCancellation()
                count += Int64(data.count)
                guard count <= Self.limit, count <= Int64(fileSize) else { throw VaultError.tooLarge }
                hash.update(data: data)
                try output.write(contentsOf: data)
            }
            guard count == Int64(fileSize) else { throw VaultError.invalid }
            try output.synchronize()
            let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
            if let existing = items.first(where: { $0.sha256 == digest && fm.fileExists(atPath: root.appendingPathComponent($0.id.uuidString + ".ipa").path) }) {
                try fm.removeItem(at: dest)
                return existing
            }
            let item = StagedPackage(id: id, name: source.lastPathComponent, bytes: count, sha256: digest, importedAt: .now)
            items.append(item)
            try save(items)
            return item
        } catch {
            try? fm.removeItem(at: dest)
            throw error
        }
    }

    func remove(_ id: UUID) throws {
        var items = try list()
        guard items.contains(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        try save(items)
        let file = root.appendingPathComponent(id.uuidString + ".ipa")
        if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
    }
}
