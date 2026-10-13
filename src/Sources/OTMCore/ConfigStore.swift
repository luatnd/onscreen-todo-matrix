import Foundation

public enum ConfigLoadResult: Equatable {
    case loaded(AppConfig)
    /// A v1.1 file (no `accounts` key), converted in memory only; `ConfigMigration.finish` persists it.
    case legacy(AppConfig)
    case missing
    case corrupt(backup: URL)
}

public final class ConfigStore {
    public let url: URL
    /// Backup of the v1.1 file, written by the migration and kept.
    public let legacyBackupURL: URL

    public init(directory: URL) {
        url = directory.appendingPathComponent("config.json")
        legacyBackupURL = directory.appendingPathComponent("config.v1.json")
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("onscreen-todo-matrix")
    }

    /// Never rewrites a readable file: a v1.1 file comes back as `.legacy` and stays on disk untouched.
    public func load() -> ConfigLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let data = try Data(contentsOf: url)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.coderReadCorrupt)
            }
            if object["accounts"] == nil { return .legacy(try ConfigMigration.migrated(from: data)) }
            return .loaded(try JSONDecoder().decode(AppConfig.self, from: data))
        } catch {
            let backup = url.deletingLastPathComponent().appendingPathComponent("config.json.bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            return .corrupt(backup: backup)
        }
    }

    public func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(config).write(to: url, options: .atomic)
    }
}
