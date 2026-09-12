import Foundation
import Network

/// One datagram, one deadline, one continuation; all completion paths are serialized.
private final class NTPQuery: @unchecked Sendable {
    private let host: String
    private let queue = DispatchQueue(label: "clock.ntp.query", qos: .userInitiated)
    private var connection: NWConnection?
    private var continuation: CheckedContinuation<TimeSample, Error>?
    private var deadline: DispatchWorkItem?
    private var finished = false
    private var sent = false
    init(host: String) { self.host = host }

    func run() async throws -> TimeSample {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    guard !self.finished else { continuation.resume(throwing: CancellationError()); return }
                    self.continuation = continuation
                    let connection = NWConnection(host: NWEndpoint.Host(self.host), port: 123, using: .udp)
                    self.connection = connection
                    connection.stateUpdateHandler = { [weak self] state in
                        guard let self else { return }
                        switch state {
                        case .ready: self.send()
                        case .failed(let error): self.finish(.failure(error))
                        default: break
                        }
                    }
                    let deadline = DispatchWorkItem { [weak self] in
                        self?.finish(.failure(URLError(.timedOut)))
                    }
                    self.deadline = deadline
                    self.queue.asyncAfter(deadline: .now() + 4, execute: deadline)
                    connection.start(queue: self.queue)
                }
            }
        }, onCancel: { self.queue.async { self.finish(.failure(CancellationError())) } })
    }
    private func send() {
        guard !sent, !finished, let connection else { return }
        sent = true
        let t1 = Date().timeIntervalSince1970
        let start = ContinuousSeconds.now
        let request = SNTP.request(at: t1)
        connection.send(content: Data(request), completion: .contentProcessed { [weak self] error in
            if let error { self?.finish(.failure(error)) }
        })
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self, !self.finished else { return }
            let end = ContinuousSeconds.now
            if let error { self.finish(.failure(error)); return }
            guard let data else { self.finish(.failure(TimeValidationError.invalidPacket)); return }
            do {
                // Reconstruct t4 from elapsed time; a wall-clock correction during the query must not corrupt RTT.
                let sample = try SNTP.parse(Array(data), request: request, sent: t1,
                                            received: t1 + end - start, continuous: end, host: self.host)
                self.finish(.success(sample))
            } catch { self.finish(.failure(error)) }
        }
    }
    private func finish(_ result: Result<TimeSample, Error>) {
        guard !finished else { return }
        finished = true
        deadline?.cancel(); deadline = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel(); connection = nil
        let callback = continuation; continuation = nil
        callback?.resume(with: result)
    }
}

enum NetworkTime {
    static func synchronize() async throws -> TimeSample {
        let samples = await withTaskGroup(of: TimeSample?.self, returning: [TimeSample].self) { group in
            for host in ["time.apple.com", "time.cloudflare.com", "ntp.aliyun.com"] {
                group.addTask { try? await NTPQuery(host: host).run() }
            }
            var samples: [TimeSample] = []
            for await sample in group { if let sample { samples.append(sample) } }
            return samples
        }
        try Task.checkCancellation()
        guard !samples.isEmpty else { throw URLError(.cannotConnectToHost) }
        return try SNTP.select(samples)
    }
}
