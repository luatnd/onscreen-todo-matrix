import KeyboardShortcuts
import OTMCore
import SwiftUI

enum SettingsTab: Hashable { case connection, filters, axes, shortcuts, general }

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var vm: SettingsViewModel
    @State var tab: SettingsTab = .connection
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
            TabView(selection: $tab) {
                ConnectionTab(vm: vm).tabItem { Text("1. Connect") }.tag(SettingsTab.connection)
                FiltersTab(model: model, vm: vm).tabItem { Text("2. Filter") }.tag(SettingsTab.filters)
                AxesTab(model: model, vm: vm).tabItem { Text("3. Axes") }.tag(SettingsTab.axes)
                ShortcutsTab().tabItem { Text("Shortcuts") }.tag(SettingsTab.shortcuts)
                GeneralTab(model: model, vm: vm).tabItem { Text("General") }.tag(SettingsTab.general)
            }
            .padding(12)
        }
        .frame(minWidth: 620, minHeight: 520)
    }

    private var setupHeader: some View {
        HStack(spacing: 14) {
            step("1. Connect", done: vm.isConnected || (model.storedToken != nil && model.config.siteURL != nil))
            step("2. Filter", done: !model.config.presets.isEmpty)
            step("3. Axes", done: model.config.axes.isComplete)
            Spacer()
            Button(tab == .axes ? "Done · show panel" : "Next") {
                switch tab {
                case .connection: tab = .filters
                case .filters: tab = .axes
                default: if model.isConfigured { onDone() }
                }
            }
            .disabled(tab == .axes && !model.isConfigured)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.08))
    }

    private func step(_ title: String, done: Bool) -> some View {
        Label(title, systemImage: done ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(done ? .green : .secondary)
    }
}

struct ConnectionTab: View {
    @ObservedObject var vm: SettingsViewModel
    var body: some View {
        Form {
            TextField("Jira site", text: $vm.site, prompt: Text("your-company.atlassian.net"))
            TextField("Email", text: $vm.email)
            SecureField("API token", text: $vm.token)
            Link("Create an API token at id.atlassian.com", destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                .font(.caption)
            HStack {
                Button("Save & Test") { Task { await vm.saveAndTest() } }
                    .disabled(vm.busy || vm.site.isEmpty || vm.email.isEmpty || vm.token.isEmpty)
                if vm.busy { ProgressView().controlSize(.small) }
                Text(vm.connectionStatus).foregroundStyle(vm.isConnected ? .green : .secondary)
            }
            Text("The API token is stored only in your macOS Keychain. The app only reads from Jira.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct FiltersTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        Form {
            ForEach(model.config.presets) { preset in
                Section {
                    TextField("Name", text: binding(preset.id, \.name))
                    TextField("JQL", text: binding(preset.id, \.jql), axis: .vertical).lineLimit(2...5)
                    HStack {
                        Button("Test") { Task { await vm.testJQL(currentPreset(preset.id) ?? preset) } }
                        Text(vm.jqlStatus[preset.id] ?? "").foregroundStyle(.secondary)
                        Spacer()
                        if model.config.activePresetId == preset.id {
                            Text("Active").foregroundStyle(.green)
                        } else {
                            Button("Make active") {
                                model.selectPreset(id: preset.id)
                                Task { await model.refresh(.manual) }
                            }
                        }
                        Button("Delete", role: .destructive) { delete(preset.id) }
                            .disabled(model.config.presets.count <= 1)
                    }
                }
            }
            Button("Add preset") {
                var c = model.config
                c.presets.append(JQLPreset(id: UUID().uuidString, name: "New preset", jql: "assignee = currentUser() AND statusCategory != Done"))
                model.updateConfig(c)
            }
        }
        .formStyle(.grouped)
    }

    private func currentPreset(_ id: String) -> JQLPreset? { model.config.presets.first { $0.id == id } }

    private func binding(_ id: String, _ path: WritableKeyPath<JQLPreset, String>) -> Binding<String> {
        Binding(
            get: { currentPreset(id)?[keyPath: path] ?? "" },
            set: { value in
                var c = model.config
                guard let i = c.presets.firstIndex(where: { $0.id == id }) else { return }
                c.presets[i][keyPath: path] = value
                model.updateConfig(c)
            }
        )
    }

    private func delete(_ id: String) {
        var c = model.config
        c.presets.removeAll { $0.id == id }
        let wasActive = c.activePresetId == id
        if wasActive { c.activePresetId = c.presets.first?.id ?? JQLPreset.myOpenWork.id }
        model.updateConfig(c)
        if wasActive { Task { await model.refresh(.manual) } }
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

    private var cfg: AxisConfig { model.config.axes[axis] }

    private func update(_ change: (inout AxisConfig) -> Void) {
        var c = model.config
        change(&c.axes[axis])
        model.updateConfig(c)
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
                    let mapping = vm.fields.first(where: { $0.id == id }).flatMap { DefaultMappings.mapping(for: $0) }
                    update { $0.mapping = mapping }
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
            if axis == .effort, cfg.mapping?.fieldId == "timeoriginalestimate" { timelineEditor }
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

    /// D21: effort fallback for issues without an Original estimate (logged time, then Start → Due window).
    @ViewBuilder
    private var timelineEditor: some View {
        let dateFields = DefaultMappings.timelineDateFields(vm.fields)
        Toggle("If missing, estimate from timeline (Start → Due)", isOn: Binding(
            get: { cfg.timeline != nil },
            set: { on in update { $0.timeline = on ? TimelineFallback(startFieldId: DefaultMappings.guessStartField(vm.fields)?.id ?? "") : nil } }
        ))
        if let tl = cfg.timeline {
            Picker("Start field", selection: Binding(
                get: { tl.startFieldId },
                set: { id in update { $0.timeline?.startFieldId = id } }
            )) {
                Text("— choose —").tag("")
                ForEach(dateFields) { f in Text(f.name).tag(f.id) }
            }
            Picker("End field", selection: Binding(
                get: { tl.endFieldId },
                set: { id in update { $0.timeline?.endFieldId = id } }
            )) {
                ForEach(dateFields) { f in Text(f.name).tag(f.id) }
            }
            Picker("Effort unit", selection: Binding(
                get: { tl.unit },
                set: { u in update { $0.timeline?.unit = u } }
            )) {
                Text("Hours").tag(EffortUnit.hours)
                Text("Days").tag(EffortUnit.days)
            }
            .pickerStyle(.segmented)
            Text("Shown on the card as hours or days. Order: logged time (spent + remaining), then working days Mon–Fri × 8 h between Start and End (1 day = 8 h; holidays ignored; Epics skipped). A window is an upper bound.")
                .font(.caption).foregroundStyle(.secondary)
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
