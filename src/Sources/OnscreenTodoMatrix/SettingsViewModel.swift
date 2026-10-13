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
        site = model.config.site
        email = model.config.email
        token = model.storedToken ?? ""
    }

    var isConnected: Bool { connectionStatus.hasPrefix("Connected as") }

    func saveAndTest() async {
        busy = true
        defer { busy = false }
        var c = model.config
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        c.site = site
        c.email = email
        model.updateConfig(c)
        do {
            try model.setToken(token)
        } catch {
            connectionStatus = "Could not save token to Keychain: \(error.localizedDescription)"
            return
        }
        do {
            let me = try await model.makeAPI().myself()
            connectionStatus = "Connected as \(me.displayName)"
            await loadFields()
            await model.refresh(.manual)
        } catch {
            connectionStatus = Self.describe(error)
        }
    }

    func loadFields() async {
        guard let api = try? model.makeAPI() else { return }
        do {
            fields = try await api.fields().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            connectionStatus = Self.describe(error)
            return
        }
        if let p = try? await api.priorities() { priorities = p }
        if !fields.isEmpty && !isConnected { connectionStatus = "Connected" }
        let suggested = DefaultMappings.suggest(fields: fields, current: model.config.axes)
        if suggested != model.config.axes {
            var c = model.config
            c.axes = suggested
            model.updateConfig(c)
        }
    }

    func testJQL(_ preset: JQLPreset) async {
        jqlStatus[preset.id] = "Testing…"
        do {
            let n = try await model.makeAPI().approximateCount(jql: preset.jql)
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
