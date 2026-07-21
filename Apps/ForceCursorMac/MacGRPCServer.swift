import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2TransportServices

struct MacGRPCState: Sendable {
    var summary: String
    var isListening: Bool
    var isConnected: Bool
}

private struct CursorRPCService: ForceCursorRPC.SimpleServiceProtocol {
    let inputHandler: @Sendable (ForceCursorInput) -> Void
    let stateHandler: @Sendable (MacGRPCState) -> Void

    func control(
        request: RPCAsyncSequence<ForceCursorInput, any Error>,
        response: RPCWriter<ForceCursorStatus>,
        context: ServerContext
    ) async throws {
        stateHandler(.init(summary: "Apple Watch connected", isListening: true, isConnected: true))

        var ready = ForceCursorStatus()
        ready.message = "ready"
        try await response.write(ready)

        do {
            for try await input in request {
                inputHandler(input)

                if input.action != .motion {
                    var acknowledgement = ForceCursorStatus()
                    acknowledgement.acceptedSequence = input.sequence
                    acknowledgement.message = "accepted"
                    try await response.write(acknowledgement)
                }
            }
        } catch {
            stateHandler(.init(summary: "Watch stream ended", isListening: true, isConnected: false))
            throw error
        }

        stateHandler(.init(summary: "Waiting for Apple Watch", isListening: true, isConnected: false))
    }
}

final class MacGRPCServer: @unchecked Sendable {
    typealias InputHandler = @Sendable (ForceCursorInput) -> Void
    typealias StateHandler = @Sendable (MacGRPCState) -> Void

    private let port: Int
    private let inputHandler: InputHandler
    private let stateHandler: StateHandler
    private var serverTask: Task<Void, Never>?

    init(port: Int, inputHandler: @escaping InputHandler, stateHandler: @escaping StateHandler) {
        self.port = port
        self.inputHandler = inputHandler
        self.stateHandler = stateHandler
    }

    func start() {
        guard serverTask == nil else { return }

        let port = self.port
        let inputHandler = self.inputHandler
        let stateHandler = self.stateHandler
        serverTask = Task.detached(priority: .userInitiated) {
            let service = CursorRPCService(inputHandler: inputHandler, stateHandler: stateHandler)
            let server = GRPCServer(
                transport: .http2NIOTS(
                    address: .ipv4(host: "0.0.0.0", port: port),
                    transportSecurity: .plaintext
                ),
                services: [service]
            )

            stateHandler(.init(
                summary: "Waiting for Apple Watch",
                isListening: true,
                isConnected: false
            ))

            do {
                try await server.serve()
            } catch {
                stateHandler(.init(
                    summary: "gRPC server failed: \(error.localizedDescription)",
                    isListening: false,
                    isConnected: false
                ))
            }
        }
    }
}
