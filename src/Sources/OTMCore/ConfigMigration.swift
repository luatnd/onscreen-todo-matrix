import Foundation

/// The v1.1 keys that moved into `accounts[]` in v1.2 (§11.4). Every key optional: tolerant decoding.
struct LegacyAppConfigV1: Decodable {
    var site: String?
    var email: String?
    var axes: AxesConfig?
}

/// v1.1 → v1.2: one account per Jira site, keyed tokens, cache per preset. Must never lose the user's setup.
public enum ConfigMigration {
    /// Pure conversion of a v1.1 `config.json`. Presets, active preset, views, quick settings and
    /// launch-at-login decode as-is; site/email/axes become account "default" (no account when the site is empty).
    public static func migrated(from data: Data) throws -> AppConfig {
        let decoder = JSONDecoder()
        var config = try decoder.decode(AppConfig.self, from: data)
        let legacy = try decoder.decode(LegacyAppConfigV1.self, from: data)
        let site = (legacy.site ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        config.accounts = site.isEmpty ? [] : [JiraAccount(id: JiraAccount.defaultId, name: "Personal", site: site,
                                                           email: legacy.email ?? "", axes: legacy.axes ?? AxesConfig())]
        config.presets = config.presets.map { var p = $0; p.accountId = JiraAccount.defaultId; return p }
        return config
    }

    /// Persists a `.legacy` config:
    /// 1. copy `config.json` → `config.v1.json` (kept);
    /// 2. copy the Keychain token `jira-api-token` → `jira-api-token:default`, delete the legacy item only after
    ///    reading the copy back;
    /// 3. move `last-fetch.json` → `cache/<activePresetId>.json`;
    /// 4. save the new format.
    /// Returns false — leaving `config.json` and the legacy token untouched — if step 1, 2 or 4 fails.
    /// Every step is idempotent, so the next launch simply retries.
    public static func finish(_ config: AppConfig, store: ConfigStore, tokens: TokenStore, cache: IssueCache) -> Bool {
        let fm = FileManager.default
        if !fm.fileExists(atPath: store.legacyBackupURL.path) {
            guard (try? fm.copyItem(at: store.url, to: store.legacyBackupURL)) != nil else { return false }
        }
        if config.account(id: JiraAccount.defaultId) != nil {
            do {
                if let legacy = try tokens.readLegacy() {
                    if try tokens.read(accountId: JiraAccount.defaultId) != legacy {
                        try tokens.write(legacy, accountId: JiraAccount.defaultId)
                    }
                    guard try tokens.read(accountId: JiraAccount.defaultId) == legacy else { return false }
                    try? tokens.deleteLegacy()
                }
            } catch {
                return false
            }
        }
        if let preset = config.activePreset {
            cache.migrateLegacy(toPresetId: preset.id, accountId: preset.accountId)
        }
        return (try? store.save(config)) != nil
    }
}
