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
@testable import WireDataModel


class MessageObserverTests : NotificationDispatcherTestBase {
    
    
    
    var messageObserver : MessageObserver!
    
    override func setUp() {
        super.setUp()
        messageObserver = MessageObserver()
    }

    override func tearDown() {
        messageObserver = nil
        super.tearDown()
    }
    
    func checkThatItNotifiesTheObserverOfAChange<T: ZMMessage>(
        _ message: T,
        modifier: (T) -> Void,
        expectedChangedField: String?,
        customAffectedKeys: AffectedKeys? = nil
        ) {
        
        // given
        withExtendedLifetime(MessageChangeInfo.add(observer: self.messageObserver, for: message, managedObjectContext: self.uiMOC)) { () -> () in
            
            self.uiMOC.saveOrRollback()
            
            // when
            modifier(message)
            self.uiMOC.saveOrRollback()
            self.spinMainQueue(withTimeout: 0.5)
            
            // then
            XCTAssertEqual(messageObserver.notifications.count, expectedChangedField != nil ? 1 : 0)
            
            // and when
            self.uiMOC.saveOrRollback()
            
            // then
            XCTAssertTrue(messageObserver.notifications.count <= 1, "Should have changed only once")
            
            let messageInfoKeys = [
                #keyPath(MessageChangeInfo.imageChanged),
                #keyPath(MessageChangeInfo.deliveryStateChanged),
                #keyPath(MessageChangeInfo.senderChanged),
                #keyPath(MessageChangeInfo.linkPreviewChanged),
                #keyPath(MessageChangeInfo.isObfuscatedChanged),
                #keyPath(MessageChangeInfo.childMessagesChanged),
                #keyPath(MessageChangeInfo.reactionsChanged),
                #keyPath(MessageChangeInfo.transferStateChanged)
            ]

            guard let changedField = expectedChangedField else { return }
            guard let changes = messageObserver.notifications.first else { return }
            changes.checkForExpectedChangeFields(userInfoKeys: messageInfoKeys,
                                                 expectedChangedFields: [changedField])
        }
    }

    func testThatItNotifiesObserverWhenTheFileTransferStateChanges() {
        // given
        let message = ZMAssetClientMessage.insertNewObject(in: self.uiMOC)
        message.transferState = .uploading
        uiMOC.saveOrRollback()

        // when
        self.checkThatItNotifiesTheObserverOfAChange(
            message,
            modifier: { $0.transferState = .uploaded },
            expectedChangedField: #keyPath(MessageChangeInfo.transferStateChanged)
        )
    }
    
    
    func testThatItNotifiesObserverWhenTheMediumImageDataChanges() {
        // given
        let message = ZMAssetClientMessage.insertNewObject(in: self.uiMOC)
        uiMOC.saveOrRollback()

        let imageData = verySmallJPEGData()
        let imageSize = ZMImagePreprocessor.sizeOfPrerotatedImage(with: imageData)
        let properties = ZMIImageProperties(size:imageSize, length:UInt(imageData.count), mimeType:"image/jpeg")
        let keys = ZMImageAssetEncryptionKeys(otrKey: Data.randomEncryptionKey(),
                                              macKey: Data.zmRandomSHA256Key(),
                                              mac: Data.zmRandomSHA256Key())

        let imageMessage = ZMGenericMessage.genericMessage(mediumImageProperties: properties,
                                                           processedImageProperties: properties,
                                                           encryptionKeys: keys,
                                                           nonce: UUID.create().transportString(),
                                                           format: .preview)

        // when
        self.checkThatItNotifiesTheObserverOfAChange(
            message,
            modifier: { $0.add(imageMessage) },
            expectedChangedField: #keyPath(MessageChangeInfo.imageChanged)
        )
    }

    func testThatItNotifiesObserverWhenTheLinkPreviewStateChanges() {
        // when
        checkThatItNotifiesTheObserverOfAChange(
            ZMClientMessage.insertNewObject(in: uiMOC),
            modifier: { $0.linkPreviewState = .downloaded },
            expectedChangedField: #keyPath(MessageChangeInfo.linkPreviewChanged)
        )
    }
    
    func testThatItNotifiesObserverWhenTheLinkPreviewStateChanges_NewGenericMessageData() {
        // given
        let clientMessage = ZMClientMessage.insertNewObject(in: uiMOC)
        let nonce = UUID.create()
        clientMessage.add(ZMGenericMessage.message(text: name!, nonce: nonce.transportString()).data())
        let preview = ZMLinkPreview.linkPreview(
            withOriginalURL: "www.example.com",
            permanentURL: "www.example.com/permanent",
            offset: 42,
            title: "title",
            summary: "summary",
            imageAsset: nil
        )
        let updateGenericMessage = ZMGenericMessage.message(text: name!, linkPreview: preview, nonce: nonce.transportString())
        uiMOC.saveOrRollback()
        
        // when
        checkThatItNotifiesTheObserverOfAChange(
            clientMessage,
            modifier: { $0.add(updateGenericMessage.data()) },
            expectedChangedField: #keyPath(MessageChangeInfo.linkPreviewChanged)
        )
    }
    
    func testThatItDoesNotNotifiyObserversWhenTheSmallImageDataChanges() {
        // given
        let message = ZMImageMessage.insertNewObject(in: self.uiMOC)
        uiMOC.saveOrRollback()

        // when
        self.checkThatItNotifiesTheObserverOfAChange(
            message,
            modifier: { $0.previewData = verySmallJPEGData() },
            expectedChangedField: nil
        )
    }
    
    func testThatItNotifiesWhenAReactionIsAddedOnMessage() {
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        let message = conversation.appendMessage(withText: "foo") as! ZMClientMessage
        uiMOC.saveOrRollback()

        // when
        self.checkThatItNotifiesTheObserverOfAChange(
            message,
            modifier: { $0.addReaction("LOVE IT, HUH", forUser: ZMUser.selfUser(in: self.uiMOC))},
            expectedChangedField: #keyPath(MessageChangeInfo.reactionsChanged)
        )
    }
    
    func testThatItNotifiesWhenAReactionIsAddedOnMessageFromADifferentUser() {
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        let message = conversation.appendMessage(withText: "foo") as! ZMClientMessage

        let otherUser = ZMUser.insertNewObject(in:uiMOC)
        otherUser.name = "Hans"
        otherUser.remoteIdentifier = .create()
        uiMOC.saveOrRollback()

        // when
        checkThatItNotifiesTheObserverOfAChange(
            message,
            modifier: { $0.addReaction("👻", forUser: otherUser) },
            expectedChangedField: #keyPath(MessageChangeInfo.reactionsChanged)
        )
    }
    
    func testThatItNotifiesWhenAReactionIsUpdateForAUserOnMessage() {
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        let message = conversation.appendMessage(withText: "foo") as! ZMClientMessage

        let selfUser = ZMUser.selfUser(in: self.uiMOC)
        message.addReaction("LOVE IT, HUH", forUser: selfUser)
        uiMOC.saveOrRollback()

        // when
        self.checkThatItNotifiesTheObserverOfAChange(
            message,
            modifier: {$0.addReaction(nil, forUser: selfUser)},
            expectedChangedField: #keyPath(MessageChangeInfo.reactionsChanged)
        )
    }
    
    func testThatItNotifiesWhenAReactionFromADifferentUserIsAddedOnTopOfSelfReaction() {
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        let message = conversation.appendMessage(withText: "foo") as! ZMClientMessage

        let otherUser = ZMUser.insertNewObject(in:uiMOC)
        otherUser.name = "Hans"
        otherUser.remoteIdentifier = .create()
        
        let selfUser = ZMUser.selfUser(in: self.uiMOC)
        message.addReaction("👻", forUser: selfUser)
        uiMOC.saveOrRollback()

        // when
        checkThatItNotifiesTheObserverOfAChange(
            message,
            modifier: { $0.addReaction("👻", forUser: otherUser) },
            expectedChangedField: #keyPath(MessageChangeInfo.reactionsChanged)
        )
    }

    func testThatItNotifiesObserversWhenDeliveredChanges(){
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        let message = conversation.appendMessage(withText: "foo") as! ZMClientMessage
        XCTAssertFalse(message.delivered)
        uiMOC.saveOrRollback()
        
        // when
        checkThatItNotifiesTheObserverOfAChange(
            message,
            modifier: { $0.markAsSent(); XCTAssertTrue($0.delivered) },
            expectedChangedField: #keyPath(MessageChangeInfo.deliveryStateChanged)
        )
    }
    
    func testThatItStopsNotifyingAfterUnregisteringTheToken() {
        
        // given
        let message = ZMClientMessage.insertNewObject(in: self.uiMOC)
        self.uiMOC.saveOrRollback()
        
        self.performIgnoringZMLogError{
            _ = MessageChangeInfo.add(observer: self.messageObserver, for: message, managedObjectContext: self.uiMOC)
        }
        // when
        message.serverTimestamp = Date()
        self.uiMOC.saveOrRollback()
        
        // then
        XCTAssertEqual(messageObserver.notifications.count, 0)
    }

    func testThatItNotifiesWhenTheChildMessagesOfASystemMessageChange() {
        // given
        let conversation = ZMConversation.insertNewObject(in: uiMOC)
        let message = conversation.appendPerformedCallMessage(with: 42, caller: .selfUser(in: uiMOC))
        let otherMessage = ZMSystemMessage.insertNewObject(in: uiMOC)

        checkThatItNotifiesTheObserverOfAChange(
            message,
            modifier: { $0.mutableSetValue(forKey: #keyPath(ZMSystemMessage.childMessages)).add(otherMessage) },
            expectedChangedField: #keyPath(MessageChangeInfo.childMessagesChanged)
        )
    }

}
