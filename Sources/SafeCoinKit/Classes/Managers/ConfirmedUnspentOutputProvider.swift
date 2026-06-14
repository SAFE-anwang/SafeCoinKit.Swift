import BitcoinCore

public class ConfirmedUnspentOutputProvider {
    let storage: IDashStorage
    let confirmationsThreshold: Int

    // 性能修复:将 reserve 字段白名单的三个 hex 字符串从函数体中提取为类型级静态常量,
    // 避免每次 isOutputConfirmed 调用都重新构造(尤其是 130 字节的 coinbase reward 串)。
    // 改为 static let 后,Swift 会保证全局只分配一次。
    private static let normalTxReserveHex = "73616665"                                                              // 普通交易
    private static let coinbaseRewardReserveHex = "7361666573706f730100c2f824c4364195b71a1fcfa0a28ebae20f3501b21b08ae6d6ae8a3bca98ad9d64136e299eba2400183cd0a479e6350ffaec71bcaf0714a024d14183c1407805d75879ea2bf6b691214c372ae21939b96a695c746a6"   // coinbase 收益
    private static let safeMemoReservePrefix = "736166650100c9dcee22bb18bd289bca86e2c8bbb6487089adc9a13d875e538dd35c70a6bea42c0100000a02010012"                       // safe 备注(同样属于 safe 交易)

    init(storage: IDashStorage, confirmationsThreshold: Int) {
        self.storage = storage
        self.confirmationsThreshold = confirmationsThreshold
    }
}

extension ConfirmedUnspentOutputProvider: IUnspentOutputProvider {
    public func spendableUtxo(filters: UtxoFilters) -> [UnspentOutput] {
        let lastBlockHeight = storage.lastBlock?.height ?? 0

        // Output must have a public key, that is, must belong to the user
        // 性能修复:移除链尾冗余的 isOutputConfirmed 二次过滤 —— 上方 .filter 中已对每条 utxo 调用过,重复调用既浪费 CPU 又会重复构造下面的长 hex 常量
        return storage.unspentOutputs().filter { utxo in
            guard isOutputConfirmed(unspentOutput: utxo, lastBlockHeight: lastBlockHeight) else {
                return false
            }

            if let scriptTypes = filters.scriptTypes, !scriptTypes.contains(utxo.output.scriptType) {
                return false
            }

            if let outputsCount = filters.maxOutputsCountForInputs,
               storage.outputsCount(transactionHash: utxo.transaction.dataHash) > outputsCount
            {
                return false
            }

            return true
        }
    }
    
    public func confirmedSpendableUtxo(filters: UtxoFilters) -> [UnspentOutput] {
        spendableUtxo(filters: filters)
    }
    
    private func isOutputConfirmed(unspentOutput: UnspentOutput, lastBlockHeight: Int) -> Bool {

        guard let blockHeight = unspentOutput.blockHeight else {
            return false
        }

        guard let unlockedHeight = unspentOutput.output.unlockedHeight else {
            return false
        }

        // 性能修复:reserve 字段白名单对比改用类型级静态常量,避免每次调用都重新构造 hex 字符串
        if let reserveHex = unspentOutput.output.reserve?.hs.hex {
            if  reserveHex != Self.normalTxReserveHex,
                reserveHex != Self.coinbaseRewardReserveHex,
                !reserveHex.starts(with: Self.safeMemoReservePrefix) {
                return false
            }
        }

        return (blockHeight <= lastBlockHeight - confirmationsThreshold + 1 && lastBlockHeight > unlockedHeight)
    }
    
    public func getLockUxto() -> [UnspentOutput] {
           return storage.unspentOutputs().filter({ isLock(unspentOutput: $0) })
    }

   private func isLock(unspentOutput: UnspentOutput) -> Bool {
       guard let unlockedHeight = unspentOutput.output.unlockedHeight else { return false }
       return unlockedHeight > 0
   }
}


