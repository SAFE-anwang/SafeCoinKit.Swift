import HsToolKit
import RxSwift
import RxRelay

class MainSafeNetService {
    private let baseUrl = "https://chain.anwang.org"
    private let networkManager: NetworkManager
    
    private var disposeBag = DisposeBag()
    private let stateRelay = PublishRelay<State>()
    private(set) var state: State = .loading {
        didSet {
            stateRelay.accept(state)
        }
    }
    
    init() {
        self.networkManager = NetworkManager()
    }
    
    private func fetch() {
        if case .failed = state {
            state = .loading
        }
        
        let request = networkManager.session.request("\(baseUrl)/insight-api-safe/utils/address/seed", method: .get, parameters: [:])
        networkManager.single(request: request, mapper: self)
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .userInitiated))
            .subscribe(onSuccess: { [weak self] datas in
                self?.handle(datas: datas)
            }, onError: { [weak self] error in
                self?.state = .failed(error: error)
            })
            .disposed(by: disposeBag)
    }
    
    private func handle(datas: [String]) {
        state = .completed(datas: datas)
    }
}

extension MainSafeNetService {
    
    var stateObservable: Observable<State> {
        stateRelay.asObservable()
    }

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

extension MainSafeNetService: IApiMapper {

    public func map(statusCode: Int, data: Any?) throws -> [String] {
        guard let array = data as? [String] else {
            throw NetworkManager.RequestError.invalidResponse(statusCode: statusCode, data: data)
        }
        return array
    }

}

