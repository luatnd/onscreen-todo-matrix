import OTMCore
import SwiftUI

/// Presets tab (§11.7): presets grouped by account; drag to reorder within an account (= menu order = ⌘1…⌘9).
struct PresetsTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var vm: SettingsViewModel
    @State private var testStatus: [String: String] = [:]

    private var orphans: [JQLPreset] {
        model.config.presets.filter { model.config.account(id: $0.accountId) == nil }
    }

    var body: some View {
        List {
            ForEach(Array(model.config.accounts.enumerated()), id: \.element.id) { index, account in
                Section {
                    ForEach(model.config.presets.filter { $0.accountId == account.id }) { preset in
                        presetRow(preset)
                    }
                    .onMove { source, destination in
                        var c = model.config
                        c.presets = c.movingPresets(accountId: account.id, fromOffsets: source, toOffset: destination)
                        model.updateConfig(c)
                    }
                    Button("+ New preset") { vm.openNewPreset(accountId: account.id) }
                } header: {
                    HStack(spacing: 6) {
                        AccountDot(color: AccountPalette.color(at: index))
                        Text(account.name)
                    }
                }
            }
            if !orphans.isEmpty {
                Section("⚠ account missing") {
                    ForEach(orphans) { preset in orphanRow(preset) }
                }
            }
            if model.config.accounts.isEmpty {
                Text("Add an account first (Accounts tab).").foregroundStyle(.secondary)
            }
        }
    }

    private func presetRow(_ preset: JQLPreset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Name", text: binding(preset.id, \.name))
            if !model.config.isPresetNameValid(preset.name, accountId: preset.accountId, excludingId: preset.id) {
                Text("Preset names must be unique within an account.").font(.caption).foregroundStyle(.orange)
            }
            TextField("JQL", text: binding(preset.id, \.jql), axis: .vertical)
                .lineLimit(2...5)
                .font(.system(.body, design: .monospaced))
            HStack {
                Button("Test") { Task { await test(preset.id) } }
                Text(testStatus[preset.id] ?? "").foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                if model.config.activePreset?.id == preset.id {
                    Text("Active").foregroundStyle(.green)
                } else {
                    Button("Make active") {
                        if model.selectPreset(id: preset.id) == .selected { Task { await model.refresh(.manual) } }
                    }
                }
                Button("Delete", role: .destructive) { delete(preset.id) }
                    .disabled(model.config.presets.count <= 1)
            }
        }
        .padding(.vertical, 4)
    }

    /// A preset whose account was deleted: reassign it (it cannot be activated until then) or delete it.
    private func orphanRow(_ preset: JQLPreset) -> some View {
        HStack {
            Text(preset.name)
            Spacer()
            Picker("Account", selection: Binding(
                get: { "" },
                set: { newId in
                    var c = model.config
                    guard !newId.isEmpty, let i = c.presets.firstIndex(where: { $0.id == preset.id }) else { return }
                    c.presets[i].accountId = newId
                    model.updateConfig(c)
                }
            )) {
                Text("Choose…").tag("")
                ForEach(model.config.accounts) { account in Text(account.name).tag(account.id) }
            }
            .frame(width: 200)
            Button("Delete", role: .destructive) { delete(preset.id) }
        }
    }

    private func current(_ id: String) -> JQLPreset? { model.config.presets.first { $0.id == id } }

    private func binding(_ id: String, _ path: WritableKeyPath<JQLPreset, String>) -> Binding<String> {
        Binding(
            get: { current(id)?[keyPath: path] ?? "" },
            set: { value in
                var c = model.config
                guard let i = c.presets.firstIndex(where: { $0.id == id }) else { return }
                c.presets[i][keyPath: path] = value
                model.updateConfig(c)
            }
        )
    }

    private func test(_ id: String) async {
        guard let preset = current(id) else { return }
        testStatus[id] = "Testing…"
        testStatus[id] = await model.testJQL(preset.jql, accountId: preset.accountId).text
    }

    /// Deleting the active preset activates the next one and refreshes immediately.
    private func delete(_ id: String) {
        let wasActive = model.config.activePreset?.id == id
        model.deletePreset(id: id)
        if wasActive { Task { await model.refresh(.manual) } }
    }
}
