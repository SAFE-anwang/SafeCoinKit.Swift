import BitcoinCore
import Foundation
import HsExtensions

/// Lazy wrapper around the raw bytes of a `mnlistdiff` P2P message.
///
/// `MasternodeListDiffMessageParser.parse(data:)` is called on BitcoinCore's
/// peer event thread (which can be the main thread). For a single DIP-3 diff
/// message containing 1000+ masternodes and 100+ quorums, the full parse
/// (1000+ SHA256 chains + 1000+ `Masternode` allocations + 100+ `Quorum`
/// allocations) blocks that thread for hundreds of milliseconds.
///
/// This envelope defers all of that work until `.value` is first accessed.
/// The header (first 64 bytes: `baseBlockHash` + `blockHash`) is read eagerly
/// so the request/task routing layer can match the response without triggering
/// the heavy parse. The `.value` accessor must only be called from the
/// dedicated processing queue (see `MasternodeListSyncer.handleCompletedTask`).
final class MasternodeListDiffMessageEnvelope: IMessage {
    let rawData: Data
    let baseBlockHash: Data
    let blockHash: Data

    private let parser: (Data) -> MasternodeListDiffMessage
    private var _value: MasternodeListDiffMessage?

    var description: String {
        "\(baseBlockHash) \(blockHash)"
    }

    init(rawData: Data, parser: @escaping (Data) -> MasternodeListDiffMessage) {
        self.rawData = rawData
        self.parser = parser
        // Eager header parse (~0.01ms) for routing/validation on the peer
        // event thread. The full body parse is deferred to `.value`.
        let stream = ByteStream(rawData)
        self.baseBlockHash = stream.read(Data.self, count: 32)
        self.blockHash = stream.read(Data.self, count: 32)
    }

    /// Triggers the full parse on first access and caches the result.
    /// MUST be called from a single serial queue (e.g. `processingQueue`)
    /// — the lazy init here is not thread-safe by design.
    var value: MasternodeListDiffMessage {
        if let cached = _value {
            return cached
        }
        let parsed = parser(rawData)
        _value = parsed
        return parsed
    }
}
