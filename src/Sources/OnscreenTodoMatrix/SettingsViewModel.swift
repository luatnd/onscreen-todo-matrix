import Foundation
import OTMCore

/// Asks Settings to show the New preset sheet (§11.7) with this account pre-selected.
struct NewPresetRequest: Identifiable, Equatable {
    let id = UUID()
    var accountId: String?
}

/// Which Settings tab / sheet is showing, set by the panel (`openSettings {tab}`, `newPreset {accountId}`)
/// and by the tabs themselves. Each tab keeps its own form state.
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var tab: SettingsTab = .accounts
    /// Accounts tab: open this account's form (e.g. from "Jira sign-in failed (Company) · Open settings").
    @Published var editAccountId: String?
    /// Axes tab: the account being mapped (nil = the active preset's account).
    @Published var axesAccountId: String?
    /// Non-nil while the New preset sheet is shown.
    @Published var newPreset: NewPresetRequest?
    @Published var generalError = ""

    // Used by the v1.1 Axes tab until Task 10 replaces it.
    @Published var fields: [JiraField] = []
    @Published var priorities: [String] = []

    let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    /// Routes an `openSettings {tab}` request. `accountId` selects the account for the Accounts/Axes tabs.
    func open(tab: SettingsTab?, accountId: String?) {
        guard let tab else { return }
        self.tab = tab
        switch tab {
        case .accounts: editAccountId = accountId
        case .axes: axesAccountId = accountId ?? axesAccountId
        default: break
        }
    }

    func openNewPreset(accountId: String?) {
        tab = .presets
        newPreset = NewPresetRequest(accountId: accountId)
    }

    /// Loads fields/priorities and applies the suggested mapping for `accountId` (default: the active account).
    func loadFields(accountId: String? = nil) async {
        guard let account = accountId.flatMap({ model.config.account(id: $0) }) ?? model.activeAccount,
              let api = try? model.makeAPI(accountId: account.id) else { return }
        guard let loaded = try? await api.fields() else { return }
        let sorted = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let loadedPriorities = try? await api.priorities()
        // The Axes tab edits the active account, so only its fields feed the shared lists.
        if account.id == model.activeAccount?.id {
            fields = sorted
            if let p = loadedPriorities { priorities = p }
        }
        // Re-read after the awaits so edits made during the network calls aren't overwritten.
        guard let current = model.config.account(id: account.id) else { return }
        let suggested = DefaultMappings.suggest(fields: sorted, current: current.axes)
        if suggested != current.axes { model.updateAxes(accountId: account.id) { $0 = suggested } }
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
