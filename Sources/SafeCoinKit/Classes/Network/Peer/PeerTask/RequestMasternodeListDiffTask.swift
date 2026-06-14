import BitcoinCore
import Foundation
import HsExtensions

class RequestMasternodeListDiffTask: PeerTask {
    let baseBlockHash: Data
    let blockHash: Data

    // Holds the raw response wrapped in a lazy envelope. The full parse is
    // deferred until the syncer dispatches it to its processing queue.
    private var envelope: MasternodeListDiffMessageEnvelope?

    /// Exposes the envelope without triggering the heavy parse. Callers that
    /// want to do the parse on a background queue should read this and call
    /// `.value` from that queue.
    var masternodeListDiffMessageEnvelope: MasternodeListDiffMessageEnvelope? {
        return envelope
    }

    init(baseBlockHash: Data, blockHash: Data) {
        self.baseBlockHash = baseBlockHash
        self.blockHash = blockHash
    }

    override func start() {
        let message = GetMasternodeListDiffMessage(baseBlockHash: baseBlockHash, blockHash: blockHash)

        requester?.send(message: message)

        super.start()
    }

    override func handle(message: IMessage) -> Bool {
        // Match against the eagerly-parsed header on the envelope. This keeps
        // request matching cheap on the peer event thread.
        if let env = message as? MasternodeListDiffMessageEnvelope,
           env.baseBlockHash == baseBlockHash,
           env.blockHash == blockHash {
            envelope = env

            delegate?.handle(completedTask: self)
            return true
        }
        return false
    }
}
