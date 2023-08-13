import BitcoinCore
import HsToolKit

class Configuration {
    static let shared = Configuration()

    let minLogLevel: Logger.Level = .verbose
    let testNet = false
    let defaultWords = [
        "divorce install scatter rabbit diet ride tuna evoke erupt nut guilt useless",
    ]

}
