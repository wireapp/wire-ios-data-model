//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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


import XCTest
@testable import WireDataModel

final class ClientMessageTests_EditingSwift: BaseZMClientMessageTests {}

// MARK: - Payload creation
extension ClientMessageTests_EditingSwift {
    
    private func checkThatItCanEditAMessageFrom(sameSender: Bool, shouldEdit: Bool) {
        // given
        let oldText = "Hallo"
        let newText = "Hello"
        let sender = sameSender
            ? self.selfUser
            : ZMUser.insertNewObject(in:self.uiMOC)
        
        if !sameSender {
            sender?.remoteIdentifier = UUID.create()
        }
        
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID.create()
        let message = conversation.append(text: oldText) as! ZMClientMessage
        message.sender = sender
        message.markAsSent()
        message.serverTimestamp = Date.init(timeIntervalSinceNow: -20)
        let originalNonce = message.nonce
        
        XCTAssertEqual(message.visibleInConversation, conversation)
        XCTAssertEqual(conversation.allMessages.count, 1)
        XCTAssertEqual(conversation.hiddenMessages.count, 0)
        
        // when
        message.textMessageData?.editText(newText, mentions: [], fetchLinkPreview: true)
        
        // then
        
        XCTAssertEqual(conversation.allMessages.count, 1)
        
        if shouldEdit {
            XCTAssertEqual(message.textMessageData?.messageText, newText)
            XCTAssertEqual(message.normalizedText, newText.lowercased())
            XCTAssertEqual(message.underlyingMessage?.edited.replacingMessageID, originalNonce!.transportString())
            XCTAssertNotEqual(message.nonce, originalNonce)
        } else {
            XCTAssertEqual(message.textMessageData?.messageText, oldText)
        }
    }
    
    func testThatItCanEditAMessage_SameSender() {
        checkThatItCanEditAMessageFrom(sameSender: true, shouldEdit: true)
    }
    
    func testThatItCanNotEditAMessage_DifferentSender() {
        checkThatItCanEditAMessageFrom(sameSender: false, shouldEdit: false)
    }
    
    func testThatExtremeCombiningCharactersAreRemovedFromTheMessage() {
        // GIVEN
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID.create()
        
        // WHEN
        let message: ZMMessage = conversation.append(text: "ť̹̱͉̥̬̪̝ͭ͗͊̕e͇̺̳̦̫̣͕ͫͤ̅s͇͎̟͈̮͎̊̾̌͛ͭ́͜t̗̻̟̙͑ͮ͊ͫ̂") as! ZMMessage
        
        // THEN
        XCTAssertEqual(message.textMessageData?.messageText, "test̻̟̙")
    }

    func testThatItResetsTheLinkPreviewState() {
        // given
        let oldText = "Hallo"
        let newText = "Hello"
        
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID.create()
        let message = conversation.append(text: oldText) as! ZMClientMessage
        message.serverTimestamp = Date.init(timeIntervalSinceNow: -20)
        message.linkPreviewState = ZMLinkPreviewState.done
        message.markAsSent()
        
        XCTAssertEqual(message.linkPreviewState, ZMLinkPreviewState.done)
        
        // when
        message.textMessageData?.editText(newText, mentions: [], fetchLinkPreview: true)
        
        // then
        XCTAssertEqual(message.linkPreviewState, ZMLinkPreviewState.waitingToBeProcessed)
    }

    func testThatItDoesNotFetchLinkPreviewIfExplicitlyToldNotTo() {
        // given
        let oldText = "Hallo"
        let newText = "Hello"
        
        let fetchLinkPreview = false
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID.create()
        let message = conversation.append(text: oldText, mentions: [], fetchLinkPreview: fetchLinkPreview, nonce: UUID.create()) as! ZMClientMessage
        message.serverTimestamp = Date.init(timeIntervalSinceNow: -20)
        message.markAsSent()
        
        XCTAssertEqual(message.linkPreviewState, ZMLinkPreviewState.done)
        
        // when
        message.textMessageData?.editText(newText, mentions: [], fetchLinkPreview: fetchLinkPreview)
        
        // then
        XCTAssertEqual(message.linkPreviewState, ZMLinkPreviewState.done)
    }
    
    func testThatItDoesNotEditAMessageThatFailedToSend() {
        // given
        let oldText = "Hallo"
        let newText = "Hello"
        
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID.create()
        let message: ZMMessage = conversation.append(text: oldText) as! ZMMessage
        message.serverTimestamp = Date.init(timeIntervalSinceNow: -20)
        message.expire()
        XCTAssertEqual(message.deliveryState, ZMDeliveryState.failedToSend)
        
        // when
        message.textMessageData?.editText(newText, mentions: [], fetchLinkPreview: true)
        
        // then
        XCTAssertEqual(message.textMessageData?.messageText, oldText)
    }
    
    func testThatItUpdatesTheUpdatedTimestampAfterSuccessfulUpdate() {
        // given
        let oldText = "Hallo"
        let newText = "Hello"
        let originalDate = Date.init(timeIntervalSinceNow: -50)
        let updateDate: Date = Date.init(timeIntervalSinceNow: -20)
        
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID.create()
        let message = conversation.append(text: oldText) as! ZMMessage
        message.serverTimestamp = originalDate
        message.markAsSent()
        
        conversation.lastModifiedDate = originalDate
        conversation.lastServerTimeStamp = originalDate
        
        XCTAssertEqual(message.visibleInConversation, conversation)
        XCTAssertEqual(conversation.allMessages.count, 1)
        XCTAssertEqual(conversation.hiddenMessages.count, 0)
        
        message.textMessageData?.editText(newText, mentions: [], fetchLinkPreview: false)
        
        // when
        message.update(withPostPayload: ["time": updateDate], updatedKeys: nil)
        
        // then
        XCTAssertEqual(message.serverTimestamp, originalDate)
        XCTAssertEqual(message.updatedAt, updateDate)
        XCTAssertEqual(message.textMessageData?.messageText, newText)
    }

    func testThatItDoesNotOverwritesEditedTextWhenMessageExpiresButReplacesNonce() {
        // given
        let oldText = "Hallo"
        let newText = "Hello"
        let originalDate = Date.init(timeIntervalSinceNow: -50)
        
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID.create()
        let message = conversation.append(text: oldText) as! ZMMessage
        message.serverTimestamp = originalDate
        message.markAsSent()
        
        conversation.lastModifiedDate = originalDate
        conversation.lastServerTimeStamp = originalDate
        let originalNonce = message.nonce
        
        XCTAssertEqual(message.visibleInConversation, conversation)
        XCTAssertEqual(conversation.allMessages.count, 1)
        XCTAssertEqual(conversation.hiddenMessages.count, 0)
        
        message.textMessageData?.editText(newText, mentions: [], fetchLinkPreview: false)
        
        // when
        message.expire()
        
        // then
        XCTAssertEqual(message.nonce, originalNonce)
    }
    
    func testThatWhenResendingAFailedEditItReappliesTheEdit() {
        // given
        let oldText = "Hallo"
        let newText = "Hello"
        let originalDate = Date.init(timeIntervalSinceNow: -50)
        
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID.create()
        let message: ZMClientMessage = conversation.append(text: oldText) as! ZMClientMessage
        message.serverTimestamp = originalDate
        message.markAsSent()
        
        conversation.lastModifiedDate = originalDate;
        conversation.lastServerTimeStamp = originalDate;
        let originalNonce = message.nonce
        
        XCTAssertEqual(message.visibleInConversation, conversation)
        XCTAssertEqual(conversation.allMessages.count, 1)
        XCTAssertEqual(conversation.hiddenMessages.count, 0)
        
        message.textMessageData?.editText(newText, mentions: [], fetchLinkPreview: false)
        let editNonce1 = message.nonce
        
        message.expire()
        
        // when
        message.resend()
        let editNonce2 = message.nonce
        
        // then
        XCTAssertFalse(message.isExpired)
        XCTAssertNotEqual(editNonce2, editNonce1)
        XCTAssertEqual(message.underlyingMessage?.edited.replacingMessageID, originalNonce?.transportString())
    }
    
    private func createMessageEditUpdateEvent(oldNonce: UUID, newNonce: UUID, conversationID: UUID, senderID: UUID,  newText: String) -> ZMUpdateEvent? {
        let genericMessage: GenericMessage = GenericMessage(content: MessageEdit(replacingMessageID: oldNonce, text: Text(content: newText, mentions: [], linkPreviews: [], replyingTo: nil)), nonce: newNonce)
        
        let data = try? genericMessage.serializedData().base64String()
        let payload: NSMutableDictionary = [
            "conversation": conversationID.transportString(),
            "from": senderID.transportString(),
            "time": Date().transportString(),
            "data": [
                "text": data ?? "",
            ],
            "type": "conversation.otr-message-add"
        ]
        
        return ZMUpdateEvent.eventFromEventStreamPayload(payload, uuid: UUID.create())
    }

    private func createTextAddedEvent(nonce: UUID, conversationID: UUID, senderID: UUID) -> ZMUpdateEvent? {
        let genericMessage: GenericMessage = GenericMessage(content: Text(content: "Yeah!", mentions: [], linkPreviews: [], replyingTo: nil), nonce: nonce)
        
        let data = try? genericMessage.serializedData().base64String()
        let payload: NSMutableDictionary = [
            "conversation": conversationID.transportString,
            "from": senderID.transportString,
            "time": Date().transportString(),
            "data": [
                "text": data ?? ""
            ],
            "type": "conversation.otr-message-add"
        ]
        
        return ZMUpdateEvent.eventFromEventStreamPayload(payload, uuid: UUID.create())
    }

    func testThatItEditsMessageWithQuote() {
        // given
        let oldText = "Hallo"
        let newText = "Hello"
        let senderID = self.selfUser.remoteIdentifier
        
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID.create()
        let quotedMessage = conversation.append(text: "Quote") as! ZMMessage
        let message = conversation.append(text: oldText,
                                          mentions: [],
                                          replyingTo: quotedMessage,
                                          fetchLinkPreview: false,
                                          nonce: UUID.create()) as! ZMMessage
        self.uiMOC.saveOrRollback
        
        let updateEvent = createMessageEditUpdateEvent(oldNonce: message.nonce!, newNonce: UUID.create(), conversationID: conversation.remoteIdentifier!, senderID: senderID!, newText: newText)

        let oldNonce = message.nonce
        
        // when
        self.performPretendingUiMocIsSyncMoc {
            ZMClientMessage.createOrUpdate(from: updateEvent!, in: self.uiMOC, prefetchResult: nil)
            }
        
        // then
        XCTAssertEqual(message.textMessageData?.messageText, newText)
        XCTAssertTrue(message.textMessageData!.hasQuote)
        XCTAssertNotEqual(message.nonce, oldNonce)
        XCTAssertEqual(message.textMessageData?.quote, quotedMessage)
    }
    
    func testThatReadExpectationIsKeptAfterEdit() {
        // given
        let oldText = "Hallo"
        let newText = "Hello"
        let senderID = self.selfUser.remoteIdentifier
        
        self.selfUser.readReceiptsEnabled = true
        
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID.create()
        conversation.conversationType = ZMConversationType.oneOnOne
        
        let message = conversation.append(text: oldText, mentions: [], fetchLinkPreview: false, nonce: UUID.create()) as! ZMClientMessage
        var genericMessage = message.underlyingMessage!
        genericMessage.setExpectsReadConfirmation(true)
        
        do {
            message.add(try genericMessage.serializedData())
        } catch {
            return
        }
        
        let updateEvent = createMessageEditUpdateEvent(oldNonce: message.nonce!, newNonce: UUID.create(), conversationID: conversation.remoteIdentifier!, senderID: senderID!, newText: newText)
        let oldNonce = message.nonce
        
        // when
        self.performPretendingUiMocIsSyncMoc {
            ZMClientMessage.createOrUpdate(from: updateEvent!, in: self.uiMOC, prefetchResult: nil)
        }
        
        // then
        XCTAssertEqual(message.textMessageData?.messageText, newText)
        XCTAssertNotEqual(message.nonce, oldNonce)
        XCTAssertTrue(message.needsReadConfirmation)
    }
    
//    - (void)checkThatItEditsMessageForSameSender:(BOOL)sameSender shouldEdit:(BOOL)shouldEdit
//    {
//    // given
//    NSString *oldText = @"Hallo";
//    NSString *newText = @"Hello";
//    NSUUID *senderID = sameSender ? self.selfUser.remoteIdentifier : [NSUUID createUUID];
//
//    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
//    conversation.remoteIdentifier = [NSUUID createUUID];
//    ZMMessage *message = (id) [conversation appendMessageWithText:oldText];
//
//    [message addReaction:@"👻" forUser:self.selfUser];
//    [self.uiMOC saveOrRollback];
//
//    ZMUpdateEvent *updateEvent = [self createMessageEditUpdateEventWithOldNonce:message.nonce newNonce:[NSUUID createUUID] conversationID:conversation.remoteIdentifier senderID:senderID newText:newText];
//    NSUUID *oldNonce = message.nonce;
//
//    // when
//    [self performPretendingUiMocIsSyncMoc:^{
//    [ZMClientMessage createOrUpdateMessageFromUpdateEvent:updateEvent inManagedObjectContext:self.uiMOC prefetchResult:nil];
//    }];
//    WaitForAllGroupsToBeEmpty(0.5);
//
//    // then
//    if (shouldEdit) {
//    XCTAssertEqualObjects(message.textMessageData.messageText, newText);
//    XCTAssertNotEqualObjects(message.nonce, oldNonce);
//    XCTAssertTrue(message.reactions.isEmpty);
//    XCTAssertEqual(message.visibleInConversation, conversation);
//    XCTAssertNil(message.hiddenInConversation);
//    } else {
//    XCTAssertEqualObjects(message.textMessageData.messageText, oldText);
//    XCTAssertEqualObjects(message.nonce, oldNonce);
//    XCTAssertEqual(message.visibleInConversation, conversation);
//    XCTAssertNil(message.hiddenInConversation);
//    }
//    }
//
//    - (void)testThatEditsMessageWhenSameSender
//    {
//    [self checkThatItEditsMessageForSameSender:YES shouldEdit:YES];
//    }
//
//    - (void)testThatDoesntEditMessageWhenSenderIsDifferent
//    {
//    [self checkThatItEditsMessageForSameSender:NO shouldEdit:NO];
//    }
//
//    - (void)testThatItDoesNotInsertAMessageWithANonceBelongingToAHiddenMessage
//    {
//    // given
//    NSString *oldText = @"Hallo";
//    NSUUID *senderID = self.selfUser.remoteIdentifier;
//
//    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
//    conversation.remoteIdentifier = [NSUUID createUUID];
//    ZMMessage *message = (id) [conversation appendMessageWithText:oldText];
//    message.visibleInConversation = nil;
//    message.hiddenInConversation = conversation;
//
//    ZMUpdateEvent *updateEvent = [self createTextAddedEventWithNonce:message.nonce conversationID:conversation.remoteIdentifier senderID:senderID];
//
//    // when
//    __block ZMClientMessage *newMessage;
//    [self performPretendingUiMocIsSyncMoc:^{
//    newMessage = [ZMClientMessage createOrUpdateMessageFromUpdateEvent:updateEvent inManagedObjectContext:self.uiMOC prefetchResult:nil];
//    }];
//    WaitForAllGroupsToBeEmpty(0.5);
//
//    // then
//    XCTAssertNil(newMessage);
//    }
//
//    - (void)testThatItSetsTheTimestampsOfTheOriginalMessage
//    {
//    // given
//    NSString *oldText = @"Hallo";
//    NSString *newText = @"Hello";
//    NSDate *oldDate = [NSDate dateWithTimeIntervalSinceNow:-20];
//    ZMUser *sender = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
//    sender.remoteIdentifier = [NSUUID createUUID];
//
//    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
//    conversation.remoteIdentifier = [NSUUID createUUID];
//    ZMMessage *message = (id) [conversation appendMessageWithText:oldText];
//    message.sender = sender;
//    message.serverTimestamp = oldDate;
//
//    conversation.lastModifiedDate = oldDate;
//    conversation.lastServerTimeStamp = oldDate;
//    conversation.lastReadServerTimeStamp = oldDate;
//    XCTAssertEqual(conversation.estimatedUnreadCount, 0u);
//
//    ZMUpdateEvent *updateEvent = [self createMessageEditUpdateEventWithOldNonce:message.nonce newNonce:[NSUUID createUUID] conversationID:conversation.remoteIdentifier senderID:sender.remoteIdentifier newText:newText];
//
//    // when
//    __block ZMClientMessage *newMessage;
//
//    [self performPretendingUiMocIsSyncMoc:^{
//    newMessage = [ZMClientMessage createOrUpdateMessageFromUpdateEvent:updateEvent inManagedObjectContext:self.uiMOC prefetchResult:nil];
//    }];
//    WaitForAllGroupsToBeEmpty(0.5);
//
//    // then
//    XCTAssertEqualObjects(conversation.lastModifiedDate, oldDate);
//    XCTAssertEqualObjects(conversation.lastServerTimeStamp, oldDate);
//    XCTAssertEqualObjects(newMessage.serverTimestamp, oldDate);
//    XCTAssertEqualObjects(newMessage.updatedAt, updateEvent.timeStamp);
//
//    XCTAssertEqual(conversation.estimatedUnreadCount, 0u);
//    }
    
    func testThatItDoesNotReinsertAMessageThatHasBeenPreviouslyHiddenLocally() {
        // given
        let oldText = "Hallo"
        let newText = "Hello"
        let oldDate = Date.init(timeIntervalSinceNow: -20)
        let sender = ZMUser.insertNewObject(in:self.uiMOC)
        sender.remoteIdentifier = UUID.create()
        
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID.create()
        
        // insert message locally
        let message: ZMMessage = conversation.append(text: oldText) as! ZMMessage
        message.sender = sender
        message.serverTimestamp = oldDate
        
        // hide message locally
        ZMMessage.hideMessage(message)
        XCTAssertTrue(message.isZombieObject)
        
        let updateEvent = createMessageEditUpdateEvent(oldNonce: message.nonce!, newNonce: UUID.create(), conversationID: conversation.remoteIdentifier!, senderID: sender.remoteIdentifier, newText: newText)
        
        // when
        var newMessage: ZMClientMessage?
        
        self.performPretendingUiMocIsSyncMoc {
            newMessage = ZMClientMessage.createOrUpdate(from: updateEvent!, in: self.uiMOC, prefetchResult: nil)
        }
        
        // then
        XCTAssertNil(newMessage)
        XCTAssertNil(message.visibleInConversation)
        XCTAssertTrue(message.isZombieObject)
        XCTAssertTrue(message.hasBeenDeleted)
        XCTAssertNil(message.textMessageData)
        XCTAssertNil(message.sender)
        XCTAssertNil(message.senderClientID)
        
        let clientMessage = message as! ZMClientMessage
        XCTAssertNil(clientMessage.underlyingMessage)
        XCTAssertEqual(clientMessage.dataSet.count, 0)
    }
    
//    - (void)testThatItClearsReactionsWhenAMessageIsEdited
//    {
//    // given
//    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
//    conversation.remoteIdentifier = [NSUUID createUUID];
//    ZMMessage *message = (id) [conversation appendMessageWithText:@"Hallo"];
//
//    ZMUser *otherUser = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
//    otherUser.remoteIdentifier = NSUUID.createUUID;
//
//    [message addReaction:@"😱" forUser:self.selfUser];
//    [message addReaction:@"🤗" forUser:otherUser];
//
//    [self.uiMOC saveOrRollback];
//    XCTAssertFalse(message.reactions.isEmpty);
//
//    ZMUpdateEvent *updateEvent = [self createMessageEditUpdateEventWithOldNonce:message.nonce
//    newNonce:NSUUID.createUUID
//    conversationID:conversation.remoteIdentifier
//    senderID:message.sender.remoteIdentifier
//    newText:@"Hello"];
//    // when
//    __block ZMClientMessage *newMessage;
//
//    [self performPretendingUiMocIsSyncMoc:^{
//    newMessage = [ZMClientMessage createOrUpdateMessageFromUpdateEvent:updateEvent inManagedObjectContext:self.uiMOC prefetchResult:nil];
//    }];
//    WaitForAllGroupsToBeEmpty(0.5);
//
//    // then
//    XCTAssertTrue(message.reactions.isEmpty);
//    XCTAssertEqual(conversation.allMessages.count, 1lu);
//
//    ZMMessage *editedMessage = conversation.lastMessage;
//    XCTAssertTrue(editedMessage.reactions.isEmpty);
//    XCTAssertEqualObjects(editedMessage.textMessageData.messageText, @"Hello");
//    }
//
//    - (void)testThatItClearsReactionsWhenAMessageIsEditedRemotely
//    {
//    // given
//    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
//    conversation.remoteIdentifier = [NSUUID createUUID];
//    ZMMessage *message = (id) [conversation appendMessageWithText:@"Hallo"];
//
//    ZMUser *otherUser = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
//    otherUser.remoteIdentifier = NSUUID.createUUID;
//
//    [message addReaction:@"😱" forUser:self.selfUser];
//    [message addReaction:@"🤗" forUser:otherUser];
//
//    [self.uiMOC saveOrRollback];
//    XCTAssertFalse(message.reactions.isEmpty);
//
//    ZMUpdateEvent *updateEvent = [self createMessageEditUpdateEventWithOldNonce:message.nonce
//    newNonce:NSUUID.createUUID
//    conversationID:conversation.remoteIdentifier
//    senderID:message.sender.remoteIdentifier
//    newText:@"Hello"];
//    // when
//    __block ZMClientMessage *newMessage;
//
//    [self performPretendingUiMocIsSyncMoc:^{
//    newMessage = [ZMClientMessage createOrUpdateMessageFromUpdateEvent:updateEvent inManagedObjectContext:self.uiMOC prefetchResult:nil];
//    }];
//    WaitForAllGroupsToBeEmpty(0.5);
//
//    // then
//    XCTAssertTrue(message.reactions.isEmpty);
//    ZMMessage *editedMessage = conversation.lastMessage;
//    XCTAssertTrue(editedMessage.reactions.isEmpty);
//    XCTAssertEqualObjects(editedMessage.textMessageData.messageText, @"Hello");
//    }
//
//    - (void)testThatMessageNonPersistedIdentifierDoesNotChangeAfterEdit
//    {
//    // given
//    NSString *oldText = @"Mamma mia";
//    NSString *newText = @"here we go again";
//    NSUUID *oldNonce = [NSUUID createUUID];
//
//    ZMUser *sender = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
//    sender.remoteIdentifier = [NSUUID createUUID];
//
//    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
//    conversation.remoteIdentifier = [NSUUID createUUID];
//    ZMMessage *message = (id) [conversation appendMessageWithText:oldText];
//    message.sender = sender;
//    message.nonce = oldNonce;
//
//    NSString *oldIdentifier = message.nonpersistedObjectIdentifer;
//    ZMUpdateEvent *updateEvent = [self createMessageEditUpdateEventWithOldNonce:message.nonce newNonce:[NSUUID createUUID] conversationID:conversation.remoteIdentifier senderID:sender.remoteIdentifier newText:newText];
//
//    // when
//    __block ZMClientMessage *newMessage;
//
//    [self performPretendingUiMocIsSyncMoc:^{
//    newMessage = [ZMClientMessage createOrUpdateMessageFromUpdateEvent:updateEvent inManagedObjectContext:self.uiMOC prefetchResult:nil];
//    }];
//    WaitForAllGroupsToBeEmpty(0.5);
//
//    // then
//    XCTAssertNotEqualObjects(oldNonce, newMessage.nonce);
//    XCTAssertEqualObjects(oldIdentifier, newMessage.nonpersistedObjectIdentifer);
//    }
}
