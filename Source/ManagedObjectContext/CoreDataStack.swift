//
// Wire
// Copyright (C) 2021 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//

import Foundation
import CoreData

@objc
public protocol ContextProvider {

    var account: Account { get }

    var viewContext: NSManagedObjectContext { get }
    var syncContext: NSManagedObjectContext { get }
    var searchContext: NSManagedObjectContext { get }
    var eventContext: NSManagedObjectContext { get }

}

extension URL {

    /// Appends a suffix to the last path (e.g. from `/foo/bar` to `/foo/bar_1`)
    func appendingSuffixToLastPathComponent(suffix: String) -> URL {
        let modifiedComponent = lastPathComponent + suffix
        return deletingLastPathComponent().appendingPathComponent(modifiedComponent)
    }

    /// Appends the name of the store to the path
    func appendingStoreFile() -> URL {
        return self.appendingPathComponent("store.wiredatabase")
    }

    func appendingEventStoreFile() -> URL {
        return self.appendingPathComponent("ZMEventModel.sqlite")

    }

    /// Returns the location of the persistent store file in the given account folder
    func appendingPersistentStoreLocation() -> URL {
        return self.appendingPathComponent("store").appendingStoreFile()
    }

    /// Returns the location of the persistent store file in the given account folder
    func appendingEventStoreLocation() -> URL {
        return self.appendingPathComponent("events").appendingEventStoreFile()
    }
}

@objcMembers
public class CoreDataStack: NSObject, ContextProvider {

    public let account: Account

    public var viewContext: NSManagedObjectContext {
        messagesContainer.viewContext
    }

    public lazy var syncContext: NSManagedObjectContext = {
        return messagesContainer.newBackgroundContext()
    }()

    public lazy var searchContext: NSManagedObjectContext = {
        return messagesContainer.newBackgroundContext()
    }()

    public lazy var eventContext: NSManagedObjectContext = {
        return eventsContainer.newBackgroundContext()
    }()

    public let accountContainer: URL
    public let applicationContainer: URL

    let messagesContainer: PersistentContainer
    let eventsContainer: PersistentContainer
    let dispatchGroup: ZMSDispatchGroup?

    public init(account: Account,
                applicationContainer: URL,
                inMemoryStore: Bool = false,
                dispatchGroup: ZMSDispatchGroup? = nil) {

        if #available(iOSApplicationExtension 12.0, *) {
            ExtendedSecureUnarchiveFromData.register()
        }

        self.applicationContainer = applicationContainer
        self.account = account
        self.dispatchGroup = dispatchGroup

        let accountDirectory = Self.accountFolder(accountIdentifier: account.userIdentifier,
                                                  applicationContainer: applicationContainer)

        self.accountContainer = accountDirectory


        let eventContainer = PersistentContainer(name: "ZMEventModel")
        let messagesContainer = PersistentContainer(name: "zmessaging")

        let description: NSPersistentStoreDescription
        let eventStoreDescription: NSPersistentStoreDescription

        if inMemoryStore {
            description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType

            eventStoreDescription = NSPersistentStoreDescription()
            eventStoreDescription.type = NSInMemoryStoreType
        } else {
            let storeURL = accountDirectory.appendingPersistentStoreLocation()
            description = NSPersistentStoreDescription(url: storeURL)

            // https://www.sqlite.org/pragma.html
            description.setValue("WAL" as NSObject,
                                 forPragmaNamed: "journal_mode")
            description.setValue("FULL" as NSObject,
                                 forPragmaNamed: "synchronous")
            description.setValue("TRUE" as NSObject,
                                 forPragmaNamed: "secure_delete")

            let eventStoreURL = accountDirectory.appendingEventStoreLocation()
            eventStoreDescription = NSPersistentStoreDescription(url: eventStoreURL)
        }

        messagesContainer.persistentStoreDescriptions = [description]
        eventContainer.persistentStoreDescriptions = [eventStoreDescription]

        self.messagesContainer = messagesContainer
        self.eventsContainer = eventContainer

        super.init()

        clearStorageIfNecessary()
    }

    deinit {
        viewContext.tearDown()
        syncContext.tearDown()
        searchContext.tearDown()
        closeStores()
    }

    func closeStores() {
        do {
            try closeStores(in: messagesContainer)
            try closeStores(in: eventsContainer)
        } catch let error {
            Logging.localStorage.error("Error while closing persistent store: \(error)")
        }
    }

    func closeStores(in container: PersistentContainer) throws {
        try container.persistentStoreCoordinator.persistentStores.forEach({
            try container.persistentStoreCoordinator.remove($0)
        })
    }

    public func loadStores(completionHandler: @escaping (Error?) -> Void) {

        let dispatchGroup = DispatchGroup()
        var loadingStoreError: Error? = nil

        dispatchGroup.enter()
        loadMessagesStore { (error) in
            loadingStoreError = loadingStoreError ?? error
            dispatchGroup.leave()
        }

        dispatchGroup.enter()
        loadEventStore { (error) in
            loadingStoreError = loadingStoreError ?? error
            dispatchGroup.leave()
        }

        dispatchGroup.notify(queue: .main) {
            completionHandler(loadingStoreError)
        }
    }

    func loadMessagesStore(completionHandler: @escaping (Error?) -> Void) {
        messagesContainer.loadPersistentStores { (store, error) in

            guard error == nil else {
                completionHandler(error)
                return
            }

            self.configureContextReferences()
            self.configureViewContext(self.viewContext)
            self.configureSyncContext(self.syncContext)
            self.configureSearchContext(self.searchContext)

            #if DEBUG
            MemoryReferenceDebugger.register(self.viewContext)
            MemoryReferenceDebugger.register(self.syncContext)
            MemoryReferenceDebugger.register(self.searchContext)
            #endif

            completionHandler(nil)
        }
    }

    func loadEventStore(completionHandler: @escaping (Error?) -> Void) {
        eventsContainer.loadPersistentStores { (store, error) in

            guard error == nil else {
                completionHandler(error)
                return
            }

            self.configureEventContext(self.eventContext)

            #if DEBUG
            MemoryReferenceDebugger.register(self.eventContext)
            #endif

            completionHandler(nil)
        }
    }

    public var needsMigration: Bool {
        return messagesContainer.needsMigration || eventsContainer.needsMigration
    }

    func configureViewContext(_ context: NSManagedObjectContext) {
        context.markAsUIContext()
        context.createDispatchGroups()
        dispatchGroup.apply(context.add)
        context.mergePolicy = NSMergePolicy(merge: .rollbackMergePolicyType)
        ZMUser.selfUser(in: context)
        Label.fetchOrCreateFavoriteLabel(in: context, create: true)
    }

    func configureContextReferences() {
        viewContext.performAndWait {
            viewContext.zm_sync = syncContext
        }
        syncContext.performAndWait {
            syncContext.zm_userInterface = viewContext
        }
    }

    func configureSyncContext(_ context: NSManagedObjectContext) {
        context.markAsSyncContext()
        context.performAndWait {
            context.createDispatchGroups()
            dispatchGroup.apply(context.add)
            context.setupLocalCachedSessionAndSelfUser()
            context.setupUserKeyStore(accountDirectory: accountContainer,
                                      applicationContainer: applicationContainer)
            context.undoManager = nil
            context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

        }

        // this will be done async, not to block the UI thread, but
        // enqueued on the syncMOC anyway, so it will execute before
        // any other block of code has a chance to use it
        context.performGroupedBlock {
            context.applyPersistedDataPatchesForCurrentVersion()
        }
    }

    func configureSearchContext(_ context: NSManagedObjectContext) {
        context.markAsSearch()
        context.performAndWait {
            context.createDispatchGroups()
            dispatchGroup.apply(context.add)
            context.setupLocalCachedSessionAndSelfUser()
            context.undoManager = nil
            context.mergePolicy = NSMergePolicy(merge: .rollbackMergePolicyType)

        }
    }

    func configureEventContext(_ context: NSManagedObjectContext) {
        context.performAndWait {
            context.createDispatchGroups()
            dispatchGroup.apply(context.add)
        }
    }

    public static func accountFolder(accountIdentifier: UUID, applicationContainer: URL) -> URL {
        return applicationContainer
            .appendingPathComponent("AccountData")
            .appendingPathComponent(accountIdentifier.uuidString)
    }

}

class PersistentContainer: NSPersistentContainer {

    var needsMigration: Bool {
        guard let storeURL = persistentStoreDescriptions.first?.url else {
            return false
        }

        return managedObjectModel.isConfiguration(
            withName: nil,
            compatibleWithStoreMetadata: metadataForStore(at: storeURL))
    }

    /// Retrieves the metadata for the store
    func metadataForStore(at url: URL) -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path),
              let metadata = try? NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: url) else {
            return [:]
        }

        return metadata
    }

}
