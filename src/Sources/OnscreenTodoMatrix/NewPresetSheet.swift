import OTMCore
import SwiftUI

/// New preset sheet (§11.7): account picker, name, JQL template chips and a live Test.
/// "Create & show" saves the preset, makes it active, closes Settings (which shows the panel and refreshes).
struct NewPresetSheet: View {
    @ObservedObject var model: AppModel
    let request: NewPresetRequest
    let onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var accountId = ""
    @State private var name = ""
    @State private var jql = ""
    @State private var test: JQLTestResult?
    @State private var testing = false

    private var trimmedJQL: String { jql.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New preset").font(.headline)
            Form {
                Picker("Account", selection: $accountId) {
                    ForEach(model.config.accounts) { account in Text(account.name).tag(account.id) }
                }
                TextField("Name", text: $name)
                if !name.trimmingCharacters(in: .whitespaces).isEmpty,
                   !model.config.isPresetNameValid(name, accountId: accountId) {
                    Text("A preset with this name already exists for this account.").font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    ForEach(JQLTemplate.all, id: \.title) { template in
                        Button(template.title) { apply(template) }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                TextField("JQL", text: $jql, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.system(.body, design: .monospaced))
                HStack {
                    Button("Test") { Task { await runTest() } }
                        .disabled(trimmedJQL.isEmpty || testing)
                    if testing { ProgressView().controlSize(.small) }
                    Text(test?.text ?? "").foregroundStyle(testColor).lineLimit(3)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create & show") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedJQL.isEmpty
                              || !model.config.canCreatePreset(name: name, accountId: accountId, lastTest: test))
            }
        }
        .padding(16)
        .frame(width: 600)
        .onAppear {
            accountId = request.accountId.flatMap { model.config.account(id: $0)?.id }
                ?? model.activeAccount?.id ?? model.config.accounts.first?.id ?? ""
        }
        .task(id: "\(accountId)\n\(jql)") {
            // Live Test: runs 600 ms after the last edit; editing clears the previous result.
            test = nil
            guard !trimmedJQL.isEmpty, !accountId.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            await runTest()
        }
    }

    private var testColor: Color {
        switch test {
        case .count?: return .green
        case .jqlError?, .failed?: return .orange
        case nil: return .secondary
        }
    }

    /// Fills the JQL; also the name while it is still empty ("Unassigned in project…" → "Unassigned in project").
    private func apply(_ template: JQLTemplate) {
        jql = template.jql
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            name = template.title.replacingOccurrences(of: "…", with: "")
        }
    }

    private func runTest() async {
        testing = true
        test = await model.testJQL(trimmedJQL, accountId: accountId)
        testing = false
    }

    private func create() {
        let preset = JQLPreset(id: UUID().uuidString, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                               jql: trimmedJQL, accountId: accountId)
        model.addPreset(preset, activate: true)
        dismiss()
        DispatchQueue.main.async(execute: onCreated) // close Settings once the sheet is gone
    }
}
