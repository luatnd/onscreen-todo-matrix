import AppKit
import CoreImage.CIFilterBuiltins
import OTMCore
import SwiftUI

/// "Send to phone…": shows a QR code and a one-time code for Glance Lite. Nothing is stored; closing wipes both.
struct PhoneSendSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var accountId = ""
    @State private var generated: Generated?
    @State private var error = ""
    @State private var busy = false
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    struct Generated {
        var link: URL
        var code: String
        var expires: Date
    }

    private var accounts: [JiraAccount] {
        model.config.accounts.filter { a in model.config.presets.contains { $0.accountId == a.id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Send to phone").font(.title3.bold())
            if let g = generated, now < g.expires {
                qrView(g)
            } else {
                form
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            url = model.config.phoneURL
            accountId = model.activeAccount?.id ?? accounts.first?.id ?? ""
        }
        .onReceive(tick) { now = $0 }
        .onDisappear { generated = nil }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            if generated != nil { Text("The code expired. Create a new one.").foregroundStyle(.orange) }
            Text("Glance Lite is the read-only web app for your iPhone. Settings of one account and its presets are sent, encrypted. Your Jira token is never sent.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Glance Lite address, e.g. glance-lite.you.workers.dev", text: $url)
                .textFieldStyle(.roundedBorder)
            if accounts.count > 1 {
                Picker("Account", selection: $accountId) { ForEach(accounts) { Text($0.name).tag($0.id) } }
            }
            Text("On the phone you will also paste a separate read-only API token (id.atlassian.com → Security → API tokens).")
                .font(.caption).foregroundStyle(.secondary)
            if !error.isEmpty { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(busy ? "Working…" : "Show QR code") { create() }
                    .keyboardShortcut(.defaultAction).disabled(busy || url.trimmingCharacters(in: .whitespaces).isEmpty || accountId.isEmpty)
            }
        }
    }

    private func qrView(_ g: Generated) -> some View {
        VStack(spacing: 10) {
            Image(nsImage: Self.qr(g.link.absoluteString)).interpolation(.none).resizable().frame(width: 320, height: 320)
                .background(Color.white).cornerRadius(6)
            Text("1. Scan with the iPhone camera and open the link").font(.callout)
            Text("2. Type this code on the phone").font(.callout)
            Text(PhoneExport.display(g.code)).font(.system(size: 30, weight: .bold, design: .monospaced)).textSelection(.enabled)
            Text("Expires in \(max(0, Int(g.expires.timeIntervalSince(now)))) s · the link alone is useless without the code")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Copy link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(g.link.absoluteString, forType: .string)
                }
                Spacer()
                Button("Done") { generated = nil; dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func create() {
        error = ""
        let base = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PhoneExport.link(base: base, blob: "x") != nil else { error = "Enter an https address."; return }
        var c = model.config
        c.phoneURL = base
        model.updateConfig(c)
        let config = model.config, id = accountId
        busy = true
        Task.detached {
            do {
                let code = try PhoneExport.makeCode()
                let blob = try PhoneExport.seal(config: config, accountId: id, code: code)
                guard let link = PhoneExport.link(base: base, blob: blob) else { throw PhoneExport.Failure.malformed }
                await MainActor.run {
                    generated = Generated(link: link, code: code, expires: Date().addingTimeInterval(PhoneExport.ttl))
                    now = Date(); busy = false
                }
            } catch {
                await MainActor.run { self.error = "Could not create the link (\(error))."; busy = false }
            }
        }
    }

    static func qr(_ text: String) -> NSImage {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage else { return NSImage() }
        let scaled = out.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let rep = NSCIImageRep(ciImage: scaled)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}
