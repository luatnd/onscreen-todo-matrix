import Foundation
import OTMCore

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var site: String
    @Published var email: String
    @Published var token: String
    @Published var connectionStatus = ""
    @Published var fields: [JiraField] = []
    @Published var priorities: [String] = []
    @Published var jqlStatus: [String: String] = [:]
    @Published var generalError = ""
    @Published var busy = false

    let model: AppModel

    init(model: AppModel) {
        self.model = model
        let account = model.activeAccount
        site = account?.site ?? ""
        email = account?.email ?? ""
        token = account.flatMap { model.storedToken(accountId: $0.id) } ?? ""
    }

    var isConnected: Bool { connectionStatus.hasPrefix("Connected as") }

    func saveAndTest() async {
        busy = true
        defer { busy = false }
        var account = model.activeAccount ?? JiraAccount(id: model.newAccountId(), name: "Personal")
        account.site = site.trimmingCharacters(in: .whitespacesAndNewlines)
        account.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try model.saveAccount(account, token: token)
        } catch {
            connectionStatus = "Could not save token to Keychain: \(error.localizedDescription)"
            return
        }
        do {
            let me = try await model.makeAPI(accountId: account.id).myself()
            connectionStatus = "Connected as \(me.displayName)"
            await loadFields()
            await model.refresh(.manual)
        } catch {
            connectionStatus = Self.describe(error)
        }
    }

    func loadFields() async {
        guard let account = model.activeAccount, let api = try? model.makeAPI(accountId: account.id) else { return }
        do {
            fields = try await api.fields().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            connectionStatus = Self.describe(error)
            return
        }
        if let p = try? await api.priorities() { priorities = p }
        if !fields.isEmpty && !isConnected { connectionStatus = "Connected" }
        let suggested = DefaultMappings.suggest(fields: fields, current: account.axes)
        if suggested != account.axes { model.updateAxes(accountId: account.id) { $0 = suggested } }
    }

    func testJQL(_ preset: JQLPreset) async {
        jqlStatus[preset.id] = "Testing…"
        do {
            let n = try await model.makeAPI(accountId: preset.accountId).approximateCount(jql: preset.jql)
            jqlStatus[preset.id] = "\(n) issues match"
        } catch {
            jqlStatus[preset.id] = Self.describe(error)
        }
    }

    /// Values offered in the option-level editor.
    func optionValues(for mapping: AxisMapping) -> [String] {
        guard case .option(let fieldId, let levels) = mapping else { return [] }
        var values = fieldId == "priority" && !priorities.isEmpty
            ? priorities : AxisMapper.observedLabels(fieldId: fieldId, issues: model.issues)
        for key in levels.keys.sorted() where !values.contains(key) { values.append(key) }
        return values
    }

    func usableFields(matching filter: String) -> [JiraField] {
        fields.filter {
            FieldClassifier.kind(of: $0) != .unsupported
                && (filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) || $0.id.localizedCaseInsensitiveContains(filter))
        }
    }

    static func describe(_ error: Error) -> String {
        if let e = error as? JiraError { return AppModel.bannerText(e, syncedAt: nil) }
        return error.localizedDescription
    }
}
