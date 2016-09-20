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


#import "ZMMessage+Internal.h"

@class UserClient;
@class MessageUpdateResult;

extern NSString * const DeliveredKey;

@interface ZMOTRMessage : ZMMessage

@property (nonatomic) BOOL delivered;
@property (nonatomic) NSOrderedSet *dataSet;
@property (nonatomic, readonly) NSSet *missingRecipients;
@property (nonatomic, readonly) NSString *dataSetDebugInformation;

- (void)missesRecipient:(UserClient *)recipient;
- (void)missesRecipients:(NSSet<UserClient *> *)recipients;
- (void)doesNotMissRecipient:(UserClient *)recipient;
- (void)doesNotMissRecipients:(NSSet<UserClient *> *)recipients;

- (void)updateWithGenericMessage:(ZMGenericMessage *)message updateEvent:(ZMUpdateEvent *)updateEvent;

+ (ZMMessage *)preExistingPlainMessageForGenericMessage:(ZMGenericMessage *)message
                                         inConversation:(ZMConversation *)conversation
                                 inManagedObjectContext:(NSManagedObjectContext *)moc
                                         prefetchResult:(ZMFetchRequestBatchResult *)prefetchResult;

+ (MessageUpdateResult *)messageUpdateResultFromUpdateEvent:(ZMUpdateEvent *)updateEvent
                                     inManagedObjectContext:(NSManagedObjectContext *)moc
                                             prefetchResult:(ZMFetchRequestBatchResult *)prefetchResult;

+ (instancetype)createOrUpdateMessageFromUpdateEvent:(ZMUpdateEvent *)updateEvent
                              inManagedObjectContext:(NSManagedObjectContext *)moc
                                      prefetchResult:(ZMFetchRequestBatchResult *)prefetchResult NS_UNAVAILABLE;

@end
