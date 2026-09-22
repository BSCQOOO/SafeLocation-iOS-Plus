import Foundation
import Network

final class PairableHostAdvertiser {
    private var listener: NWListener?
    private var activeRelay: RelayPipe?
    private var rustLoopbackPort: UInt16 = 0

    func publish(
        port: UInt16,
        serviceIdentifier: String,
        name: String,
        model: String,
        authTag: String,
        ver: String,
        minVer: String
    ) {
        stop()
        rustLoopbackPort = port

        var txt = NWTXTRecord()
        txt["name"] = name
        txt["identifier"] = serviceIdentifier
        txt["authTag"] = authTag
        txt["model"] = model
        txt["flags"] = "1"
        txt["ver"] = ver
        txt["minVer"] = minVer

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.includePeerToPeer = true
            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(
                name: serviceIdentifier,
                type: "_remotepairing-pairable-host._tcp",
                domain: "local",
                txtRecord: txt
            )
            listener.newConnectionHandler = { [weak self] connection in self?.relay(connection) }
            listener.start(queue: .global(qos: .userInitiated))
            self.listener = listener
        } catch {
            NSLog("[SafeLocation] advertiser failed: %@", error.localizedDescription)
        }
    }

    func stop() {
        activeRelay?.cancel()
        activeRelay = nil
        listener?.cancel()
        listener = nil
    }

    private func relay(_ inbound: NWConnection) {
        activeRelay?.cancel()
        guard rustLoopbackPort > 0, let port = NWEndpoint.Port(rawValue: rustLoopbackPort) else {
            inbound.cancel()
            return
        }
        let outbound = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        let pipe = RelayPipe(inbound: inbound, outbound: outbound)
        activeRelay = pipe
        pipe.start()
    }
}

private final class RelayPipe {
    private let inbound: NWConnection
    private let outbound: NWConnection
    private let queue = DispatchQueue(label: "safelocation.pairable.relay")

    init(inbound: NWConnection, outbound: NWConnection) {
        self.inbound = inbound
        self.outbound = outbound
    }

    func start() {
        inbound.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.cancel() }
            if case .cancelled = state { self?.cancel() }
        }
        outbound.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.pump(from: self.inbound, to: self.outbound)
                self.pump(from: self.outbound, to: self.inbound)
            case .failed, .cancelled:
                self.cancel()
            default:
                break
            }
        }
        inbound.start(queue: queue)
        outbound.start(queue: queue)
    }

    func cancel() {
        inbound.cancel()
        outbound.cancel()
    }

    private func pump(from: NWConnection, to: NWConnection) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil { self.cancel(); return }
            if let data, !data.isEmpty {
                to.send(content: data, completion: .contentProcessed { sendError in
                    if sendError != nil || isComplete { self.cancel() }
                    else { self.pump(from: from, to: to) }
                })
            } else if isComplete {
                self.cancel()
            } else {
                self.pump(from: from, to: to)
            }
        }
    }
}
