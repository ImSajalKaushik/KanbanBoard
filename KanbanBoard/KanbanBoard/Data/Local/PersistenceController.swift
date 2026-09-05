//
//  PersistenceController.swift
//  KanbanBoard
//
//  Created by Sajal Kaushik on 04/09/26.
//

import CoreData

enum PersistenceError: LocalizedError {
    case storeDescriptionUnavailable
    case storeLoadFailed(Error)

    var errorDescription: String? {
        switch self {
        case .storeDescriptionUnavailable:
            "The Core Data store could not be configured."
        case .storeLoadFailed(let error):
            "The Core Data store could not be loaded: \(error.localizedDescription)"
        }
    }
}

final class PersistenceController {
    let container: NSPersistentContainer

    init(inMemory: Bool = false, storeURL: URL? = nil) throws {
        container = NSPersistentContainer(name: "KanbanBoard")

        guard let description = container.persistentStoreDescriptions.first else {
            throw PersistenceError.storeDescriptionUnavailable
        }

        if inMemory {
            description.type = NSInMemoryStoreType
            description.url = URL(fileURLWithPath: "/dev/null")
        } else if let storeURL {
            description.url = storeURL
        }

        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
    }

    func load() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            container.loadPersistentStores { _, error in
                if let error {
                    continuation.resume(throwing: PersistenceError.storeLoadFailed(error))
                } else {
                    continuation.resume()
                }
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.undoManager = nil
        return context
    }
}