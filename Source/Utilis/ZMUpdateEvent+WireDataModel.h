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


@import WireTransport;

@class ZMConversation;
@class NSManagedObjectContext;

@interface ZMUpdateEvent (WireDataModel)

- (BOOL)canUnarchiveConversation:(nonnull ZMConversation *)conversation;

/// May be nil (e.g. for call state events)
- (nullable NSDate *)timeStamp;
- (nullable NSUUID *)senderUUID;
- (nullable NSUUID *)conversationUUID;
- (nullable NSUUID *)messageNonce;
- (nullable NSString *)senderClientID;
- (nullable NSString *)recipientClientID;

- (nonnull NSMutableSet *)usersFromUserIDsInManagedObjectContext:(nonnull NSManagedObjectContext *)context createIfNeeded:(BOOL)createIfNeeded;

@end


typedef NS_ENUM(NSUInteger, ZMCallEventType) {
    ZMCallEventTypeNone,
    ZMCallEventTypeCallEnded,
    ZMCallEventTypeIncomingCall,
    ZMCallEventTypeIncomingVideoCall,
    ZMCallEventTypeSelfUserJoined,
    ZMCallEventTypeUndefined
};

@interface ZMUpdateEvent (Calling)

- (ZMCallEventType)callEventTypeOnManagedObjectContext:(nonnull NSManagedObjectContext *)context;

@end

