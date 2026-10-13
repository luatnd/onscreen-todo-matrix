import KeyboardShortcuts
import OTMCore
import SwiftUI

/// Raw values are the `tab` strings of the panel's `openSettings {tab}` message.
enum SettingsTab: String, Hashable { case accounts, presets, axes, shortcuts, general }

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var vm: SettingsViewModel
    let onDone: () -> Void
    /// Latched at creation so the setup header (and its Done button) survives becoming configured mid-wizard.
    @State private var wizard: Bool

    init(model: AppModel, vm: SettingsViewModel, onDone: @escaping () -> Void) {
        self.model = model
        self.vm = vm
        self.onDone = onDone
        _wizard = State(initialValue: !model.isConfigured)
    }

    var body: some View {
        VStack(spacing: 0) {
            if wizard { setupHeader }
            TabView(selection: $vm.tab) {
                AccountsTab(model: model, vm: vm).tabItem { Text("Accounts") }.tag(SettingsTab.accounts)
                PresetsTab(model: model, vm: vm).tabItem { Text("Presets") }.tag(SettingsTab.presets)
                AxesTab(model: model, vm: vm).tabItem { Text("Axes") }.tag(SettingsTab.axes)
                ShortcutsTab().tabItem { Text("Shortcuts") }.tag(SettingsTab.shortcuts)
                GeneralTab(model: model, vm: vm).tabItem { Text("General") }.tag(SettingsTab.general)
            }
            .padding(12)
        }
        .frame(minWidth: 620, minHeight: 520)
        .sheet(item: $vm.newPreset) { request in
            NewPresetSheet(model: model, request: request, onCreated: onDone)
        }
    }

    private var setupHeader: some View {
        HStack(spacing: 14) {
            step("1. Add account", done: model.config.accounts.contains { model.hasCredentials($0) })
            step("2. Presets", done: model.activeAccount != nil)
            step("3. Axes", done: model.activeAccount?.axes.isComplete ?? false)
            Spacer()
            Button(vm.tab == .axes ? "Done · show panel" : "Next") {
                switch vm.tab {
                case .accounts: vm.tab = .presets
                case .presets: vm.tab = .axes
                default: if model.isConfigured { onDone() }
                }
            }
            .disabled(vm.tab == .axes && !model.isConfigured)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.08))
    }

    private func step(_ title: String, done: Bool) -> some View {
        Label(title, systemImage: done ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(done ? .green : .secondary)
    }
}

struct AxesTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        Form {
            if vm.fields.isEmpty {
                Text("Connect to Jira first (tab 1) to load your fields.").foregroundStyle(.secondary)
                Button("Reload fields") { Task { await vm.loadFields() } }
            }
            ForEach(OTMCore.Axis.allCases, id: \.self) { axis in
                AxisEditor(axis: axis, model: model, vm: vm)
            }
        }
        .formStyle(.grouped)
    }
}

struct AxisEditor: View {
    let axis: OTMCore.Axis
    @ObservedObject var model: AppModel
    @ObservedObject var vm: SettingsViewModel
    @State private var filter = ""

    private var cfg: AxisConfig { model.activeAccount?.axes[axis] ?? AxisConfig() }

    private func update(_ change: (inout AxisConfig) -> Void) {
        guard let id = model.activeAccount?.id else { return }
        model.updateAxes(accountId: id) { change(&$0[axis]) }
    }

    private var title: String {
        switch axis {
        case .value: return "Value (X)"
        case .effort: return "Effort (Y)"
        case .urgency: return "Urgency (Z)"
        }
    }

    var body: some View {
        Section(title) {
            TextField("Filter fields", text: $filter)
            Picker("Field", selection: Binding(
                get: { cfg.mapping?.fieldId ?? "" },
                set: { id in
                    let field = vm.fields.first(where: { $0.id == id })
                    update {
                        $0.mapping = field.flatMap { DefaultMappings.mapping(for: $0) }
                        $0.fieldName = field?.name
                    }
                }
            )) {
                Text("— none —").tag("")
                let usable = vm.usableFields(matching: filter)
                if let current = cfg.mapping?.fieldId, !usable.contains(where: { $0.id == current }) {
                    Text(vm.fields.first(where: { $0.id == current })?.name ?? current).tag(current)
                }
                ForEach(usable) { f in
                    Text("\(f.name)  ·  \(f.schemaType ?? "?")").tag(f.id)
                }
            }
            if let mapping = cfg.mapping { editor(for: mapping) }
            HStack {
                Text("Missing value position")
                Slider(value: Binding(get: { cfg.missingDefault }, set: { v in update { $0.missingDefault = v } }), in: 0...1)
                Text(String(format: "%.2f", cfg.missingDefault)).monospacedDigit()
            }
            Text(liveLine).font(.caption).foregroundStyle(.secondary)
            if let unmapped = model.unmappedLabels[axis], !unmapped.isEmpty {
                Text("Unmapped values (placed at the middle): \(unmapped.joined(separator: ", "))")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private var liveLine: String {
        let tasks = model.renderState.tasks
        let missing = tasks.filter { $0.missing[axis] }.count
        return "\(tasks.count) issues mapped · \(missing) missing value"
    }

    @ViewBuilder
    private func editor(for mapping: AxisMapping) -> some View {
        switch mapping {
        case .option(let fieldId, let levels):
            ForEach(vm.optionValues(for: mapping), id: \.self) { label in
                HStack {
                    Text(label).frame(width: 140, alignment: .leading)
                    Slider(value: Binding(
                        get: { levels[label] ?? 2.5 },
                        set: { v in
                            var l = levels
                            l[label] = v
                            update { $0.mapping = .option(fieldId: fieldId, levels: l) }
                        }
                    ), in: 0...5, step: 0.25)
                    Text(String(format: "%.2f", levels[label] ?? 2.5)).monospacedDigit()
                }
            }
        case .number(let fieldId, let lo, let hi, let invert):
            Toggle("Auto range (from current issues)", isOn: Binding(
                get: { lo == nil && hi == nil },
                set: { auto in update { $0.mapping = .number(fieldId: fieldId, min: auto ? nil : 0, max: auto ? nil : 10, invert: invert) } }
            ))
            if lo != nil || hi != nil {
                HStack {
                    TextField("Min", value: Binding(get: { lo ?? 0 }, set: { v in update { $0.mapping = .number(fieldId: fieldId, min: v, max: hi, invert: invert) } }), format: .number)
                    TextField("Max", value: Binding(get: { hi ?? 10 }, set: { v in update { $0.mapping = .number(fieldId: fieldId, min: lo, max: v, invert: invert) } }), format: .number)
                }
            }
            Toggle("Invert", isOn: Binding(get: { invert }, set: { v in update { $0.mapping = .number(fieldId: fieldId, min: lo, max: hi, invert: v) } }))
        case .date(let fieldId, let horizon, let invert):
            Stepper("Horizon: \(horizon) days (due today or overdue = max)", value: Binding(
                get: { horizon },
                set: { v in update { $0.mapping = .date(fieldId: fieldId, horizonDays: v, invert: invert) } }
            ), in: 1...90)
            Toggle("Invert", isOn: Binding(get: { invert }, set: { v in update { $0.mapping = .date(fieldId: fieldId, horizonDays: horizon, invert: v) } }))
        }
    }
}

struct ShortcutsTab: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Show / hide panel:", name: .togglePanel)
            Text("Default ⌥Space. If it conflicts with Raycast, Alfred or ChatGPT, record another shortcut.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct GeneralTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: Binding(
                get: { model.config.launchAtLogin },
                set: { on in
                    do {
                        try LoginItem.set(on)
                        var c = model.config
                        c.launchAtLogin = on
                        model.updateConfig(c)
                        vm.generalError = ""
                    } catch {
                        vm.generalError = "Could not change login item: \(error.localizedDescription)"
                    }
                }
            ))
            Picker("Auto refresh", selection: Binding(
                get: { model.config.quick.refreshMinutes },
                set: { v in model.setQuickSetting(key: "refreshMinutes", value: .number(Double(v))) }
            )) {
                Text("1 min").tag(1); Text("5 min").tag(5); Text("15 min").tag(15); Text("Off").tag(0)
            }
            if !vm.generalError.isEmpty { Text(vm.generalError).foregroundStyle(.red) }
            if model.configWasCorrupt {
                Text("Your previous config file was unreadable and was saved as config.json.bak.")
                    .foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
    }
}
