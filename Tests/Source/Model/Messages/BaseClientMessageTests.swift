//
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
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
@testable import ZMCDataModel

class BaseZMClientMessageTests : BaseZMMessageTests {
    
    var syncSelfUser: ZMUser!
    var syncUser1: ZMUser!
    var syncUser2: ZMUser!
    var syncUser3: ZMUser!
    
    var syncSelfClient1: UserClient!
    var syncSelfClient2: UserClient!
    var syncUser1Client1: UserClient!
    var syncUser1Client2: UserClient!
    var syncUser2Client1: UserClient!
    var syncUser2Client2: UserClient!
    var syncUser3Client1: UserClient!
    
    var syncConversation: ZMConversation!
    var syncExpectedRecipients: [String: [String]]!

    var user1: ZMUser!
    var user2: ZMUser!
    var user3: ZMUser!
    
    var selfClient1: UserClient!
    var selfClient2: UserClient!
    var user1Client1: UserClient!
    var user1Client2: UserClient!
    var user2Client1: UserClient!
    var user2Client2: UserClient!
    var user3Client1: UserClient!
    
    var conversation: ZMConversation!
    
    var expectedRecipients: [String: [String]]!
    
    override func setUp() {
        super.setUp()

        self.syncMOC.performGroupedBlockAndWait {
            self.syncSelfUser = ZMUser.selfUser(in: self.syncMOC)
            
            self.syncSelfClient1 = self.createSelfClient(onMOC: self.syncMOC)
            self.syncMOC.setPersistentStore(metadata: self.syncSelfClient1.remoteIdentifier, for: "PersistedClientId")
            
            self.syncSelfClient2 = self.createClient(for: self.syncSelfUser, createSessionWithSelfUser: true, onMOC: self.syncMOC)
            
            self.syncUser1 = ZMUser.insertNewObject(in: self.syncMOC)
            self.syncUser1Client1 = self.createClient(for: self.syncUser1, createSessionWithSelfUser: true, onMOC: self.syncMOC)
            self.syncUser1Client2 = self.createClient(for: self.syncUser1, createSessionWithSelfUser: true, onMOC: self.syncMOC)
            
            self.syncUser2 = ZMUser.insertNewObject(in: self.syncMOC)
            self.syncUser2Client1 = self.createClient(for: self.syncUser2, createSessionWithSelfUser: true, onMOC: self.syncMOC)
            self.syncUser2Client2 = self.createClient(for: self.syncUser2, createSessionWithSelfUser: false, onMOC: self.syncMOC)
            
            self.syncUser3 = ZMUser.insertNewObject(in: self.syncMOC)
            self.syncUser3Client1 = self.createClient(for: self.syncUser3, createSessionWithSelfUser: false, onMOC: self.syncMOC)
            
            self.syncConversation = ZMConversation.insertGroupConversation(into: self.syncMOC, withParticipants: [self.syncUser1, self.syncUser2, self.syncUser3])
            self.syncConversation.remoteIdentifier = UUID.create()
            
            self.expectedRecipients = [
                self.syncSelfUser.remoteIdentifier!.transportString(): [
                    self.syncSelfClient2.remoteIdentifier!
                ],
                self.syncUser1.remoteIdentifier!.transportString(): [
                    self.syncUser1Client1.remoteIdentifier!,
                    self.syncUser1Client2.remoteIdentifier!
                ],
                self.syncUser2.remoteIdentifier!.transportString(): [
                    self.syncUser2Client1.remoteIdentifier!
                ]
            ]
            
            self.syncMOC.saveOrRollback()
        }
        
        self.selfUser = try! self.uiMOC.existingObject(with: self.syncSelfUser.objectID) as! ZMUser
        self.selfClient1 = try! self.uiMOC.existingObject(with: self.syncSelfClient1.objectID) as! UserClient
        self.uiMOC.setPersistentStore(metadata: self.selfClient1.remoteIdentifier!, for: "PersistedClientId")
        
        self.selfClient2 = try! self.uiMOC.existingObject(with: self.syncSelfClient2.objectID) as! UserClient
        
        self.user1 = try! self.uiMOC.existingObject(with: self.syncUser1.objectID) as! ZMUser
        self.user1Client1 = try! self.uiMOC.existingObject(with: self.syncUser1Client1.objectID) as! UserClient
        self.user1Client2 = try! self.uiMOC.existingObject(with: self.syncUser1Client2.objectID) as! UserClient
        
        self.user2 = try! self.uiMOC.existingObject(with: self.syncUser2.objectID) as! ZMUser
        self.user2Client1 = try! self.uiMOC.existingObject(with: self.syncUser2Client1.objectID) as! UserClient
        self.user2Client2 = try! self.uiMOC.existingObject(with: self.syncUser2Client2.objectID) as! UserClient
        
        self.user3 = try! self.uiMOC.existingObject(with: self.syncUser3.objectID) as! ZMUser
        self.user3Client1 = try! self.uiMOC.existingObject(with: self.syncUser3Client1.objectID) as! UserClient
        
        self.conversation = try! self.uiMOC.existingObject(with: self.syncConversation.objectID) as! ZMConversation
        self.expectedRecipients = [
            self.selfUser.remoteIdentifier!.transportString(): [
                self.selfClient2.remoteIdentifier!
            ],
            self.user1.remoteIdentifier!.transportString(): [
                self.user1Client1.remoteIdentifier!,
                self.user1Client2.remoteIdentifier!
            ],
            self.user2.remoteIdentifier!.transportString(): [
                self.user2Client1.remoteIdentifier!
            ]
        ]
    }
    
    override func tearDown() {
        syncMOC.performGroupedBlockAndWait {
            self.syncMOC.setPersistentStore(metadata: nil, for: "PersistedClientId")
        }
        wipeCaches()
        super.tearDown()
    }
    
    func assertRecipients(_ recipients: [ZMUserEntry], file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(recipients.count, expectedRecipients.count, file: file, line: line)
        
        for recipientEntry in recipients {
            var uuid : NSUUID!
            recipientEntry.user.uuid.withUnsafeBytes({ bytes in
                uuid = NSUUID(uuidBytes: bytes)
            })
            guard let expectedClientsIds : [String] = self.expectedRecipients[uuid.transportString()]?.sorted() else {
                XCTFail("Unexpected otr client in recipients", file: file, line: line)
                return
            }
            let clientIds = (recipientEntry.clients).map { String(format: "%llx", $0.client.client) }.sorted()
            XCTAssertEqual(clientIds, expectedClientsIds, file: file, line: line)
            let hasTexts = (recipientEntry.clients).map { $0.hasText() }
            XCTAssertFalse(hasTexts.contains(false), file: file, line: line)
            
        }
    }
    
    func createUpdateEvent(_ nonce: UUID, conversationID: UUID, genericMessage: ZMGenericMessage, senderID: UUID = .create(), eventSource: ZMUpdateEventSource = .download) -> ZMUpdateEvent {
        let payload : [String : Any] = [
            "conversation": conversationID.transportString(),
            "from": senderID.transportString(),
            "time": Date().transportString(),
            "data": [
                "text": genericMessage.data().base64String()
            ],
            "type": "conversation.otr-message-add"
        ]
        switch eventSource {
        case .download:
            return ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nonce)!
        default:
            let streamPayload = ["payload" : [payload],
                                 "id" : UUID.create().transportString()] as [String : Any]
            let event = ZMUpdateEvent.eventsArray(from: streamPayload as ZMTransportData,
                                                                   source: eventSource)!.first!
            XCTAssertNotNil(event)
            return event
        }
    }
    
}



