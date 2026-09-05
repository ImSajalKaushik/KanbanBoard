//
//  MainHostingController.swift
//  KanbanBoard
//
//  Created by Sajal Kaushik on 04/09/26.
//

import SwiftUI

final class MainHostingController: UIHostingController<MainContentView> {
    private let viewModel: KanbanViewModel
    private var lifecycleObservers: [NSObjectProtocol] = []

    init(viewModel: KanbanViewModel) {
        self.viewModel = viewModel
        super.init(rootView: MainContentView(viewModel: viewModel))
    }

    convenience init(errorMessage: String) {
        self.init(viewModel: KanbanViewModel(errorMessage: errorMessage))
    }

    required init?(coder aDecoder: NSCoder) {
        let message = "The app must be launched through its configured scene."
        let viewModel = KanbanViewModel(errorMessage: message)
        self.viewModel = viewModel
        super.init(coder: aDecoder, rootView: MainContentView(viewModel: viewModel))
    }

    deinit {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeSceneLifecycle()
    }

    private func observeSceneLifecycle() {
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] notification in
                self?.forwardIfOwnScene(notification) {
                    self?.requestSync()
                }
            },
            center.addObserver(forName: UIScene.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] notification in
                self?.forwardIfOwnScene(notification) {
                    self?.stopSync()
                }
            }
        ]
    }
    
    private func requestSync() {
        viewModel.requestSync()
    }
    
    private func stopSync() {
        viewModel.stopSync()
    }

    /// Ignores notifications from other scenes so multi-window apps don't cross-trigger sync.
    private func forwardIfOwnScene(_ notification: Notification, action: (() -> Void)?) {
        guard let scene = notification.object as? UIScene, scene === view.window?.windowScene else { return }
        action?()
    }
}
