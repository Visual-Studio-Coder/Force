import SwiftUI

struct MacContentView: View {
    let model: MacAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: model.isWatchConnected ? "applewatch.radiowaves.left.and.right" : "applewatch")
                    .font(.system(size: 38))
                    .foregroundStyle(model.isWatchConnected ? .green : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("ForceCursor")
                        .font(.largeTitle.bold())
                    Text(model.connectionSummary)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox("1. Accessibility") {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        model.accessibilityGranted ? "Permission granted" : "Permission required",
                        systemImage: model.accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(model.accessibilityGranted ? .green : .orange)

                    Text("macOS requires Accessibility permission before ForceCursor can post pointer and click events.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button("Request Permission") { model.requestAccessibility() }
                        Button("Refresh") { model.refreshAccessibility() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox("2. Test the Mac client") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Verify local cursor control before involving the Watch.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Move right 80 px") { model.testMovement() }
                        Button("Left click") { model.testClick() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            GroupBox("3. Connect the Watch") {
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Mac address", value: "\(model.localAddress):\(model.port)")
                    LabeledContent("gRPC server", value: model.serverState)
                    LabeledContent("Latest event", value: model.lastInputDescription)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            Spacer()
        }
        .padding(24)
        .onAppear { model.refreshAccessibility() }
    }
}
