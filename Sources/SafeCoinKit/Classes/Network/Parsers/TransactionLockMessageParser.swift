import BitcoinCore
import Foundation
// todo identical code with transactionMessageParser
class TransactionLockMessageParser: IMessageParser {
    var id: String { "ix" }

    func parse(data: Data) -> IMessage {
        return TransactionLockMessage(transaction: TransactionSerializer.deserialize(data: data, isSafe: true))
    }
}
