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

    /// Loads one account's fields + priorities and pre-fills its empty axes (DefaultMappings.suggest).
    /// Used by the Axes tab and by Accounts "Save & Test" (auto-map).
    func fetchFields(accountId: String) async throws -> (fields: [JiraField], priorities: [String]) {
        let api = try model.makeAPI(accountId: accountId)
        let loaded = try await api.fields()
        let sorted = loaded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let priorities = (try? await api.priorities()) ?? []
        // Re-read after the awaits so edits made during the network calls aren't overwritten.
        if let current = model.config.account(id: accountId) {
            let suggested = DefaultMappings.suggest(fields: sorted, current: current.axes)
            if suggested != current.axes { model.updateAxes(accountId: accountId) { $0 = suggested } }
        }
        return (sorted, priorities)
    }

    static func describe(_ error: Error) -> String {
        if let e = error as? JiraError { return AppModel.bannerText(e, syncedAt: nil) }
        return error.localizedDescription
    }
}
