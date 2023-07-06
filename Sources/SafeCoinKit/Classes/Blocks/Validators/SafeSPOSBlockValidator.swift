import Foundation
import BigInt
import BitcoinCore

public class SafeSPOSBlockValidator: IBlockValidator {
    private let difficultyEncoder: IDifficultyEncoder

    public init(difficultyEncoder: IDifficultyEncoder) {
        self.difficultyEncoder = difficultyEncoder
    }

    public func validate(block: Block, previousBlock: Block) throws {
//        guard difficultyEncoder.compactFrom(hash: block.headerHash) < block.bits else {
//            throw BitcoinCoreErrors.BlockValidation.invalidProofOfWork
//        }
    }

}
