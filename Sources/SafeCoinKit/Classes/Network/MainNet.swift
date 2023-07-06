import Foundation
import BitcoinCore
import HsExtensions
import Checkpoints
import RxSwift
import RxRelay

public class MainNet: INetwork {
    public let protocolVersion: Int32 = 70210

    public let bundleName = "safe"

    public let maxBlockSize: UInt32 = 2_000_000_000
    public let pubKeyHash: UInt8 = 0x4c
    public let privateKey: UInt8 = 0x80
    public let scriptHash: UInt8 = 0x10
    public let bech32PrefixPattern: String = "bc"
    // 与Android的配置有差异，需要高低位反转
    public let xPubKey: UInt32 = 0x1eb28804
    public let xPrivKey: UInt32 = 0xe4ad0004
    public let magic: UInt32 = 0x62696ecc
    public let port = 5555
    public let coinType: UInt32 = 5
    public let sigHash: SigHashType = .bitcoinAll
    public var syncableFromApi: Bool = true
    public var dnsSeeds =
                ["120.78.227.96",
                 "114.215.31.37",
                 "47.96.254.235",
                 "106.14.66.206",
                 "47.52.9.168",
                 "47.75.17.223",
                 "47.88.247.232",
                 "47.89.208.160",
                 "47.74.13.245"]

    public let dustRelayTxFee = 1000
    
    public var bip44Checkpoint: Checkpoint {
        try! getCheckpoint(bundleName: bundleName, network: .main, blockType: .bip44)
    }

    public var lastCheckpoint: Checkpoint {
        try! getCheckpoint(bundleName: bundleName, network: .main, blockType: .last)
    }

    private var connectFailedIp = [String]()
    private let disposeBag = DisposeBag()
    private let mainSafeNetService: MainSafeNetService

    public init() {
        mainSafeNetService = MainSafeNetService()
        mainSafeNetService.load()
        
        mainSafeNetService.stateObservable
                .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                .observeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
                .subscribe{
                    [weak self] in self?.sync(state: $0)
                }
                .disposed(by: disposeBag)

    }
    public func isMainNode(ip: String?) -> Bool {
        if let ip = ip, ip.count > 0 {
            return dnsSeeds.contains(ip)
        }
        return true
    }

    public func getMainNodeIp(list: [String]) -> String? {
        if list.count == 0 {
            return dnsSeeds.randomElement()
        }
        let unconnectIp = dnsSeeds.filter{ !list.contains($0) && !connectFailedIp.contains($0) }
        return unconnectIp.count > 0 ? unconnectIp.randomElement() : nil
    }
    
    public func markedFailed(ip: String?) {
        if let _ip = ip {
            connectFailedIp.append(_ip)
        }
        
    }
    
    public func isSafe() -> Bool {
        return true
    }
    
    private func sync(state: MainSafeNetService.State) {
        switch state {
        case .loading: break
        case .completed(let datas):
                dnsSeeds = datas
        case .failed(_): break
        }
    }
}

extension MainNet {
    
    // 参考 CheckpointData init 方法实现
    private func getCheckpoint(bundleName: String, network: CheckpointData.Network, blockType: CheckpointData.BlockType) throws -> Checkpoint {
        var checkpoint: String?
        switch blockType {
        case .bip44:
            checkpoint =  "00000020825bf0aeb3b45ee3f1888ae2c4c64da19b332d7281d8a0b3f4ecf248b2699ea399e9e696fe774676381894ee6483c0b057aad8630822b370cd84ede5d50d88f576aa625af0ff0f1ea9e40600ae500c00e920f497c5492aba1c5fa8badbccff0ebd04a1db0903d20b1c57c5e968060000"
        case .last:
            checkpoint =  "00000020366538f586d460d4339b7172c863dbd92648891d1e0523b79c0cfef937f25c47fd79850f1ebf2e8dd2aa2a746e5b473a6ebee600218c725dc0f819c209cbdd52183bd96300000000160c50068de845000c55c274d2942e417d792abe9054088db4dfc75d39f1a14bd6ff64262d12a69f"
        }
        
        guard let  string = checkpoint else {
            throw CheckpointData.ParseError.invalidUrl
        }
        var lines = string.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            throw CheckpointData.ParseError.invalidFile
        }

        guard let block = lines.removeFirst().hs.hexData else {
            throw CheckpointData.ParseError.invalidFile
        }

        var additionalBlocks = [Data]()
        for line in lines {
            guard let additionalData = line.hs.hexData else {
                throw CheckpointData.ParseError.invalidFile
            }
            additionalBlocks.append(additionalData)
        }
        
        let pBlock = try readBlock(data: block)
        let pAdditionalBlocks = try additionalBlocks.map { try readBlock(data: $0) }
        
        return Checkpoint(block: pBlock, additionalBlocks: pAdditionalBlocks)
    }
    
    ///照搬 Checkpoint类中同名方法
    private func readBlock(data: Data) throws -> Block {
        let byteStream = ByteStream(data)

        let version = Int(byteStream.read(Int32.self))
        let previousBlockHeaderHash = byteStream.read(Data.self, count: 32)
        let merkleRoot = byteStream.read(Data.self, count: 32)
        let timestamp = Int(byteStream.read(UInt32.self))
        let bits = Int(byteStream.read(UInt32.self))
        let nonce = Int(byteStream.read(UInt32.self))
        let height = Int(byteStream.read(UInt32.self))
        let headerHash = byteStream.read(Data.self, count: 32)

        let header = BlockHeader(
                version: version,
                headerHash: headerHash,
                previousBlockHeaderHash: previousBlockHeaderHash,
                merkleRoot: merkleRoot,
                timestamp: timestamp,
                bits: bits,
                nonce: nonce
        )
        return Block(withHeader: header, height: height)
    }
}
