import OTMCore
import SwiftUI

/// Axes tab (§11.7): account picker at the top; mappings are per account, fields/priorities come from that account's site.
struct AxesTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var vm: SettingsViewModel
    @State private var fields: [JiraField] = []
    @State private var priorities: [String] = []
    @State private var fieldsAccountId: String?
    @State private var loadMessage = ""

    /// vm.axesAccountId if it still exists, else the active preset's account, else the first account.
    private var accountId: String? {
        if let id = vm.axesAccountId, model.config.account(id: id) != nil { return id }
        return model.activeAccount?.id ?? model.config.accounts.first?.id
    }

    var body: some View {
        Form {
            if let accountId {
                Picker("Account", selection: Binding(get: { accountId }, set: { vm.axesAccountId = $0 })) {
                    ForEach(model.config.accounts) { account in Text(account.name).tag(account.id) }
                }
                if fields.isEmpty || fieldsAccountId != accountId {
                    Text(loadMessage.isEmpty ? "Loading fields from this account's site…" : loadMessage)
                        .foregroundStyle(.secondary)
                } else if !loadMessage.isEmpty {
                    Text(loadMessage).foregroundStyle(.orange)
                }
                if !loadMessage.isEmpty {
                    Button("Reload fields") { Task { await loadFields(accountId) } }
                }
                ForEach(OTMCore.Axis.allCases, id: \.self) { axis in
                    AxisEditor(axis: axis, accountId: accountId, model: model,
                               fields: fieldsAccountId == accountId ? fields : [],
                               priorities: fieldsAccountId == accountId ? priorities : [])
                }
            } else {
                Text("Add an account first (Accounts tab).").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task(id: accountId) { if let accountId { await loadFields(accountId) } }
    }

    /// A failed reload keeps the previously loaded fields of the same account and shows the error.
    /// Every write after an await is dropped if the picker moved on (the old task was cancelled).
    private func loadFields(_ id: String) async {
        loadMessage = ""
        do {
            let r = try await vm.fetchFields(accountId: id)
            guard !Task.isCancelled, id == accountId else { return }
            fields = r.fields
            priorities = r.priorities
            fieldsAccountId = id
        } catch {
            guard !Task.isCancelled, id == accountId,
                  !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            loadMessage = (error as? JiraError) == .notConfigured
                ? "Connect this account first (Accounts tab)." : SettingsViewModel.describe(error)
        }
    }
}

struct AxisEditor: View {
    let axis: OTMCore.Axis
    let accountId: String
    @ObservedObject var model: AppModel
    let fields: [JiraField]
    let priorities: [String]
    @State private var filter = ""

    private var cfg: AxisConfig { model.config.account(id: accountId)?.axes[axis] ?? AxisConfig() }
    /// Issue-based hints (live line, observed values, unmapped values) only make sense for the account on screen.
    private var isActiveAccount: Bool { model.activeAccount?.id == accountId }

    private func update(_ change: (inout AxisConfig) -> Void) {
        model.updateAxes(accountId: accountId) { change(&$0[axis]) }
    }

    private var title: String {
        switch axis {
        case .value: return "Value (X)"
        case .effort: return "Effort (Y)"
        case .urgency: return "Urgency (Z)"
        }
    }

    private var usableFields: [JiraField] {
        fields.filter {
            FieldClassifier.kind(of: $0) != .unsupported
                && (filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) || $0.id.localizedCaseInsensitiveContains(filter))
        }
    }

    var body: some View {
        Section(title) {
            TextField("Filter fields", text: $filter)
            Picker("Field", selection: Binding(
                get: { cfg.mapping?.fieldId ?? "" },
                set: { id in
                    let field = fields.first(where: { $0.id == id })
                    update {
                        $0.mapping = field.flatMap { DefaultMappings.mapping(for: $0) }
                        $0.fieldName = $0.mapping == nil ? nil : field?.name
                    }
                }
            )) {
                Text("— none —").tag("")
                let usable = usableFields
                if let current = cfg.mapping?.fieldId, !usable.contains(where: { $0.id == current }) {
                    Text(fields.first(where: { $0.id == current })?.name ?? current).tag(current)
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
            if isActiveAccount {
                Text(liveLine).font(.caption).foregroundStyle(.secondary)
                if let unmapped = model.unmappedLabels[axis], !unmapped.isEmpty {
                    Text("Unmapped values (placed at the middle): \(unmapped.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    /// D29: effort fallback for issues without an Original estimate (logged time, then Start → Due window).
    @ViewBuilder
    private var timelineEditor: some View {
        let dateFields = DefaultMappings.timelineDateFields(fields)
        Toggle("If missing, estimate from timeline (Start → Due)", isOn: Binding(
            get: { cfg.timeline != nil },
            set: { on in update { $0.timeline = on ? TimelineFallback(startFieldId: DefaultMappings.guessStartField(fields)?.id ?? "") : nil } }
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

    /// Values offered in the option-level editor.
    private func optionValues(fieldId: String, levels: [String: Double]) -> [String] {
        var values: [String]
        if fieldId == "priority" && !priorities.isEmpty {
            values = priorities
        } else {
            values = isActiveAccount ? AxisMapper.observedLabels(fieldId: fieldId, issues: model.issues) : []
        }
        for key in levels.keys.sorted() where !values.contains(key) { values.append(key) }
        return values
    }

    @ViewBuilder
    private func editor(for mapping: AxisMapping) -> some View {
        switch mapping {
        case .option(let fieldId, let levels):
            ForEach(optionValues(fieldId: fieldId, levels: levels), id: \.self) { label in
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
