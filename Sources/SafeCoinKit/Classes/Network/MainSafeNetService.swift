import Foundation
import HsToolKit
import HsExtensions

class MainSafeNetService {
    private let baseUrl = "https://chain.anwang.org"
    private let networkManager: NetworkManager
    private var tasks = Set<AnyTask>()
    private let timeoutInterval: TimeInterval = 30.0
    private let maxConcurrentRequests: Int = 3
    private var activeRequests: Int = 0
    private let requestQueue = DispatchQueue(label: "io.safewallet.safe-kit.network-queue", qos: .utility)

    @PostPublished private(set) var state: State = .loading
    
    init() {
        self.networkManager = NetworkManager()
    }
    
    private func fetch() {
        tasks = Set()
        if case .failed = state {
            state = .loading
        }
        
        // 使用任务队列和并发控制来限制网络请求
        requestQueue.async {
            // 检查是否有太多活跃请求
            guard self.activeRequests < self.maxConcurrentRequests else {
                // 如果请求太多，延迟后重试
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.fetch()
                }
                return
            }
            
            // 增加活跃请求计数
            self.activeRequests += 1
            
            Task { [weak self] in
                defer {
                    // 减少活跃请求计数
                    self?.activeRequests -= 1
                }
                
                guard let self = self else { return }
                
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


