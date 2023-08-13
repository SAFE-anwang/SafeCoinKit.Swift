import Foundation
import Combine
import SafeCoinKit
import BitcoinCore
import HsToolKit
import HdWalletKit

class DashAdapter: BaseAdapter {
    override var feeRate: Int { return 1 }
    private let dashKit: Kit
    private let coinRate: Decimal = pow(10, 8)
    
    init(words: [String], testMode: Bool, syncMode: BitcoinCore.SyncMode, logger: Logger) {
        let networkType: Kit.NetworkType = testMode ? .testNet : .mainNet
        let seed = Mnemonic.seed(mnemonic: words)
        dashKit = try! Kit(seed: seed ?? Data(), walletId: "walletId", syncMode: syncMode, networkType: networkType, logger: logger.scoped(with: "DashKit"))

        super.init(name: "Dash", coinCode: "DASH", abstractKit: dashKit)
        dashKit.delegate = self
        
        let lockUxto = dashKit.getConfirmedUnspentOutputProvider().getLockUxto()
        syncLockedRecordItems(items: lockUxto)
        
    }

    override func transactions(fromUid: String?, type: TransactionFilterType? = nil, limit: Int) -> [TransactionRecord] {
        dashKit.transactions(fromUid: fromUid, type: type, limit: limit)
                .compactMap {
                    transactionRecord(fromTransaction: $0)
                }
    }

    private func transactionRecord(fromTransaction transaction: DashTransactionInfo) -> TransactionRecord {
        var record = transactionRecord(fromTransaction: transaction as TransactionInfo)
        if transaction.instantTx {
            record.transactionExtraType = "Instant"
        }

        return record
    }

    class func clear() {
        try? Kit.clear()
    }
    
    func syncLockedRecordItems(items: [UnspentOutput]) {
        
        var viewItems = [ViewItem]()
        
        for item in items {
            let lastHeight: Int = dashKit.lastBlockInfo?.height ?? 0
            var height: Int = 0

            if let h = item.blockHeight {
                height = h
            }else {
                 height = lastHeight
            }
            if let unlockedHeight = item.output.unlockedHeight {
                let lockAmount = "\((Decimal(item.output.value) / coinRate).formattedAmount)"
                let lockMonth = (unlockedHeight - height) / 86300
                let isLocked = lastHeight <= unlockedHeight
                let viewItem = ViewItem(height: height, lockAmount: lockAmount, lockMonth: lockMonth, isLocked: isLocked, address: item.output.address ?? "")
                viewItems.append(viewItem)
            }

        }
        print("-------------->:\(viewItems)")
    }
}

extension DashAdapter: DashKitDelegate {

    public func transactionsUpdated(inserted: [DashTransactionInfo], updated: [DashTransactionInfo]) {
        transactionsSubject.send()
    }

    func transactionsDeleted(hashes: [String]) {
        transactionsSubject.send()
    }

    func balanceUpdated(balance: BalanceInfo) {
        balanceSubject.send()
    }

    func lastBlockInfoUpdated(lastBlockInfo: BlockInfo) {
        lastBlockSubject.send()
    }

    public func kitStateUpdated(state: BitcoinCore.KitState) {
        syncStateSubject.send()
    }

}

struct ViewItem {
    let height: Int
    let lockAmount: String
    let lockMonth: Int
    let isLocked: Bool
    let address: String
}
