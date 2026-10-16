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
        .sheet(isPresented: $vm.showPhone) { PhoneSendSheet(model: model) }
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
            Button("Send to phone…") { vm.showPhone = true }
                .disabled(model.config.presets.isEmpty || model.config.accounts.isEmpty)
            if !vm.generalError.isEmpty { Text(vm.generalError).foregroundStyle(.red) }
            if model.configWasCorrupt {
                Text("Your previous config file was unreadable and was saved as config.json.bak.")
                    .foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
    }
}
