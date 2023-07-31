import Foundation
import Combine
import BitcoinCore
import HsExtensions
import Checkpoints

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
    private let mainSafeNetService: MainSafeNetService
    private var cancellables = Set<AnyCancellable>()
    
    public init() {
        mainSafeNetService = MainSafeNetService()
        mainSafeNetService.load()
        
        mainSafeNetService.$state
                    .sink { [weak self] in self?.sync(state: $0) }
                    .store(in: &cancellables)

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
    
    public func getCheckpoint(date: CheckpointData.FallbackDate? = nil) throws -> Checkpoint {
        try getCheckpoint(bundleName: bundleName, network: .main, blockType: .bip44, fallbackDate: date)
    }
    
    // 参考 CheckpointData init 方法实现
    private func getCheckpoint(bundleName: String, network: CheckpointData.Network, blockType: CheckpointData.BlockType, fallbackDate: CheckpointData.FallbackDate? = nil) throws -> Checkpoint {
        var checkpoint: String?
        if let fallbackDate {
            checkpoint = fallbackDate.rawValue
        }else {
            switch blockType {
            case .bip44:
                checkpoint =  "00000020825bf0aeb3b45ee3f1888ae2c4c64da19b332d7281d8a0b3f4ecf248b2699ea399e9e696fe774676381894ee6483c0b057aad8630822b370cd84ede5d50d88f576aa625af0ff0f1ea9e40600ae500c00e920f497c5492aba1c5fa8badbccff0ebd04a1db0903d20b1c57c5e968060000"
            case .last:
                checkpoint =  "00000020366538f586d460d4339b7172c863dbd92648891d1e0523b79c0cfef937f25c47fd79850f1ebf2e8dd2aa2a746e5b473a6ebee600218c725dc0f819c209cbdd52183bd96300000000160c50068de845000c55c274d2942e417d792abe9054088db4dfc75d39f1a14bd6ff64262d12a69f"
            }
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

public extension CheckpointData {
    
    enum FallbackDate: String {
        case date_202209 = "00000020a37726e39bb3222bd32b6135034e03036f1d9d1091daf65a2f77bd6cbb35de488634eac85c3951073ea55df5c92f4fd93240284f32ea99ce2478ef0973e0cc2b98850f6300000000ac6e8505ad943f005f105701936837196a1bcd75b1a2a547265c22fc974e72ab555195cdb44b4837"
        case date_202210 = "000000205e8a5fac2647c01701bea015745feab4739efeacd9315bdbadf432b952801f3d5aba7a683e6f674cd50dfbd73e8d7a39cadea115580fc51db524f888951184ab981237630000000048aea90501ca4000d54f97158b411e170c30cd61b69646eacb906bca1f2f827f9e4453dc1717aba7"
        case date_202211 = "0000002086519473f6f15f50502cdc1510ae016aea7ef3fa6e0767a7f041c631f3b53b7e90bbe41430e096746444eb8faec0f99f1e96e63fb7220a5ee51a395ae54253cd2df15f6300000000be5cd00514144200ed1947d43c89a4b9cb3d55a98789753ff03cd6e0a05e6727600ccc5c962e05ec"
        case date_202212 = "00000020416569c2ad820b44b5b9e614a9dd23886983a374c05af483d514ea302e38060b33b8e17f5d09972423d0266244a2045c27f495681f2b97119a646b31142665a9187e876300000000c86b020624524300f4a1b353c8948d439002d89ce0441a22d4ee73347a765e1e9ebfe41fb8454ee1"
        case date_202301 = "00000020a9c4c1e8f121faa99e63c37e47757dc2cc740e42126fd506ee0b46719ce92d7648bffe8b7185ae174c9eff6eae0917e10d720eceac07dc5b74efd955b048898e8f5cb06300000000d4721c065b9d440092bfcf62f9b1964ae566def3866f203b3d180efa7e3ec1ac00f3abc14e6c572e"
        case date_202302 = "00000020366538f586d460d4339b7172c863dbd92648891d1e0523b79c0cfef937f25c47fd79850f1ebf2e8dd2aa2a746e5b473a6ebee600218c725dc0f819c209cbdd52183bd96300000000160c50068de845000c55c274d2942e417d792abe9054088db4dfc75d39f1a14bd6ff64262d12a69f"
        case date_202303 = "00000020acb8d43c5ed7d231c179e039a7d8101d472a4d5f83a5f350dbb6d8cb923fc77dce35a7ce5edcf559c1a34c5876512c5cc686eb0751344318556851c98ff6f4ee2d25fe630000000020656506d50b4700477b3c17e53e31aeb3f6bf281c02f7aab6cda3b397ddb1419f69367a669c8c3f"
        case date_202304 = "000000205e4bd60a69b1391da24721e1bdc1ec43ba2f509460f840d1273d41b2959220acf52fd21a96bab2efb1d7a7b9177a2f6cb5efe1e7a53a5b5e38fde62ed8f245a1ad032764000000000aa08b060e524800b2d7fb13f03267fefdb432a275923dab22ad50ea803d23930ccab221bf34f911"
    }
}
