import SwiftData
import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(SettingsManager.self) private var settings
    @Query private var snippets: [Snippet]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)
                Text("Keyed")
                    .fontWeight(.semibold)
                Spacer()
                Toggle("", isOn: Bindable(settings).isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            Divider()

            HStack {
                Text("\(snippets.count) snippets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Button("Open Keyed...") {
                openMainWindow()
            }

            Divider()

            Button("Quit Keyed") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 240)
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Keyed" || $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            // Open settings window as fallback (the main window)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}
