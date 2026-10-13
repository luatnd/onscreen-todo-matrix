import OTMCore
import SwiftUI

extension Color {
    /// "#rrggbb" (AccountPalette).
    init(hex: String) {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0x6b7895
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
}

/// The account's stable colour dot (same palette and order as the panel's preset menu).
struct AccountDot: View {
    let color: String
    var body: some View { Circle().fill(Color(hex: color)).frame(width: 9, height: 9) }
}

/// Form state for adding (id == nil) or editing one account.
struct AccountDraft: Equatable {
    var id: String?
    var name = ""
    var site = ""
    var email = ""
    var token = ""
}

/// Accounts tab (§11.7): list with status, + Add account, Edit, Remove (with confirmation).
struct AccountsTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var vm: SettingsViewModel
    @State private var draft: AccountDraft?
    @State private var status: [String: String] = [:]
    @State private var formMessage = ""
    @State private var busy = false
    @State private var confirmRemove: JiraAccount?

    var body: some View {
        Form {
            if let form = Binding($draft) {
                accountForm(form)
            } else {
                accountList
            }
            Text("API tokens are stored only in your macOS Keychain. The app only reads from Jira.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear(perform: openRequestedForm)
        .onChange(of: vm.editAccountId) { openRequestedForm() }
        .task { await testAccounts() }
        .confirmationDialog(
            "Remove \(confirmRemove?.name ?? "")?",
            isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }),
            presenting: confirmRemove
        ) { account in
            Button("Remove", role: .destructive) {
                model.removeAccount(id: account.id)
                status[account.id] = nil
            }
        } message: { _ in
            Text("Its presets and its API token in the Keychain are deleted too.")
        }
    }

    // MARK: - List

    private var accountList: some View {
        Section("Accounts") {
            ForEach(Array(model.config.accounts.enumerated()), id: \.element.id) { index, account in
                accountRow(account, color: AccountPalette.color(at: index))
            }
            Button("+ Add account") {
                formMessage = ""
                draft = AccountDraft()
            }
        }
    }

    private func accountRow(_ account: JiraAccount, color: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                AccountDot(color: color)
                Text(account.name).fontWeight(.medium)
                Text(account.site).foregroundStyle(.secondary)
                Spacer()
                Button("Edit") { edit(account) }
                Button("Remove", role: .destructive) { confirmRemove = account }
            }
            let line = statusLine(account)
            if !line.isEmpty {
                Text(line).font(.caption).foregroundStyle(line.hasPrefix("Connected as") ? .green : .orange)
            }
            if !account.axes.isComplete {
                Button("Map axes for \(account.name)") {
                    vm.axesAccountId = account.id
                    vm.tab = .axes
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func statusLine(_ account: JiraAccount) -> String {
        if model.hasError(accountId: account.id) { return "Jira sign-in failed" }
        if let s = status[account.id] { return s }
        return model.hasCredentials(account) ? "" : "Not connected"
    }

    // MARK: - Form

    private func accountForm(_ d: Binding<AccountDraft>) -> some View {
        Section(d.wrappedValue.id == nil ? "Add account" : "Edit account") {
            TextField("Name", text: d.name, prompt: Text("Personal, Company…"))
            TextField("Jira site", text: d.site, prompt: Text("your-company.atlassian.net"))
            TextField("Email", text: d.email)
            SecureField("API token", text: d.token)
            Link("Create an API token at id.atlassian.com",
                 destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!)
                .font(.caption)
            if !d.wrappedValue.name.trimmingCharacters(in: .whitespaces).isEmpty,
               !model.config.isAccountNameValid(d.wrappedValue.name, excludingId: d.wrappedValue.id) {
                Text("An account with this name already exists.").font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button("Save & Test") { Task { await saveAndTest(d.wrappedValue) } }
                    .disabled(busy || !canSave(d.wrappedValue))
                if busy { ProgressView().controlSize(.small) }
                Text(formMessage).foregroundStyle(.secondary)
                Spacer()
                if !model.config.accounts.isEmpty {
                    Button("Cancel") {
                        draft = nil
                        vm.editAccountId = nil
                    }
                }
            }
        }
    }

    private func canSave(_ d: AccountDraft) -> Bool {
        model.config.isAccountNameValid(d.name, excludingId: d.id)
            && AppConfig.normalizeSite(d.site) != nil
            && !d.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !d.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func edit(_ account: JiraAccount) {
        formMessage = ""
        draft = AccountDraft(id: account.id, name: account.name, site: account.site, email: account.email,
                             token: model.storedToken(accountId: account.id) ?? "")
    }

    /// Opens the form the panel asked for (vm.editAccountId), or the Add form when there is no account yet.
    private func openRequestedForm() {
        if let id = vm.editAccountId, let account = model.config.account(id: id) {
            edit(account)
        } else if model.config.accounts.isEmpty, draft == nil {
            draft = AccountDraft(name: "Personal")
        }
    }

    /// Trims, saves the account + Keychain token, then calls /myself. Success closes the form.
    private func saveAndTest(_ d: AccountDraft) async {
        busy = true
        defer { busy = false }
        let id = d.id ?? model.newAccountId()
        var account = model.config.account(id: id) ?? JiraAccount(id: id, name: "")
        account.name = d.name.trimmingCharacters(in: .whitespacesAndNewlines)
        account.site = d.site.trimmingCharacters(in: .whitespacesAndNewlines)
        account.email = d.email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try model.saveAccount(account, token: d.token.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            formMessage = "Could not save token to Keychain: \(error.localizedDescription)"
            return
        }
        draft?.id = id // a second Save & Test edits this account instead of adding another
        do {
            let me = try await model.makeAPI(accountId: id).myself()
            status[id] = "Connected as \(me.displayName)"
            draft = nil
            vm.editAccountId = nil
            formMessage = ""
            if model.activeAccount?.id == id { await model.refresh(.manual) }
        } catch {
            formMessage = SettingsViewModel.describe(error)
        }
    }

    /// Fills "Connected as …" for every account that has credentials.
    private func testAccounts() async {
        for account in model.config.accounts where model.hasCredentials(account) && status[account.id] == nil {
            do {
                let me = try await model.makeAPI(accountId: account.id).myself()
                status[account.id] = "Connected as \(me.displayName)"
            } catch {
                status[account.id] = SettingsViewModel.describe(error)
            }
        }
    }
}
