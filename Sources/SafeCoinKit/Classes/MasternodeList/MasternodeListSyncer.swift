import BitcoinCore
import Combine
import Foundation

class MasternodeListSyncer: IMasternodeListSyncer {
    private var cancellables = Set<AnyCancellable>()
    private weak var bitcoinCore: BitcoinCore?
    private let initialBlockDownload: IInitialDownload
    private let peerTaskFactory: IPeerTaskFactory
    private let masternodeListManager: IMasternodeListManager

    private var workingPeer: IPeer? = nil
    private let queue: DispatchQueue
    // Serial queue for the heavy masternode-list-diff processing. This offloads
    // BLS verify + double merkle root + sync DB reads from BitcoinCore's peer
    // event thread (which can be the main thread) to a dedicated background queue.
    // Safe because MasternodeListManager is a single-writer to its in-memory
    // masternodeSortedList, and we serialize all writes through this queue.
    private let processingQueue: DispatchQueue

    init(bitcoinCore: BitcoinCore, initialBlockDownload: IInitialDownload, peerTaskFactory: IPeerTaskFactory, masternodeListManager: IMasternodeListManager,
         queue: DispatchQueue = DispatchQueue(label: "io.horizontalsystems.dash-kit.masternode-list-syncer", qos: .background),
         processingQueue: DispatchQueue = DispatchQueue(label: "io.horizontalsystems.dash-kit.masternode-list-processor", qos: .userInitiated))
    {
        self.bitcoinCore = bitcoinCore
        self.initialBlockDownload = initialBlockDownload
        self.peerTaskFactory = peerTaskFactory
        self.masternodeListManager = masternodeListManager
        self.queue = queue
        self.processingQueue = processingQueue
    }

    private func assignNextSyncPeer() {
        queue.async {
            guard self.workingPeer == nil,
                  let lastBlockInfo = self.bitcoinCore?.lastBlockInfo,
                  let syncedPeer = self.initialBlockDownload.syncedPeers.first,
                  let blockHash = lastBlockInfo.headerHash.reversedData
            else {
                return
            }

            let baseBlockHash = self.masternodeListManager.baseBlockHash

            if blockHash != baseBlockHash {
                let task = self.peerTaskFactory.createRequestMasternodeListDiffTask(baseBlockHash: baseBlockHash, blockHash: blockHash)
                syncedPeer.add(task: task)

                self.workingPeer = syncedPeer
            }
        }
    }

    func subscribeTo(publisher: AnyPublisher<PeerGroupEvent, Never>) {
        publisher
            .sink { [weak self] event in
                switch event {
                case let .onPeerDisconnect(peer, error): self?.onPeerDisconnect(peer: peer, error: error)
                default: ()
                }
            }
            .store(in: &cancellables)
    }

    func subscribeTo(publisher: AnyPublisher<InitialDownloadEvent, Never>) {
        publisher
            .sink { [weak self] event in
                switch event {
                case let .onPeerSynced(peer): self?.onPeerSynced(peer: peer)
                default: ()
                }
            }
            .store(in: &cancellables)
    }
}

extension MasternodeListSyncer {
    private func onPeerSynced(peer _: IPeer) {
        assignNextSyncPeer()
    }
}

extension MasternodeListSyncer {
    private func onPeerDisconnect(peer: IPeer, error _: Error?) {
        if peer.equalTo(workingPeer) {
            workingPeer = nil

            assignNextSyncPeer()
        }
    }
}

extension MasternodeListSyncer: IPeerTaskHandler {
    func handleCompletedTask(peer: IPeer, task: PeerTask) -> Bool {
        switch task {
        case let listDiffTask as RequestMasternodeListDiffTask:
            // Access the envelope, not the parsed message. The full parse
            // (1000+ masternode + 100+ quorum SHA256 chains, thousands of
            // allocations) must run on processingQueue, not on the peer event
            // thread that BitcoinCore just dispatched us on.
            guard let envelope = listDiffTask.masternodeListDiffMessageEnvelope else {
                return true
            }
            processingQueue.async { [weak self] in
                guard let self = self else { return }
                // Trigger the heavy parse here, on processingQueue, instead of
                // letting `masternodeListDiffMessage` trigger it on the peer
                // event thread.
                let message = envelope.value
                do {
                    try self.masternodeListManager.updateList(masternodeListDiffMessage: message)
                    // workingPeer reset must run on `queue` to serialize with
                    // assignNextSyncPeer reads/writes.
                    self.queue.async { self.workingPeer = nil }
                } catch {
                    // peer.disconnect must also hop to `queue` to stay on the
                    // peer event thread that BitcoinCore owns; otherwise it
                    // races with the peer's own socket / state-machine work.
                    self.queue.async { peer.disconnect(error: error) }
                }
            }
            return true
        default: return false
        }
    }
}
