//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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
import XCTest
@testable import WireDataModel

class StorageStackTests: DatabaseBaseTest {
    
    var appURL: URL {
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
    }
    
    var baseURL: URL {
        return self.appURL.appendingPathComponent("StorageStackTests")
    }
    
    override func setUp() {
        super.setUp()
        self.clearStorageFolder()
        try! FileManager.default.createDirectory(at: self.appURL, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        StorageStack.reset()
        super.tearDown()
        self.clearStorageFolder()
    }
    
    func testThatTheContextDirectoryIsRetainedInTheSingleton() {

        // WHEN
        weak var contextDirectory: ManagedObjectContextDirectory? = self.createStorageStackAndWaitForCompletion(container: self.baseURL)

        // THEN
        XCTAssertNotNil(contextDirectory)
    }
    
    func testThatItCreatesSubfolderForStorageWithUUID() {
        
        // WHEN
        _ = self.createStorageStackAndWaitForCompletion(container: self.baseURL)

        // THEN
        XCTAssertTrue(FileManager.default.fileExists(atPath: self.baseURL.path))
    }
    
    func testThatTheContextDirectoryIsTornDown() {
        
        // GIVEN
        weak var contextDirectory: ManagedObjectContextDirectory? = self.createStorageStackAndWaitForCompletion(container: self.baseURL)

        // WHEN
        StorageStack.reset()
        
        // THEN
        XCTAssertNil(contextDirectory)
        
    }
    
    func testThatItCanReopenAPreviouslyExistingDatabase() {
    
        // GIVEN
        let uuid = UUID()
        let firstStackExpectation = self.expectation(description: "Callback invoked")
        let testValue = "12345678"
        let testKey = "aassddffgg"
        weak var contextDirectory: ManagedObjectContextDirectory! = nil
        StorageStack.shared.createManagedObjectContextDirectory(
            accountIdentifier: uuid,
            container: self.baseURL
        ) { directory in
            contextDirectory = directory
            firstStackExpectation.fulfill()
        }
        
        self.waitForExpectations(timeout: 1)
        
        // create an entry to check that it is reopening the same DB
        contextDirectory.uiContext.setPersistentStoreMetadata(testValue, key: testKey)
        let conversationTemp = ZMConversation.insertNewObject(in: contextDirectory.uiContext)
        contextDirectory.uiContext.forceSaveOrRollback()
        let objectID = conversationTemp.objectID
        
        // WHEN
        StorageStack.reset()
        let secondStackExpectation = self.expectation(description: "Callback invoked")
        
        StorageStack.shared.createManagedObjectContextDirectory(
            accountIdentifier: uuid,
            container: self.baseURL
        ) { directory in
            contextDirectory = directory
            secondStackExpectation.fulfill()
        }
        
        // THEN
        self.waitForExpectations(timeout: 1)
        XCTAssertEqual(contextDirectory.uiContext.persistentStoreCoordinator!.persistentStores.count, 1)

        guard let readValue = contextDirectory.uiContext.persistentStoreMetadata(forKey: testKey) as? String else {
            XCTFail("Can't read previous value from the context")
            return
        }
        guard let _ = try? contextDirectory.uiContext.existingObject(with: objectID) as? ZMConversation else {
            XCTFail("Can't find previous conversation in the context")
            return
        }
        XCTAssertEqual(readValue, testValue)
    }
    
    func testThatItPerformsMigrationCallbackWhenDifferentVersion() {
        
        // GIVEN
        let uuid = UUID()
        let completionExpectation = self.expectation(description: "Callback invoked")
        let migrationExpectation = self.expectation(description: "Migration started")
        let storeURL = FileManager.currentStoreURLForAccount(with: uuid, in: self.baseURL)
        try! FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        // copy old version database into the expected location
        guard let source = Bundle(for: type(of: self)).url(forResource: "store2-3", withExtension: "wiredatabase") else {
            XCTFail("missing resource")
            return
        }
        let destination = URL(string: storeURL.absoluteString)!
        try! FileManager.default.copyItem(at: source, to: destination)
        
        // WHEN
        var contextDirectory: ManagedObjectContextDirectory? = nil
        StorageStack.shared.createManagedObjectContextDirectory(
            accountIdentifier: uuid,
            container: self.baseURL,
            startedMigrationCallback: { _ in migrationExpectation.fulfill() }
        ) { directory in
            contextDirectory = directory
            completionExpectation.fulfill()
        }
        
        // THEN
        self.waitForExpectations(timeout: 2)
        guard let uiContext = contextDirectory?.uiContext else {
            XCTFail("No context")
            return
        }
        let messageCount = try! uiContext.count(for: ZMClientMessage.sortedFetchRequest()!)
        XCTAssertGreaterThan(messageCount, 0)
        
    }
    
    func testThatItPerformsMigrationWhenStoreIsInOldLocation() {
        
        let oldLocations = PersistentStoreRelocator.possiblePreviousStoreLocations(sharedContainerURL: self.baseURL)
        let userID = UUID()
        let testValue = "12345678"
        let testKey = "aassddffgg"
        
        oldLocations.forEach { oldPath in
            
            // GIVEN
            StorageStack.reset()
            self.clearStorageFolder()
            
            createStorageStackAndWaitForCompletion(path: oldPath) { contextDirectory in
                contextDirectory.uiContext.setPersistentStoreMetadata(testValue, key: testKey)
                contextDirectory.uiContext.forceSaveOrRollback()
            }
            
            // expectations
            let migrationExpectation = self.expectation(description: "Migration started")
            let completionExpectation = self.expectation(description: "Stack initialization completed")
            
            // WHEN
            // create the stack, check that the value is there and that it calls the migration callback
            StorageStack.shared.createManagedObjectContextDirectory(
                accountIdentifier: userID,
                container: self.baseURL,
                startedMigrationCallback: { _ in migrationExpectation.fulfill() }
            ) { MOCs in
                defer { completionExpectation.fulfill() }
                guard let string = MOCs.uiContext.persistentStoreMetadata(forKey: testKey) as? String else {
                    XCTFail("Failed to find same value after migrating from \(oldPath.path)")
                    return
                }
                XCTAssertEqual(string, testValue)
            }
            
            // THEN
            self.waitForExpectations(timeout: 1)
            StorageStack.reset()
        }
    }
    
    func testThatItDoesNotInvokeTheMigrationCallback() {
        
        // GIVEN
        let uuid = UUID()
        let completionExpectation = self.expectation(description: "Callback invoked")
        let migrationExpectation = self.expectation(description: "Migration started")
        migrationExpectation.isInverted = true
        
        // WHEN
        StorageStack.shared.createManagedObjectContextDirectory(
            accountIdentifier: uuid,
            container: self.baseURL,
            startedMigrationCallback: { _ in migrationExpectation.fulfill() }
        ) { directory in
            completionExpectation.fulfill()
        }
        
        // THEN
        self.waitForExpectations(timeout: 1)
    }
}

// MARK: - Legacy User ID

extension StorageStackTests {
    
    func testThatItReturnsNilWhenLegacyStoreDoesNotExist() {
        
        // GIVEN
        let completionExpectation = self.expectation(description: "Callback invoked")
        let migrationExpectation = self.expectation(description: "Migration invoked")
        migrationExpectation.isInverted = true
        
        // WHEN
        StorageStack.shared.fetchUserIDFromLegacyStore(
            container: self.baseURL,
            startedMigrationCallback: { migrationExpectation.fulfill() }
        ) { userID in
            completionExpectation.fulfill()
            XCTAssertNil(userID)
        }
        
        // THEN
        self.waitForExpectations(timeout: 0.5)
    }
    
    func testThatItReturnsNilWhenLegacyStoreExistsButThereIsNoUser() {
        
        // GIVEN
        let oldLocations = PersistentStoreRelocator.possiblePreviousStoreLocations(sharedContainerURL: self.baseURL)
        
        oldLocations.forEach { oldPath in
            
            let completionExpectation = self.expectation(description: "Callback invoked")
            let migrationExpectation = self.expectation(description: "Migration invoked")
            migrationExpectation.isInverted = true
            createStorageStackAndWaitForCompletion(path: oldPath, changes: nil)
            
            // WHEN
            StorageStack.shared.fetchUserIDFromLegacyStore(
                container: self.baseURL,
                startedMigrationCallback: { migrationExpectation.fulfill() }
            ) { userID in
                completionExpectation.fulfill()
                XCTAssertNil(userID)
            }
            
            // THEN
            self.wait(for: [completionExpectation, migrationExpectation], timeout: 0.5)
            StorageStack.reset()
            clearStorageFolder()
        }
    }
    
    func testThatItReturnsUserIDFromLegacyStoreWhenItExists() {
        
        // GIVEN
        let oldLocations = PersistentStoreRelocator.possiblePreviousStoreLocations(sharedContainerURL: self.baseURL)
        
        oldLocations.forEach { oldPath in
            
            let userID = UUID()
            let completionExpectation = self.expectation(description: "Callback invoked")
            let migrationExpectation = self.expectation(description: "Migration invoked")
            migrationExpectation.isInverted = true
            
            createStorageStackAndWaitForCompletion(path: oldPath) { contextDirectory in
                ZMUser.selfUser(in: contextDirectory.uiContext).remoteIdentifier = userID
                contextDirectory.uiContext.forceSaveOrRollback()
            }
            
            // WHEN
            StorageStack.shared.fetchUserIDFromLegacyStore(
                container: self.baseURL,
                startedMigrationCallback: { migrationExpectation.fulfill() }
            ) { fetchedUserID in
                completionExpectation.fulfill()
                XCTAssertEqual(userID, fetchedUserID)
            }
            
            // THEN
            self.wait(for: [completionExpectation, migrationExpectation], timeout: 0.5)
            StorageStack.reset()
            clearStorageFolder()
        }
    }
}

extension StorageStackTests {
    
    fileprivate func clearStorageFolder() {
        try? FileManager.default.removeItem(at: self.baseURL)
        
    }
}

extension DatabaseBaseTest {
    
    func createStorageStackAndWaitForCompletion(
        container: URL,
        userID: UUID = UUID()
        ) -> ManagedObjectContextDirectory {
        
        var contextDirectory: ManagedObjectContextDirectory? = nil
        
        StorageStack.shared.createManagedObjectContextDirectory(
            accountIdentifier: userID,
            container: container
        ) { directory in
            contextDirectory = directory
        }
        
        guard self.waitOnMainLoop(until: { contextDirectory != nil }, timeout: 5) else {
            XCTFail()
            fatalError()
        }
        let psc = contextDirectory!.uiContext.persistentStoreCoordinator!.persistentStores.first!
        self.createExternalSupportFileForDatabase(at: psc.url!)
        return contextDirectory!
    }
    
    @objc public func createLegacyStore(path: FileManager.SearchPathDirectory) {
        let directory = FileManager.default.urls(for: path, in: .userDomainMask).first!
        self.createStorageStackAndWaitForCompletion(path: directory)
    }
    
    @objc public func createStorageStackAndWaitForCompletion(path: URL) {
        self.createStorageStackAndWaitForCompletion(path: path, changes: nil)
    }
    
    func createStorageStackAndWaitForCompletion(path: URL, changes: ((ManagedObjectContextDirectory) -> Void)?) {
        
        // create a proper stack and set some values, so we have something to migrate
        let storeURL: URL = {
            // keep this variable in a scope, so contextDirectory is released at the end of scope
            let contextDirectory = self.createStorageStackAndWaitForCompletion(
                container: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!,
                userID: UUID()
            )
            changes?(contextDirectory)
            return contextDirectory.uiContext.persistentStoreCoordinator!.persistentStores.first!.url!
        }()
        StorageStack.reset()
        
        // move the stack to "old" location, to simulate that the database needs to be migrated from there
        let initialFolderWithDatabase = storeURL.deletingLastPathComponent()
        let legacyFolderWithDatabase = path.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: legacyFolderWithDatabase.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! FileManager.default.moveItem(at: initialFolderWithDatabase, to: legacyFolderWithDatabase)
    }
}











