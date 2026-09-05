//
//  NetworkMonitor.swift
//  KanbanBoard
//
//  Created by Sajal Kaushik on 04/09/26.
//

import Combine
import Foundation
import Network

protocol NetworkMonitoring: AnyObject {
    var isConnected: Bool { get }
    var connectivityPublisher: AnyPublisher<Bool, Never> { get }
}

final class NWPathNetworkMonitor: NetworkMonitoring {
    static let shared = NWPathNetworkMonitor()

    private let monitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "sajal.io.KanbanBoard.network-monitor")
    private let connectivityLock = NSLock()
    private let connectivity = CurrentValueSubject<Bool, Never>(false)
    private var connectionState = false

    var isConnected: Bool {
        connectivityLock.lock()
        defer { connectivityLock.unlock() }
        return connectionState
    }

    var connectivityPublisher: AnyPublisher<Bool, Never> {
        connectivity
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    private init(monitor: NWPathMonitor = NWPathMonitor()) {
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let isConnected = path.status == .satisfied
            self?.updateConnectivity(isConnected)
        }
        monitor.start(queue: monitorQueue)
    }

    private func updateConnectivity(_ isConnected: Bool) {
        connectivityLock.lock()
        let didChange = connectionState != isConnected
        connectionState = isConnected
        connectivityLock.unlock()

        guard didChange else { return }
        connectivity.send(isConnected)
    }
}
