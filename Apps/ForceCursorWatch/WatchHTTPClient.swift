import Foundation
import SwiftProtobuf

struct WatchHTTPState: Sendable {
    var summary: String
    var isConnecting: Bool
    var isConnected: Bool
}

private enum WatchHTTPError: LocalizedError {
    case invalidAddress
    case unexpectedStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            "Enter a valid Mac IPv4 address"
        case .unexpectedStatus(let status):
            "Mac returned HTTP \(status)"
        }
    }
}

@MainActor
final class WatchHTTPClient {
    typealias StateHandler = @Sendable (WatchHTTPState) -> Void

    private let stateHandler: StateHandler
    private var session: URLSession?
    private var baseURL: URL?
    private var connectionID = UUID()
    private var connectionTask: Task<Void, Never>?
    private var drainTask: Task<Void, Never>?
    private var queuedCommands: [ForceCursorInput] = []
    private var latestMotion: ForceCursorInput?
    private var isConnected = false

    init(stateHandler: @escaping StateHandler) {
        self.stateHandler = stateHandler
    }

    func connect(host: String, port: Int) {
        disconnect(emitState: false)

        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        guard let baseURL = components.url else {
            stateHandler(.init(
                summary: WatchHTTPError.invalidAddress.localizedDescription,
                isConnecting: false,
                isConnected: false
            ))
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 6
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 1

        let session = URLSession(configuration: configuration)
        let connectionID = UUID()
        self.session = session
        self.baseURL = baseURL
        self.connectionID = connectionID
        stateHandler(.init(summary: "Connecting to Mac…", isConnecting: true, isConnected: false))

        connectionTask = Task { [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: baseURL.appending(path: "health"))
                request.httpMethod = "GET"
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (_, response) = try await session.data(for: request)
                try Self.validate(response, expectedStatus: 200)

                guard self.connectionID == connectionID else { return }
                self.isConnected = true
                self.stateHandler(.init(
                    summary: "Connected to Mac",
                    isConnecting: false,
                    isConnected: true
                ))
            } catch {
                guard self.connectionID == connectionID, !Task.isCancelled else { return }
                self.handleFailure(error, prefix: "Connection failed")
            }
        }
    }

    func send(_ input: ForceCursorInput) {
        guard isConnected, session != nil, baseURL != nil else { return }

        if input.action == .motion {
            if var accumulatedMotion = latestMotion {
                accumulatedMotion.sequence = input.sequence
                accumulatedMotion.timestampNanoseconds = input.timestampNanoseconds
                accumulatedMotion.x += input.x
                accumulatedMotion.y += input.y
                latestMotion = accumulatedMotion
            } else {
                latestMotion = input
            }
        } else {
            if let latestMotion {
                queuedCommands.append(latestMotion)
                self.latestMotion = nil
            }
            queuedCommands.append(input)
        }

        startDrainingIfNeeded()
    }

    func disconnect() {
        disconnect(emitState: true)
    }

    private func startDrainingIfNeeded() {
        guard drainTask == nil, let session, let baseURL else { return }
        let connectionID = self.connectionID

        drainTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled, self.connectionID == connectionID {
                guard let input = self.nextInput() else { break }

                do {
                    var request = URLRequest(url: baseURL.appending(path: "control"))
                    request.httpMethod = "POST"
                    request.setValue("application/x-protobuf", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try input.serializedData()
                    let (_, response) = try await session.data(for: request)
                    try Self.validate(response, expectedStatus: 204)

                    if input.action == .motion {
                        try await Task.sleep(for: .milliseconds(33))
                    }
                } catch is CancellationError {
                    break
                } catch {
                    guard self.connectionID == connectionID, !Task.isCancelled else { return }
                    self.handleFailure(error, prefix: "Control request failed")
                    return
                }
            }

            guard self.connectionID == connectionID else { return }
            self.drainTask = nil
            if !self.queuedCommands.isEmpty || self.latestMotion != nil {
                self.startDrainingIfNeeded()
            }
        }
    }

    private func nextInput() -> ForceCursorInput? {
        if !queuedCommands.isEmpty {
            return queuedCommands.removeFirst()
        }

        defer { latestMotion = nil }
        return latestMotion
    }

    private func handleFailure(_ error: Error, prefix: String) {
        isConnected = false
        queuedCommands.removeAll(keepingCapacity: true)
        latestMotion = nil
        stateHandler(.init(
            summary: "\(prefix): \(error.localizedDescription)",
            isConnecting: false,
            isConnected: false
        ))
    }

    private func disconnect(emitState: Bool) {
        connectionID = UUID()
        isConnected = false
        connectionTask?.cancel()
        connectionTask = nil
        drainTask?.cancel()
        drainTask = nil
        queuedCommands.removeAll(keepingCapacity: true)
        latestMotion = nil
        session?.invalidateAndCancel()
        session = nil
        baseURL = nil

        if emitState {
            stateHandler(.init(summary: "Disconnected", isConnecting: false, isConnected: false))
        }
    }

    private static func validate(_ response: URLResponse, expectedStatus: Int) throws {
        guard let response = response as? HTTPURLResponse else {
            throw WatchHTTPError.unexpectedStatus(0)
        }
        guard response.statusCode == expectedStatus else {
            throw WatchHTTPError.unexpectedStatus(response.statusCode)
        }
    }
}
