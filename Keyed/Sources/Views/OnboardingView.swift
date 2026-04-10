import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SnippetStore.self) private var store
    let accessibilityService: AccessibilityService
    let initialStep: OnboardingStep
    @State private var step: OnboardingStep

    init(
        accessibilityService: AccessibilityService,
        initialStep: OnboardingStep = .welcome
    ) {
        self.accessibilityService = accessibilityService
        self.initialStep = initialStep
        _step = State(initialValue: initialStep)
    }

    enum OnboardingStep {
        case welcome
        case accessibility
        case starterSnippets
        case done
    }

    var body: some View {
        VStack(spacing: 24) {
            switch step {
            case .welcome:
                welcomeStep
            case .accessibility:
                accessibilityStep
            case .starterSnippets:
                starterSnippetsStep
            case .done:
                doneStep
            }
        }
        .padding(40)
        .frame(width: 480, height: 400)
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Welcome to Keyed")
                .font(.title)
                .fontWeight(.semibold)
            Text(
                "A lightweight text expansion tool for your Mac. Type a short abbreviation, and Keyed replaces it with the full text — everywhere."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            Spacer()
            Button("Get Started") { step = .accessibility }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private var accessibilityStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(initialStep == .accessibility ? "Permission Required" : "Accessibility Permission")
                .font(.title2)
                .fontWeight(.semibold)
            Text(
                initialStep == .accessibility
                    ? "Keyed needs Accessibility permission to detect what you type and replace abbreviations. Without it, text expansion cannot work. This happens entirely on your device — nothing leaves your Mac."
                    : "Keyed uses macOS Accessibility to detect what you type and replace abbreviations with your saved snippets. This happens entirely on your device. Nothing leaves your Mac."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            Spacer()
            if accessibilityService.isTrusted {
                Label("Permission granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Button(initialStep == .accessibility ? "Done" : "Continue") {
                    if initialStep == .accessibility {
                        dismiss()
                    } else {
                        step = .starterSnippets
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Grant Permission") {
                    accessibilityService.requestTrust()
                    Task {
                        for _ in 0..<60 {
                            try? await Task.sleep(for: .seconds(1))
                            accessibilityService.refresh()
                            if accessibilityService.isTrusted { return }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Open System Settings") {
                    accessibilityService.openSystemSettings()
                }

                if initialStep != .accessibility {
                    Button("Skip for now") { step = .starterSnippets }
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { accessibilityService.refresh() }
    }

    private var starterSnippetsStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Starter Snippets")
                .font(.title2)
                .fontWeight(.semibold)
            Text("We'll create a few example snippets to get you started. You can edit or delete them anytime.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                starterRow(abbreviation: "::email", expansion: "your@email.com")
                starterRow(abbreviation: "::sig", expansion: "Best regards,\nYour Name")
                starterRow(abbreviation: "::date", expansion: "{date}")
            }
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            Spacer()
            Button("Create Snippets") {
                createStarterSnippets()
                step = .done
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Skip") { step = .done }
                .foregroundStyle(.secondary)
        }
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("You're all set!")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Keyed is running in your menu bar. Type any abbreviation to expand it.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private func starterRow(abbreviation: String, expansion: String) -> some View {
        HStack {
            Text(abbreviation)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            Text(expansion)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private struct StarterSnippet {
        let abbreviation: String
        let expansion: String
        let label: String
    }

    private func createStarterSnippets() {
        let starters: [StarterSnippet] = [
            StarterSnippet(abbreviation: "::email", expansion: "your@email.com", label: "Email address"),
            StarterSnippet(
                abbreviation: "::sig",
                expansion: "Best regards,\nYour Name",
                label: "Email signature"
            ),
            StarterSnippet(abbreviation: "::date", expansion: "{date}", label: "Today's date"),
            StarterSnippet(abbreviation: "::shrug", expansion: "¯\\_(ツ)_/¯", label: "Shrug"),
        ]
        for starter in starters {
            _ = try? store.addSnippet(
                abbreviation: starter.abbreviation,
                expansion: starter.expansion,
                label: starter.label,
                groupID: nil
            )
        }
    }
}
