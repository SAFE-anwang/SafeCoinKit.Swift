import BitcoinCore

public class ConfirmedUnspentOutputProvider {
    let storage: IDashStorage
    let confirmationsThreshold: Int

    init(storage: IDashStorage, confirmationsThreshold: Int) {
        self.storage = storage
        self.confirmationsThreshold = confirmationsThreshold
    }
}

extension ConfirmedUnspentOutputProvider: IUnspentOutputProvider {
    public func spendableUtxo(filters: UtxoFilters) -> [UnspentOutput] {
        let lastBlockHeight = storage.lastBlock?.height ?? 0

        // Output must have a public key, that is, must belong to the user
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
        }.filter { isOutputConfirmed(unspentOutput: $0, lastBlockHeight: lastBlockHeight) }
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
        
        if let reserveHex = unspentOutput.output.reserve?.hs.hex {
            
            let str = "7361666573706f730100c2f824c4364195b71a1fcfa0a28ebae20f3501b21b08ae6d6ae8a3bca98ad9d64136e299eba2400183cd0a479e6350ffaec71bcaf0714a024d14183c1407805d75879ea2bf6b691214c372ae21939b96a695c746a6"
             
            if  reserveHex != "73616665", // 普通交易,
                reserveHex != str,  // coinbase 收益,
                !reserveHex.starts(with: "736166650100c9dcee22bb18bd289bca86e2c8bbb6487089adc9a13d875e538dd35c70a6bea42c0100000a02010012") {// safe备注，也是属于safe交易
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


