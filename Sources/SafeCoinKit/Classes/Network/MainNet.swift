import Foundation
import Combine
import BitcoinCore
import HsExtensions
import Checkpoints

public class MainNet: INetwork {
    public var blockchairChainId: String = ""
    
    public let protocolVersion: Int32 = 70210

    public let bundleName = "Safe"

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

