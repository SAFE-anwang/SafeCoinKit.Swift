import Foundation
import HsToolKit
import HsExtensions

class MainSafeNetService {
    private let baseUrl = "https://chain.anwang.org"
    private let networkManager: NetworkManager
    private var tasks = Set<AnyTask>()

    @PostPublished private(set) var state: State = .loading
    
    init() {
        self.networkManager = NetworkManager()
    }
    
    private func fetch() {
        tasks = Set()
        if case .failed = state {
            state = .loading
        }
        Task { [weak self] in
            do {
                guard let json = try await networkManager.fetchJson(url: "\(baseUrl)/insight-api-safe/utils/address/seed") as? [String] else { return }
                self?.handle(datas: json)
            } catch {
                self?.state = .failed(error: error)
            }
        }.store(in: &tasks)
    }
    
    private func handle(datas: [String]) {
        state = .completed(datas: datas)
    }
}

extension MainSafeNetService {
    
    func load() {
        fetch()
    }

    func refresh() {
        fetch()
    }
}
extension MainSafeNetService {

    enum State {
        case loading
        case completed(datas: [String])
        case failed(error: Error)
    }
}

//extension MainSafeNetService: IApiMapper {
//
//    public func map(statusCode: Int, data: Any?) throws -> [String] {
//        guard let array = data as? [String] else {
//            throw NetworkManager.RequestError.invalidResponse(statusCode: statusCode, data: data)
//        }
//        return array
//    }
//
//}

