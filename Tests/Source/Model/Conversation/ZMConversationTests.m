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


@import ZMTransport;

#import "ZMConversationTests.h"
#import "ZMUser.h"
#import "ZMConversation+Internal.h"
#import "ZMMessage+Internal.h"
#import "ZMConversationList+Internal.h"
#import "ZMConversationMessageWindow.h"
#import "ZMConnection+Internal.h"
#import "ZMConversation+Internal.h"
#import "ZMConversationList+Internal.h"
#import "ZMClientMessage.h"
#import "ZMConversation+UnreadCount.h"
#import "ZMConversation+Transport.h"


@interface ZMConversationTestsBase ()

@property (nonatomic) NSMutableArray *receivedNotifications;

- (ZMConversation *)insertConversationWithParticipants:(NSArray *)participants
                                      callParticipants:(NSArray *)callParticipants
                  callStateNeedsToBeUpdatedFromBackend:(BOOL)callStateNeedsToBeUpdatedFromBackend;
- (NSDate *)timeStampForSortAppendMessageToConversation:(ZMConversation *)conversation;

- (ZMMessage *)insertDownloadedMessageAfterMessageIntoConversation:(ZMConversation *)conversation;
- (ZMMessage *)insertDownloadedMessageIntoConversation:(ZMConversation *)conversation;

@end


@implementation ZMConversationTestsBase

- (void)setUp;
{
    [super setUp];
    
    [self setupSelfConversation]; // when updating lastRead we are posting to the selfConversation
}

- (void)setupSelfConversation
{
    NSUUID *selfUserID =  [NSUUID UUID];
    [ZMUser selfUserInContext:self.uiMOC].remoteIdentifier = selfUserID;
    ZMConversation *selfConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    selfConversation.remoteIdentifier = selfUserID;
    selfConversation.conversationType = ZMConversationTypeSelf;
    [self.uiMOC saveOrRollback];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.syncMOC refreshObject:[ZMUser selfUserInContext:self.syncMOC] mergeChanges:NO];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)didReceiveWindowNotification:(NSNotification *)notification
{
    self.lastReceivedNotification = notification;
}

- (id)mockUserSessionWithUIMOC;
{
    id userSession = [OCMockObject mockForProtocol:@protocol(ZMManagedObjectContextProvider)];
    [[[userSession stub] andReturn:self.uiMOC] managedObjectContext];
    return userSession;
}

- (ZMUser *)createUser
{
    return [self createUserOnMoc:self.uiMOC];
}

- (ZMUser *)createUserOnMoc:(NSManagedObjectContext *)moc
{
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:moc];
    user.remoteIdentifier = [NSUUID createUUID];
    return user;
}

- (ZMConversation *)insertConversationWithParticipants:(NSArray *)participants
                                      callParticipants:(NSArray *)callParticipants
                  callStateNeedsToBeUpdatedFromBackend:(BOOL)callStateNeedsToBeUpdatedFromBackend
{
    __block NSManagedObjectID *objectID;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        
        NSArray *syncParticipants = [[participants mapWithBlock:^id(ZMUser *user){
            return [self.syncMOC objectWithID:user.objectID];
        }] filterWithBlock:^BOOL(ZMUser *user){
            return user != selfUser;
        }];
        ZMConversation *conversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC withParticipants:syncParticipants];
        conversation.conversationType = ZMConversationTypeGroup;
        conversation.remoteIdentifier = NSUUID.createUUID;
        for (ZMUser *user in callParticipants) {
            ZMUser *syncUser = (id)[self.syncMOC objectWithID:user.objectID];
            [[conversation mutableOrderedSetValueForKey:ZMConversationCallParticipantsKey] addObject:syncUser];
        }
        conversation.callStateNeedsToBeUpdatedFromBackend = callStateNeedsToBeUpdatedFromBackend;
        [self.syncMOC saveOrRollback];
        objectID = conversation.objectID;
    }];
    
    return (ZMConversation *)[self.uiMOC objectWithID:objectID];
}

- (NSDate *)timeStampForSortAppendMessageToConversation:(ZMConversation *)conversation
{
    if (conversation.lastServerTimeStamp == nil) {
        conversation.lastServerTimeStamp = [NSDate date];
    }
    ZMMessage *message = [ZMMessage insertNewObjectInManagedObjectContext:conversation.managedObjectContext];
    message.serverTimestamp = [conversation.lastServerTimeStamp dateByAddingTimeInterval:5];
    [conversation resortMessagesWithUpdatedMessage:message];
    conversation.lastServerTimeStamp = message.serverTimestamp;
    return message.serverTimestamp;
}


- (ZMMessage *)insertDownloadedMessageIntoConversation:(ZMConversation *)conversation
{
    NSDate *newTime = conversation.lastServerTimeStamp ? [conversation.lastServerTimeStamp dateByAddingTimeInterval:5] : [NSDate date];
    
    ZMTextMessage *message = [ZMTextMessage insertNewObjectInManagedObjectContext:self.uiMOC];
    message.serverTimestamp = newTime;
    conversation.lastServerTimeStamp = message.serverTimestamp;
    [conversation.mutableMessages addObject:message];
    return message;
}

- (ZMMessage *)insertDownloadedMessageAfterMessageIntoConversation:(ZMConversation *)conversation
{
    NSDate *newTime = conversation.lastServerTimeStamp ? [conversation.lastServerTimeStamp dateByAddingTimeInterval:5] : [NSDate date];
    
    ZMTextMessage *message = [ZMTextMessage insertNewObjectInManagedObjectContext:self.uiMOC];
    message.serverTimestamp = newTime;
    conversation.lastServerTimeStamp = message.serverTimestamp;
    [conversation.mutableMessages addObject:message];
    return message;
}


@end




@interface ZMConversationTests : ZMConversationTestsBase

@end



@implementation ZMConversationTests

- (void)testThatItSetsTheSelfUserAsCreatorWhenCreatingAGroupConversationFromTheUI
{
    // given
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    ZMUser *otherUser1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *otherUser2 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // when
    ZMConversation *conversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.uiMOC withParticipants:@[otherUser1, otherUser2]];
    
    // then
    XCTAssertEqualObjects(conversation.creator, selfUser);
    XCTAssertEqual(conversation.messages.count, 1u); // new conversation system message
}

- (void)testThatItHasLocallyModifiedDataFields
{
    XCTAssertTrue([ZMConversation isTrackingLocalModifications]);
    NSEntityDescription *entity = self.uiMOC.persistentStoreCoordinator.managedObjectModel.entitiesByName[ZMConversation.entityName];
    XCTAssertNotNil(entity.attributesByName[@"modifiedKeys"]);
}

- (void)testThatWeCanSetAttributesOnConversation
{
    [self checkConversationAttributeForKey:@"draftMessageText" value:@"It’s cold outside."];
    [self checkConversationAttributeForKey:ZMConversationUserDefinedNameKey value:@"Foo"];
    [self checkConversationAttributeForKey:@"normalizedUserDefinedName" value:@"Foo"];
    [self checkConversationAttributeForKey:@"conversationType" value:@(1)];
    [self checkConversationAttributeForKey:@"lastModifiedDate" value:[NSDate dateWithTimeIntervalSince1970:123456]];
    [self checkConversationAttributeForKey:@"remoteIdentifier" value:[NSUUID createUUID]];
    [self checkConversationAttributeForKey:ZMConversationIsSilencedKey value:@YES];
    [self checkConversationAttributeForKey:ZMConversationIsSilencedKey value:@NO];
    [self checkConversationAttributeForKey:ZMConversationIsArchivedKey value:@YES];
    [self checkConversationAttributeForKey:ZMConversationIsArchivedKey value:@NO];
    [self checkConversationAttributeForKey:ZMConversationIsSelfAnActiveMemberKey value:@YES];
    [self checkConversationAttributeForKey:ZMConversationIsSelfAnActiveMemberKey value:@NO];
    [self checkConversationAttributeForKey:@"needsToBeUpdatedFromBackend" value:@YES];
    [self checkConversationAttributeForKey:@"needsToBeUpdatedFromBackend" value:@NO];
    [self checkConversationAttributeForKey:ZMConversationLastReadServerTimeStampKey value:[NSDate date]];
    [self checkConversationAttributeForKey:ZMConversationLastServerTimeStampKey value:[NSDate date]];

}

- (void)checkConversationAttributeForKey:(NSString *)key value:(id)value;
{
    [self checkAttributeForClass:[ZMConversation class] key:key value:value];
}

- (void)testThatSpecialKeysAreNotPartOfTheLocallyModifiedKeys
{
    // given
    NSSet *expected = [NSSet setWithArray:@[
                          ZMConversationUserDefinedNameKey,
                          ZMConversationUnsyncedInactiveParticipantsKey,
                          ZMConversationUnsyncedActiveParticipantsKey,
                          ZMConversationIsSelfAnActiveMemberKey,
                          ZMConversationCallDeviceIsActiveKey,
                          ZMConversationLastReadServerTimeStampKey,
                          ZMConversationClearedTimeStampKey,
                          ZMConversationIsSendingVideoKey,
                          ZMConversationIsIgnoringCallKey,
                          ZMConversationSilencedChangedTimeStampKey,
                          ZMConversationArchivedChangedTimeStampKey,
                          ]];
    
    // when
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];

    // then
    XCTAssertEqualObjects(conversation.keysTrackedForLocalModifications, expected);
}

- (void)testThatItAddsCallDeviceIsActiveToLocallyModifiedKeysIfHasLocalModificationsForCallDeviceIsActiveIsSet
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeOneOnOne;
    XCTAssertFalse(conversation.hasLocalModificationsForCallDeviceIsActive);
    XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:ZMConversationCallDeviceIsActiveKey]);

    // when
    conversation.callDeviceIsActive = YES;
    
    // then
    XCTAssertTrue(conversation.hasLocalModificationsForCallDeviceIsActive);
    XCTAssertTrue([conversation.keysThatHaveLocalModifications containsObject:ZMConversationCallDeviceIsActiveKey]);
}


- (void)testThatItReturnsAnExistingConversationByUUID
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        NSUUID *uuid = NSUUID.createUUID;
        conversation.remoteIdentifier = uuid;
        
        // when
        ZMConversation *found = [ZMConversation conversationWithRemoteID:uuid createIfNeeded:NO inContext:self.syncMOC];
        
        // then
        XCTAssertEqualObjects(found.remoteIdentifier, uuid);
        XCTAssertEqualObjects(found.objectID, conversation.objectID);
    }];
}

- (void)testThatItDoesNotCreateTheSelfConversationOnTheSyncMoc
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        NSUUID *uuid = NSUUID.createUUID;
        [ZMUser selfUserInContext:self.syncMOC].remoteIdentifier = uuid;
        [self.syncMOC saveOrRollback];
        
        // when
        ZMConversation *conversation = [ZMConversation conversationWithRemoteID:uuid createIfNeeded:YES inContext:self.syncMOC];
        
        // then
        XCTAssertNotNil(conversation);
    }];
}


- (void)testThatItReturnsAnExistingConversationByUUIDEvenIfTheTypeIsInvalid
{
    // given
    NSUUID *uuid = NSUUID.createUUID;
    __block NSManagedObjectID *moid;
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeInvalid;
        conversation.remoteIdentifier = uuid;
        
        [self.syncMOC saveOrRollback];
        moid = conversation.objectID;
    }];
    
    // when
    ZMConversation *found = [ZMConversation conversationWithRemoteID:uuid createIfNeeded:NO inContext:self.uiMOC];
    
    // then
    XCTAssertEqualObjects(found.remoteIdentifier, uuid);
    XCTAssertEqualObjects(found.objectID, moid);
}

- (void)testThatItDoesNotReturnANonExistingUserByUUID
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        NSUUID *uuid = NSUUID.createUUID;
        NSUUID *secondUUID = NSUUID.createUUID;
        
        conversation.remoteIdentifier = uuid;
        
        // when
        ZMConversation *found = [ZMConversation conversationWithRemoteID:secondUUID createIfNeeded:NO inContext:self.syncMOC];
        
        // then
        XCTAssertNil(found);
    }];
}

- (void)testThatItCreatesAUserForNonExistingUUID
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        NSUUID *uuid = NSUUID.createUUID;
        
        // when
        ZMConversation *found = [ZMConversation conversationWithRemoteID:uuid createIfNeeded:YES inContext:self.syncMOC];
        
        // then
        XCTAssertNotNil(found);
        XCTAssertEqualObjects(uuid, found.remoteIdentifier);
    }];
}


- (void)testThatConversationsDoNotGetInsertedUpstreamUnlessTheyAreGroupConversations;
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    NSPredicate *predicate = [ZMConversation predicateForObjectsThatNeedToBeInsertedUpstream];
    ZMConversationType types[] = {
        ZMConversationTypeSelf,
        ZMConversationTypeOneOnOne,
        ZMConversationTypeGroup,
        ZMConversationTypeConnection,
        ZMConversationTypeInvalid,
    };
    
    for (size_t i = 0; i < (sizeof(types)/sizeof(*types)); ++i) {
        // when
        conversation.conversationType = types[i];
        
        // then
        if (types[i] == ZMConversationTypeGroup) {
            XCTAssertTrue([predicate evaluateWithObject:conversation], @"type == %d", types[i]);
        } else {
            XCTAssertFalse([predicate evaluateWithObject:conversation], @"type == %d", types[i]);
        }
    }
}

- (void)testThatTheConversationListFiltersOutConversationOfInvalidType
{
    // given
    ZMConversation *oneToOneConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConversation *invalidConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    oneToOneConversation.conversationType = ZMConversationTypeOneOnOne;
    invalidConversation.conversationType = ZMConversationTypeInvalid;
    
    // when
    NSArray *conversationsInContext = [ZMConversation conversationsIncludingArchivedInContext:self.uiMOC];
    
    // then
    XCTAssertEqualObjects(conversationsInContext, @[oneToOneConversation]);
}

- (void)testThatConversationByUUIDDoesNotFilterOutConversationsOfInvalidType
{
    // given
    ZMConversation *invalidConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    invalidConversation.conversationType = ZMConversationTypeInvalid;
    invalidConversation.remoteIdentifier = [NSUUID createUUID];
    
    // when
    ZMConversation *fetchedConversation = [ZMConversation conversationWithRemoteID:invalidConversation.remoteIdentifier createIfNeeded:NO inContext:self.uiMOC];
    
    // then
    XCTAssertEqual(fetchedConversation, invalidConversation);
}

- (void)testThatConversationsDoNotGetUpdatedUpstreamIfTheyDoNotHaveARemoteIdentifier
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    [conversation setLocallyModifiedKeys:[NSSet setWithObject:ZMConversationUserDefinedNameKey]];
    
    NSPredicate *predicate = [ZMConversation predicateForObjectsThatNeedToBeUpdatedUpstream];

    // then
    XCTAssertFalse([predicate evaluateWithObject:conversation]);
}

- (void)testThatConversationsDoNotGetUpdatedUpstreamWhenTheyAreInvalidOrConnectionConversations;
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    [conversation setLocallyModifiedKeys:[NSSet setWithObject:ZMConversationUserDefinedNameKey]];
    NSPredicate *predicate = [ZMConversation predicateForObjectsThatNeedToBeUpdatedUpstream];
    ZMConversationType types[] = {
        ZMConversationTypeConnection,
        ZMConversationTypeInvalid,
    };
    
    for (size_t i = 0; i < (sizeof(types)/sizeof(*types)); ++i) {
        // when
        conversation.conversationType = types[i];
        
        // then
        if (types[i] == ZMConversationTypeGroup) {
            XCTAssertTrue([predicate evaluateWithObject:conversation], @"type == %d", types[i]);
        } else {
            XCTAssertFalse([predicate evaluateWithObject:conversation], @"type == %d", types[i]);
        }
    }
}

- (void)testThatPendingConversationsAreUpdatedUpstream;
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeConnection;
    conversation.remoteIdentifier = NSUUID.createUUID;
    [conversation setLocallyModifiedKeys:[NSSet setWithObject:ZMConversationArchivedChangedTimeStampKey]];
    
    NSPredicate *predicate = [ZMConversation predicateForObjectsThatNeedToBeUpdatedUpstream];
    
    // then
    XCTAssertTrue([predicate evaluateWithObject:conversation]);
}

- (void)testThatItSortsTheConversationBasedOnServerTimestamp
{
    // given
    const NSUInteger numberOfMessages = 50;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *creator = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.creator = creator;
        
        for(NSUInteger i = 0; i < numberOfMessages; ++i) {
            NSString *text = [NSString stringWithFormat:@"Conversation test message %lu", (unsigned long)i];
            ZMTextMessage *message = [ZMTextMessage insertNewObjectInManagedObjectContext:self.syncMOC];
            message.text = text;
            message.visibleInConversation = conversation;
            message.sender = creator;
            uint64_t poorRandom2 = (13 + i * 98953) % 93179;
            message.serverTimestamp = [NSDate dateWithTimeIntervalSinceReferenceDate:poorRandom2*100];
        }
        
        // when
        [conversation sortMessages];
        
        // then
        NSDate *lastFoundDate;
        for(ZMMessage *message in conversation.messages)
        {
            if(lastFoundDate != nil) {
                XCTAssertEqual([lastFoundDate compare:message.serverTimestamp], NSOrderedAscending);
            }
            lastFoundDate = message.serverTimestamp;
        }
        XCTAssertNotNil(lastFoundDate);
    }];
}

- (void)testThatItFetchesMessagesAndSetsTheUnreadCountAfterSortingMessages
{
    // given
    const NSUInteger numberOfMessages = 10;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];

        ZMUser *creator = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.creator = creator;
        
        for(NSUInteger i = 0; i < numberOfMessages; ++i) {
            NSString *text = [NSString stringWithFormat:@"Conversation test message %lu", (unsigned long)i];
            ZMTextMessage *message = [ZMTextMessage insertNewObjectInManagedObjectContext:self.syncMOC];
            message.text = text;
            message.visibleInConversation = conversation;
            message.sender = creator;
            uint64_t poorRandom2 = (13 + i * 98953) % 93179;
            message.serverTimestamp = [NSDate dateWithTimeIntervalSinceReferenceDate:poorRandom2*100];
        }
        
        XCTAssertEqual(conversation.estimatedUnreadCount, 0u);
        
        // when
        [conversation sortMessages];
        
        // then
        XCTAssertEqual(conversation.estimatedUnreadCount, 10u);
    }];
}

- (void)testThatItDoesNotTouchTheMessagesRelationWhenItIsAlreadySorted;
{
    // If we dirty the relationship (on the sync context), changes in the UI context might
    // get rolled back.
    // We were seeing that messages would get lost when the user quickly inserts a lot
    // of messages.
    
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMMessage *mA = (id)[conversation appendMessageWithText:@"A"];
    mA.serverTimestamp = [NSDate dateWithTimeIntervalSinceNow:10000];
    ZMMessage *mB = (id)[conversation appendMessageWithText:@"B"];
    mB.serverTimestamp = [NSDate dateWithTimeIntervalSinceNow:20000];
    [self performIgnoringZMLogError:^{
        [conversation sortMessages];
    }];
    XCTAssert([self.uiMOC saveOrRollback]);
    XCTAssertEqual(conversation.changedValues.count, 0u);
    
    // when
    [self performIgnoringZMLogError:^{
        [conversation sortMessages];
    }];
    
    // then
    XCTAssertEqual(conversation.changedValues.count, 0u);
}

- (void)testThatItRemovesAndAppendsTheMessageWhenResortingWithUpdatedMessage
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMMessage *message1 = (id)[conversation appendMessageWithText:@"hallo"];
    message1.serverTimestamp = [NSDate dateWithTimeIntervalSinceNow:-50];
    ZMMessage *message2 = (id)[conversation appendMessageWithText:@"hallo"];
    message2.serverTimestamp = [NSDate dateWithTimeIntervalSinceNow:-40];
    ZMMessage *message3 = (id)[conversation appendMessageWithText:@"hallo"];
    message3.serverTimestamp = [NSDate dateWithTimeIntervalSinceNow:-30];

    NSOrderedSet *messages = [NSOrderedSet orderedSetWithArray:@[message1, message2, message3]];
    XCTAssertEqualObjects(messages, conversation.messages);
    
    // when
    message1.serverTimestamp = [NSDate date];
    [conversation resortMessagesWithUpdatedMessage:message1];
    
    // then
    NSOrderedSet *expectedMessages = [NSOrderedSet orderedSetWithArray:@[message2, message3, message1]];
    XCTAssertEqualObjects(expectedMessages, conversation.messages);
}

- (void)testThatItUsesServerTimestampWhenResortingWithUpdatedMessage
{
    // given
    NSDate *date1 = [NSDate dateWithTimeIntervalSinceReferenceDate:2000];
    NSDate *date2 = [NSDate dateWithTimeIntervalSinceReferenceDate:3000];
    NSDate *date3 = [NSDate dateWithTimeIntervalSinceReferenceDate:4000];
    
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMMessage *message1 = (id)[conversation appendMessageWithText:@"hallo 1"];
    message1.serverTimestamp = date1;
    ZMMessage *message2 = (id)[conversation appendMessageWithText:@"hallo 2"];
    message2.serverTimestamp = date3;
    ZMMessage *message3 = (id)[conversation appendMessageWithText:@"hallo 3"];
    
    NSOrderedSet *messages = [NSOrderedSet orderedSetWithArray:@[message1, message2, message3]];
    XCTAssertEqualObjects(messages, conversation.messages);
    
    // when
    message3.serverTimestamp = date2;
    [conversation resortMessagesWithUpdatedMessage:message3];
    
    // then
    NSOrderedSet *expectedMessages = [NSOrderedSet orderedSetWithArray:@[message1, message3, message2]];
    XCTAssertEqualObjects(expectedMessages, conversation.messages);
}

- (void)testThatLastModifiedDateOfTheConversationGetsUpdatedWhenAMessageIsInserted
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.lastModifiedDate = [NSDate dateWithTimeIntervalSinceReferenceDate:1000];
    
    // when
    [conversation appendMessageWithText:@"foo"];
    
    // then
    AssertDateIsRecent(conversation.lastModifiedDate);
}


- (void)testThatItCreatesAMessageWithLongText
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // when
    NSString *longText = [@"" stringByPaddingToLength:ZMConversationMaxTextMessageLength + 1000 withString:@"😋" startingAtIndex:0];
    
    // then
    id<ZMConversationMessage> message = (id)[conversation appendMessageWithText:longText];

    XCTAssertEqualObjects(message.textMessageData.messageText, longText);
    XCTAssertEqual(conversation.messages.count, 1lu);
}

- (void)testThatItRejectsWhitespaceOnlyText
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    NSString *whiteSpaceString = @"      ";
    
    // when
    [self performIgnoringZMLogError:^{
        [conversation appendMessageWithText:whiteSpaceString];
    }];
    
    // then    
    XCTAssertEqual(conversation.messages.count, 0u);
}


- (void)testThatItDoesNotRejectNonWhitespaceOnlyText
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    NSString *someString = @"some string";
    
    // when
    [conversation appendMessageWithText:someString];
    
    // then
    XCTAssertEqual(conversation.messages.count, 1u);
}


- (void)testThatItSetsTheLastModifiedDateToNowWhenInsertingAGroupConversationFromTheUI;
{
    // given
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // when
    ZMConversation *sut = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.uiMOC withParticipants:@[user1, user2]];
    
    // then
    AssertDateIsRecent(sut.lastModifiedDate);
}


- (void)testThatItSetsTheExpirationDateOnATextMessage
{
    // given
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConversation *sut = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.uiMOC withParticipants:@[user1, user2]];
    
    // when
    ZMMessage *message = (id)[sut appendMessageWithText:@"Quux"];

    // then
    XCTAssertNotNil(message.expirationDate);
    NSDate *expectedDate = [NSDate dateWithTimeIntervalSinceNow:[ZMMessage defaultExpirationTime]];
    XCTAssertLessThan(fabs([message.expirationDate timeIntervalSinceDate:expectedDate]), 1);
}



- (void)testThatItDeletesCachedValueForRemoteIDAfterAwakingFromSnapshotEvents
{
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.remoteIdentifier = [NSUUID createUUID];
    
    [conversation willAccessValueForKey:@"remoteIdentifier"];
    NSUUID *cachedRemoteID = [conversation primitiveValueForKey:@"remoteIdentifier"];
    [conversation didAccessValueForKey:@"remoteIdentifier"];
    
    XCTAssertEqualObjects(cachedRemoteID, conversation.remoteIdentifier);
    
    // when
    
    [conversation awakeFromSnapshotEvents:NSSnapshotEventUndoUpdate];
    
    [conversation willAccessValueForKey:@"remoteIdentifier"];
    NSUUID *cachedIDAfterDeleting = [conversation primitiveValueForKey:@"remoteIdentifier"];
    [conversation didAccessValueForKey:@"remoteIdentifier"];
    
    XCTAssertNil(cachedIDAfterDeleting);
}

- (void)testThatTheUserDefinedNameIsCopied
{
    // given
    NSString *originalValue = @"will@foo.co";
    NSMutableString *mutableValue = [originalValue mutableCopy];
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // when
    conversation.userDefinedName = mutableValue;
    [mutableValue appendString:@".uk"];
    
    // then
    XCTAssertEqualObjects(conversation.userDefinedName, originalValue);
}

- (void)testThatTheNormalizedUserDefinedNameIsCopied
{
    // given
    NSString *originalValue = @"will@foo.co";
    NSMutableString *mutableValue = [originalValue mutableCopy];
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // when
    conversation.normalizedUserDefinedName = mutableValue;
    [mutableValue appendString:@".uk"];
    
    // then
    XCTAssertEqualObjects(conversation.normalizedUserDefinedName, originalValue);
}

- (void)testThatTheDraftTextIsCopied
{
    // given
    NSString *originalValue = @"will@foo.co";
    NSMutableString *mutableValue = [originalValue mutableCopy];
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // when
    conversation.draftMessageText = mutableValue;
    [mutableValue appendString:@".uk"];
    
    // then
    XCTAssertEqualObjects(conversation.draftMessageText, originalValue);
}

- (void)addNotification:(NSNotification *)note
{
    [self.receivedNotifications addObject:note];
}


- (void)testThatItDetectsTheSelfConversationRemoteID;
{
    // given
    NSUUID *selfID = [NSUUID createUUID];
    [ZMUser selfUserInContext:self.uiMOC].remoteIdentifier = selfID;
    
    // then
    XCTAssertTrue([selfID isSelfConversationRemoteIdentifierInContext:self.uiMOC]);
    XCTAssertFalse([NSUUID.createUUID isSelfConversationRemoteIdentifierInContext:self.uiMOC]);
}

- (void)testThatWhenSetNotToBeUpdatedFromBackendCallStateDoesNotChangeFromTrue
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.callStateNeedsToBeUpdatedFromBackend = YES;
    
    // when
    conversation.needsToBeUpdatedFromBackend = NO;
    
    // then
    XCTAssertTrue(conversation.callStateNeedsToBeUpdatedFromBackend);
}

- (void)testThatWhenSetNotToBeUpdatedFromBackendCallStateDoesNotChangeFromFalse
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.callStateNeedsToBeUpdatedFromBackend = NO;
    
    // when
    conversation.needsToBeUpdatedFromBackend = NO;
    
    // then
    XCTAssertFalse(conversation.callStateNeedsToBeUpdatedFromBackend);
}

- (void)testThatItDoesNotUpdateLastModifiedDateWithLocalSystemMessages
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.lastModifiedDate = [NSDate.date dateByAddingTimeInterval:-100];
    ZMMessage *firstMessage = (id)[conversation appendMessageWithText:@"Test Message"];
    
    // then
    XCTAssertEqualObjects(conversation.lastModifiedDate, firstMessage.serverTimestamp);
 
    // when
    NSDate *future = [NSDate.date dateByAddingTimeInterval:100];
    [conversation appendNewPotentialGapSystemMessageWithUsers:nil timestamp:future];
    
    // then
    XCTAssertEqualObjects(conversation.lastModifiedDate, firstMessage.serverTimestamp);
    XCTAssertEqual(conversation.messages.count, 2lu);
}

- (void)testThatItUpdatesLastModifiedDateWithMessageServerTimestamp_ClientMessage
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.lastModifiedDate = [NSDate.date dateByAddingTimeInterval:-100];
    ZMClientMessage *clientMessage = [conversation appendOTRMessageWithText:@"Test Message" nonce:[NSUUID new] fetchLinkPreview:YES];
    
    // then
    XCTAssertEqualObjects(conversation.lastModifiedDate, clientMessage.serverTimestamp);
    
    NSDate *serverDate = [clientMessage.serverTimestamp dateByAddingTimeInterval:0.2];
    // when
    [clientMessage updateWithPostPayload:@{@"time": serverDate} updatedKeys:[NSSet set]];
    
    // then
    XCTAssertEqualObjects(conversation.lastModifiedDate, serverDate);
    XCTAssertEqualObjects(clientMessage.serverTimestamp, serverDate);
    
    // cleanup
}

- (void)testThatItDoesNotUpdatesLastModifiedDateWithMessageServerTimestampIfNotNeeded_ClientMessage
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.lastModifiedDate = [NSDate.date dateByAddingTimeInterval:-100];
    ZMClientMessage *clientMessage = [conversation appendOTRMessageWithText:@"Test Message" nonce:[NSUUID new] fetchLinkPreview:YES];
    
    NSDate *postingDate = clientMessage.serverTimestamp;
    // then
    XCTAssertEqualObjects(conversation.lastModifiedDate, clientMessage.serverTimestamp);
    
    NSDate *serverDate = [clientMessage.serverTimestamp dateByAddingTimeInterval:-0.2];
    // when
    [clientMessage updateWithPostPayload:@{@"time": serverDate} updatedKeys:[NSSet set]];
    
    // then
    XCTAssertEqualObjects(conversation.lastModifiedDate, postingDate);
    XCTAssertEqualObjects(clientMessage.serverTimestamp, serverDate);
}

- (void)testThatItUpdatesLastModifiedDateWithMessageServerTimestamp_PlaintextMessage
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.lastModifiedDate = [NSDate.date dateByAddingTimeInterval:-100];
    ZMMessage *firstMessage = (id)[conversation appendMessageWithText:@"Test Message"];
    
    // then
    XCTAssertEqualObjects(conversation.lastModifiedDate, firstMessage.serverTimestamp);
    
    NSDate *serverDate = [firstMessage.serverTimestamp dateByAddingTimeInterval:0.2];
    // when
    [firstMessage updateWithPostPayload:@{@"time": serverDate, @"data": @{@"nonce": firstMessage.nonce}, @"type": @"conversation.message-add"} updatedKeys:[NSSet set]];
    
    // then
    XCTAssertEqualObjects(conversation.lastModifiedDate, serverDate);
    XCTAssertEqualObjects(firstMessage.serverTimestamp, serverDate);
}

- (void)testThatItDoesNotUpdatesLastModifiedDateWithMessageServerTimestampIfNotNeeded_PlaintextMessage
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.lastModifiedDate = [NSDate.date dateByAddingTimeInterval:-100];
    ZMMessage *firstMessage = (id)[conversation appendMessageWithText:@"Test Message"];
    
    NSDate *postingDate = firstMessage.serverTimestamp;
    // then
    XCTAssertEqualObjects(conversation.lastModifiedDate, firstMessage.serverTimestamp);
    
    NSDate *serverDate = [firstMessage.serverTimestamp dateByAddingTimeInterval:-0.2];
    // when
    [firstMessage updateWithPostPayload:@{@"time": serverDate, @"data": @{@"nonce": firstMessage.nonce}, @"type": @"conversation.message-add"} updatedKeys:[NSSet set]];
    
    // then
    XCTAssertEqualObjects(conversation.lastModifiedDate, postingDate);
    XCTAssertEqualObjects(firstMessage.serverTimestamp, serverDate);
}

- (void)testThatAppendingNewConversationSystemMessageTwiceDoesNotCreateTwoSystemMessage;
{
    //given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    [conversation appendNewConversationSystemMessageIfNeeded];
    XCTAssertEqual(conversation.messages.count, 1u);
    
    //when
    [conversation appendNewConversationSystemMessageIfNeeded];
    
    //then
    XCTAssertEqual(conversation.messages.count, 1u);
}

@end // general



@implementation ZMConversationTests (ReadOnly)

- (void)testThatAGroupConversationWhereTheUserIsActiveIsNotReadOnly
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    conversation.isSelfAnActiveMember = YES;
    
    // then
    XCTAssertFalse(conversation.isReadOnly);
}

- (void)testThatAGroupConversationWhereTheUserIsNotActiveIsReadOnly
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    conversation.isSelfAnActiveMember = NO;
    
    // then
    XCTAssertTrue(conversation.isReadOnly);
}

- (void)testThatAOneToOneConversationIsNotReadOnly
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeOneOnOne;
    
    // then
    XCTAssertFalse(conversation.isReadOnly);
}

- (void)testThatAPendingConnectionConversationIsReadOnly
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeConnection;
    
    // then
    XCTAssertTrue(conversation.isReadOnly);
}

- (void)testThatTheSelfConversationIsReadOnly
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeConnection;
    
    // then
    XCTAssertTrue(conversation.isReadOnly);
}

- (void)testThatAnInvalidConversationIsReadOnly
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeInvalid;
    
    // then
    XCTAssertTrue(conversation.isReadOnly);
}

- (void)testThatItRecalculatesIsReadOnlyWhenIsSelfActiveMemberChanges
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeOneOnOne;
    conversation.isSelfAnActiveMember = YES;

    // expect
    [self keyValueObservingExpectationForObject:conversation keyPath:@"isReadOnly" expectedValue:nil];
    
    // when
    conversation.isSelfAnActiveMember = NO;
    
    // then
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatItRecalculatesIsReadOnlyWhenConversationTypeChanges
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeOneOnOne;
    conversation.isSelfAnActiveMember = YES;
    
    // expect
    [self keyValueObservingExpectationForObject:conversation keyPath:@"isReadOnly" expectedValue:nil];
    
    // when
    conversation.conversationType = ZMConversationTypeGroup;
    
    // then
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

@end




@implementation ZMConversationTests (Connections)

- (void)testThatItReturnsTheConnectionMessage;
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.conversation = conversation;
    NSString *message = @"HELLOOOOOO!!!!";
    connection.message = message;
    
    // then
    XCTAssertEqualObjects(conversation.connectionMessage, message);
}

- (void)testThatTheConnectionConversationLastModifiedDateIsSet
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewSentConnectionToUser:user];

    // then
    AssertDateIsRecent(connection.conversation.lastModifiedDate);
}


- (void)testThatIsInvitationConversationReturnsTrueIfItHasAPendingConnection
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.conversation = conversation;
    connection.status = ZMConnectionStatusPending;
    
    // then
    XCTAssertTrue(conversation.isPendingConnectionConversation);
}

- (void)testThatIsInvitationConversationReturnsFalseIfItHasNoConnection
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];

    // then
    XCTAssertFalse(conversation.isPendingConnectionConversation);
}

- (void)testThatIsInvitationConversationReturnsFalseIfItHasTheWrongConnectionStatus
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.conversation = conversation;
    NSArray *statusesToTest = @[
                        @(ZMConnectionStatusAccepted),
                        @(ZMConnectionStatusBlocked),
                        @(ZMConnectionStatusIgnored),
                        @(ZMConnectionStatusInvalid),
                        @(ZMConnectionStatusSent)
                    ];

    for(NSNumber *status in statusesToTest) {
        connection.status = (ZMConnectionStatus) status.intValue;
        
        // then
        XCTAssertFalse(conversation.isPendingConnectionConversation);
    }
    
}

- (void)testThatExistingOneOnOneConversationWithUserReturnsNilIfNotConnected
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConversation *SomeOtherConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    NOT_USED(SomeOtherConversation);
    
    // when
    ZMConversation *fetchedConversation = [ZMConversation existingOneOnOneConversationWithUser:user inUserSession:self.mockUserSessionWithUIMOC];
    
    // then
    XCTAssertNil(fetchedConversation);
    
}

- (void)testThatExistingOneOnOneConversationWithUserReturnsTheConnectionConversation
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConversation *connectionConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    
    connection.to = user;
    connection.conversation = connectionConversation;
    
    // when
    ZMConversation *fetchedConversation = [ZMConversation existingOneOnOneConversationWithUser:user inUserSession:self.mockUserSessionWithUIMOC];

    // then
    XCTAssertEqual(fetchedConversation, connectionConversation);
}

- (void)testThatItRecalculatesIsPendingConnectionWhenConnectionStatusChanges
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.conversation = conversation;
    connection.status = ZMConnectionStatusPending;
    
    XCTAssertTrue(conversation.isPendingConnectionConversation);
    
    // expect
    [self keyValueObservingExpectationForObject:conversation keyPath:@"isPendingConnectionConversation" expectedValue:nil];
    
    // when
    connection.status = ZMConnectionStatusAccepted;
    
    // then
    XCTAssertFalse(conversation.isPendingConnectionConversation);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}


- (void)testThatItRecalculatesIsPendingConnectionWhenConnectionChanges
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMConnection *connection1 = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection1.conversation = conversation;
    connection1.status = ZMConnectionStatusPending;
    
    XCTAssertEqualObjects(conversation.connection, connection1);
    XCTAssertTrue(conversation.isPendingConnectionConversation);

    // expect
    [self keyValueObservingExpectationForObject:conversation keyPath:@"isPendingConnectionConversation" expectedValue:nil];
    
    // when
    ZMConnection *connection2 = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection1.status = ZMConnectionStatusAccepted;
    conversation.connection = connection2;
    
    // then
    XCTAssertEqualObjects(conversation.connection, connection2);
    XCTAssertFalse(conversation.isPendingConnectionConversation);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

@end // connections


@implementation ZMConversationTests (DisplayName)


- (void)testThatSettingTheUseDefinedNameDoesNotMakeTheNormalizedUserDefinedNameIsLocallyModified;
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    conversation.userDefinedName = @"Naïve piñata talk";
    [self.uiMOC saveOrRollback];
    [conversation resetLocallyModifiedKeys:[conversation keysThatHaveLocalModifications]];
    [self.uiMOC saveOrRollback];
    XCTAssertFalse([[conversation keysThatHaveLocalModifications] containsObject:ZMConversationUserDefinedNameKey]);
    XCTAssertFalse([[conversation keysThatHaveLocalModifications] containsObject:@"normalizedUserDefinedName"]);
    
    // when
    conversation.userDefinedName = @"Fancy New Name";
    [self.uiMOC saveOrRollback];
    
    // then
    XCTAssertTrue([[conversation keysThatHaveLocalModifications] containsObject:ZMConversationUserDefinedNameKey]);
    XCTAssertFalse([[conversation keysThatHaveLocalModifications] containsObject:@"normalizedUserDefinedName"]);
}

- (void)testThatTheDisplayNameIsTheConnectedUserNameWhenItIsAPendingConnectionConversation;
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *user = [self createUser];
    user.name = @"Foo Bar Baz";
    conversation.conversationType = ZMConversationTypeConnection;
    conversation.userDefinedName = @"JKAHJKADSKHJ";
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.conversation = conversation;
    connection.status = ZMConnectionStatusPending;
    connection.to = user;
    [self.uiMOC saveOrRollback];
    
    // when
    NSString *name = [conversation.displayName copy];
    
    // then
    XCTAssertEqualObjects(name, user.name);
}

- (void)testThatTheDisplayNameIsTheConnectedUserNameWhenItIsASentConnectionConversation;
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *user = [self createUser];
    user.name = @"Foo Bar Baz";
    conversation.conversationType = ZMConversationTypeConnection;
    conversation.userDefinedName = @"JKAHJKADSKHJ";
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.conversation = conversation;
    connection.status = ZMConnectionStatusSent;
    connection.to = user;
    [self.uiMOC saveOrRollback];
    
    // when
    NSString *name = [conversation.displayName copy];
    
    // then
    XCTAssertEqualObjects(name, user.name);
}

- (void)testThatTheDisplayNameIsTheConnectedUserNameWhenItIsAOneOnOneConversationWithoutOtherActiveParticipants
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *user = [self createUser];
    user.name = @"Foo Bar Baz";
    conversation.conversationType = ZMConversationTypeOneOnOne;
    conversation.userDefinedName = @"JKAHJKADSKHJ";
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.conversation = conversation;
    connection.status = ZMConnectionStatusPending;
    connection.to = user;
    [self.uiMOC saveOrRollback];

    // when
    NSString *name = [conversation.displayName copy];
    
    // then
    XCTAssertEqualObjects(name, user.name);
}

- (void)testThatTheDisplayNameIsTheUserDefinedNameWhenSetInAGroupConversation
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *user = [self createUser];
    user.name = @"Foo 1";
    [conversation.mutableOtherActiveParticipants addObject:user];
    [conversation.mutableOtherActiveParticipants addObject:[ZMUser selfUserInContext:self.uiMOC]];
    conversation.conversationType = ZMConversationTypeGroup;
    [self.uiMOC saveOrRollback];
    NSString *name = @"My Conversation";
    
    // when
    conversation.userDefinedName = name;
    
    // then
    XCTAssertEqualObjects(conversation.displayName, name);
}

- (void)testThatTheDisplayNameIsTheUserDefinedNameWhenThereAreNoOtherParticipants
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeConnection;
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.name = @"Me Myself";
    [self.uiMOC saveOrRollback];
    
    // when
    conversation.userDefinedName = @"Egg";
    
    // then
    XCTAssertEqualObjects(conversation.displayName, @"Egg");
}


- (void)testThatTheDisplayNameIsTheOtherUsersNameWhenTheUserDefinedNameIsNotSet
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    user1.name = @"Foo 1";
    user2.name = @"Bar 2";
    selfUser.name = @"Me Myself";
    [conversation.mutableOtherActiveParticipants addObject:user1];
    [conversation.mutableOtherActiveParticipants addObject:user2];
    [conversation.mutableOtherActiveParticipants addObject:[ZMUser selfUserInContext:self.uiMOC]];
    [self.uiMOC saveOrRollback];
    [self updateDisplayNameGeneratorWithUsers:@[user1, user2, selfUser]];
    
    NSString *expected = @"Foo, Bar";
    
    // when
    conversation.userDefinedName = nil;
    
    // then
    XCTAssertEqualObjects(conversation.displayName, expected);
}

- (void)testThatTheDisplayNameBasedOnUserNamesDoesNotIncludeUsersWithAnEmptyName
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *user3 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *user4 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    user1.name = @"";
    user2.name = @"Bar 2";
    user3.name = nil;
    user4.name = @"Baz 4";
    selfUser.name = @"Me Myself";
    [conversation.mutableOtherActiveParticipants addObjectsFromArray:@[user1, user2, user3, user4]];
    [conversation.mutableOtherActiveParticipants addObject:[ZMUser selfUserInContext:self.uiMOC]];
    [self.uiMOC saveOrRollback];
    
    NSString *expected = @"Bar, Baz";
    
    // when
    conversation.userDefinedName = nil;
    [self updateDisplayNameGeneratorWithUsers:@[user1, user2, user3, user4, selfUser]];
    
    // then
    XCTAssertEqualObjects(conversation.displayName, expected);
}


- (void)testThatTheDisplayNameIsTheOtherUser;
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeOneOnOne;
    conversation.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.connection.to = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.connection.to.name = @"User 1";
    [self.uiMOC saveOrRollback];
    
    // then
    XCTAssertEqualObjects(conversation.displayName, @"User 1");
}

- (void)testThatTheDisplayNameForDeletedUserIsEllipsis;
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeOneOnOne;
    conversation.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.connection.to = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.connection.to.name = nil;
    [self.uiMOC saveOrRollback];
    
    // then
    XCTAssertEqualObjects(conversation.displayName, @"…");
}

- (void)testThatTheDisplayNameForGroupConversationWithoutParticipantsIsTheEmptyGroupConversationName;
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    [self.uiMOC saveOrRollback];

    // then
    XCTAssertEqualObjects(conversation.displayName, @"conversation.displayname.emptygroup");
}

- (void)testThatTheDisplayNameIsTheOtherUsersNameForAConnectionRequest;
{
    __block NSManagedObjectID *moid;
    [self.syncMOC performGroupedBlockAndWait:^{
        // when
        ZMUser *user = [ZMUser userWithRemoteID:NSUUID.createUUID createIfNeeded:YES inContext:self.syncMOC];
        user.name = @"Skyler Saša";
        user.needsToBeUpdatedFromBackend = YES;
        ZMConnection *connection = [ZMConnection insertNewSentConnectionToUser:user];
        connection.message = @"Hey, there!";
        ZMConversation *conversation = connection.conversation;
        XCTAssert([self.syncMOC saveOrRollback]);
        moid = conversation.objectID;
    }];
    ZMConversation *conversation = (id) [self.uiMOC objectWithID:moid];
    
    // then
    XCTAssertNotNil(conversation);
    XCTAssertEqualObjects(conversation.displayName, @"Skyler Saša");
}

- (void)testThatTheDisplayNameIsEllipsisWhenTheOtherUsersNameForAConnectionRequestIsEmpty;
{
    __block NSManagedObjectID *moid;
    [self.syncMOC performGroupedBlockAndWait:^{
        // when
        ZMUser *user = [ZMUser userWithRemoteID:NSUUID.createUUID createIfNeeded:YES inContext:self.syncMOC];
        user.name = @"";
        user.needsToBeUpdatedFromBackend = YES;
        ZMConnection *connection = [ZMConnection insertNewSentConnectionToUser:user];
        connection.message = @"Hey, there!";
        ZMConversation *conversation = connection.conversation;
        XCTAssert([self.syncMOC saveOrRollback]);
        moid = conversation.objectID;
    }];
    ZMConversation *conversation = (id) [self.uiMOC objectWithID:moid];
    
    // then
    XCTAssertNotNil(conversation);
    XCTAssertEqualObjects(conversation.displayName, @"…");
}

- (void)testThatTheDisplayNameIsAlwaysTheOtherparticipantsNameInOneOnOneConversations
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    user.name = @"Hans Maisenkaiser";
    selfUser.name = @"Jan Schneidezahn";
    [conversation.mutableOtherActiveParticipants addObject:user];
    [conversation.mutableOtherActiveParticipants addObject:selfUser];
    conversation.conversationType = ZMConversationTypeOneOnOne;
    [self.uiMOC saveOrRollback];
    
    // when
    conversation.userDefinedName = @"FAIL FAIL FAIL";
    
    // then
    XCTAssertEqualObjects(conversation.displayName, user.name);
}

- (void)testThatItSetsNormalizedNameWhenSettingName
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.userDefinedName = @"Naïve piñata talk";
    [self.uiMOC saveOrRollback];
    
    // when
    NSString *normalizedName = conversation.normalizedUserDefinedName;
    
    // then
    XCTAssertEqualObjects(normalizedName, @"naive pinata talk");
    
}

@end



@implementation ZMConversationTests (ReadingLastReadMessage)


- (void)testThatItReturnsTheLastReadMessageIfWeHaveItLocally;
{
    // given
    NSDate *serverTimeStamp = [NSDate date];
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // when
    conversation.lastReadServerTimeStamp = serverTimeStamp;
    ZMTextMessage *message = [ZMTextMessage insertNewObjectInManagedObjectContext:self.uiMOC];
    message.serverTimestamp = serverTimeStamp;
    [conversation.mutableMessages addObject:message];
    
    // then
    XCTAssertEqual(conversation.lastReadMessage, message);
}


- (void)testThatItReturnsThePreviousMessageIfTheLastReadServerTimeStampIsNoMessage
{
    // event ID
    //   1.1     message A
    //   2.1     message B     <--- last read message should be this
    //   3.1     (no message)  <--- last read event ID
    //   4.1     message C
    //   5.1     message D
    
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        [self timeStampForSortAppendMessageToConversation:conversation];
        [self timeStampForSortAppendMessageToConversation:conversation];
        NSDate *noMessageTimeStamp = [conversation.lastServerTimeStamp dateByAddingTimeInterval:5];
        conversation.lastServerTimeStamp = noMessageTimeStamp;
        [self timeStampForSortAppendMessageToConversation:conversation];
        [self timeStampForSortAppendMessageToConversation:conversation];
        
        ZMMessage *expectedLastReadMessage = conversation.messages[1];
        
        // when
        conversation.lastReadServerTimeStamp = noMessageTimeStamp;
        
        // then
        XCTAssertEqual(conversation.lastReadMessage, expectedLastReadMessage,
                       @"%@ == %@", conversation.lastReadMessage.serverTimestamp, expectedLastReadMessage.serverTimestamp);
    }];
}


- (void)testThatItReturnsTheLastMessageIfTheLastReadServerTimeStampIsBiggerThanTheLastMessageServerTimeStamp
{
    // event ID
    //   1.1     message A
    //   2.1     message B
    //  -------------------
    //   					last read event ID is 3.1

    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        [self timeStampForSortAppendMessageToConversation:conversation];
        [self timeStampForSortAppendMessageToConversation:conversation];
        NSDate *noMessageTimeStamp = [conversation.lastServerTimeStamp dateByAddingTimeInterval:5];
        conversation.lastServerTimeStamp = noMessageTimeStamp;
        ZMMessage *expectedLastReadMessage = conversation.messages[1];
        
        // when
        conversation.lastReadServerTimeStamp = noMessageTimeStamp;
        
        // then
        XCTAssertEqual(conversation.lastReadMessage, expectedLastReadMessage,
                       @"%@ == %@", conversation.lastReadMessage.serverTimestamp, expectedLastReadMessage.serverTimestamp);
    }];
    
}


- (void)testThatItReturnsNilIfTheLastReadEventIsOlderThanTheFirstMessageServerTimeStamp
{
    // event ID
    //   					last read event ID is 1.1
    //  -------------------
    //   2.1     message A
    //   3.1     message B

    
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        NSDate *noMessageTimeStamp = [NSDate date];
        conversation.lastServerTimeStamp = noMessageTimeStamp;
        [self timeStampForSortAppendMessageToConversation:conversation];
        [self timeStampForSortAppendMessageToConversation:conversation];
        
        // when
        conversation.lastReadServerTimeStamp = noMessageTimeStamp;
        
        // then
        XCTAssertNil(conversation.lastReadMessage);
    }];
}

- (ZMMessage *)insertMessageIntoConversation:(ZMConversation *)conversation
{
    ZMTextMessage *message = [ZMTextMessage insertNewObjectInManagedObjectContext:self.uiMOC];
    message.serverTimestamp = [[NSDate date] dateByAddingTimeInterval:2];
    message.text = [NSString stringWithFormat:@"Text %@", message.serverTimestamp];
    [conversation.mutableMessages addObject:message];
    return message;
}

- (ZMConversation *)createConversationWithManyMessages;
{
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    
    for (size_t i = 1; i < 5000; ++i) {
        [self insertMessageIntoConversation:conversation];
    }
    
    ZMMessage *lastMessage = conversation.messages.lastObject;
    conversation.lastServerTimeStamp = lastMessage.serverTimestamp;
    return conversation;
}

- (void)testPerformanceOfLastReadMessage_IsOneOfLast;
{
    // given
    ZMConversation *conversation = [self createConversationWithManyMessages];
    XCTAssert([self.uiMOC saveOrRollback]);
    NSMutableArray *timeStamps = [NSMutableArray array];
    NSUInteger const count = 10;
    for (size_t i = 0; i < count; ++i) {
        ZMMessage *message = conversation.messages[conversation.messages.count - 1 - i * 10];
        [timeStamps addObject:message.serverTimestamp];
    }
    
    // measure:
    [self measureBlock:^{
        for (size_t i = 0; i < count; ++i) {
            conversation.lastReadServerTimeStamp = timeStamps[i];
            XCTAssertNotNil(conversation.lastReadMessage);
        }
    }];
}

- (void)testPerformanceOfLastReadMessage_IsOneOfFirst;
{
    // given
    ZMConversation *conversation = [self createConversationWithManyMessages];
    XCTAssert([self.uiMOC saveOrRollback]);
    NSMutableArray *timeStamps = [NSMutableArray array];
    NSUInteger const count = 10;
    for (size_t i = 0; i < count; ++i) {
        ZMMessage *message = conversation.messages[i * 10];
        [timeStamps addObject:message.serverTimestamp];
    }
    
    // measure:
    [self measureBlock:^{
        for (size_t i = 0; i < count; ++i) {
            conversation.lastReadServerTimeStamp = timeStamps[i];
            XCTAssertNotNil(conversation.lastReadMessage);
        }
        [NSThread sleepForTimeInterval:0.00145];
    }];
}

- (void)testPerformanceOfLastReadMessage_Middle;
{
    // given
    ZMConversation *conversation = [self createConversationWithManyMessages];
    XCTAssert([self.uiMOC saveOrRollback]);
    NSMutableArray *timeStamps = [NSMutableArray array];
    NSUInteger const count = 10;
    for (size_t i = 0; i < count; ++i) {
        ZMMessage *message = conversation.messages[(conversation.messages.count - count * 10) / 2 + i * 10];
        [timeStamps addObject:message.serverTimestamp];
    }
    
    // measure:
    [self measureBlock:^{
        for (size_t i = 0; i < count; ++i) {
            conversation.lastReadServerTimeStamp = timeStamps[i];
            XCTAssertNotNil(conversation.lastReadMessage);
        }
    }];
}

@end


@implementation ZMConversationTests (SettingLastReadMessage)

- (void)testThatItSetsTheLastReadServerTimeStampToTheLastReadMessageInTheVisibleRange;
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.lastReadTimestampSaveDelay = 0.1;
    ZMMessage *message = [self insertDownloadedMessageIntoConversation:conversation];
    for (int i = 0; i < 10; ++i) {
        message = [self insertDownloadedMessageAfterMessageIntoConversation:conversation];
    }
    
    // when
    [conversation setVisibleWindowFromMessage:conversation.messages[2] toMessage:conversation.messages[4]];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(conversation.lastReadServerTimeStamp, ((ZMMessage *) conversation.messages[4]).serverTimestamp);
}

- (void)testThatItSavesTheLastReadServerTimeStampBeforeDelayedDispatchEnds;
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.lastReadTimestampSaveDelay = 2.0;
    ZMMessage *message = [self insertDownloadedMessageIntoConversation:conversation];
    for (int i = 0; i < 10; ++i) {
        message = [self insertDownloadedMessageAfterMessageIntoConversation:conversation];
    }
    
    // when
    [conversation setVisibleWindowFromMessage:conversation.messages[2] toMessage:conversation.messages[4]];
    [conversation savePendingLastRead];
    
    // then
    XCTAssertEqualObjects(conversation.lastReadServerTimeStamp, ((ZMMessage *) conversation.messages[4]).serverTimestamp);
}

- (void)testThatItDoesNotUpdateTheLastReadMessageToAnOlderMessage;
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.lastReadTimestampSaveDelay = 0.1;
    
    ZMMessage *message = [self insertDownloadedMessageIntoConversation:conversation];
    for (int i = 0; i < 10; ++i) {
        message = [self insertDownloadedMessageAfterMessageIntoConversation:conversation];
    }
    
    NSDate *originalLastReadTimeStamp = ((ZMMessage *)conversation.messages[9]).serverTimestamp;
    conversation.lastReadServerTimeStamp = originalLastReadTimeStamp;
    
    // when
    [conversation setVisibleWindowFromMessage:conversation.messages[2] toMessage:conversation.messages[4]];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqualObjects(conversation.lastReadServerTimeStamp, originalLastReadTimeStamp);
}

- (void)testThatItDoesNotUpdateTheLastReadMessageIfTheVisibleWindowIsNil;
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.lastReadTimestampSaveDelay = 0.1;
    
    ZMMessage *message = [self insertDownloadedMessageIntoConversation:conversation];
    for (int i = 0; i < 10; ++i) {
        message = [self insertDownloadedMessageAfterMessageIntoConversation:conversation];
    }
    
    NSDate *originalLastReadTimeStamp = ((ZMMessage *)conversation.messages[9]).serverTimestamp;
    conversation.lastReadServerTimeStamp = originalLastReadTimeStamp;

    // when
    [conversation setVisibleWindowFromMessage:nil toMessage:nil];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqualObjects(conversation.lastReadServerTimeStamp, originalLastReadTimeStamp);
}



- (void)testThatItSetsTheLastReadServerTimeStampToTheLastEventAfterTheLastMessage
{
    //  "downloaded"
    //  event 1.1    message       <-\
    //  event 2.1    message         |--- visible range
    //  event 3.1    message         |
    //  event 4.1    message       <-/
    //  event 5.1    (no message)
    //  event 6.1    (no message)  <--- this should be the last read event ID
    //
    
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.lastReadTimestampSaveDelay = 0.1;
    
    ZMMessage *message = [self insertDownloadedMessageIntoConversation:conversation];
    for (int i = 0; i < 3; ++i) {
        message = [self insertDownloadedMessageAfterMessageIntoConversation:conversation];
    }
    NSDate *serverTimeStamp = message.serverTimestamp;
    for (int i = 0; i < 2; ++i) {
        serverTimeStamp = [serverTimeStamp dateByAddingTimeInterval:1];
        conversation.lastServerTimeStamp = serverTimeStamp;
    }
    
    // when
    [conversation setVisibleWindowFromMessage:conversation.messages.firstObject toMessage:conversation.messages.lastObject];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqualObjects(conversation.lastReadServerTimeStamp, serverTimeStamp);
}

@end

@implementation ZMConversationTests (Participants)

- (void)testThatAddingParticipantsSetsTheModifiedKeys
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    XCTAssertTrue([self.uiMOC saveOrRollback]);
    
    // when
    [conversation addParticipant:user1];
    XCTAssertTrue([self.uiMOC saveOrRollback]);
    
    // then
    XCTAssertEqualObjects(conversation.keysThatHaveLocalModifications, [NSSet setWithObject:ZMConversationUnsyncedActiveParticipantsKey]);
}

- (void)testThatRemovingParticipantsSetsTheModifiedKeys
{
    // given
    NSUUID *convID = [NSUUID createUUID];
    NSUUID *userID = [NSUUID createUUID];
    [self.syncMOC performGroupedBlockAndWait:^{
    
        
        
        ZMConversation *conversation = [ZMConversation conversationWithRemoteID:convID createIfNeeded:YES inContext:self.syncMOC];
        XCTAssertNotNil(conversation);
        NSDictionary *payload = @{
                                  @"creator" : userID.transportString,
                                  @"id" : convID.transportString,
                                  @"last_event" : @"10.aabb",
                                  @"last_event_time" : @"2014-08-08T18:08:17.723Z",
                                  @"type" : @0,
                                  @"name" : @"Boo",
                                  @"members" :
                                      @{
                                          @"others" : @[
                                                  @{
                                                      @"id" : userID.transportString,
                                                      @"status" : @0
                                                      }
                                                  ],
                                          @"self" : @{
                                                  @"archived" : [NSNull null],
                                                  @"id" : @"90c74fe0-cef7-446a-affb-6cba0e75d5da",
                                                  @"last_read" : @"5a4.800122000a64d6bf",
                                                  @"muted" : [NSNull null],
                                                  @"muted_time" : [NSNull null],
                                                  @"status" : @0,
                                                  @"status_ref" : @"0.0",
                                                  @"status_time" : @"2014-06-18T12:08:44.428Z"
                                                  }
                                          },
                                  };
        
        [conversation updateWithTransportData:payload];
        [self.syncMOC saveOrRollback];
    }];
    
    ZMConversation *conversation = [ZMConversation conversationWithRemoteID:convID createIfNeeded:NO inContext:self.uiMOC];
    XCTAssertNotNil(conversation);
    [conversation resetLocallyModifiedKeys:[NSSet setWithArray:@[ZMConversationArchivedChangedTimeStampKey, ZMConversationSilencedChangedTimeStampKey]]];
    
    ZMUser *user = conversation.otherActiveParticipants.firstObject;
    XCTAssertNotNil(user);
    
    // when
    [conversation removeParticipant:user];
    XCTAssertTrue([self.uiMOC saveOrRollback]);
    
    // then
    XCTAssertEqualObjects(conversation.keysThatHaveLocalModifications, [NSSet setWithObject:ZMConversationUnsyncedInactiveParticipantsKey]);
}

- (void)testThatItDoesNotAddTheSelfUserToServerSyncedActiveParticipants
{
    // given
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // when
    [conversation synchronizeAddedUser:selfUser];
    
    // then
    XCTAssertFalse([conversation.unsyncedActiveParticipants containsObject:selfUser]);
    XCTAssertFalse([conversation.unsyncedInactiveParticipants containsObject:selfUser]);
}


- (void)testThatItRecalculatesActiveParticipantsWhenOtherActiveParticipantsKeyChanges
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    conversation.isSelfAnActiveMember = YES;

    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    
    [conversation addParticipant:user1];
    [conversation addParticipant:user2];
    
    XCTAssertTrue(conversation.isSelfAnActiveMember);
    XCTAssertEqual(conversation.otherActiveParticipants.count, 2u);
    XCTAssertEqual(conversation.activeParticipants.count, 3u);
    
    // expect
    [self keyValueObservingExpectationForObject:conversation keyPath:@"activeParticipants" expectedValue:nil];
    
    // when

    [conversation removeParticipant:user2];
    
    // then
    XCTAssertTrue(conversation.isSelfAnActiveMember);
    XCTAssertEqual(conversation.otherActiveParticipants.count, 1u);
    XCTAssertEqual(conversation.activeParticipants.count, 2u);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatItRecalculatesActiveParticipantsWhenIsSelfActiveUserKeyChanges
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    conversation.isSelfAnActiveMember = YES;
    
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    
    [conversation addParticipant:user1];
    [conversation addParticipant:user2];
    
    XCTAssertTrue(conversation.isSelfAnActiveMember);
    XCTAssertEqual(conversation.otherActiveParticipants.count, 2u);
    XCTAssertEqual(conversation.activeParticipants.count, 3u);
    
    // expect
    [self keyValueObservingExpectationForObject:conversation keyPath:@"activeParticipants" expectedValue:nil];
    
    // when
    conversation.isSelfAnActiveMember = NO;
    
    // then
    XCTAssertFalse(conversation.isSelfAnActiveMember);
    XCTAssertEqual(conversation.otherActiveParticipants.count, 2u);
    XCTAssertEqual(conversation.activeParticipants.count, 2u);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatItResetsModificationsToActiveParticipants
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *newUser = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    
    [conversation addParticipant:user1];
    [conversation addParticipant:user2];
    
    [conversation synchronizeAddedUser:user1];
    [conversation synchronizeAddedUser:user2];
    
    
    XCTAssertTrue(conversation.isSelfAnActiveMember);
    XCTAssertEqual(conversation.activeParticipants.count, 3u);
    [conversation setLocallyModifiedKeys:[NSSet setWithObject:@"unsyncedActiveParticipants"]];
    
    // when
    [conversation addParticipant:newUser];
    XCTAssertEqual(conversation.unsyncedActiveParticipants.count, 1u);
    [conversation resetParticipantsBackToLastServerSync];
    
    // then
    XCTAssertEqual(conversation.activeParticipants.count, 3u);
    XCTAssertTrue([conversation.activeParticipants containsObject:user1]);
    XCTAssertTrue([conversation.activeParticipants containsObject:user2]);
    XCTAssertFalse([conversation.activeParticipants containsObject:newUser]);
    
    XCTAssertEqual(conversation.unsyncedActiveParticipants.count, 0u);
    XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:@"unsyncedActiveParticipants"]);
}



- (void)testThatItResetsModificationsToInactiveParticipants
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *newUser = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    
    [conversation addParticipant:user1];
    [conversation addParticipant:user2];
    [conversation addParticipant:newUser];
    
    [conversation synchronizeAddedUser:user1];
    [conversation synchronizeAddedUser:user2];
    [conversation synchronizeAddedUser:newUser];
    
    
    XCTAssertTrue(conversation.isSelfAnActiveMember);
    XCTAssertEqual(conversation.activeParticipants.count, 4u);
    
    // when
    [conversation removeParticipant:newUser];
    [conversation setLocallyModifiedKeys:[NSSet setWithObject:@"unsyncedInactiveParticipants"]];
    XCTAssertEqual(conversation.unsyncedInactiveParticipants.count, 1u);
    
    [conversation resetParticipantsBackToLastServerSync];
    
    // then
    XCTAssertEqual(conversation.activeParticipants.count, 4u);
    XCTAssertTrue([conversation.activeParticipants containsObject:user1]);
    XCTAssertTrue([conversation.activeParticipants containsObject:user2]);
    XCTAssertTrue([conversation.activeParticipants containsObject:newUser]);
    
    XCTAssertEqual(conversation.unsyncedInactiveParticipants.count, 0u);
    XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:@"unsyncedInactiveParticipants"]);
}


@end

@implementation ZMConversationTests (KeyValueObserving)

- (void)testThatItRecalculatesHasDraftMessageWhenDraftMessageTextChanges
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.draftMessageText = @"This is a test";
    
    XCTAssertTrue(conversation.hasDraftMessageText);
    
    // expect
    [self keyValueObservingExpectationForObject:conversation keyPath:@"hasDraftMessageText" expectedValue:nil];
    
    // when
    conversation.draftMessageText = @"";
    
    // then
    XCTAssertFalse(conversation.hasDraftMessageText);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}


- (void)testThatItRecalculatesLastReadMessageWhenLastReadServerTimeStampChanges
{
    // given
    ZMTextMessage *message1 = [ZMTextMessage insertNewObjectInManagedObjectContext:self.uiMOC];
    message1.serverTimestamp = [NSDate date];
    
    ZMTextMessage *message2 = [ZMTextMessage insertNewObjectInManagedObjectContext:self.uiMOC];
    message2.serverTimestamp = [NSDate date];
    
    ZMTextMessage *message3 = [ZMTextMessage insertNewObjectInManagedObjectContext:self.uiMOC];
    message3.serverTimestamp = [NSDate date];
    
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    [conversation.mutableMessages addObject:message1];
    [conversation.mutableMessages addObject:message2];
    [conversation.mutableMessages addObject:message3];

    conversation.lastReadServerTimeStamp = message2.serverTimestamp;
    
    XCTAssertEqualObjects(conversation.lastReadMessage, message2);
    
    // expect
    [self keyValueObservingExpectationForObject:conversation keyPath:@"lastReadMessage" expectedValue:nil];
    
    // when
    conversation.lastReadServerTimeStamp = message3.serverTimestamp;

    // then
    XCTAssertEqualObjects(conversation.lastReadMessage, message3);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}


- (void)testThatItRecalculatesLastReadMessageWhenMessagesChanges
{
    // given
    ZMTextMessage *message1 = [ZMTextMessage insertNewObjectInManagedObjectContext:self.uiMOC];
    message1.serverTimestamp = [NSDate date];
    
    ZMTextMessage *message2 = [ZMTextMessage insertNewObjectInManagedObjectContext:self.uiMOC];
    message2.serverTimestamp = [NSDate date];
    
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    [conversation.mutableMessages addObject:message1];
    
    conversation.lastReadServerTimeStamp = message2.serverTimestamp;
    
    
    XCTAssertEqualObjects(conversation.lastReadMessage, message1);
    
    // expect
    [self keyValueObservingExpectationForObject:conversation keyPath:@"lastReadMessage" expectedValue:nil];
    
    // when
    [conversation.mutableMessages addObject:message2];
    
    // then
    XCTAssertEqualObjects(conversation.lastReadMessage, message2);
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}


- (void)testThatTheSelfConversationHasTheSameRemoteIdentifierAsTheSelfUser
{
    // given
    NSUUID *selfUserID = [NSUUID createUUID];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = selfUserID;
    }];
    
    // when
    __block NSUUID *selfConversationID = nil;
    [self.syncMOC performGroupedBlockAndWait:^{
        selfConversationID = [ZMConversation selfConversationIdentifierInContext:self.syncMOC];
    }];
    
    // then
    XCTAssertEqualObjects(selfConversationID, selfUserID);
}

@end



@implementation ZMConversationTests (Clearing)

- (void)testThatGettingRemovedIsNotMovingConversationToClearedList
{
    // given
    ZMUser *user0 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user0.remoteIdentifier = [NSUUID createUUID];
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user1.remoteIdentifier = [NSUUID createUUID];
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    
    [self.uiMOC saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSArray *users = @[user0, user1, selfUser];
    ZMConversation *conversation = [self insertConversationWithParticipants:users callParticipants:users callStateNeedsToBeUpdatedFromBackend:NO];
    [conversation appendMessageWithText:@"0"];
    
    ZMConversationList *activeList = [ZMConversationList conversationsInUserSession:self.mockUserSessionWithUIMOC];
    ZMConversationList *archivedList = [ZMConversationList archivedConversationsInUserSession:self.mockUserSessionWithUIMOC];
    ZMConversationList *clearedList = [ZMConversationList clearedConversationsInUserSession:self.mockUserSessionWithUIMOC];
    
    // when
    [conversation internalRemoveParticipant:selfUser sender:user0];
    
    // then
    XCTAssertTrue([activeList predicateMatchesConversation:conversation]);
    XCTAssertFalse([archivedList predicateMatchesConversation:conversation]);
    XCTAssertFalse([clearedList predicateMatchesConversation:conversation]);
}


- (void)testThatClearingMessageHistoryDeletesAllMessages
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        
        ZMMessage *message1 = (id)[conversation appendMessageWithText:@"B"];
        [message1 expire];
        
        [conversation appendMessageWithText:@"A"];
        
        ZMMessage *message3 = (id)[conversation appendMessageWithText:@"B"];
        [message3 expire];
        conversation.lastServerTimeStamp = message3.serverTimestamp;
        
        // when
        conversation.clearedTimeStamp = conversation.lastServerTimeStamp;
        
        // then
        for (ZMMessage *message in conversation.messages) {
            XCTAssertTrue(message.isDeleted);
        }
    }];
}

- (void)testThatSettingClearedTimeStampDueToRemoteChangeDoesNotDeleteUnsentMessages
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        
        ZMMessage *message1 = (id)[conversation appendMessageWithText:@"A"];
        [message1 expire];
        
        NSDate *clearedTimestamp = [NSDate date];
        ZMMessage *message2 = (id)[conversation appendMessageWithText:@"B"];
        message2.serverTimestamp = clearedTimestamp;
        conversation.lastServerTimeStamp = clearedTimestamp;
        
        [self spinMainQueueWithTimeout:1];
        
        ZMMessage *message3 = (id)[conversation appendMessageWithText:@"C"];
        [message3 expire];
        
        // when
        conversation.clearedTimeStamp = clearedTimestamp;
        
        // then
        XCTAssertTrue(message1.isDeleted);
        XCTAssertTrue(message2.isDeleted);
        XCTAssertFalse(message3.isDeleted);

    }];
}

- (void)testThatSettingClearedTimeStampDueToRemoteChangeOnlyDeletesOlderMessages_EventIsNotMessage
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        
        ZMMessage *message1 = (id)[conversation appendMessageWithText:@"A"];
        message1.serverTimestamp = [NSDate date];
        
        NSDate *clearedTimestamp = [message1.serverTimestamp dateByAddingTimeInterval:10];
        
        ZMMessage *message2 = (id)[conversation appendMessageWithText:@"B"];
        message2.serverTimestamp = [clearedTimestamp dateByAddingTimeInterval:10];
        
        // when
        conversation.clearedTimeStamp = clearedTimestamp;
        
        // then
        XCTAssertTrue(message1.isDeleted);
        XCTAssertFalse(message2.isDeleted);
    }];
}

- (void)testThatClearingMessageHistorySetsLastReadServerTimeStampToLastServerTimeStamp
{
    // given
    NSDate *clearedTimeStamp = [NSDate date];

    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.lastServerTimeStamp = clearedTimeStamp;

    ZMMessage *message1 = (id)[conversation appendMessageWithText:@"B"];
    message1.serverTimestamp = clearedTimeStamp;
    
    XCTAssertNil(conversation.lastReadServerTimeStamp);
    
    // when
    [conversation clearMessageHistory];
    [self.uiMOC saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(conversation.lastReadServerTimeStamp, clearedTimeStamp);
}

- (void)testThatClearingMessageHistorySetsClearedTimeStampToLastServerTimeStamp
{
    // given
    NSDate *clearedTimeStamp = [NSDate date];
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.lastServerTimeStamp = clearedTimeStamp;
    ZMMessage *message1 = (id)[conversation appendMessageWithText:@"B"];
    message1.serverTimestamp = clearedTimeStamp;
    
    XCTAssertNil(conversation.clearedTimeStamp);
    
    // when
    [conversation clearMessageHistory];
    [self.uiMOC saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(conversation.clearedTimeStamp, clearedTimeStamp);
}


- (void)testThatRemovingOthersInConversationDoesntClearsMessages
{
    // given
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    [self.uiMOC saveOrRollback];
    NSArray *users = @[user1, user2, selfUser];
    ZMConversation *conversation = [self insertConversationWithParticipants:users callParticipants:users callStateNeedsToBeUpdatedFromBackend:NO];
    
    ZMMessage *message1 = (id)[conversation appendMessageWithText:@"1"];
    message1.serverTimestamp = [NSDate date];
    
    ZMMessage *message2 = (id)[conversation appendMessageWithText:@"2"];
    message2.serverTimestamp = [NSDate date];
    
    // when
    [conversation removeParticipant:user1];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertFalse(conversation.isArchived);
    XCTAssertNil(conversation.clearedTimeStamp);

    ZMConversationMessageWindow *window = [conversation conversationWindowWithSize:2];
    XCTAssertEqual(window.messages.count, 2u);
}


- (void)testThatClearingMessageHistorySetsIsArchived
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    XCTAssertFalse(conversation.isArchived);
    
    // when
    [conversation clearMessageHistory];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(conversation.isArchived);
}

@end



@implementation ZMConversationTests (Archiving)

- (void)testThatLeavingAConversationMarksItAsArchived
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.remoteIdentifier = NSUUID.createUUID;
    ZMUser *otherUser = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    [conversation.mutableOtherActiveParticipants addObject:otherUser];
    XCTAssertFalse(conversation.isArchived);
    
    // when
    [conversation removeParticipant:selfUser];
    WaitForAllGroupsToBeEmpty(0.5f);
    
    // then
    XCTAssertTrue(conversation.isArchived);
}

- (void)testThatAppendingATextMessageInAnArchivedConversationUnarchivesIt
{
    [self assertThatAppendingAMessageUnarchivesAConversation:^(ZMConversation *conversation) {
        [conversation appendMessageWithText:@"Text"];
    }];
}

- (void)testThatAppendingAnImageMessageInAnArchivedConversationUnarchivesIt
{
    [self assertThatAppendingAMessageUnarchivesAConversation:^(ZMConversation *conversation) {
        [conversation appendMessageWithImageData:self.verySmallJPEGData];
    }];
}

- (void)testThatAppendingALocationMessageInAnArchivedConversationUnarchivesIt
{
    [self assertThatAppendingAMessageUnarchivesAConversation:^(ZMConversation *conversation) {
        ZMLocationData *location = [ZMLocationData locationDataWithLatitude:42 longitude:8 name:@"Mars" zoomLevel:9000];
        [conversation appendMessageWithLocationData:location];
    }];
}

- (void)assertThatAppendingAMessageUnarchivesAConversation:(void (^)(ZMConversation *))insertBlock
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.remoteIdentifier = NSUUID.createUUID;
    ZMUser *otherUser = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    [conversation.mutableOtherActiveParticipants addObject:otherUser];
    conversation.isArchived = YES;
    XCTAssertTrue(conversation.isArchived);

    // when
    insertBlock(conversation);
    WaitForAllGroupsToBeEmpty(0.5f);

    // then
    XCTAssertFalse(conversation.isArchived);
}

- (void)testThat_UnarchiveConversationFromEvent_unarchivesAConversationAndSetsLocallyModifications;
{

    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.remoteIdentifier = NSUUID.createUUID;
    conversation.lastServerTimeStamp = [NSDate date];
    conversation.isArchived = YES;
    [self.uiMOC saveOrRollback];
    [conversation resetLocallyModifiedKeys:[NSSet setWithObject:ZMConversationArchivedChangedTimeStampKey]];
    
    NSDictionary *payload = @{@"conversation" : conversation.remoteIdentifier.transportString,
                              @"time" : [[conversation.lastServerTimeStamp dateByAddingTimeInterval:100] transportString],
                              @"data" : @{},
                              @"from" : @"f76c1c7a-7278-4b70-9df7-eca7980f3a5d",
                              @"id" : [NSUUID UUID].transportString,
                              @"type": @"conversation.message-add"
                              };
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:(id)payload  uuid:nil];
    
    // when
    [conversation unarchiveConversationFromEvent:event];
    [self.uiMOC saveOrRollback];

    // then
    XCTAssertFalse(conversation.isArchived);
    XCTAssertTrue([conversation.keysThatHaveLocalModifications containsObject:ZMConversationArchivedChangedTimeStampKey]);

}

- (void)testThat_UnarchiveConversationFromEvent_DoesNotUnarchive_AConversation_WhenItIsSilenced
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.remoteIdentifier = NSUUID.createUUID;
    conversation.lastServerTimeStamp = [NSDate date];
    conversation.isArchived = YES;
    conversation.isSilenced = YES;
    
    NSDictionary *payload = @{@"conversation" : conversation.remoteIdentifier.transportString,
                              @"time" : [conversation.lastServerTimeStamp dateByAddingTimeInterval:5].transportString,
                              @"data" : @{},
                              @"from" : @"f76c1c7a-7278-4b70-9df7-eca7980f3a5d",
                              @"type": @"conversation.message-add"
                              };
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:(id)payload  uuid:nil];
    
    // when
    [conversation unarchiveConversationFromEvent:event];
    
    // then
    XCTAssertTrue(conversation.isArchived);
    XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:ZMConversationIsArchivedKey]);
    
}

- (void)testThatArchivingAConversationSetsTheArchivedTimestamp
{
    // given
    NSDate *archivedTimestamp = [NSDate date];
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.lastServerTimeStamp = archivedTimestamp;
    
    // when
    conversation.isArchived = YES;
    
    // then
    XCTAssertEqualObjects(conversation.archivedChangedTimestamp, archivedTimestamp);
}

- (void)testThatUnarchivingAConversationSetsTheArchivedChangedTimestamp
{
    // given
    NSDate *archivedTimestamp = [NSDate date];
    NSDate *unarchivedTimestamp = [archivedTimestamp dateByAddingTimeInterval:100];

    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.lastServerTimeStamp = archivedTimestamp;
    conversation.isArchived = YES;
    XCTAssertNotNil(conversation.archivedChangedTimestamp);
    XCTAssertEqual([conversation.archivedChangedTimestamp timeIntervalSince1970], [conversation.lastServerTimeStamp timeIntervalSince1970]);

    // when
    conversation.lastServerTimeStamp = unarchivedTimestamp;
    conversation.isArchived = NO;
    
    // then
    XCTAssertNotNil(conversation.archivedChangedTimestamp);
    XCTAssertEqual([conversation.archivedChangedTimestamp timeIntervalSince1970], [conversation.lastServerTimeStamp timeIntervalSince1970]);
}

@end



@implementation ZMConversationTests (Knocking)

- (ZMConversation *)createConversationWithMessages;
{
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
    conversation.remoteIdentifier = NSUUID.createUUID;
    for (NSString *text in @[@"A", @"B", @"C", @"D", @"E"]) {
        [conversation appendMessageWithText:text];
    }
    XCTAssert([self.syncMOC saveOrRollback]);
    return conversation;
}

- (void)testThatItCanInsertAKnock;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        ZMConversation *conversation = [self createConversationWithMessages];
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        
        // when
        id<ZMConversationMessage> knock = [conversation appendKnock];
        id<ZMConversationMessage> msg = [conversation.messages lastObject];
        
        // then
        XCTAssertEqual(knock, msg);
        XCTAssertNotNil(knock.knockMessageData);
        XCTAssertEqual(knock.sender, selfUser);
    }];

}

- (void)waitForInterval:(NSTimeInterval)interval {
    [self spinMainQueueWithTimeout:interval];
}

@end


@implementation ZMConversationTests (ObjectIds)

- (ZMConversation *)insertConversationWithUnread:(BOOL)hasUnread
{
    NSDate *messageDate = [NSDate dateWithTimeIntervalSince1970:230000000];
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
    conversation.conversationType = ZMConversationTypeOneOnOne;
    conversation.lastServerTimeStamp = messageDate;
    if(hasUnread) {
        ZMClientMessage *message = [ZMClientMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        message.serverTimestamp = messageDate;
        conversation.lastReadServerTimeStamp = [messageDate dateByAddingTimeInterval:-1000];
        [conversation sortedAppendMessage:message];
        [conversation resortMessagesWithUpdatedMessage:message];
    }
    [self.syncMOC saveOrRollback];
    return conversation;
}

- (void)testThatItCountsConversationsWithUnreadMessagesAsUnread_IfItHasUnread
{
    // given
    
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqual([ZMConversation unreadConversationCountInContext:self.syncMOC], 0lu);
        [self insertConversationWithUnread:YES];
        
        // when
        XCTAssert([self.syncMOC saveOrRollback]);
        
        //then
        XCTAssertEqual([ZMConversation unreadConversationCountInContext:self.syncMOC], 1lu);
    }];
}


- (void)testThatItDoesNotCountConversationsWithUnreadMessagesAsUnread_IfItHasNoUnread
{
    // give
    
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqual([ZMConversation unreadConversationCountInContext:self.syncMOC], 0lu);
        [self insertConversationWithUnread:NO];
        
        // when
        XCTAssert([self.syncMOC saveOrRollback]);
        
        //then
        XCTAssertEqual([ZMConversation unreadConversationCountInContext:self.syncMOC], 0lu);
    }];
}

- (void)testThatItCountsConversationsWithPendingConnectionAsUnread
{
    // given

    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqual([ZMConversation unreadConversationCountInContext:self.syncMOC], 0lu);
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeConnection;
        ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        connection.conversation = conversation;
        connection.status = ZMConnectionStatusPending;
        
        // when
        XCTAssert([self.syncMOC saveOrRollback]);
        
        // then
        XCTAssertEqual([ZMConversation unreadConversationCountInContext:self.syncMOC], 1lu);
    }];
}

- (void)testThatItDoesNotCountConversationsWithSentConnectionAsUnread
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqual([ZMConversation unreadConversationCountInContext:self.syncMOC], 0lu);
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeConnection;
        ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        connection.conversation = conversation;
        connection.status = ZMConnectionStatusSent;
        
        // when
        XCTAssert([self.syncMOC saveOrRollback]);
        
        // then
        XCTAssertEqual([ZMConversation unreadConversationCountInContext:self.syncMOC], 0lu);
    }];
}

- (void)testThatItDoesNotCountBlockedConversationsAsUnread
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqual([ZMConversation unreadConversationCountInContext:self.syncMOC], 0lu);
    
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeConnection;
        ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        connection.conversation = conversation;
        connection.status = ZMConnectionStatusBlocked;
        
        // when
        XCTAssert([self.syncMOC saveOrRollback]);
        
        // then
        XCTAssertEqual([ZMConversation unreadConversationCountInContext:self.syncMOC], 0lu);
    }];
}

- (void)testThatItDoesNotCountIgnoredConversationsAsUnread
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqual([ZMConversation unreadConversationCountInContext:self.syncMOC], 0lu);

        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeConnection;
        ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        connection.conversation = conversation;
        connection.status = ZMConnectionStatusIgnored;
        
        // when
        XCTAssert([self.syncMOC saveOrRollback]);
        
        // then
        XCTAssertEqual([ZMConversation unreadConversationCountInContext:self.syncMOC], 0lu);
    }];
}

- (void)testThatItDoesNotCountSilencedConversationsEvenWithUnreadContentAsUnread;
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqual([ZMConversation unreadConversationCountInContext:self.syncMOC], 0lu);
    
        ZMConversation *conversation = [self insertConversationWithUnread:YES];
        conversation.isSilenced = YES;
        
        // when
        XCTAssert([self.syncMOC saveOrRollback]);
        
        // then
        XCTAssertEqual([ZMConversation unreadConversationCountInContext:self.syncMOC], 0lu);
    }];
}

- (void)testThatItCountsArchivedConversationsWithUnreadMessagesAsUnread;
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqual([ZMConversation unreadConversationCountInContext:self.syncMOC], 0lu);

        ZMConversation *conversation = [self insertConversationWithUnread:YES];
        conversation.isArchived = YES;
        
        // when
        XCTAssert([self.syncMOC saveOrRollback]);
        
        // then
        XCTAssertEqual([ZMConversation unreadConversationCountInContext:self.syncMOC], 1lu);
    }];
}

- (void)testThatItDoesNotCountConversationsThatAreClearedAsUnread;
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqual([ZMConversation unreadConversationCountInContext:self.syncMOC], 0lu);

        ZMConversation *conversation = [self insertConversationWithUnread:YES];
        conversation.isArchived = YES;
        [conversation clearMessageHistory];
        
        // when
        XCTAssert([self.syncMOC saveOrRollback]);
        
        // then
        XCTAssertEqual([ZMConversation unreadConversationCountInContext:self.syncMOC], 0lu);
    }];
}

@end



@implementation ZMConversationTests (ConversaitonListIndicator)

- (void)setConversationAsHavingKnock:(ZMConversation *)conversation
{
    [self simulateUnreadMissedKnockInConversation:conversation];
}

- (void)setConversationAsHavingMissedCall:(ZMConversation *)conversation
{
    [self simulateUnreadMissedCallInConversation:conversation];
}

- (void)setConversationAsHavingActiveCall:(ZMConversation *)conversation
{
    conversation.callDeviceIsActive = YES;
}

- (void)setConversationAsHavingIgnoredCall:(ZMConversation *)conversation
{
    conversation.isIgnoringCall = YES;
    
    ZMUser *participant = [self createUserOnMoc:self.syncMOC];
    NSMutableOrderedSet *participants = [conversation mutableOrderedSetValueForKey:ZMConversationCallParticipantsKey];
    [participants addObject:participant];
}

- (void)setConversationAsBeingPending:(ZMConversation *)conversation inContext:(NSManagedObjectContext *)context
{
    conversation.conversationType = ZMConversationTypeConnection;
    conversation.connection = [ZMConnection insertNewObjectInManagedObjectContext:context];
    conversation.connection.to = [ZMUser insertNewObjectInManagedObjectContext:context];
    conversation.connection.status = ZMConnectionStatusSent;
}


- (void)testThatConversationListIndicatorIsNoneByDefault
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // then
    XCTAssertEqual(conversation.conversationListIndicator, ZMConversationListIndicatorNone);
}

- (void)testThatConversationListIndicatorIsUnreadMessageWhenItHasUnread
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        [self simulateUnreadCount:2 forConversation:conversation];
        
        // then
        XCTAssertEqual(conversation.conversationListIndicator, ZMConversationListIndicatorUnreadMessages);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatConversationListIndicatorIsKnockWhenItHasUnreadAndKnock
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        [self simulateUnreadCount:1 forConversation:conversation];
        [self simulateUnreadMissedKnockInConversation:conversation];
        
        // then
        XCTAssertEqual(conversation.conversationListIndicator, ZMConversationListIndicatorKnock);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatConversationListIndicatorIsMissedCallWhenItHasMissedCallAndLowerPriorityEvents
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        [self simulateUnreadCount:1 forConversation:conversation];
        [self simulateUnreadMissedKnockInConversation:conversation];
        [self simulateUnreadMissedCallInConversation:conversation];
        
        // then
        XCTAssertEqual(conversation.conversationListIndicator, ZMConversationListIndicatorMissedCall);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatConversationListIndicatorIsExpiredMessageWhenItHasExpiredMessageAndLowerPriorityEvents
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        [self simulateUnreadCount:1 forConversation:conversation];
        [self simulateUnreadMissedKnockInConversation:conversation];
        [self simulateUnreadMissedCallInConversation:conversation];
        [conversation setHasUnreadUnsentMessage:YES];
        
        // then
        XCTAssertEqual(conversation.conversationListIndicator, ZMConversationListIndicatorExpiredMessage);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatConversationListIndicatorIsVoiceInactiveWhenItHasIgnoredActiveVoiceChannelAndLowerPriorityEvents
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        [self simulateUnreadCount:1 forConversation:conversation];
        [self simulateUnreadMissedKnockInConversation:conversation];
        [self simulateUnreadMissedCallInConversation:conversation];
        [conversation setHasUnreadUnsentMessage:YES];
        [self setConversationAsHavingIgnoredCall:conversation];
        
        // then
        XCTAssertEqual(conversation.conversationListIndicator, ZMConversationListIndicatorInactiveCall);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatConversationListIndicatorIsPendingConversationWhenItIsAPendingConnectionAndItHasLowerPriorityEvents
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        [self simulateUnreadCount:1 forConversation:conversation];
        [self simulateUnreadMissedKnockInConversation:conversation];
        [self simulateUnreadMissedCallInConversation:conversation];
        [conversation setHasUnreadUnsentMessage:YES];
        [self setConversationAsBeingPending:conversation inContext:self.syncMOC];
        
        // then
        XCTAssertEqual(conversation.conversationListIndicator, ZMConversationListIndicatorPending);

    }];
    WaitForAllGroupsToBeEmpty(0.5);
}


@end


@implementation ZMConversationTests (SearchQuerys)

- (void)testThatItFindsConversationsWithUserDefinedNameByParticipantName
{
    // given
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user1.name = @"User1";
    ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user2.name = @"User2";
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    [conversation.mutableOtherActiveParticipants addObjectsFromArray:@[user1, user2]];
    conversation.userDefinedName = @"Conversation";
    conversation.conversationType = ZMConversationTypeGroup;
    [self.uiMOC saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Conversation"];
    request.predicate = [ZMConversation predicateForSearchString:@"User1"];
    
    NSArray *result = [self.uiMOC executeFetchRequestOrAssert:request];
    
    // then
    XCTAssertEqual(result.count, 1u);
    XCTAssertEqualObjects(result.firstObject, conversation);
}

- (void)testThatItFindsConversationsWithUserDefinedNameByParticipantName_SecondSearchComponent
{
    // given
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user1.name = @"Foo 1";
    ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user2.name = @"Bar 2";
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    [conversation.mutableOtherActiveParticipants addObjectsFromArray:@[user1, user2]];
    conversation.userDefinedName = @"Conversation";
    conversation.conversationType = ZMConversationTypeGroup;
    [self.uiMOC saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Conversation"];
    request.predicate = [ZMConversation predicateForSearchString:@"Foo Bar"];
    
    NSArray *result = [self.uiMOC executeFetchRequestOrAssert:request];
    
    // then
    XCTAssertEqual(result.count, 1u);
    XCTAssertEqualObjects(result.firstObject, conversation);
}


- (void)testThatItFindsConversationByUserDefinedName
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.userDefinedName = @"The Wire Club";
    conversation.conversationType = ZMConversationTypeGroup;
    [self.uiMOC saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Conversation"];
    request.predicate = [ZMConversation userDefinedNamePredicateForSearchString:@"The Wire"];
    
    NSArray *result = [self.uiMOC executeFetchRequestOrAssert:request];
    
    // then
    XCTAssertEqual(result.count, 1u);
    XCTAssertEqualObjects(result.firstObject, conversation);
}

- (void)testThatItOnlyFindsConversationsWithAllComponents
{
    // given
    ZMConversation *conversation1 = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation1.userDefinedName = @"The Wire";
    conversation1.conversationType = ZMConversationTypeGroup;
    ZMConversation *conversation2 = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation2.userDefinedName = @"The Club";
    conversation2.conversationType = ZMConversationTypeGroup;
    [self.uiMOC saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Conversation"];
    request.predicate = [ZMConversation userDefinedNamePredicateForSearchString:@"The Wire"];
    
    NSArray *result = [self.uiMOC executeFetchRequestOrAssert:request];
    
    // then
    XCTAssertEqual(result.count, 1u);
    XCTAssertEqualObjects(result.firstObject, conversation1);
}


- (void)testThatItFindsConversationsWithMatchingUserNameOrMatchingUserDefinedName
{
    // given
    ZMConversation *conversation1 = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation1.userDefinedName = @"Bine in da Haus";
    conversation1.conversationType = ZMConversationTypeGroup;
    
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user1.name = @"Bine hallo";
    ZMConversation *conversation2 = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation2.userDefinedName = @"The Club";
    conversation2.conversationType = ZMConversationTypeGroup;
    [conversation2.mutableOtherActiveParticipants addObject:user1];
    [self.uiMOC saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Conversation"];
    request.predicate = [ZMConversation predicateForSearchString:@"Bine"];
    
    NSArray *result = [self.uiMOC executeFetchRequestOrAssert:request];
    
    // then
    XCTAssertEqual(result.count, 2u);
}


- (void)testThatItDoesNotFindAOneOnOneConversationByUserDefinedName
{
    // given
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user1.name = @"Foo";
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];

    [conversation.mutableOtherActiveParticipants addObjectsFromArray:@[user1]];
    conversation.userDefinedName = @"Conversation";
    conversation.conversationType = ZMConversationTypeOneOnOne;
    [self.uiMOC saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Conversation"];
    request.predicate = [ZMConversation userDefinedNamePredicateForSearchString:@"Find Conversation"];
    
    NSArray *result = [self.uiMOC executeFetchRequestOrAssert:request];
    
    // then
    XCTAssertEqual(result.count, 0u);
}


- (void)testThatItDoesNotFindAConversationThatDoesNotStartWithButContainsTheSearchString
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.userDefinedName = @"FindTheString";
    conversation.conversationType = ZMConversationTypeGroup;
    [self.uiMOC saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:@"Conversation"];
    request.predicate = [ZMConversation userDefinedNamePredicateForSearchString:@"TheString"];
    
    NSArray *result = [self.uiMOC executeFetchRequestOrAssert:request];
    
    // then
    XCTAssertEqual(result.count, 0u);
}

@end



@implementation ZMConversationTests (Predicates)



- (void)testThatItFetchesConversationsWithCallStateNeededToBeSynced
{
    //given
    ZMUser *otherUser = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *secondUser = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    [self.uiMOC saveOrRollback];
    
    NSArray *users = @[otherUser,secondUser];
    
    ZMConversation *conversationWithCallParticipants = [self insertConversationWithParticipants:users callParticipants:users callStateNeedsToBeUpdatedFromBackend:NO];
    ZMConversation *alreadyMarkedConversation = [self insertConversationWithParticipants:users callParticipants:users callStateNeedsToBeUpdatedFromBackend:YES];
    ZMConversation *conversationWithNoCallParticipants = [self insertConversationWithParticipants:users callParticipants:@[] callStateNeedsToBeUpdatedFromBackend:NO];
    
    //when
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:[ZMConversation entityName]];
    request.predicate = [ZMConversation predicateForUpdatingCallStateDuringSlowSync];
    
    // when
    NSArray *result = [self.uiMOC executeFetchRequestOrAssert:request];
    XCTAssertTrue([result containsObject:conversationWithCallParticipants]);
    XCTAssertFalse([result containsObject:alreadyMarkedConversation]);
    XCTAssertFalse([result containsObject:conversationWithNoCallParticipants]);
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItFiltersOut_SelfConversation
{
    // given
    NSUUID *selfUserID = [NSUUID UUID];
    [ZMUser selfUserInContext:self.uiMOC].remoteIdentifier = selfUserID;
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeSelf;
    conversation.remoteIdentifier = selfUserID;
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    NSPredicate *sut = [ZMConversation predicateForConversationsIncludingArchived];
    
    // then
    XCTAssertFalse([sut evaluateWithObject:conversation]);
}

- (void)testThatItDoesNotFilterOut_NotCleared_Archived_Conversations_IncludingArchivedPredicate
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    [self performIgnoringZMLogError:^{
        [self timeStampForSortAppendMessageToConversation:conversation];
    }];
    conversation.isArchived = YES;
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue(conversation.isArchived);
    XCTAssertNil(conversation.clearedTimeStamp);
    
    // when
    NSPredicate *sut = [ZMConversation predicateForConversationsIncludingArchived];
    
    // then
    XCTAssertTrue([sut evaluateWithObject:conversation]);
}

- (void)testThatItDoesNotFilterOut_Cleared_Archived_Conversations_WithNewMessages_IncludingArchivedPredicate
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    __block NSDate *clearedTimeStamp;
    [self performIgnoringZMLogError:^{
        clearedTimeStamp = [self timeStampForSortAppendMessageToConversation:conversation];
    }];

    [conversation clearMessageHistory];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self performIgnoringZMLogError:^{
        [self timeStampForSortAppendMessageToConversation:conversation];
    }];
    XCTAssertTrue(conversation.isArchived);
    XCTAssertEqualObjects(conversation.clearedTimeStamp, clearedTimeStamp);
    
    // when
    NSPredicate *sut = [ZMConversation predicateForConversationsIncludingArchived];
    
    // then
    XCTAssertTrue([sut evaluateWithObject:conversation]);
}


- (void)testThatItFiltersOutArchivedAndClearedConversations_IncludingArchivedPredicate
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    __block NSDate *clearedTimeStamp;
    [self performIgnoringZMLogError:^{
        clearedTimeStamp = [self timeStampForSortAppendMessageToConversation:conversation];
    }];

    [conversation clearMessageHistory];
    WaitForAllGroupsToBeEmpty(0.5);

    XCTAssertTrue(conversation.isArchived);
    XCTAssertEqualObjects(conversation.clearedTimeStamp, clearedTimeStamp);

    // when
    NSPredicate *sut = [ZMConversation predicateForConversationsIncludingArchived];
    
    // then
    XCTAssertFalse([sut evaluateWithObject:conversation]);
}

- (void)testThatItDoesNotFilterClearedConversationsThatAreNotArchived_IncludingArchivedPredicate
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    __block NSDate *clearedTimeStamp;
    [self performIgnoringZMLogError:^{
        clearedTimeStamp = [self timeStampForSortAppendMessageToConversation:conversation];
    }];
    
    [conversation clearMessageHistory];
    WaitForAllGroupsToBeEmpty(0.5);
    
    conversation.isArchived = NO;
    XCTAssertFalse(conversation.isArchived);
    XCTAssertEqualObjects(conversation.clearedTimeStamp, clearedTimeStamp);
    
    // when
    NSPredicate *sut = [ZMConversation predicateForConversationsIncludingArchived];
    
    // then
    XCTAssertTrue([sut evaluateWithObject:conversation]);
}

- (void)testThatItReturnsClearedConversationsInWhichSelfIsActiveMember_SearchStringPredicate
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.userDefinedName = @"lala";
    conversation.conversationType = ZMConversationTypeGroup;
    __block NSDate *clearedTimeStamp;
    [self performIgnoringZMLogError:^{
        clearedTimeStamp = [self timeStampForSortAppendMessageToConversation:conversation];
    }];
    [self.uiMOC saveOrRollback];
    
    [conversation clearMessageHistory];
    conversation.isSelfAnActiveMember = YES;
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue(conversation.isArchived);
    XCTAssertTrue(conversation.isSelfAnActiveMember);
    XCTAssertEqualObjects(conversation.clearedTimeStamp, clearedTimeStamp);
    
    // when
    NSPredicate *sut = [ZMConversation predicateForSearchString:@"lala"];
    
    // then
    XCTAssertTrue([sut evaluateWithObject:conversation]);
}

- (void)testThatIt_DoesNot_ReturnClearedConversationsInWhichSelfIs_Not_ActiveMember_SearchStringPredicate
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.userDefinedName = @"lala";
    conversation.conversationType = ZMConversationTypeGroup;
    __block NSDate *clearedTimeStamp;
    [self performIgnoringZMLogError:^{
        clearedTimeStamp = [self timeStampForSortAppendMessageToConversation:conversation];
    }];

    [self.uiMOC saveOrRollback];
    
    [conversation clearMessageHistory];
    conversation.isSelfAnActiveMember = NO;
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue(conversation.isArchived);
    XCTAssertFalse(conversation.isSelfAnActiveMember);
    XCTAssertEqualObjects(conversation.clearedTimeStamp, clearedTimeStamp);
    
    // when
    NSPredicate *sut = [ZMConversation predicateForSearchString:@"lala"];
    
    // then
    XCTAssertFalse([sut evaluateWithObject:conversation]);
}

- (void)testThatItReturnsConversationsInWhichSelfIs_Not_ActiveMember_NotCleared_SearchStringPredicate
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.userDefinedName = @"lala";
    conversation.conversationType = ZMConversationTypeGroup;
    [self performIgnoringZMLogError:^{
        [self timeStampForSortAppendMessageToConversation:conversation];
    }];
    conversation.isSelfAnActiveMember = NO;
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertFalse(conversation.isSelfAnActiveMember);
    XCTAssertNil(conversation.clearedTimeStamp);
    
    // when
    NSPredicate *sut = [ZMConversation predicateForSearchString:@"lala"];
    
    // then
    XCTAssertTrue([sut evaluateWithObject:conversation]);
}

- (void)testThatItFetchesSharableConversations
{
    //given
    ZMUser *otherUser = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    ZMUser *secondUser = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    
    ZMConversation *conversationWithOtherUser = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversationWithOtherUser.conversationType = ZMConversationTypeOneOnOne;
    conversationWithOtherUser.remoteIdentifier = [NSUUID createUUID];
    [conversationWithOtherUser.mutableOtherActiveParticipants addObject:otherUser];

    ZMConversation *notSyncedConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    notSyncedConversation.conversationType = ZMConversationTypeOneOnOne;
    [notSyncedConversation.mutableOtherActiveParticipants addObject:otherUser];

    ZMConversation *conversationWithSecondUser = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversationWithSecondUser.conversationType = ZMConversationTypeOneOnOne;
    conversationWithSecondUser.remoteIdentifier = [NSUUID createUUID];
    [conversationWithSecondUser.mutableOtherActiveParticipants addObject:secondUser];
    
    ZMConversation *emptyConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    emptyConversation.conversationType = ZMConversationTypeOneOnOne;
    
    ZMConversation *conversationWithSentRequest = [ZMConnection insertNewSentConnectionToUser:otherUser].conversation;
    
    ZMConversation *conversationWithIncommingRequest = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversationWithIncommingRequest.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    conversationWithIncommingRequest.conversationType = ZMConversationTypeConnection;
    conversationWithIncommingRequest.connection.status = ZMConnectionStatusPending;
    conversationWithIncommingRequest.remoteIdentifier = [NSUUID createUUID];
    
    ZMConversation *groupConversationWithSelf = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.uiMOC withParticipants:@[otherUser, secondUser]];
    groupConversationWithSelf.isSelfAnActiveMember = YES;
    groupConversationWithSelf.remoteIdentifier = [NSUUID createUUID];
    
    ZMConversation *groupConversationWithoutSelf = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.uiMOC withParticipants:@[otherUser, secondUser]];
    groupConversationWithoutSelf.isSelfAnActiveMember = NO;
    groupConversationWithSelf.remoteIdentifier = [NSUUID createUUID];
    
    ZMConversation *groupConversationWithNoOtherParticipants = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.uiMOC withParticipants:@[otherUser, secondUser]];
    [groupConversationWithNoOtherParticipants removeParticipant:otherUser];
    [groupConversationWithNoOtherParticipants removeParticipant:secondUser];
    groupConversationWithNoOtherParticipants.isSelfAnActiveMember = YES;
    
    ZMConversation *archived = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    [archived.mutableOtherActiveParticipants addObject:otherUser];
    archived.conversationType = ZMConversationTypeOneOnOne;
    archived.isArchived = YES;
    archived.remoteIdentifier = [NSUUID createUUID];
    
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:[ZMConversation entityName]];
    request.predicate = [ZMConversation predicateForSharableConversations];
    
    //when
    NSArray *result = [self.uiMOC executeFetchRequestOrAssert:request];
    
    //then
    XCTAssertEqual(result.count, 4u);
    XCTAssertTrue([result containsObject:conversationWithOtherUser]);
    XCTAssertTrue([result containsObject:conversationWithSecondUser]);
    XCTAssertTrue([result containsObject:groupConversationWithSelf]);
    XCTAssertTrue([result containsObject:archived]);
    
    XCTAssertFalse([result containsObject:emptyConversation]);
    XCTAssertFalse([result containsObject:conversationWithSentRequest]);
    XCTAssertFalse([result containsObject:conversationWithIncommingRequest]);
    XCTAssertFalse([result containsObject:groupConversationWithoutSelf]);
    XCTAssertFalse([result containsObject:groupConversationWithNoOtherParticipants]);
    XCTAssertFalse([result containsObject:notSyncedConversation]);
}

@end



@implementation ZMConversationTests (SelfConversationSync)

- (void)testThatItSetsHasLocalModificationsForLastReadServerTimeStampWhenSettingLastRead
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        conversation.lastReadServerTimeStamp = [NSDate date];
        NSDate *newLastRead = [conversation.lastReadServerTimeStamp dateByAddingTimeInterval:5];
        
        NSDictionary *payload = @{@"conversation" : conversation.remoteIdentifier.transportString,
                                  @"time" : newLastRead.transportString,
                                  @"data" : @{},
                                  @"from" : @"f76c1c7a-7278-4b70-9df7-eca7980f3a5d",
                                  @"type": @"conversation.message-add"
                                  };
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:(id)payload uuid:nil];
        
        // when
        [conversation updateLastReadFromPostPayloadEvent:event];
        [self.syncMOC saveOrRollback];
        
        // then
        XCTAssertTrue([conversation hasLocalModificationsForKey:ZMConversationLastReadServerTimeStampKey]);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItUpdatesTheConversationWhenItReceivesALastReadMessage
{
    // given
    __block ZMConversation *updatedConversation;
    NSDate *oldLastRead = [NSDate date];
    NSDate *newLastRead = [oldLastRead dateByAddingTimeInterval:100];

    [self.syncMOC performGroupedBlockAndWait:^{
        NSUUID *selfUserID = [ZMUser selfUserInContext:self.syncMOC].remoteIdentifier;
        XCTAssertNotNil(selfUserID);
        
        updatedConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        updatedConversation.remoteIdentifier = [NSUUID createUUID];
        updatedConversation.lastReadServerTimeStamp = oldLastRead;
        
        ZMGenericMessage *message = [ZMGenericMessage messageWithLastRead:newLastRead ofConversationWithID:updatedConversation.remoteIdentifier.transportString nonce:[NSUUID UUID].transportString];
        NSData *contentData = message.data;
        NSString *data = [contentData base64EncodedStringWithOptions:0];
        
        NSDictionary *payload = @{@"conversation" : selfUserID.transportString,
                                  @"time" : newLastRead.transportString,
                                  @"data" : data,
                                  @"from" : selfUserID.transportString,
                                  @"type": @"conversation.client-message-add"
                                  };
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:(id)payload uuid:nil];
        
        // when
        [ZMClientMessage messageUpdateResultFromUpdateEvent:event inManagedObjectContext:self.syncMOC prefetchResult:nil];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertEqualWithAccuracy([updatedConversation.lastReadServerTimeStamp timeIntervalSince1970], [newLastRead timeIntervalSince1970], 1.5);
    }];
}

- (void)testThatItRemovesTheMessageWhenItReceivesAHidingMessage;
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        NSUUID *messageID = [NSUUID createUUID];
        NSUUID *selfUserID = [ZMUser selfUserInContext:self.syncMOC].remoteIdentifier;
        XCTAssertNotNil(selfUserID);
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        [conversation appendOTRMessageWithText:@"Le fromage c'est delicieux" nonce:messageID fetchLinkPreview:YES];
        
        ZMGenericMessage *message = [ZMGenericMessage messageWithHideMessage:messageID.transportString inConversation:conversation.remoteIdentifier.transportString nonce:[NSUUID createUUID].transportString];
        NSData *contentData = message.data;
        NSString *data = [contentData base64EncodedStringWithOptions:0];
        
        NSDictionary *payload = @{@"conversation" : selfUserID.transportString,
                                  @"time" : [NSDate date].transportString,
                                  @"data" : data,
                                  @"from" : selfUserID.transportString,
                                  @"type": @"conversation.client-message-add"
                                  };
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:(id)payload uuid:nil];
        
        // when
        [ZMClientMessage messageUpdateResultFromUpdateEvent:event inManagedObjectContext:self.syncMOC prefetchResult:nil];
        [self.syncMOC saveOrRollback];
        
        // then
        ZMMessage *fetchedMessage = [ZMMessage fetchMessageWithNonce:messageID forConversation:conversation inManagedObjectContext:self.syncMOC];
        XCTAssertNil(fetchedMessage);
    }];
}

- (void)testThatItRemovesImageAssetsWhenItReceivesADeletionMessage;
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        NSUUID *messageID = [NSUUID createUUID];
        NSUUID *selfUserID = [ZMUser selfUserInContext:self.syncMOC].remoteIdentifier;
        NSData *imageData = [NSData secureRandomDataOfLength:100];
        XCTAssertNotNil(selfUserID);
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        [conversation appendOTRMessageWithImageData:[NSData secureRandomDataOfLength:500] nonce:messageID];
        
        // store asset data
        [self.syncMOC.zm_imageAssetCache storeAssetData:messageID format:ZMImageFormatOriginal encrypted:NO data:imageData];
        [self.syncMOC.zm_imageAssetCache storeAssetData:messageID format:ZMImageFormatPreview encrypted:NO data:imageData];
        [self.syncMOC.zm_imageAssetCache storeAssetData:messageID format:ZMImageFormatMedium encrypted:NO data:imageData];
        [self.syncMOC.zm_imageAssetCache storeAssetData:messageID format:ZMImageFormatPreview encrypted:YES data:imageData];
        [self.syncMOC.zm_imageAssetCache storeAssetData:messageID format:ZMImageFormatMedium encrypted:YES data:imageData];
        
        // delete
        ZMGenericMessage *message = [ZMGenericMessage messageWithHideMessage:messageID.transportString inConversation:conversation.remoteIdentifier.transportString nonce:[NSUUID createUUID].transportString];
        NSData *contentData = message.data;
        NSString *data = [contentData base64EncodedStringWithOptions:0];
        
        NSDictionary *payload = @{@"conversation" : selfUserID.transportString,
                                  @"time" : [NSDate date].transportString,
                                  @"data" : data,
                                  @"from" : selfUserID.transportString,
                                  @"type": @"conversation.client-message-add"
                                  };
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:(id)payload uuid:nil];
        
        // when
        [ZMClientMessage messageUpdateResultFromUpdateEvent:event inManagedObjectContext:self.syncMOC prefetchResult:nil];
        [self.syncMOC saveOrRollback];
        
        // then
        XCTAssertNil([self.syncMOC.zm_imageAssetCache assetData:messageID format:ZMImageFormatOriginal encrypted:NO]);
        XCTAssertNil([self.syncMOC.zm_imageAssetCache assetData:messageID format:ZMImageFormatPreview encrypted:NO]);
        XCTAssertNil([self.syncMOC.zm_imageAssetCache assetData:messageID format:ZMImageFormatMedium encrypted:NO]);
        XCTAssertNil([self.syncMOC.zm_imageAssetCache assetData:messageID format:ZMImageFormatPreview encrypted:YES]);
        XCTAssertNil([self.syncMOC.zm_imageAssetCache assetData:messageID format:ZMImageFormatMedium encrypted:YES]);
    }];
}

- (void)testThatItRemovesFileAssetsWhenItReceivesADeletionMessage;
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        NSUUID *messageID = [NSUUID createUUID];
        NSUUID *selfUserID = [ZMUser selfUserInContext:self.syncMOC].remoteIdentifier;
        NSData *fileData = [NSData secureRandomDataOfLength:100];
        NSString *fileName = @"foo.bar";
        
        NSString *documentsURL = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
        NSURL *fileURL = [[NSURL fileURLWithPath:documentsURL] URLByAppendingPathComponent:fileName];
        [fileData writeToURL:fileURL atomically:NO];
        
        XCTAssertNotNil(selfUserID);
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        ZMFileMetadata *fileMetadata = [[ZMFileMetadata alloc] initWithFileURL:fileURL thumbnail:nil];
        [conversation appendOTRMessageWithFileMetadata:fileMetadata nonce:messageID];
        
        // store asset data
        [self.syncMOC.zm_fileAssetCache storeAssetData:messageID fileName:fileName encrypted:NO data:fileData];
        [self.syncMOC.zm_fileAssetCache storeAssetData:messageID fileName:fileName encrypted:YES data:fileData];
        
        // delete
        ZMGenericMessage *message = [ZMGenericMessage messageWithHideMessage:messageID.transportString inConversation:conversation.remoteIdentifier.transportString nonce:[NSUUID createUUID].transportString];
        NSData *contentData = message.data;
        NSString *data = [contentData base64EncodedStringWithOptions:0];
        
        NSDictionary *payload = @{@"conversation" : selfUserID.transportString,
                                  @"time" : [NSDate date].transportString,
                                  @"data" : data,
                                  @"from" : selfUserID.transportString,
                                  @"type": @"conversation.client-message-add"
                                  };
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:(id)payload uuid:nil];
        
        // when
        [ZMClientMessage messageUpdateResultFromUpdateEvent:event inManagedObjectContext:self.syncMOC prefetchResult:nil];
        [self.syncMOC saveOrRollback];
        
        // then
        XCTAssertNil([self.syncMOC.zm_fileAssetCache assetData:messageID fileName:fileName encrypted:NO]);
        XCTAssertNil([self.syncMOC.zm_fileAssetCache assetData:messageID fileName:fileName encrypted:YES]);
    }];
}

- (void)testThatItDoesNotRemovesANonExistingMessageWhenItReceivesADeletionMessage;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        NSUUID *selfUserID = [ZMUser selfUserInContext:self.syncMOC].remoteIdentifier;
        XCTAssertNotNil(selfUserID);
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        
        [conversation appendOTRMessageWithText:@"Le fromage c'est delicieux" nonce:[NSUUID createUUID] fetchLinkPreview:YES];
        NSUInteger previusMessagesCount = conversation.messages.count;
        
        ZMGenericMessage *message = [ZMGenericMessage messageWithHideMessage:[NSUUID createUUID].transportString inConversation:conversation.remoteIdentifier.transportString nonce:[NSUUID createUUID].transportString];
        NSData *contentData = message.data;
        NSString *data = [contentData base64EncodedStringWithOptions:0];
        
        NSDictionary *payload = @{@"conversation" : selfUserID.transportString,
                                  @"time" : [NSDate date].transportString,
                                  @"data" : data,
                                  @"from" : selfUserID.transportString,
                                  @"type": @"conversation.client-message-add"
                                  };
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:(id)payload uuid:nil];
        
        // when
        [ZMClientMessage messageUpdateResultFromUpdateEvent:event inManagedObjectContext:self.syncMOC prefetchResult:nil];
        [self.syncMOC saveOrRollback];
        
        // then
        XCTAssertEqual(previusMessagesCount, conversation.messages.count);
    }];
}

- (void)testThatItDoesNotRemovesAMessageWhenItReceivesADeletionMessageNotFromSelfUser;
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        NSUUID *messageID = [NSUUID createUUID];
        NSUUID *selfUserID = [ZMUser selfUserInContext:self.syncMOC].remoteIdentifier;
        XCTAssertNotNil(selfUserID);
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        [conversation appendOTRMessageWithText:@"Le fromage c'est delicieux" nonce:messageID fetchLinkPreview:YES];
        NSUInteger previusMessagesCount = conversation.messages.count;
        
        ZMGenericMessage *message = [ZMGenericMessage messageWithHideMessage:messageID.transportString inConversation:conversation.remoteIdentifier.transportString nonce:[NSUUID createUUID].transportString];
        NSData *contentData = message.data;
        NSString *data = [contentData base64EncodedStringWithOptions:0];
        
        NSDictionary *payload = @{@"conversation" : selfUserID.transportString,
                                  @"time" : [NSDate date].transportString,
                                  @"data" : data,
                                  @"from" : [NSUUID createUUID].transportString,
                                  @"type": @"conversation.client-message-add"
                                  };
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:(id)payload uuid:nil];
        
        // when
        [ZMClientMessage messageUpdateResultFromUpdateEvent:event inManagedObjectContext:self.syncMOC prefetchResult:nil];
        [self.syncMOC saveOrRollback];
        
        // then
        XCTAssertEqual(previusMessagesCount, conversation.messages.count);
    }];
}

- (void)testThatItDoesNotRemovesAMessageWhenItReceivesADeletionMessageNotInTheSelfConversation;
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        NSUUID *messageID = [NSUUID createUUID];
        NSUUID *selfUserID = [ZMUser selfUserInContext:self.syncMOC].remoteIdentifier;
        XCTAssertNotNil(selfUserID);
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        [conversation appendOTRMessageWithText:@"Le fromage c'est delicieux" nonce:messageID fetchLinkPreview:YES];
        NSUInteger previusMessagesCount = conversation.messages.count;
        
        ZMGenericMessage *message = [ZMGenericMessage messageWithHideMessage:messageID.transportString inConversation:conversation.remoteIdentifier.transportString nonce:[NSUUID createUUID].transportString];
        NSData *contentData = message.data;
        NSString *data = [contentData base64EncodedStringWithOptions:0];
        
        NSDictionary *payload = @{@"conversation" : [NSUUID createUUID].transportString,
                                  @"time" : [NSDate date].transportString,
                                  @"data" : data,
                                  @"from" : selfUserID.transportString,
                                  @"type": @"conversation.client-message-add"
                                  };
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:(id)payload uuid:nil];
        
        // when
        [ZMClientMessage messageUpdateResultFromUpdateEvent:event inManagedObjectContext:self.syncMOC prefetchResult:nil];
        [self.syncMOC saveOrRollback];
        
        // then
        XCTAssertEqual(previusMessagesCount, conversation.messages.count);
    }];
}

@end


@implementation ZMConversationTests (SendOnlyEncryptedMessages)

- (void)testThatItInsertsEncryptedTextMessages
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // when
    [conversation appendMessageWithText:@"hello"];
    
    // then
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:[ZMMessage entityName]];
    NSArray *result = [self.uiMOC executeFetchRequestOrAssert:request];
    
    XCTAssertEqual(result.count, 1u);
    XCTAssertTrue([result.firstObject isKindOfClass:[ZMClientMessage class]]);
}



- (void)testThatItInsertsEncryptedImageMessages
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // when
    [conversation appendMessageWithImageData:self.verySmallJPEGData];
    
    // then
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:[ZMMessage entityName]];
    NSArray *result = [self.uiMOC executeFetchRequestOrAssert:request];
    
    XCTAssertEqual(result.count, 1u);
    XCTAssertTrue([result.firstObject isKindOfClass:[ZMAssetClientMessage class]]);
}

- (void)testThatItInsertsEncryptedKnockMessages
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    
    // when
    [conversation appendKnock];
    
    // then
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:[ZMMessage entityName]];
    NSArray *result = [self.uiMOC executeFetchRequestOrAssert:request];
    
    XCTAssertEqual(result.count, 1u);
    XCTAssertTrue([result.firstObject isKindOfClass:[ZMClientMessage class]]);
}

@end

