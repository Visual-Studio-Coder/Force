import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2TransportServices

struct WatchGRPCState: Sendable {
    var summary: String
    var isConnecting: Bool
    var isConnected: Bool
}

@MainActor
final class WatchGRPCClient {
    typealias StateHandler = @Sendable (WatchGRPCState) -> Void

    private let stateHandler: StateHandler
    private var inputContinuation: AsyncStream<ForceCursorInput>.Continuation?
    private var connectionsTask: Task<Void, Never>?
    private var controlTask: Task<Void, Never>?
    private var client: GRPCClient<HTTP2ClientTransport.TransportServices>?

    init(stateHandler: @escaping StateHandler) {
        self.stateHandler = stateHandler
    }

    func connect(host: String, port: Int) {
        disconnect(emitState: false)
        stateHandler(.init(summary: "Connecting to Mac…", isConnecting: true, isConnected: false))

        do {
            let transport = try HTTP2ClientTransport.TransportServices.http2NIOTS(
                target: .ipv4(address: host, port: port),
                transportSecurity: .plaintext
            )
            let client = GRPCClient(transport: transport)
            let (inputStream, inputContinuation) = AsyncStream.makeStream(
                of: ForceCursorInput.self,
                bufferingPolicy: .unbounded
            )

            self.client = client
            self.inputContinuation = inputContinuation

            connectionsTask = Task {
                do {
                    try await client.runConnections()
                } catch is CancellationError {
                    return
                } catch {
                    stateHandler(.init(
                        summary: "Connection failed: \(error.localizedDescription)",
                        isConnecting: false,
                        isConnected: false
                    ))
                }
            }

            controlTask = Task {
                let cursor = ForceCursorRPC.Client(wrapping: client)
                do {
                    try await cursor.control { requestStream in
                        for await input in inputStream {
                            try await requestStream.write(input)
                        }
                    } onResponse: { responseStream in
                        for try await status in responseStream.messages {
                            let summary = status.message == "ready" ? "Connected to Mac" : "Connected"
                            self.stateHandler(.init(
                                summary: summary,
                                isConnecting: false,
                                isConnected: true
                            ))
                        }
                    }
                } catch is CancellationError {
                    return
                } catch {
                    stateHandler(.init(
                        summary: "Control stream failed: \(error.localizedDescription)",
                        isConnecting: false,
                        isConnected: false
                    ))
                }
            }
        } catch {
            stateHandler(.init(
                summary: "Invalid Mac address: \(error.localizedDescription)",
                isConnecting: false,
                isConnected: false
            ))
        }
    }

    func send(_ input: ForceCursorInput) {
        inputContinuation?.yield(input)
    }

    func disconnect() {
        disconnect(emitState: true)
    }

    private func disconnect(emitState: Bool) {
        inputContinuation?.finish()
        inputContinuation = nil
        controlTask?.cancel()
        controlTask = nil
        connectionsTask?.cancel()
        connectionsTask = nil
        client?.beginGracefulShutdown()
        client = nil

        if emitState {
            stateHandler(.init(summary: "Disconnected", isConnecting: false, isConnected: false))
        }
    }
}
