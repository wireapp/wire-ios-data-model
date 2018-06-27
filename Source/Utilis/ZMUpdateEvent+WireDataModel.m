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

@import WireProtos;

#import "ZMUpdateEvent+WireDataModel.h"
#import "ZMConversation+Internal.h"
#import "ZMMessage+Internal.h"
#import "ZMUser+Internal.h"
#import "ZMGenericMessage+UpdateEvent.h"

@implementation ZMUpdateEvent (WireDataModel)

- (NSDate *)timeStamp
{
    if (self.isTransient || self.type == ZMUpdateEventTypeUserConnection) {
        return nil;
    }
    return [self.payload dateForKey:@"time"];
}

- (NSUUID *)senderUUID
{
    if (self.type == ZMUpdateEventTypeUserConnection) {
        return [[self.payload optionalDictionaryForKey:@"connection"] optionalUuidForKey:@"to"];
    }
    
    if (self.type == ZMUpdateEventTypeUserContactJoin) {
        return [[self.payload optionalDictionaryForKey:@"user"] optionalUuidForKey:@"id"];
    }

    return [self.payload optionalUuidForKey:@"from"];
}

- (NSUUID *)conversationUUID;
{
    if (self.type == ZMUpdateEventTypeUserConnection) {
        return  [[self.payload optionalDictionaryForKey:@"connection"] optionalUuidForKey:@"conversation"];
    }
    return [self.payload optionalUuidForKey:@"conversation"];
}

- (NSString *)senderClientID
{
    if (self.type == ZMUpdateEventTypeConversationOtrMessageAdd || self.type == ZMUpdateEventTypeConversationOtrAssetAdd) {
        return [[self.payload optionalDictionaryForKey:@"data"] optionalStringForKey:@"sender"];
    }
    return nil;
}

- (NSString *)recipientClientID
{
    if (self.type == ZMUpdateEventTypeConversationOtrMessageAdd || self.type == ZMUpdateEventTypeConversationOtrAssetAdd) {
        return [[self.payload optionalDictionaryForKey:@"data"] optionalStringForKey:@"recipient"];
    }
    return nil;
}

- (NSUUID *)messageNonce;
{
    switch (self.type) {
        case ZMUpdateEventTypeConversationMessageAdd:
        case ZMUpdateEventTypeConversationAssetAdd:
        case ZMUpdateEventTypeConversationKnock:
            return [[self.payload optionalDictionaryForKey:@"data"] optionalUuidForKey:@"nonce"];
            
        case ZMUpdateEventTypeConversationClientMessageAdd:
        case ZMUpdateEventTypeConversationOtrMessageAdd:
        case ZMUpdateEventTypeConversationOtrAssetAdd:
        {
            ZMGenericMessage *message = [ZMGenericMessage genericMessageFromUpdateEvent:self];
            return [NSUUID uuidWithTransportString:message.messageId];
        }
        default:
            return nil;
            break;
    }
}

- (NSMutableSet *)usersFromUserIDsInManagedObjectContext:(NSManagedObjectContext *)context createIfNeeded:(BOOL)createIfNeeded;
{
    NSMutableSet *users = [NSMutableSet set];
    for (NSString *uuidString in [[self.payload optionalDictionaryForKey:@"data"] optionalArrayForKey:@"user_ids"] ) {
        VerifyAction([uuidString isKindOfClass:[NSString class]], return [NSMutableSet set]);
        NSUUID *uuid = uuidString.UUID;
        VerifyAction(uuid != nil, return [NSMutableSet set]);
        ZMUser *user = [ZMUser userWithRemoteID:uuid createIfNeeded:createIfNeeded inContext:context];
        if (user != nil) {
            [users addObject:user];
        }
    }
    return users;
}

@end


