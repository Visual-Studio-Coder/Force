import SwiftUI

struct WatchContentView: View {
    @Bindable var model: WatchAppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Label(
                    model.connectionState,
                    systemImage: model.isConnected ? "desktopcomputer" : "antenna.radiowaves.left.and.right"
                )
                .font(.footnote)
                .foregroundStyle(model.isConnected ? .green : .secondary)
                .multilineTextAlignment(.center)

                TextField("Mac IP address", text: $model.host)
                    .font(.caption.monospaced())
                    .textInputAutocapitalization(.never)

                Button(model.isConnected || model.isConnecting ? "Disconnect" : "Connect") {
                    model.toggleConnection()
                }
                .disabled(model.host.isEmpty && !model.isConnected && !model.isConnecting)

                Button {
                    model.toggleCursor()
                } label: {
                    Label(
                        model.isCursorActive ? "Stop Cursor" : "Start Cursor",
                        systemImage: model.isCursorActive ? "stop.fill" : "cursorarrow.motionlines"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isCursorActive ? .red : .blue)
                .disabled(!model.isConnected)

                HStack {
                    Button {
                        model.leftClick()
                    } label: {
                        Image(systemName: "cursorarrow.click")
                    }
                    .accessibilityLabel("Left click")

                    Button {
                        model.rightClick()
                    } label: {
                        Image(systemName: "contextualmenu.and.cursorarrow")
                    }
                    .accessibilityLabel("Right click")
                }
                .disabled(!model.isConnected)

                VStack(spacing: 4) {
                    Text("Sensitivity \(model.sensitivity, specifier: "%.1f")")
                        .font(.caption2)
                    Slider(value: $model.sensitivity, in: 1...14, step: 0.5)
                }

                Text(model.lastMotion)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
        .onDisappear { model.stopCursor() }
    }
}
