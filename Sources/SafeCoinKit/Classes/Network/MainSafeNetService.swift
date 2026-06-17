import Foundation
import HsToolKit
import HsExtensions

class MainSafeNetService {
    private let baseUrl = "https://chain.anwang.org"
    private let networkManager: NetworkManager
    private var tasks = Set<AnyTask>()
    private let timeoutInterval: TimeInterval = 30.0
    private let requestQueue = DispatchQueue(label: "io.safewallet.safe-kit.network-queue", qos: .utility)
    private var fetchInFlight = false
    private var refreshRequested = false

    @PostPublished private(set) var state: State = .loading
    
    init() {
        self.networkManager = NetworkManager()
    }
    
    private func fetch() {
        requestQueue.async {
            if self.fetchInFlight {
                self.refreshRequested = true
                return
            }

            self.fetchInFlight = true
            self.refreshRequested = false
            self.tasks = Set()

            if case .failed = self.state {
                self.state = .loading
            }

            Task { [weak self] in
                guard let self = self else { return }
                defer {
                    self.requestQueue.async {
                        self.fetchInFlight = false

                        if self.refreshRequested {
                            self.refreshRequested = false
                            self.fetch()
                        }
                    }
                }

                do {
                    let url = "\(self.baseUrl)/insight-api-safe/utils/address/seed"
                    let result = try await self.withTimeout(seconds: self.timeoutInterval) {
                        try await self.networkManager.fetchJson(url: url)
                    }

                    guard let json = result as? [String] else { return }
                    self.handle(datas: json)
                } catch {
                    self.state = .failed(error: error)
                }
            }.store(in: &self.tasks)
        }
    }
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: T.self) { group in
                group.addTask { try await operation() }
                group.addTask { 
                    try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                    throw NSError(domain: "NetworkTimeout", code: -1001, userInfo: [NSLocalizedDescriptionKey: "Network request timed out"])
                }
                let result = try await group.next()!
                group.cancelAll()
                return result
            }
        } onCancel: {
        }
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

