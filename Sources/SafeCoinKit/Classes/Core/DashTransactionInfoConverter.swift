import BitcoinCore
import Foundation

class DashTransactionInfoConverter: ITransactionInfoConverter {
    public var baseTransactionInfoConverter: IBaseTransactionInfoConverter!
    private let instantTransactionManager: IInstantTransactionManager
    private let cacheLock = NSLock()
    private var cache = [String: CacheEntry]()
    private let maxCacheSize = 2048

    init(instantTransactionManager: IInstantTransactionManager) {
        self.instantTransactionManager = instantTransactionManager
    }

    func transactionInfo(fromTransaction transactionForInfo: FullTransactionForInfo) -> TransactionInfo {
        let snapshot = Snapshot(transactionForInfo: transactionForInfo)
        let instantTx = instantTransactionManager.isTransactionInstant(txHash: transactionForInfo.transactionWithBlock.transaction.dataHash)

        if let cachedInfo = cachedTransactionInfo(snapshot: snapshot, instantTx: instantTx) {
            return cachedInfo
        }

        let txInfo: DashTransactionInfo = baseTransactionInfoConverter.transactionInfo(fromTransaction: transactionForInfo)
        txInfo.instantTx = instantTx
        cache(transactionInfo: txInfo, snapshot: snapshot)
        return txInfo
    }
}

private extension DashTransactionInfoConverter {
    struct Snapshot: Equatable {
        let uid: String
        let dataHash: Data
        let transactionIndex: Int
        let timestamp: Int
        let status: TransactionStatus
        let blockHash: Data?
        let conflictingHash: String?

        init(transactionForInfo: FullTransactionForInfo) {
            let transaction = transactionForInfo.transactionWithBlock.transaction

            uid = transaction.uid
            dataHash = transaction.dataHash
            transactionIndex = transaction.order
            timestamp = transaction.timestamp
            status = transaction.status
            blockHash = transaction.blockHash
            conflictingHash = transaction.conflictingTxHash?.hs.reversedHex
        }
    }

    struct CacheEntry {
        let snapshot: Snapshot
        let transactionInfo: DashTransactionInfo
    }

    func cachedTransactionInfo(snapshot: Snapshot, instantTx: Bool) -> DashTransactionInfo? {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        guard let cached = cache[snapshot.uid], cached.snapshot == snapshot else {
            return nil
        }

        return cached.transactionInfo.copy(instantTx: instantTx)
    }

    func cache(transactionInfo: DashTransactionInfo, snapshot: Snapshot) {
        cacheLock.lock()
        defer { cacheLock.unlock() }

        if cache.count >= maxCacheSize {
            cache.removeAll(keepingCapacity: true)
        }

        cache[snapshot.uid] = CacheEntry(snapshot: snapshot, transactionInfo: transactionInfo)
    }
}

private extension DashTransactionInfo {
    func copy(instantTx: Bool) -> DashTransactionInfo {
        let copied = DashTransactionInfo(
            uid: uid,
            transactionHash: transactionHash,
            transactionIndex: transactionIndex,
            inputs: inputs,
            outputs: outputs,
            amount: amount,
            type: type,
            fee: fee,
            blockHeight: blockHeight,
            timestamp: timestamp,
            status: status,
            conflictingHash: conflictingHash,
            rbfEnabled: rbfEnabled
        )
        copied.instantTx = instantTx
        return copied
    }
}
