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


@import WireUtilities;
@import WireTransport;

#import "ZMConnection+Internal.h"
#import "ZMUser+Internal.h"
#import "ZMConversation+Internal.h"
#import "NSManagedObjectContext+zmessaging.h"
#import <WireDataModel/WireDataModel-Swift.h>


NSString * const ZMConnectionStatusKey = @"status";

static NSString * const ToUserKey = @"to";
static NSString * const RemoteIdentifierDataKey = @"remoteIdentifier_data";
static NSString * const ExistsOnBackendKey = @"existsOnBackend";
static NSString * const LastUpdateDateInGMTKey = @"lastUpdateDateInGMT";

@interface ZMConnection (CoreDataForward)

@property (nonatomic) ZMConnectionStatus primitiveStatus;

@end


@implementation ZMConnection

+ (NSString *)entityName;
{
    return @"Connection";
}

+ (NSString *)sortKey;
{
    return LastUpdateDateInGMTKey;
}

+ (instancetype)insertNewSentConnectionToUser:(ZMUser *)user existingConversation:(ZMConversation *)conversation
{
    VerifyReturnValue(user.connection == nil, user.connection);
    RequireString(user != nil, "Can not create a connection to <nil> user.");
    ZMConnection *connection = [self insertNewObjectInManagedObjectContext:user.managedObjectContext];
    connection.to = user;
    connection.lastUpdateDate = [NSDate date];
    connection.status = ZMConnectionStatusSent;
    if (conversation == nil) {
        connection.conversation = [ZMConversation insertNewObjectInManagedObjectContext:user.managedObjectContext];
       
        [connection addWithUser:user];
        
        connection.conversation.creator = [ZMUser selfUserInContext:user.managedObjectContext];
    }
    else {
        connection.conversation = conversation;
        ///TODO: add user if not exists in participantRoles??
    }
    connection.conversation.conversationType = ZMConversationTypeConnection;
    connection.conversation.lastModifiedDate = connection.lastUpdateDate;
    return connection;
}

+ (instancetype)insertNewSentConnectionToUser:(ZMUser *)user;
{
    return [self insertNewSentConnectionToUser:user existingConversation:nil];
}

- (BOOL)hasValidConversation
{
    return (self.status != ZMConnectionStatusPending) && (self.conversation.conversationType != ZMConversationTypeInvalid);
}

- (NSDate *)lastUpdateDate;
{
    return self.lastUpdateDateInGMT;
}

- (void)setLastUpdateDate:(NSDate *)lastUpdateDate;
{
    self.lastUpdateDateInGMT = lastUpdateDate;
}

@dynamic message;
@dynamic status;
@dynamic to;

@end


@implementation ZMConnection (Internal)

@dynamic conversation;
@dynamic to;
@dynamic existsOnBackend;
@dynamic lastUpdateDateInGMT;

- (NSString *)statusAsString
{
    return [[self class] stringForStatus:self.status];
}

struct stringAndStatus {
    CFStringRef string;
    ZMConnectionStatus status;
} const statusStrings[] = {
    {CFSTR("accepted"), ZMConnectionStatusAccepted},
    {CFSTR("pending"), ZMConnectionStatusPending},
    {CFSTR("blocked"), ZMConnectionStatusBlocked},
    {CFSTR("ignored"), ZMConnectionStatusIgnored},
    {CFSTR("sent"), ZMConnectionStatusSent},
    {CFSTR("cancelled"), ZMConnectionStatusCancelled},
    {CFSTR("missing-legalhold-consent"), ZMConnectionStatusBlockedMissingLegalholdConsent},
    {NULL, ZMConnectionStatusInvalid},
};

- (void)setStatus:(ZMConnectionStatus)status;
{
    [self willChangeValueForKey:ZMConnectionStatusKey];
    NSNumber *oldStatus = [self primitiveValueForKey:ZMConnectionStatusKey];
    [self setPrimitiveValue:@(status) forKey:ZMConnectionStatusKey];
    [self didChangeValueForKey:ZMConnectionStatusKey];
    NSNumber *newStatus = [self primitiveValueForKey:ZMConnectionStatusKey];
    
    if (![oldStatus isEqual:@(ZMConnectionStatusAccepted)] &&
        [newStatus isEqual:@(ZMConnectionStatusAccepted)]) {
        self.to.needsToBeUpdatedFromBackend = YES;

        if (self.conversation.isArchived) {
            // When a connection is accepted we always want to bring it out of the archive
            self.conversation.isArchived = NO;
        }
    }

    if ([newStatus isEqual:@(ZMConnectionStatusCancelled)]) {
        self.to.connection = nil;
        self.to = nil;
    }

    if (![oldStatus isEqual:newStatus]) {
        [self invalidateTopConversationCache];
    }

    [self updateConversationType];
}

+ (ZMConnectionStatus)statusFromString:(NSString *)string
{
    for (struct stringAndStatus const *s = statusStrings; s->string != NULL; ++s) {
        if ([string isEqualToString:(__bridge NSString *) s->string]) {
            return s->status;
        }
    }
    return ZMConnectionStatusInvalid;
}

+ (NSString *)stringForStatus:(ZMConnectionStatus)status;
{
    for (struct stringAndStatus const *s = statusStrings; s->string != NULL; ++s) {
        if (s->status == status) {
            return (__bridge NSString *) s->string;
        }
    }
    return nil;
}

+ (ZMConversationType)conversationTypeForConnectionStatus:(ZMConnectionStatus)status
{
    switch (status) {
        case ZMConnectionStatusPending:
        case ZMConnectionStatusIgnored:
        case ZMConnectionStatusSent:
            return ZMConversationTypeConnection;
            break;
            
        case ZMConnectionStatusAccepted:
        case ZMConnectionStatusBlocked:
            return ZMConversationTypeOneOnOne;
            break;
            
        default:
            return ZMConversationTypeInvalid;
    }
}

- (void)updateConversationType
{
    self.conversation.conversationType = [self.class conversationTypeForConnectionStatus:self.status];
}

- (NSSet *)ignoredKeys;
{
    static NSSet *ignoredKeys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray *keys = [NSMutableArray array];
        [keys addObjectsFromArray:self.entity.attributesByName.allKeys];
        [keys addObjectsFromArray:self.entity.relationshipsByName.allKeys];
        [keys removeObject:ZMConnectionStatusKey];
        ignoredKeys = [NSSet setWithArray:keys];
    });
    return ignoredKeys;
}

+ (NSPredicate *)predicateForFilteringResults
{
    static NSPredicate *predicate;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        predicate = [NSPredicate predicateWithFormat:@"%K != %d",
                     ZMConnectionStatusKey, ZMConnectionStatusCancelled];
    });
    return predicate;
}

@end
