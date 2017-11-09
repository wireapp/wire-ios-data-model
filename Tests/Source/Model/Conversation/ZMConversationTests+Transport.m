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


#import "ZMConversationTests.h"
#import "ZMConversation+Transport.h"

@interface ZMConversationTransportTests : ZMConversationTestsBase
@end

@implementation ZMConversationTransportTests

- (NSDictionary *)payloadForMetaDataOfConversation:(ZMConversation *)conversation conversationType:(ZMBackendConversationType)conversationType isArchived:(BOOL)isArchived archivedRef:(NSDate *)archivedRef isSilenced:(BOOL)isSilenced
    silencedRef: (NSDate *)silencedRef;
{
    return  [self payloadForMetaDataOfConversation:conversation conversationType:conversationType activeUserIDs:@[] isArchived:isArchived archivedRef:archivedRef isSilenced:isSilenced silencedRef:silencedRef teamID:nil];
}

- (NSDictionary *)payloadForMetaDataOfConversation:(ZMConversation *)conversation activeUserIDs:(NSArray <NSUUID *>*)activeUserIDs
{
    return  [self payloadForMetaDataOfConversation:conversation conversationType:1 activeUserIDs:activeUserIDs isArchived:NO archivedRef:nil isSilenced:NO silencedRef:nil teamID:nil];
}

- (NSDictionary *)payloadForMetaDataOfConversation:(ZMConversation *)conversation
                                  conversationType:(ZMBackendConversationType)conversationType
                                     activeUserIDs:(NSArray <NSUUID *>*)activeUserIDs
                                        isArchived:(BOOL)isArchived
                                       archivedRef:(NSDate *)archivedRef
                                        isSilenced:(BOOL)isSilenced
                                       silencedRef:(NSDate *)silencedRef
                                            teamID:(NSUUID *)teamID
{
    NSMutableArray *others = [NSMutableArray array];
    for (NSUUID *uuid in activeUserIDs) {
        NSDictionary *userInfo = @{
                                   @"id": [uuid transportString]
                                   };
        [others addObject:userInfo];
    }
    
    NSDictionary *payload = @{
                              @"name" : [NSNull null],
                              @"creator" : @"3bc5750a-b965-40f8-aff2-831e9b5ac2e9",
                              @"members" : @{
                                      @"self" : @{
                                              @"id" : @"3bc5750a-b965-40f8-aff2-831e9b5ac2e9",
                                              @"otr_archived" : @(isArchived),
                                              @"otr_archived_ref" : archivedRef ? [archivedRef transportString] : [NSNull null],
                                              @"otr_muted" : @(isSilenced),
                                              @"otr_muted_ref" : silencedRef ? [silencedRef transportString] : [NSNull null]
                                              },
                                      @"others" : others
                                      },
                              @"type" : @(conversationType),
                              @"id" : [conversation.remoteIdentifier transportString],
                              @"team": [teamID transportString] ?: [NSNull null],
                              };
    return  payload;
}

- (void)testThatItUpdatesItselfFromTransportData
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        NSUUID *uuid = NSUUID.createUUID;
        conversation.remoteIdentifier = uuid;
        NSDate *serverTimestamp = [NSDate date];
        NSDate *archivedDate = [NSDate date];
        NSDate *silencedDate = [archivedDate dateByAddingTimeInterval:10];
        
        NSDictionary *payload = [self payloadForMetaDataOfConversation:conversation conversationType:ZMConvTypeGroup isArchived:YES archivedRef:archivedDate isSilenced:YES silencedRef:silencedDate];
        
        // when
        [conversation updateWithTransportData:payload serverTimeStamp:serverTimestamp];
        
        // then
        XCTAssertEqualObjects(conversation.remoteIdentifier, [payload[@"id"] UUID]);
        XCTAssertNil(conversation.userDefinedName);
        XCTAssertEqual(conversation.conversationType, ZMConversationTypeGroup);
        XCTAssertEqualObjects(conversation.lastModifiedDate, serverTimestamp);
        XCTAssertEqualObjects(conversation.lastServerTimeStamp, serverTimestamp);
        
        XCTAssertTrue(conversation.isArchived);
        XCTAssertEqualWithAccuracy([conversation.archivedChangedTimestamp timeIntervalSince1970], [archivedDate timeIntervalSince1970], 1.0);
        XCTAssertTrue(conversation.isSilenced);
        XCTAssertEqualWithAccuracy([conversation.silencedChangedTimestamp timeIntervalSince1970], [silencedDate timeIntervalSince1970], 1.0);

        XCTAssertEqualObjects(conversation.creator.remoteIdentifier, [payload[@"creator"] UUID]);
        XCTAssertEqual(conversation.unsyncedInactiveParticipants.count, 0u);
        XCTAssertEqual(conversation.unsyncedActiveParticipants.count, 0u);
    }];
}


- (void)testThatItUpdatesItselfFromTransportDataForGroupConversation
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        NSDate *serverTimestamp = [NSDate date];
        NSUUID *uuid = NSUUID.createUUID;
        conversation.remoteIdentifier = uuid;
        
        NSUUID *user1UUID = [NSUUID createUUID];
        NSUUID *user2UUID = [NSUUID createUUID];
        
        NSDictionary *payload = [self payloadForMetaDataOfConversation:conversation activeUserIDs:@[user1UUID, user2UUID]];
        
        // when
        [conversation updateWithTransportData:payload serverTimeStamp:serverTimestamp];
        
        // then
        XCTAssertEqualObjects(conversation.remoteIdentifier, [payload[@"id"] UUID]);
        XCTAssertNil(conversation.userDefinedName);
        XCTAssertEqual(conversation.conversationType, ZMConversationTypeSelf);
        XCTAssertEqualObjects(conversation.lastModifiedDate, serverTimestamp);
        XCTAssertEqualObjects(conversation.creator.remoteIdentifier, [payload[@"creator"] UUID]);
        
        ZMUser *user1 = [ZMUser userWithRemoteID:user1UUID createIfNeeded:NO inContext:self.syncMOC];
        XCTAssertNotNil(user1);
        
        ZMUser *user2 = [ZMUser userWithRemoteID:user2UUID createIfNeeded:NO inContext:self.syncMOC];
        XCTAssertNotNil(user2);
        
        XCTAssertEqualObjects(conversation.otherActiveParticipants.set, ([NSSet setWithObjects:user1, user2, nil]) );
                        
        XCTAssertEqual(conversation.unsyncedActiveParticipants.count, 0u);
        XCTAssertEqual(conversation.unsyncedInactiveParticipants.count, 0u);
        
        XCTAssertFalse(conversation.isArchived);
        XCTAssertFalse(conversation.isSilenced);
    }];
}

- (void)testThatItSetsTheServerTimeStampAsLastModifiedAndLastServerTimeStamp
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        NSUUID *uuid = NSUUID.createUUID;
        conversation.remoteIdentifier = uuid;
        
        NSDictionary *payload = [self payloadForMetaDataOfConversation:conversation conversationType:1 isArchived:NO archivedRef:nil isSilenced:NO silencedRef:nil];

        // when
        NSDate *serverTimeStamp = [NSDate date];
        [conversation updateWithTransportData:payload serverTimeStamp:serverTimeStamp];

        // then
        XCTAssertEqualObjects(conversation.remoteIdentifier, [payload[@"id"] UUID]);
        XCTAssertNil(conversation.userDefinedName);
        XCTAssertEqual(conversation.conversationType, ZMConversationTypeSelf);
        XCTAssertEqualObjects(conversation.lastModifiedDate, serverTimeStamp);
        XCTAssertEqualObjects(conversation.creator.remoteIdentifier, [payload[@"creator"] UUID]);
    }];
}

- (void)testThatItUpdatesItselfFromTransportDataForTeamConversation
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        NSDate *serverTimestamp = [NSDate date];
        NSUUID *uuid = NSUUID.createUUID;
        conversation.remoteIdentifier = uuid;

        NSUUID *user1UUID = [NSUUID createUUID];
        NSUUID *user2UUID = [NSUUID createUUID];
        NSUUID *teamID = [NSUUID createUUID];

        NSDictionary *payload = [self payloadForMetaDataOfConversation:conversation conversationType:ZMConvTypeGroup activeUserIDs:@[user1UUID, user2UUID] isArchived:NO archivedRef:nil isSilenced:NO silencedRef:nil teamID:teamID];

        // when
        [conversation updateWithTransportData:payload serverTimeStamp:serverTimestamp];

        // then
        XCTAssertEqualObjects(conversation.remoteIdentifier, [payload[@"id"] UUID]);
        XCTAssertNil(conversation.userDefinedName);
        XCTAssertEqual(conversation.conversationType, ZMConversationTypeGroup);
        XCTAssertEqualObjects(conversation.lastModifiedDate, serverTimestamp);
        XCTAssertEqualObjects(conversation.creator.remoteIdentifier, [payload[@"creator"] UUID]);


        ZMUser *user1 = [ZMUser userWithRemoteID:user1UUID createIfNeeded:NO inContext:self.syncMOC];
        XCTAssertNotNil(user1);

        ZMUser *user2 = [ZMUser userWithRemoteID:user2UUID createIfNeeded:NO inContext:self.syncMOC];
        XCTAssertNotNil(user2);

        XCTAssertEqualObjects(conversation.otherActiveParticipants.set, ([NSSet setWithObjects:user1, user2, nil]) );
        XCTAssertNil(conversation.team);
        XCTAssertEqualObjects(conversation.teamRemoteIdentifier, teamID);

        XCTAssertEqual(conversation.unsyncedActiveParticipants.count, 0u);
        XCTAssertEqual(conversation.unsyncedInactiveParticipants.count, 0u);

        XCTAssertFalse(conversation.isArchived);
        XCTAssertFalse(conversation.isSilenced);
    }];
}

- (void)testThatItUpdatesItselfFromTransportDataForTeamConversation_ExistingTeam
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        NSDate *serverTimestamp = [NSDate date];
        NSUUID *uuid = NSUUID.createUUID;
        conversation.remoteIdentifier = uuid;

        NSUUID *user1UUID = [NSUUID createUUID];
        NSUUID *user2UUID = [NSUUID createUUID];
        Team *team = [Team fetchOrCreateTeamWithRemoteIdentifier:NSUUID.createUUID createIfNeeded:YES inContext:self.syncMOC created:nil];

        NSDictionary *payload = [self payloadForMetaDataOfConversation:conversation conversationType:ZMConvTypeGroup activeUserIDs:@[user1UUID, user2UUID] isArchived:NO archivedRef:nil isSilenced:NO silencedRef:nil teamID:team.remoteIdentifier];

        // when
        [conversation updateWithTransportData:payload serverTimeStamp:serverTimestamp];

        // then
        XCTAssertEqualObjects(conversation.remoteIdentifier, [payload[@"id"] UUID]);
        XCTAssertNil(conversation.userDefinedName);
        XCTAssertEqual(conversation.conversationType, ZMConversationTypeGroup);
        XCTAssertEqualObjects(conversation.lastModifiedDate, serverTimestamp);
        XCTAssertEqualObjects(conversation.creator.remoteIdentifier, [payload[@"creator"] UUID]);


        ZMUser *user1 = [ZMUser userWithRemoteID:user1UUID createIfNeeded:NO inContext:self.syncMOC];
        XCTAssertNotNil(user1);

        ZMUser *user2 = [ZMUser userWithRemoteID:user2UUID createIfNeeded:NO inContext:self.syncMOC];
        XCTAssertNotNil(user2);

        XCTAssertEqualObjects(conversation.otherActiveParticipants.set, ([NSSet setWithObjects:user1, user2, nil]) );
        XCTAssertNotNil(conversation.team);
        XCTAssertFalse(conversation.team.needsToBeUpdatedFromBackend);
        XCTAssertFalse(conversation.team.needsToRedownloadMembers);
        XCTAssertEqualObjects(conversation.team.remoteIdentifier, team.remoteIdentifier);

        XCTAssertEqual(conversation.unsyncedActiveParticipants.count, 0u);
        XCTAssertEqual(conversation.unsyncedInactiveParticipants.count, 0u);

        XCTAssertFalse(conversation.isArchived);
        XCTAssertFalse(conversation.isSilenced);
    }];
}

- (void)testThatItUpdatesItselfFromTransportDataWithMissingTeamInfo
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        NSDate *serverTimestamp = [NSDate date];
        NSUUID *uuid = NSUUID.createUUID;
        conversation.remoteIdentifier = uuid;

        NSUUID *user1UUID = [NSUUID createUUID];
        NSUUID *user2UUID = [NSUUID createUUID];

        NSDictionary *payload = [self payloadForMetaDataOfConversation:conversation conversationType:ZMConvTypeGroup activeUserIDs:@[user1UUID, user2UUID] isArchived:NO archivedRef:nil isSilenced:NO silencedRef:nil teamID:nil];

        // when
        [conversation updateWithTransportData:payload serverTimeStamp:serverTimestamp];

        // then
        XCTAssertEqualObjects(conversation.remoteIdentifier, [payload[@"id"] UUID]);
        XCTAssertNil(conversation.userDefinedName);
        XCTAssertEqual(conversation.conversationType, ZMConversationTypeGroup);
        XCTAssertEqualObjects(conversation.lastModifiedDate, serverTimestamp);
        XCTAssertEqualObjects(conversation.creator.remoteIdentifier, [payload[@"creator"] UUID]);

        ZMUser *user1 = [ZMUser userWithRemoteID:user1UUID createIfNeeded:NO inContext:self.syncMOC];
        XCTAssertNotNil(user1);

        ZMUser *user2 = [ZMUser userWithRemoteID:user2UUID createIfNeeded:NO inContext:self.syncMOC];
        XCTAssertNotNil(user2);

        XCTAssertEqualObjects(conversation.otherActiveParticipants.set, ([NSSet setWithObjects:user1, user2, nil]) );
        XCTAssertNil(conversation.team);
        XCTAssertEqual(conversation.unsyncedActiveParticipants.count, 0u);
        XCTAssertEqual(conversation.unsyncedInactiveParticipants.count, 0u);
        XCTAssertFalse(conversation.isArchived);
        XCTAssertFalse(conversation.isSilenced);
    }];
}

- (void)testThatUpdatingFromTransportDataDoesNotSetAnyLocalModifiedKey
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        NSUUID *uuid = NSUUID.createUUID;
        conversation.remoteIdentifier = uuid;
        conversation.archivedChangedTimestamp = [NSDate date];
        conversation.silencedChangedTimestamp = [NSDate date];

        NSUUID *user1UUID = [NSUUID createUUID];
        NSUUID *user2UUID = [NSUUID createUUID];
        NSUUID *user3UUID = [NSUUID createUUID];
        
        NSDictionary *payload = [self payloadForMetaDataOfConversation:conversation activeUserIDs:@[user1UUID, user2UUID, user3UUID]];
        // when
        [conversation updateWithTransportData:payload serverTimeStamp:nil];
        XCTAssertTrue([self.syncMOC saveOrRollback]);
        
        // then
        XCTAssertEqualObjects(conversation.keysThatHaveLocalModifications, [NSSet set]);
    }];
}

- (void)testThatItUpdatesWithoutCrashesFromTransportMissingFields
{
    
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    NSUUID *uuid = NSUUID.createUUID;
    conversation.remoteIdentifier = uuid;
    NSDictionary *payload = @{};
    
    // when
    [self performPretendingUiMocIsSyncMoc:^{
        [self performIgnoringZMLogError:^{
            [conversation updateWithTransportData:payload serverTimeStamp:nil];
        }];
    }];
    
    // then
    XCTAssertNotNil(conversation);
}

- (void)testThatItUpdatesItselfFromTransportMissingOthers
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        NSUUID *uuid = NSUUID.createUUID;
        conversation.remoteIdentifier = uuid;
        NSDictionary *payload = @{
                                  @"name" : [NSNull null],
                                  @"creator" : @"3bc5750a-b965-40f8-aff2-831e9b5ac2e9",
                                  @"members" : @{
                                          @"self" : @{
                                                  @"id" : @"3bc5750a-b965-40f8-aff2-831e9b5ac2e9"
                                                  },
                                          },
                                  @"type" : @1,
                                  @"id" : [uuid transportString]
                                  };
        
        // when
        [self performPretendingUiMocIsSyncMoc:^{
            [self performIgnoringZMLogError:^{
                [conversation updateWithTransportData:payload serverTimeStamp:nil];
            }];
        }];
        
        // then
        XCTAssertEqualObjects(conversation.remoteIdentifier, [payload[@"id"] UUID]);
    }];
}

- (void)testThatItUpdatesItselfFromTransportMissingSelf
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        NSUUID *uuid = NSUUID.createUUID;
        conversation.remoteIdentifier = uuid;
        NSDictionary *payload = @{
                                  @"name" : [NSNull null],
                                  @"creator" : @"3bc5750a-b965-40f8-aff2-831e9b5ac2e9",
                                  @"members" : @{
                                          @"others" : @[]
                                          },
                                  @"type" : @1,
                                  @"id" : [uuid UUIDString]
                                  };
        
        // when
        [self performPretendingUiMocIsSyncMoc:^{
            [self performIgnoringZMLogError:^{
                [conversation updateWithTransportData:payload serverTimeStamp:nil];
            }];
        }];
        
        // then
        XCTAssertEqualObjects(conversation.remoteIdentifier, [payload[@"id"] UUID]);
    }];
}

- (void)testThatItUpdatesItselfFromTransportInvalidFields
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        NSUUID *uuid = NSUUID.createUUID;
        conversation.remoteIdentifier = uuid;
        NSDictionary *payload = @{
                                  @"name" : @5,
                                  @"creator" : @6,
                                  @"members" : @8,
                                  @"type" : @"goo",
                                  @"id" : @100
                                  };
        
        // when
        [self performPretendingUiMocIsSyncMoc:^{
            [self performIgnoringZMLogError:^{
                [conversation updateWithTransportData:payload serverTimeStamp:nil];
            }];
        }];
        
        // then
        XCTAssertNotNil(conversation);
    }];
}

- (void)testThatItUpdatesItselfFromTransportInvalidOthersMembers
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        NSUUID *uuid = NSUUID.createUUID;
        conversation.remoteIdentifier = uuid;
        NSDictionary *payload = @{
                                  @"name" : [NSNull null],
                                  @"creator" : @"3bc5750a-b965-40f8-aff2-831e9b5ac2e9",
                                  @"members" : @{
                                          @"others" : @3
                                          },
                                  @"type" : @1,
                                  @"id" : [uuid UUIDString]
                                  };
        
        // when
        [self performPretendingUiMocIsSyncMoc:^{
            [self performIgnoringZMLogError:^{
                [conversation updateWithTransportData:payload serverTimeStamp:nil];
            }];
        }];
        
        // then
        XCTAssertNotNil(conversation);
    }];
}

@end




