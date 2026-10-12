import Foundation

public enum ConfigLoadResult: Equatable {
    case loaded(AppConfig)
    case missing
    case corrupt(backup: URL)
}

public final class ConfigStore {
    public let url: URL

    public init(directory: URL) {
        url = directory.appendingPathComponent("config.json")
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("onscreen-todo-matrix")
    }

    public func load() -> ConfigLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let data = try Data(contentsOf: url)
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
