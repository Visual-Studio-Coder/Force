import Foundation
@preconcurrency import Network
import SwiftProtobuf

struct MacHTTPState: Sendable {
    var summary: String
    var isListening: Bool
    var isConnected: Bool
}

final class MacHTTPServer: @unchecked Sendable {
    typealias InputHandler = @Sendable (ForceCursorInput) -> Void
    typealias StateHandler = @Sendable (MacHTTPState) -> Void

    private let port: UInt16
    private let inputHandler: InputHandler
    private let stateHandler: StateHandler
    private let queue = DispatchQueue(label: "ForceCursor.HTTPServer", qos: .userInteractive)
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: HTTPConnection] = [:]

    init(port: Int, inputHandler: @escaping InputHandler, stateHandler: @escaping StateHandler) {
        self.port = UInt16(port)
        self.inputHandler = inputHandler
        self.stateHandler = stateHandler
    }

    func start() {
        queue.async { [self] in
            guard listener == nil, let endpointPort = NWEndpoint.Port(rawValue: port) else { return }

            do {
                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true
                let listener = try NWListener(using: parameters, on: endpointPort)
                self.listener = listener

                listener.stateUpdateHandler = { [weak self] state in
                    self?.handleListenerState(state)
                }
                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                listener.start(queue: queue)
            } catch {
                stateHandler(.init(
                    summary: "HTTP server failed: \(error.localizedDescription)",
                    isListening: false,
                    isConnected: false
                ))
            }
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            stateHandler(.init(
                summary: "Waiting for Apple Watch",
                isListening: true,
                isConnected: !connections.isEmpty
            ))
        case .failed(let error):
            stateHandler(.init(
                summary: "HTTP server failed: \(error.localizedDescription)",
                isListening: false,
                isConnected: false
            ))
            listener?.cancel()
            listener = nil
        case .cancelled:
            stateHandler(.init(summary: "HTTP server stopped", isListening: false, isConnected: false))
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        let identifier = ObjectIdentifier(connection)
        let httpConnection = HTTPConnection(
            connection: connection,
            queue: queue,
            inputHandler: inputHandler
        ) { [weak self] in
            self?.removeConnection(identifier)
        }

        connections[identifier] = httpConnection
        stateHandler(.init(summary: "Apple Watch connected", isListening: true, isConnected: true))
        httpConnection.start()
    }

    private func removeConnection(_ identifier: ObjectIdentifier) {
        connections[identifier] = nil
        guard connections.isEmpty else { return }
        stateHandler(.init(summary: "Waiting for Apple Watch", isListening: true, isConnected: false))
    }
}

private final class HTTPConnection: @unchecked Sendable {
    private struct Request {
        var method: String
        var path: String
        var body: Data
    }

    private enum ParseResult {
        case incomplete
        case request(Request)
        case invalid(String)
    }

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let inputHandler: MacHTTPServer.InputHandler
    private let onClose: @Sendable () -> Void
    private var buffer = Data()
    private var isFinished = false

    init(
        connection: NWConnection,
        queue: DispatchQueue,
        inputHandler: @escaping MacHTTPServer.InputHandler,
        onClose: @escaping @Sendable () -> Void
    ) {
        self.connection = connection
        self.queue = queue
        self.inputHandler = inputHandler
        self.onClose = onClose
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                receiveNextChunk()
            case .failed, .cancelled:
                finish()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveNextChunk() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self, !isFinished else { return }

            if let data, !data.isEmpty {
                buffer.append(data)
                processBufferedRequests()
            }

            if error != nil || isComplete {
                finish()
            } else if !isFinished {
                receiveNextChunk()
            }
        }
    }

    private func processBufferedRequests() {
        guard buffer.count <= 131_072 else {
            send(status: 413, reason: "Payload Too Large", body: "Request too large", close: true)
            return
        }

        while !isFinished {
            switch parseRequest() {
            case .incomplete:
                return
            case .invalid(let message):
                send(status: 400, reason: "Bad Request", body: message, close: true)
                return
            case .request(let request):
                handle(request)
            }
        }
    }

    private func parseRequest() -> ParseResult {
        let delimiter = Data([13, 10, 13, 10])
        guard let headerRange = buffer.range(of: delimiter) else { return .incomplete }

        let headerData = buffer.subdata(in: buffer.startIndex..<headerRange.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return .invalid("Headers must be UTF-8")
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return .invalid("Missing request line") }
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count == 3 else { return .invalid("Invalid request line") }

        var contentLength = 0
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            if parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                guard let length = Int(parts[1].trimmingCharacters(in: .whitespaces)), length >= 0 else {
                    return .invalid("Invalid Content-Length")
                }
                contentLength = length
            }
        }

        guard contentLength <= 65_536 else { return .invalid("Body too large") }
        let bodyStart = headerRange.upperBound
        let bodyEnd = bodyStart + contentLength
        guard buffer.endIndex >= bodyEnd else { return .incomplete }

        let body = buffer.subdata(in: bodyStart..<bodyEnd)
        buffer.removeSubrange(buffer.startIndex..<bodyEnd)

        return .request(.init(
            method: String(requestParts[0]),
            path: String(requestParts[1]),
            body: body
        ))
    }

    private func handle(_ request: Request) {
        switch (request.method, request.path) {
        case ("GET", "/health"):
            send(status: 200, reason: "OK", body: "ok")
        case ("POST", "/control"):
            do {
                let input = try ForceCursorInput(serializedBytes: request.body)
                inputHandler(input)
                send(status: 204, reason: "No Content")
            } catch {
                send(status: 400, reason: "Bad Request", body: "Invalid protobuf payload")
            }
        default:
            send(status: 404, reason: "Not Found", body: "Not found")
        }
    }

    private func send(
        status: Int,
        reason: String,
        body: String = "",
        close: Bool = false
    ) {
        let bodyData = Data(body.utf8)
        let connectionValue = close ? "close" : "keep-alive"
        let header = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Length: \(bodyData.count)\r
        Content-Type: text/plain; charset=utf-8\r
        Cache-Control: no-store\r
        Connection: \(connectionValue)\r
        \r

        """

        var response = Data(header.utf8)
        response.append(bodyData)
        connection.send(content: response, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil || close {
                finish()
            }
        })
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        connection.stateUpdateHandler = nil
        connection.cancel()
        onClose()
    }
}
