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


@import Foundation;
@import WireImages;
@import WireUtilities;
@import WireTransport;
@import WireCryptobox;
@import MobileCoreServices;
@import WireImages;

#import "ZMManagedObject+Internal.h"
#import "ZMManagedObjectContextProvider.h"
#import "ZMConversation+Internal.h"
#import "ZMConversation+UnreadCount.h"

#import "ZMUser+Internal.h"

#import "ZMMessage+Internal.h"
#import "ZMClientMessage.h"

#import "NSManagedObjectContext+zmessaging.h"
#import "ZMConnection+Internal.h"

#import "ZMConversationList+Internal.h"

#import "ZMConversationListDirectory.h"
#import <WireDataModel/WireDataModel-Swift.h>
#import "NSPredicate+ZMSearch.h"

static NSString* ZMLogTag ZM_UNUSED = @"Conversations";

NSString *const ZMConversationConnectionKey = @"connection";
NSString *const ZMConversationHasUnreadMissedCallKey = @"hasUnreadMissedCall";
NSString *const ZMConversationHasUnreadUnsentMessageKey = @"hasUnreadUnsentMessage";
NSString *const ZMConversationIsArchivedKey = @"internalIsArchived";
NSString *const ZMConversationIsSelfAnActiveMemberKey = @"isSelfAnActiveMember";
NSString *const ZMConversationMutedStatusKey = @"mutedStatus";
NSString *const ZMConversationAllMessagesKey = @"allMessages";
NSString *const ZMConversationHiddenMessagesKey = @"hiddenMessages";
NSString *const ZMConversationLastServerSyncedActiveParticipantsKey = @"lastServerSyncedActiveParticipants";
NSString *const ZMConversationHasUnreadKnock = @"hasUnreadKnock";
NSString *const ZMConversationUserDefinedNameKey = @"userDefinedName";
NSString *const ZMIsDimmedKey = @"zmIsDimmed";
NSString *const ZMNormalizedUserDefinedNameKey = @"normalizedUserDefinedName";
NSString *const ZMConversationListIndicatorKey = @"conversationListIndicator";
NSString *const ZMConversationConversationTypeKey = @"conversationType";
NSString *const ZMConversationLastServerTimeStampKey = @"lastServerTimeStamp";
NSString *const ZMConversationLastReadServerTimeStampKey = @"lastReadServerTimeStamp";
NSString *const ZMConversationClearedTimeStampKey = @"clearedTimeStamp";
NSString *const ZMConversationArchivedChangedTimeStampKey = @"archivedChangedTimestamp";
NSString *const ZMConversationSilencedChangedTimeStampKey = @"silencedChangedTimestamp";

NSString *const ZMNotificationConversationKey = @"ZMNotificationConversationKey";

NSString *const ZMConversationEstimatedUnreadCountKey = @"estimatedUnreadCount";
NSString *const ZMConversationRemoteIdentifierDataKey = @"remoteIdentifier_data";

NSString *const SecurityLevelKey = @"securityLevel";

static NSString *const ConnectedUserKey = @"connectedUser";
static NSString *const CreatorKey = @"creator";
static NSString *const DraftMessageDataKey = @"draftMessageData";
static NSString *const IsPendingConnectionConversationKey = @"isPendingConnectionConversation";
static NSString *const LastModifiedDateKey = @"lastModifiedDate";
static NSString *const LastReadMessageKey = @"lastReadMessage";
static NSString *const lastEditableMessageKey = @"lastEditableMessage";
static NSString *const NeedsToBeUpdatedFromBackendKey = @"needsToBeUpdatedFromBackend";
static NSString *const RemoteIdentifierKey = @"remoteIdentifier";
static NSString *const TeamRemoteIdentifierKey = @"teamRemoteIdentifier";
NSString *const TeamRemoteIdentifierDataKey = @"teamRemoteIdentifier_data";
static NSString *const VoiceChannelKey = @"voiceChannel";
static NSString *const VoiceChannelStateKey = @"voiceChannelState";

static NSString *const LocalMessageDestructionTimeoutKey = @"localMessageDestructionTimeout";
static NSString *const SyncedMessageDestructionTimeoutKey = @"syncedMessageDestructionTimeout";
static NSString *const HasReadReceiptsEnabledKey = @"hasReadReceiptsEnabled";

static NSString *const LanguageKey = @"language";

static NSString *const DownloadedMessageIDsDataKey = @"downloadedMessageIDs_data";
static NSString *const LastEventIDDataKey = @"lastEventID_data";
static NSString *const ClearedEventIDDataKey = @"clearedEventID_data";
static NSString *const ArchivedEventIDDataKey = @"archivedEventID_data";
static NSString *const LastReadEventIDDataKey = @"lastReadEventID_data";

static NSString *const TeamKey = @"team";

static NSString *const AccessModeStringsKey = @"accessModeStrings";
static NSString *const AccessRoleStringKey = @"accessRoleString";

NSTimeInterval ZMConversationDefaultLastReadTimestampSaveDelay = 3.0;

const NSUInteger ZMConversationMaxEncodedTextMessageLength = 1500;
const NSUInteger ZMConversationMaxTextMessageLength = ZMConversationMaxEncodedTextMessageLength - 50; // Empirically we verified that the encoding adds 44 bytes

@interface ZMConversation ()

@property (nonatomic) NSString *normalizedUserDefinedName;
@property (nonatomic) ZMConversationType conversationType;
@property (nonatomic, readonly) ZMConversationType internalConversationType;

@property (nonatomic) NSTimeInterval lastReadTimestampSaveDelay;
@property (nonatomic) int64_t lastReadTimestampUpdateCounter;
@property (nonatomic) BOOL internalIsArchived;

@property (nonatomic) NSDate *pendingLastReadServerTimestamp;
@property (nonatomic) NSDate *lastReadServerTimeStamp;
@property (nonatomic) NSDate *lastServerTimeStamp;
@property (nonatomic) NSDate *clearedTimeStamp;
@property (nonatomic) NSDate *archivedChangedTimestamp;
@property (nonatomic) NSDate *silencedChangedTimestamp;

@property (nonatomic) id _recentMessagesFetcher;

@end

/// Declaration of properties implemented (automatically) by Core Data
@interface ZMConversation (CoreDataForward)

@property (nonatomic) NSDate *primitiveLastReadServerTimeStamp;
@property (nonatomic) NSDate *primitiveLastServerTimeStamp;
@property (nonatomic) NSUUID *primitiveRemoteIdentifier;
@property (nonatomic) NSNumber *primitiveConversationType;
@property (nonatomic) NSData *remoteIdentifier_data;

@property (nonatomic) ZMConversationSecurityLevel securityLevel;
@end


@implementation ZMConversation

@dynamic userDefinedName;
@dynamic allMessages;
@dynamic lastModifiedDate;
@dynamic creator;
@dynamic normalizedUserDefinedName;
@dynamic conversationType;
@dynamic clearedTimeStamp;
@dynamic lastReadServerTimeStamp;
@dynamic lastServerTimeStamp;
@dynamic internalIsArchived;
@dynamic archivedChangedTimestamp;
@dynamic silencedChangedTimestamp;
@dynamic team;

@synthesize pendingLastReadServerTimestamp;
@synthesize lastReadTimestampSaveDelay;
@synthesize lastReadTimestampUpdateCounter;
@synthesize _recentMessagesFetcher;

- (BOOL)isArchived
{
    return self.internalIsArchived;
}

- (void)setIsArchived:(BOOL)isArchived
{
    self.internalIsArchived = isArchived;
    
    if (self.lastServerTimeStamp != nil) {
        [self updateArchived:self.lastServerTimeStamp synchronize:YES];
    }
}

- (NSUInteger)estimatedUnreadCount
{
    return (unsigned long)self.internalEstimatedUnreadCount;
}

- (NSUInteger)estimatedUnreadSelfMentionCount
{
    return (unsigned long)self.internalEstimatedUnreadSelfMentionCount;
}

- (NSUInteger)estimatedUnreadSelfReplyCount
{
    return (unsigned long)self.internalEstimatedUnreadSelfReplyCount;
}

+ (NSSet *)keyPathsForValuesAffectingEstimatedUnreadCount
{
    return [NSSet setWithObjects: ZMConversationInternalEstimatedUnreadCountKey, ZMConversationLastReadServerTimeStampKey, nil];
}

+ (NSFetchRequest *)sortedFetchRequest
{
    NSFetchRequest *request = [super sortedFetchRequest];

    if(request.predicate) {
        request.predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[request.predicate, self.predicateForFilteringResults]];
    }
    else {
        request.predicate = self.predicateForFilteringResults;
    }
    return request;
}

+ (NSPredicate *)predicateForObjectsThatNeedToBeInsertedUpstream;
{
    NSPredicate *superPredicate = [super predicateForObjectsThatNeedToBeInsertedUpstream];
    NSPredicate *onlyGoupPredicate = [NSPredicate predicateWithFormat:@"%K == %@", ZMConversationConversationTypeKey, @(ZMConversationTypeGroup)];
    return [NSCompoundPredicate andPredicateWithSubpredicates:@[superPredicate, onlyGoupPredicate]];
}

+ (NSPredicate *)predicateForObjectsThatNeedToBeUpdatedUpstream;
{
    NSPredicate *superPredicate = [super predicateForObjectsThatNeedToBeUpdatedUpstream];
    NSPredicate *onlyGoupPredicate = [NSPredicate predicateWithFormat:@"(%K != NULL) AND (%K != %@) AND (%K == 0)",
                                      [self remoteIdentifierDataKey],
                                      ZMConversationConversationTypeKey, @(ZMConversationTypeInvalid),
                                      NeedsToBeUpdatedFromBackendKey];
    return [NSCompoundPredicate andPredicateWithSubpredicates:@[superPredicate, onlyGoupPredicate]];
}

- (void)awakeFromFetch;
{
    [super awakeFromFetch];
    self.lastReadTimestampSaveDelay = ZMConversationDefaultLastReadTimestampSaveDelay;
    if (self.managedObjectContext.zm_isSyncContext) {
        // From the documentation: The managed object context’s change processing is explicitly disabled around this method so that you can use public setters to establish transient values and other caches without dirtying the object or its context.
        // Therefore we need to do a dispatch async  here in a performGroupedBlock to update the unread properties outside of awakeFromFetch
        ZM_WEAK(self);
        [self.managedObjectContext performGroupedBlock:^{
            ZM_STRONG(self);
            [self calculateLastUnreadMessages];
        }];
    }
}

- (void)awakeFromInsert;
{
    [super awakeFromInsert];
    self.lastReadTimestampSaveDelay = ZMConversationDefaultLastReadTimestampSaveDelay;
    if (self.managedObjectContext.zm_isSyncContext) {
        // From the documentation: You are typically discouraged from performing fetches within an implementation of awakeFromInsert. Although it is allowed, execution of the fetch request can trigger the sending of internal Core Data notifications which may have unwanted side-effects. Since we fetch the unread messages here, we should do a dispatch async
        [self.managedObjectContext performGroupedBlock:^{
            [self calculateLastUnreadMessages];
        }];
    }
}

- (void)willTurnIntoFault
{
    [super willTurnIntoFault];
    self._recentMessagesFetcher = nil;
}



-(NSSet <ZMUser *> *)activeParticipants
{
    
    NSMutableSet *activeParticipants = [NSMutableSet set];
    
    if (self.internalConversationType != ZMConversationTypeGroup) {
        [activeParticipants addObject:[ZMUser selfUserInContext:self.managedObjectContext]];
        if (self.connectedUser != nil) {
            [activeParticipants addObject:self.connectedUser];
        }
    }
    else if(self.isSelfAnActiveMember) {
        [activeParticipants addObject:[ZMUser selfUserInContext:self.managedObjectContext]];
        [activeParticipants unionSet:[self.lastServerSyncedActiveParticipants set]];
    }
    else
    {
        [activeParticipants unionSet:[self.lastServerSyncedActiveParticipants set]];
    }
    
    return activeParticipants;
}

-(NSArray <ZMUser *> *)sortedActiveParticipants
{
    return [self sortedUsers:[self activeParticipants]];
}

- (NSArray *)sortedUsers:(NSSet *)users
{
    NSSortDescriptor *nameDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"normalizedName" ascending:YES];
    NSArray *sortedUser = [users sortedArrayUsingDescriptors:@[nameDescriptor]];
    
    return sortedUser;
}

+ (NSSet *)keyPathsForValuesAffectingActiveParticipants
{
    return [NSSet setWithObjects:ZMConversationLastServerSyncedActiveParticipantsKey, ZMConversationIsSelfAnActiveMemberKey, nil];
}

- (ZMUser *)connectedUser
{
    ZMConversationType internalConversationType = self.internalConversationType;
    
    if (internalConversationType == ZMConversationTypeOneOnOne || internalConversationType == ZMConversationTypeConnection) {
        return self.connection.to;
    }
    else if (self.conversationType == ZMConversationTypeOneOnOne) {
        return self.lastServerSyncedActiveParticipants.firstObject;
    }
    
    return nil;
}

+ (NSSet *)keyPathsForValuesAffectingConnectedUser
{
    return [NSSet setWithObject:ZMConversationConversationTypeKey];
}


- (ZMConnectionStatus)relatedConnectionState
{
    if(self.connection != nil) {
        return self.connection.status;
    }
    return ZMConnectionStatusInvalid;
}

+ (NSSet *)keyPathsForValuesAffectingRelatedConnectionState
{
    return [NSSet setWithObject:@"connection.status"];
}

- (NSSet *)ignoredKeys;
{
    static NSSet *ignoredKeys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSSet *keys = [super ignoredKeys];
        NSString * const KeysIgnoredForTrackingModifications[] = {
            ZMConversationConnectionKey,
            ZMConversationConversationTypeKey,
            CreatorKey,
            DraftMessageDataKey,
            LastModifiedDateKey,
            ZMNormalizedUserDefinedNameKey,
            ZMConversationLastServerSyncedActiveParticipantsKey,
            VoiceChannelKey,
            ZMConversationHasUnreadMissedCallKey,
            ZMConversationHasUnreadUnsentMessageKey,
            ZMConversationAllMessagesKey,
            ZMConversationHiddenMessagesKey,
            ZMConversationLastServerTimeStampKey,
            SecurityLevelKey,
            ZMConversationLastUnreadKnockDateKey,
            ZMConversationLastUnreadMissedCallDateKey,
            ZMConversationLastReadLocalTimestampKey,
            ZMConversationInternalEstimatedUnreadCountKey,
            ZMConversationInternalEstimatedUnreadSelfMentionCountKey,
            ZMConversationInternalEstimatedUnreadSelfReplyCountKey,
            ZMConversationIsArchivedKey,
            ZMConversationMutedStatusKey,
            LocalMessageDestructionTimeoutKey,
            SyncedMessageDestructionTimeoutKey,
            DownloadedMessageIDsDataKey,
            LastEventIDDataKey,
            ClearedEventIDDataKey,
            ArchivedEventIDDataKey,
            LastReadEventIDDataKey,
            TeamKey,
            TeamRemoteIdentifierKey,
            TeamRemoteIdentifierDataKey,
            AccessModeStringsKey,
            AccessRoleStringKey,
            LanguageKey,
            HasReadReceiptsEnabledKey,
        };
        
        NSSet *additionalKeys = [NSSet setWithObjects:KeysIgnoredForTrackingModifications count:(sizeof(KeysIgnoredForTrackingModifications) / sizeof(*KeysIgnoredForTrackingModifications))];
        ignoredKeys = [keys setByAddingObjectsFromSet:additionalKeys];
    });
    return ignoredKeys;
}

- (BOOL)isReadOnly
{
    return
    (self.conversationType == ZMConversationTypeInvalid) ||
    (self.conversationType == ZMConversationTypeSelf) ||
    (self.conversationType == ZMConversationTypeConnection) ||
    (self.conversationType == ZMConversationTypeGroup && !self.isSelfAnActiveMember);
}

+ (NSSet *)keyPathsForValuesAffectingIsReadOnly;
{
    return [NSSet setWithObjects:ZMConversationConversationTypeKey, ZMConversationIsSelfAnActiveMemberKey, nil];
}

+ (NSSet *)keyPathsForValuesAffectingDisplayName;
{
    return [NSSet setWithObjects:ZMConversationConversationTypeKey, ZMConversationLastServerSyncedActiveParticipantsKey, @"lastServerSyncedActiveParticipants.name", @"connection.to.name", @"connection.to.availability", ZMConversationUserDefinedNameKey, nil];
}

+ (nonnull instancetype)insertGroupConversationIntoUserSession:(nonnull id<ZMManagedObjectContextProvider> )session
                                              withParticipants:(nonnull NSArray<ZMUser *> *)participants
                                                        inTeam:(nullable Team *)team;
{

    return [self insertGroupConversationIntoUserSession:session withParticipants:participants name:nil inTeam:team];
}

+ (nonnull instancetype)insertGroupConversationIntoUserSession:(nonnull id<ZMManagedObjectContextProvider> )session
                                              withParticipants:(nonnull NSArray<ZMUser *> *)participants
                                                          name:(nullable NSString*)name
                                                        inTeam:(nullable Team *)team
{
    return [self insertGroupConversationIntoUserSession:session
                                       withParticipants:participants
                                                   name:name
                                                 inTeam:team
                                            allowGuests:YES];
}

+ (nonnull instancetype)insertGroupConversationIntoUserSession:(nonnull id<ZMManagedObjectContextProvider> )session
                                              withParticipants:(nonnull NSArray<ZMUser *> *)participants
                                                          name:(nullable NSString*)name
                                                        inTeam:(nullable Team *)team
                                                   allowGuests:(BOOL)allowGuests
{
    return [self insertGroupConversationIntoUserSession:session
                                       withParticipants:participants
                                                   name:name
                                                 inTeam:team
                                            allowGuests:allowGuests
                                           readReceipts:NO];
}


+ (nonnull instancetype)insertGroupConversationIntoUserSession:(nonnull id<ZMManagedObjectContextProvider> )session
                                              withParticipants:(nonnull NSArray<ZMUser *> *)participants
                                                          name:(nullable NSString*)name
                                                        inTeam:(nullable Team *)team
                                                   allowGuests:(BOOL)allowGuests
                                                  readReceipts:(BOOL)readReceipts
{
    VerifyReturnNil(session != nil);
    return [self insertGroupConversationIntoManagedObjectContext:session.managedObjectContext
                                                withParticipants:participants
                                                            name:name
                                                          inTeam:team
                                                     allowGuests:allowGuests
                                                    readReceipts:readReceipts];
}

+ (instancetype)existingOneOnOneConversationWithUser:(ZMUser *)otherUser inUserSession:(id<ZMManagedObjectContextProvider>)session;
{
    NOT_USED(session);
    return otherUser.connection.conversation;
}

- (void)setClearedTimeStamp:(NSDate *)clearedTimeStamp
{
    [self willChangeValueForKey:ZMConversationClearedTimeStampKey];
    [self setPrimitiveValue:clearedTimeStamp forKey:ZMConversationClearedTimeStampKey];
    [self didChangeValueForKey:ZMConversationClearedTimeStampKey];
    if (self.managedObjectContext.zm_isSyncContext) {
        [self deleteOlderMessages];
    }
}

- (void)setLastReadServerTimeStamp:(NSDate *)lastReadServerTimeStamp
{
    [self willChangeValueForKey:ZMConversationLastReadServerTimeStampKey];
    [self setPrimitiveValue:lastReadServerTimeStamp forKey:ZMConversationLastReadServerTimeStampKey];
    [self didChangeValueForKey:ZMConversationLastReadServerTimeStampKey];
    
    if (self.managedObjectContext.zm_isSyncContext) {
        [self calculateLastUnreadMessages];
    }
}

- (NSUUID *)remoteIdentifier;
{
    return [self transientUUIDForKey:RemoteIdentifierKey];
}

- (void)setRemoteIdentifier:(NSUUID *)remoteIdentifier;
{
    [self setTransientUUID:remoteIdentifier forKey:RemoteIdentifierKey];
}

- (NSUUID *)teamRemoteIdentifier;
{
    return [self transientUUIDForKey:TeamRemoteIdentifierKey];
}

- (void)setTeamRemoteIdentifier:(NSUUID *)teamRemoteIdentifier;
{
    [self setTransientUUID:teamRemoteIdentifier forKey:TeamRemoteIdentifierKey];
}


+ (NSSet *)keyPathsForValuesAffectingRemoteIdentifier
{
    return [NSSet setWithObject:ZMConversationRemoteIdentifierDataKey];
}

- (void)setUserDefinedName:(NSString *)aName {
    
    [self willChangeValueForKey:ZMConversationUserDefinedNameKey];
    [self setPrimitiveValue:[[aName copy] stringByRemovingExtremeCombiningCharacters] forKey:ZMConversationUserDefinedNameKey];
    [self didChangeValueForKey:ZMConversationUserDefinedNameKey];
    
    self.normalizedUserDefinedName = [self.userDefinedName normalizedString];
}

- (ZMConversationType)conversationType
{
    ZMConversationType conversationType = [self internalConversationType];
    
    // Exception: the group conversation is considered a 1-1 if:
    // 1. Belongs to the team.
    // 2. Has no name given.
    // 3. Conversation has only one other participant.
    // 4. This participant is not a service user (bot).
    if (conversationType == ZMConversationTypeGroup &&
        self.teamRemoteIdentifier != nil &&
        self.lastServerSyncedActiveParticipants.count == 1 &&
        !self.lastServerSyncedActiveParticipants.firstObject.isServiceUser &&
        self.userDefinedName.length == 0) {
        conversationType = ZMConversationTypeOneOnOne;
    }
    
    return conversationType;
}

- (ZMConversationType)internalConversationType
{
    [self willAccessValueForKey:ZMConversationConversationTypeKey];
    ZMConversationType conversationType =  (ZMConversationType)[[self primitiveConversationType] shortValue];
    [self didAccessValueForKey:ZMConversationConversationTypeKey];
    return conversationType;
}


+ (NSArray *)defaultSortDescriptors
{
    return @[[NSSortDescriptor sortDescriptorWithKey:ZMConversationIsArchivedKey ascending:YES],
             [NSSortDescriptor sortDescriptorWithKey:LastModifiedDateKey ascending:NO],
             [NSSortDescriptor sortDescriptorWithKey:ZMConversationRemoteIdentifierDataKey ascending:YES],];
}

- (BOOL)isPendingConnectionConversation;
{
    return self.connection != nil && self.connection.status == ZMConnectionStatusPending;
}

+ (NSSet *)keyPathsForValuesAffectingIsPendingConnectionConversation
{
    return [NSSet setWithObjects:ZMConversationConnectionKey, @"connection.status", nil];
}

- (ZMConversationListIndicator)conversationListIndicator;
{
    if (self.connectedUser.isPendingApprovalByOtherUser) {
        return ZMConversationListIndicatorPending;
    }
    else if (self.isCallDeviceActive) {
        return ZMConversationListIndicatorActiveCall;
    }
    else if (self.isIgnoringCall) {
        return ZMConversationListIndicatorInactiveCall;        
    }
    
    return [self unreadListIndicator];
}

+ (NSSet *)keyPathsForValuesAffectingConversationListIndicator
{
    return [[ZMConversation keyPathsForValuesAffectingUnreadListIndicator] union:[NSSet setWithObject: @"voiceChannelState"]];
}


- (BOOL)hasDraftMessage
{
    return (0 < self.draftMessage.text.length);
}

+ (NSSet *)keyPathsForValuesAffectingHasDraftMessage
{
    return [NSSet setWithObject:DraftMessageDataKey];
}

- (ZMMessage *)lastEditableMessage;
{
    __block ZMMessage *result;
    [self.recentMessages enumerateObjectsWithOptions:NSEnumerationReverse
                                    usingBlock:^(ZMMessage *message, NSUInteger ZM_UNUSED idx, BOOL *stop) {
                                            if ([message isEditableMessage]) {
                                                result = message;
                                                *stop = YES;
                                            }
                                    }];
    return result;
}

+ (NSSet *)keyPathsForValuesAffectingFirstUnreadMessage
{
    return [NSSet setWithObjects:ZMConversationAllMessagesKey, ZMConversationLastReadServerTimeStampKey, nil];
}

- (NSSet<NSString *> *)filterUpdatedLocallyModifiedKeys:(NSSet<NSString *> *)updatedKeys
{
    NSMutableSet *newKeys = [super filterUpdatedLocallyModifiedKeys:updatedKeys].mutableCopy;
    
    // Don't sync the conversation name if it was set before inserting the conversation
    // as it will already get synced when inserting the conversation on the backend.
    if (self.isInserted && nil != self.userDefinedName && [newKeys containsObject:ZMConversationUserDefinedNameKey]) {
        [newKeys removeObject:ZMConversationUserDefinedNameKey];
    }
    
    return newKeys;
}

- (NSMutableOrderedSet *)mutableLastServerSyncedActiveParticipants
{
    return [self mutableOrderedSetValueForKey:ZMConversationLastServerSyncedActiveParticipantsKey];
}

- (BOOL)canMarkAsUnread
{
    if (self.recentMessages.count == 0) {
        return NO;
    }
    
    if (self.estimatedUnreadCount > 0) {
        return NO;
    }
    
    if (nil == [self lastMessageCanBeMarkedUnread]) {
        return NO;
    }
    
    return YES;
}

- (ZMMessage *)lastMessageCanBeMarkedUnread
{
    NSUInteger lastMessageIndexCanBeMarkedUnread = [self.recentMessages indexOfObjectWithOptions:NSEnumerationReverse
                                                                                     passingTest:^BOOL(ZMMessage *message, NSUInteger idx, BOOL *stop) {
        NOT_USED(idx);
        NOT_USED(stop);
        return message.canBeMarkedUnread;
    }];
    
    if (lastMessageIndexCanBeMarkedUnread != NSNotFound) {
        return self.recentMessages[self.recentMessages.count - lastMessageIndexCanBeMarkedUnread - 1];
    }
    else {
        return nil;
    }
}

- (void)markAsUnread
{
    ZMMessage *lastMessageCanBeMarkedUnread = [self lastMessageCanBeMarkedUnread];
    
    if (lastMessageCanBeMarkedUnread == nil) {
        ZMLogError(@"Cannot mark as read: no message to mark in %@", self);
        return;
    }
    
    [lastMessageCanBeMarkedUnread markAsUnread];
}

@end



@implementation ZMConversation (Internal)

@dynamic connection;
@dynamic creator;
@dynamic lastModifiedDate;
@dynamic normalizedUserDefinedName;
@dynamic hiddenMessages;

+ (NSSet *)keyPathsForValuesAffectingIsArchived
{
    return [NSSet setWithObject:ZMConversationIsArchivedKey];
}

+ (NSString *)entityName;
{
    return @"Conversation";
}

- (NSMutableSet<ZMMessage *> *)mutableMessages;
{
    return [self mutableSetValueForKey:ZMConversationAllMessagesKey];
}

+ (ZMConversationList *)conversationsIncludingArchivedInContext:(NSManagedObjectContext *)moc;
{
    return moc.conversationListDirectory.conversationsIncludingArchived;
}

+ (ZMConversationList *)archivedConversationsInContext:(NSManagedObjectContext *)moc;
{
    return moc.conversationListDirectory.archivedConversations;
}

+ (ZMConversationList *)clearedConversationsInContext:(NSManagedObjectContext *)moc;
{
    return moc.conversationListDirectory.clearedConversations;
}

+ (ZMConversationList *)conversationsExcludingArchivedInContext:(NSManagedObjectContext *)moc;
{
    return moc.conversationListDirectory.unarchivedConversations;
}

+ (ZMConversationList *)pendingConversationsInContext:(NSManagedObjectContext *)moc;
{
    return moc.conversationListDirectory.pendingConnectionConversations;
}

- (void)mergeWithExistingConversationWithRemoteID:(NSUUID *)remoteID;
{
    ZMConversation *existingConversation = [ZMConversation conversationWithRemoteID:remoteID createIfNeeded:NO inContext:self.managedObjectContext];
    if ((existingConversation != nil) && ![existingConversation isEqual:self]) {
        Require(self.remoteIdentifier == nil);
        [self.mutableMessages unionSet:existingConversation.allMessages];
        // Just to be on the safe side, force update:
        self.needsToBeUpdatedFromBackend = YES;
        // This is a duplicate. Delete the other one
        [self.managedObjectContext deleteObject:existingConversation];
    }
    self.remoteIdentifier = remoteID;
}

+ (instancetype)conversationWithRemoteID:(NSUUID *)UUID createIfNeeded:(BOOL)create inContext:(NSManagedObjectContext *)moc
{
    return [self conversationWithRemoteID:UUID createIfNeeded:create inContext:moc created:NULL];
}

+ (instancetype)conversationWithRemoteID:(NSUUID *)UUID createIfNeeded:(BOOL)create inContext:(NSManagedObjectContext *)moc created:(BOOL *)created
{
    VerifyReturnNil(UUID != nil);
    
    // We must only ever call this on the sync context. Otherwise, there's a race condition
    // where the UI and sync contexts could both insert the same conversation (same UUID) and we'd end up
    // having two duplicates of that conversation, and we'd have a really hard time recovering from that.
    //
    RequireString(! create || moc.zm_isSyncContext, "Race condition!");
    
    ZMConversation *result = [self fetchObjectWithRemoteIdentifier:UUID inManagedObjectContext:moc];
    
    if (result != nil) {
        if (nil != created) {
            *created = NO;
        }
        return result;
    } else if (create) {
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:moc];
        conversation.remoteIdentifier = UUID;
        conversation.lastModifiedDate = [NSDate dateWithTimeIntervalSince1970:0];
        conversation.lastServerTimeStamp = [NSDate dateWithTimeIntervalSince1970:0];
        if (nil != created) {
            *created = YES;
        }
        return conversation;
    }
    return nil;
}

+ (instancetype)fetchOrCreateTeamConversationInManagedObjectContext:(NSManagedObjectContext *)moc withParticipant:(ZMUser *)participant team:(Team *)team
{
    VerifyReturnNil(team != nil);
    VerifyReturnNil(!participant.isSelfUser);
    ZMUser *selfUser = [ZMUser selfUserInContext:moc];
    VerifyReturnNil(selfUser.canCreateConversation);

    ZMConversation *conversation = [self existingTeamConversationInManagedObjectContext:moc withParticipant:participant team:team];
    if (nil != conversation) {
        return conversation;
    }

    conversation = (ZMConversation *)[super insertNewObjectInManagedObjectContext:moc];
    conversation.lastModifiedDate = [NSDate date];
    conversation.conversationType = ZMConversationTypeGroup;
    conversation.creator = selfUser;
    conversation.team = team;

    [conversation internalAddParticipants:[NSSet setWithObject:participant]];

    // We need to check if we should add a 'secure' system message in case all participants are trusted
    [conversation increaseSecurityLevelIfNeededAfterTrustingClients:participant.clients];
    [conversation appendNewConversationSystemMessageIfNeeded];
    return conversation;
}

+ (instancetype)existingTeamConversationInManagedObjectContext:(NSManagedObjectContext *)moc withParticipant:(ZMUser *)participant team:(Team *)team
{
    // We consider a conversation being an existing 1:1 team conversation in case the following point are true:
    //  1. It is a conversation inside the team
    //  2. The only participants are the current user and the selected user
    //  3. It does not have a custom display name

    NSPredicate *sameTeam = [ZMConversation predicateForConversationsInTeam:team];
    NSPredicate *groupConversation = [NSPredicate predicateWithFormat:@"%K == %d", ZMConversationConversationTypeKey, ZMConversationTypeGroup];
    NSPredicate *noUserDefinedName = [NSPredicate predicateWithFormat:@"%K == NULL", ZMConversationUserDefinedNameKey];
    NSPredicate *sameParticipant = [NSPredicate predicateWithFormat:@"%K.@count == 1 AND %@ IN %K ", ZMConversationLastServerSyncedActiveParticipantsKey, participant, ZMConversationLastServerSyncedActiveParticipantsKey];
    NSCompoundPredicate *compoundPredicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[sameTeam, groupConversation,noUserDefinedName, sameParticipant]];
    NSFetchRequest *request = [self sortedFetchRequestWithPredicate:compoundPredicate];
    return [moc executeFetchRequestOrAssert:request].firstObject;
}

+ (instancetype)insertGroupConversationIntoManagedObjectContext:(NSManagedObjectContext *)moc withParticipants:(NSArray *)participants
{
    return [self insertGroupConversationIntoManagedObjectContext:moc withParticipants:participants inTeam:nil];
}

+ (instancetype)insertGroupConversationIntoManagedObjectContext:(NSManagedObjectContext *)moc
                                               withParticipants:(NSArray *)participants
                                                         inTeam:(nullable Team *)team
{
    return [self insertGroupConversationIntoManagedObjectContext:moc
                                                withParticipants:participants
                                                            name:nil
                                                          inTeam:team];
}

+ (instancetype)insertGroupConversationIntoManagedObjectContext:(NSManagedObjectContext *)moc
                                               withParticipants:(NSArray *)participants
                                                           name:(NSString *)name
                                                         inTeam:(nullable Team *)team
{
    return [self insertGroupConversationIntoManagedObjectContext:moc
                                                withParticipants:participants
                                                            name:name
                                                          inTeam:team
                                                     allowGuests:YES];
}

+ (nullable instancetype)insertGroupConversationIntoManagedObjectContext:(nonnull NSManagedObjectContext *)moc
                                                        withParticipants:(nonnull NSArray <ZMUser *>*)participants
                                                                    name:(nullable NSString *)name
                                                                  inTeam:(nullable Team *)team
                                                             allowGuests:(BOOL)allowGuests
{
    return [self insertGroupConversationIntoManagedObjectContext:moc
                                                withParticipants:participants
                                                            name:name
                                                          inTeam:team
                                                     allowGuests:allowGuests
                                                    readReceipts:NO];
}


+ (nullable instancetype)insertGroupConversationIntoManagedObjectContext:(nonnull NSManagedObjectContext *)moc
                                                        withParticipants:(nonnull NSArray <ZMUser *>*)participants
                                                                    name:(nullable NSString *)name
                                                                  inTeam:(nullable Team *)team
                                                             allowGuests:(BOOL)allowGuests
                                                            readReceipts:(BOOL)readReceipts
{
    ZMUser *selfUser = [ZMUser selfUserInContext:moc];

    if (nil != team && !selfUser.canCreateConversation) {
        return nil;
    }

    ZMConversation *conversation = (ZMConversation *)[super insertNewObjectInManagedObjectContext:moc];
    conversation.lastModifiedDate = [NSDate date];
    conversation.conversationType = ZMConversationTypeGroup;
    conversation.creator = selfUser;
    conversation.team = team;
    conversation.userDefinedName = name;
    if (nil != team) {
        conversation.allowGuests = allowGuests;
        conversation.hasReadReceiptsEnabled = readReceipts;
    }
    
    for (ZMUser *participant in participants) {
        Require([participant isKindOfClass:[ZMUser class]]);
        const BOOL isSelf = (participant == selfUser);
        RequireString(!isSelf, "Can't pass self user as a participant of a group conversation");
        if(!isSelf) {
            [conversation internalAddParticipants:[NSSet setWithObject:participant]];
        }
    }
    
    NSMutableSet *allClients = [NSMutableSet set];
    for (ZMUser *user in conversation.activeParticipants) {
        [allClients unionSet:user.clients];
    }
    
    // We need to check if we should add a 'secure' system message in case all participants are trusted
    [conversation increaseSecurityLevelIfNeededAfterTrustingClients:allClients];
    [conversation appendNewConversationSystemMessageIfNeeded];
    return conversation;
}

+ (NSPredicate *)predicateForSearchQuery:(NSString *)searchQuery team:(Team *)team
{
    NSPredicate *teamPredicate = [NSPredicate predicateWithFormat:@"(%K == %@)", TeamKey, team];
    
    return [NSCompoundPredicate andPredicateWithSubpredicates:@[[ZMConversation predicateForSearchQuery:searchQuery], teamPredicate]];
}

+ (NSPredicate *)userDefinedNamePredicateForSearchString:(NSString *)searchString;
{
    NSPredicate *predicate = [NSPredicate predicateWithFormatDictionary:@{ZMNormalizedUserDefinedNameKey: @"%K MATCHES %@"}
                                                   matchingSearchString:searchString];
    return predicate;
}


+ (NSUUID *)selfConversationIdentifierInContext:(NSManagedObjectContext *)context;
{
    // remoteID of self-conversation is guaranteed to be the same as remoteID of self-user
    ZMUser *selfUser = [ZMUser selfUserInContext:context];
    return selfUser.remoteIdentifier;
}

+ (ZMConversation *)selfConversationInContext:(NSManagedObjectContext *)managedObjectContext
{
    NSUUID *selfUserID = [ZMConversation selfConversationIdentifierInContext:managedObjectContext];
    return [ZMConversation conversationWithRemoteID:selfUserID createIfNeeded:NO inContext:managedObjectContext];
}

- (ZMClientMessage *)appendClientMessageWithGenericMessage:(ZMGenericMessage *)genericMessage
{
    return [self appendClientMessageWithGenericMessage:genericMessage expires:YES hidden:NO];
}

- (ZMClientMessage *)appendClientMessageWithGenericMessage:(ZMGenericMessage *)genericMessage expires:(BOOL)expires hidden:(BOOL)hidden
{
    ZMClientMessage *message = [[ZMClientMessage alloc] initWithNonce:[NSUUID uuidWithTransportString:genericMessage.messageId]
                                                 managedObjectContext:self.managedObjectContext];
    [message addData:genericMessage.data];
    
    return [self appendMessage:message expires:expires hidden:hidden];
}

- (ZMClientMessage *)appendMessage:(ZMClientMessage *)message expires:(BOOL)expires hidden:(BOOL)hidden
{
    message.sender = [ZMUser selfUserInContext:self.managedObjectContext];
    
    if (expires) {
        [message setExpirationDate];
    }
    
    if(hidden) {
        message.hiddenInConversation = self;
    } else {
        [self appendMessage:message];
        [self unarchiveIfNeeded];
        [message updateCategoryCache];
        [message prepareToSend];
    }
    
    return message;
}

- (ZMAssetClientMessage *)appendAssetClientMessageWithNonce:(NSUUID *)nonce imageData:(NSData *)imageData
{
    ZMAssetClientMessage *message =
    [[ZMAssetClientMessage alloc] initWithOriginalImage:imageData
                                                  nonce:nonce
                                   managedObjectContext:self.managedObjectContext
                                           expiresAfter:self.messageDestructionTimeoutValue];

    message.sender = [ZMUser selfUserInContext:self.managedObjectContext];
    
    [message setExpirationDate];
    [self appendMessage:message];

    [self unarchiveIfNeeded];
    [self.managedObjectContext.zm_fileAssetCache storeAssetData:message format:ZMImageFormatOriginal encrypted:NO data:imageData];
    [message updateCategoryCache];
    [message prepareToSend];
    
    return message;
}

- (void)appendNewConversationSystemMessageIfNeeded;
{
    ZMMessage *firstMessage = self.recentMessages.firstObject;
    if ([firstMessage isKindOfClass:[ZMSystemMessage class]]) {
        ZMSystemMessage *systemMessage = (ZMSystemMessage *)firstMessage;
        if (systemMessage.systemMessageType == ZMSystemMessageTypeNewConversation) {
            return;
        }
    }
    
    ZMSystemMessage *systemMessage = [[ZMSystemMessage alloc] initWithNonce:[NSUUID UUID] managedObjectContext:self.managedObjectContext];
    systemMessage.systemMessageType = ZMSystemMessageTypeNewConversation;
    systemMessage.sender = self.creator;
    systemMessage.text = self.userDefinedName;
    systemMessage.users = self.activeParticipants;
    
    [systemMessage updateNewConversationSystemMessageIfNeededWithUsers:self.activeParticipants
                                                               context:self.managedObjectContext
                                                          conversation:self];

    // the new conversation message should be displayed first,
    // additionally the use of reference date is to ensure proper transition for older clients so the message is the very
    // first message in conversation
    systemMessage.serverTimestamp = [ZMConversation newConversationMessageTimestamp];
    
    [self appendMessage:systemMessage];
    
    if (self.hasReadReceiptsEnabled) {
        [self appendMessageReceiptModeIsOnMessageWithTimestamp:[NSDate dateWithTimeIntervalSinceReferenceDate:1]];
    }
}

+ (NSDate *)newConversationMessageTimestamp
{
    return [NSDate dateWithTimeIntervalSinceReferenceDate:0];
}

- (void)appendMessage:(ZMMessage *)message;
{
    Require(message != nil);
    [message updateNormalizedText];
    message.visibleInConversation = self;
    
    [self addAllMessagesObject:message];
    [self updateMessageFetcher];
    
    [self updateTimestampsAfterInsertingMessage:message];
}

- (void)unarchiveIfNeeded
{
    if (self.isArchived) {
        self.isArchived = NO;
    }
}

@end




@implementation ZMConversation (SelfConversation)

+ (ZMClientMessage *)appendSelfConversationWithGenericMessage:(ZMGenericMessage * )genericMessage managedObjectContext:(NSManagedObjectContext *)moc;
{
    VerifyReturnNil(genericMessage != nil);

    ZMConversation *selfConversation = [ZMConversation selfConversationInContext:moc];
    VerifyReturnNil(selfConversation != nil);
    
    ZMClientMessage *clientMessage = [selfConversation appendClientMessageWithGenericMessage:genericMessage expires:NO hidden:NO];
    return clientMessage;
}


+ (ZMClientMessage *)appendSelfConversationWithLastReadOfConversation:(ZMConversation *)conversation
{
    NSDate *lastRead = conversation.lastReadServerTimeStamp;
    NSUUID *convID = conversation.remoteIdentifier;
    if (convID == nil || lastRead == nil || [convID isEqual:[ZMConversation selfConversationIdentifierInContext:conversation.managedObjectContext]]) {
        return nil;
    }

    NSUUID *nonce = [NSUUID UUID];
    ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMLastRead lastReadWithTimestamp:lastRead conversationRemoteID:convID] nonce:nonce];
    VerifyReturnNil(message != nil);
    
    return [self appendSelfConversationWithGenericMessage:message managedObjectContext:conversation.managedObjectContext];
}

+ (void)updateConversationWithZMLastReadFromSelfConversation:(ZMLastRead *)lastRead inContext:(NSManagedObjectContext *)context
{
    double newTimeStamp = lastRead.lastReadTimestamp;
    NSDate *timestamp = [NSDate dateWithTimeIntervalSince1970:(newTimeStamp/1000)];
    NSUUID *conversationID = [NSUUID uuidWithTransportString:lastRead.conversationId];
    if (conversationID == nil || timestamp == nil) {
        return;
    }
    
    ZMConversation *conversationToUpdate = [ZMConversation conversationWithRemoteID:conversationID createIfNeeded:YES inContext:context];
    [conversationToUpdate updateLastRead:timestamp synchronize:NO];
}


+ (ZMClientMessage *)appendSelfConversationWithClearedOfConversation:(ZMConversation *)conversation
{
    NSUUID *convID = conversation.remoteIdentifier;
    NSDate *cleared = conversation.clearedTimeStamp;
    if (convID == nil || cleared == nil || [convID isEqual:[ZMConversation selfConversationIdentifierInContext:conversation.managedObjectContext]]) {
        return nil;
    }
    
    NSUUID *nonce = [NSUUID UUID];
    ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMCleared clearedWithTimestamp:cleared conversationRemoteID:convID] nonce:nonce];
    VerifyReturnNil(message != nil);
    
    return [self appendSelfConversationWithGenericMessage:message managedObjectContext:conversation.managedObjectContext];
}

+ (void)updateConversationWithZMClearedFromSelfConversation:(ZMCleared *)cleared inContext:(NSManagedObjectContext *)context
{
    double newTimeStamp = cleared.clearedTimestamp;
    NSDate *timestamp = [NSDate dateWithTimeIntervalSince1970:(newTimeStamp/1000)];
    NSUUID *conversationID = [NSUUID uuidWithTransportString:cleared.conversationId];
    
    if (conversationID == nil || timestamp == nil) {
        return;
    }
    
    ZMConversation *conversation = [ZMConversation conversationWithRemoteID:conversationID createIfNeeded:YES inContext:context];
    [conversation updateCleared:timestamp synchronize:NO];
}


@end




@implementation ZMConversation (ParticipantsInternal)

+ (NSSet<UserClient *>*)clientsOfUsers:(NSSet<ZMUser *> *)users
{
    NSMutableSet *result = [NSMutableSet set];
    [users enumerateObjectsUsingBlock:^(ZMUser * _Nonnull user, BOOL * _Nonnull stop __unused) {
        [result addObjectsFromArray:user.clients.allObjects];
    }];
    return result;
}

- (void)internalAddParticipants:(NSSet<ZMUser *> *)participants
{
    VerifyReturn(participants != nil);
    
    NSSet<ZMUser *>* selfUserSet = [NSSet setWithObject:[ZMUser selfUserInContext:self.managedObjectContext]];
    
    NSMutableSet<ZMUser *>* otherUsers = [participants mutableCopy];
    [otherUsers minusSet:selfUserSet];
    
    if ([participants intersectsSet:selfUserSet]) {
        self.isSelfAnActiveMember = YES;
        self.needsToBeUpdatedFromBackend = YES;
    }
    
    if (otherUsers.count > 0) {
        NSSet *existingUsers = [self.lastServerSyncedActiveParticipants.set copy];
        [self.mutableLastServerSyncedActiveParticipants addObjectsFromArray:otherUsers.allObjects];
        
        [otherUsers minusSet:existingUsers];
        if (otherUsers.count > 0) {
            [self decreaseSecurityLevelIfNeededAfterDiscoveringClients:[ZMConversation clientsOfUsers:otherUsers] causedByAddedUsers:otherUsers];
        }
    }
}

- (void)internalRemoveParticipants:(NSSet<ZMUser *> *)participants sender:(ZMUser *)sender
{
    VerifyReturn(participants != nil);
    
    NSSet<ZMUser *>* selfUserSet = [NSSet setWithObject:[ZMUser selfUserInContext:self.managedObjectContext]];
    NSMutableSet<ZMUser *>* otherUsers = [participants mutableCopy];
    [otherUsers minusSet:selfUserSet];
    
    if ([participants intersectsSet:selfUserSet]) {
        self.isSelfAnActiveMember = NO;
        self.isArchived = sender.isSelfUser;
    }
    
    [self.mutableLastServerSyncedActiveParticipants removeObjectsInArray:otherUsers.allObjects];
    [self increaseSecurityLevelIfNeededAfterRemovingClientForUsers:otherUsers];
}

@dynamic isSelfAnActiveMember;
@dynamic lastServerSyncedActiveParticipants;

@end


@implementation ZMConversation (KeyValueValidation)

- (BOOL)validateUserDefinedName:(NSString **)ioName error:(NSError **)outError
{
    BOOL result = [ExtremeCombiningCharactersValidator validateValue:ioName error:outError];
    if (!result || (outError != nil && *outError != nil)) {
        return NO;
    }
    
    result &= *ioName == nil || [StringLengthValidator validateValue:ioName
                                                 minimumStringLength:1
                                                 maximumStringLength:64
                                                   maximumByteLength:INT_MAX
                                                               error:outError];

    return result;
}

@end


@implementation ZMConversation (Connections)

- (NSString *)connectionMessage;
{
    return self.connection.message.stringByRemovingExtremeCombiningCharacters;
}

@end


@implementation NSUUID (ZMSelfConversation)

- (BOOL)isSelfConversationRemoteIdentifierInContext:(NSManagedObjectContext *)moc;
{
    // The self conversation has the same remote ID as the self user:
    return [self isSelfUserRemoteIdentifierInContext:moc];
}

@end


@implementation ZMConversation (Optimization)

+ (void)refreshObjectsThatAreNotNeededInSyncContext:(NSManagedObjectContext *)managedObjectContext;
{
    NSMutableArray *conversationsToKeep = [NSMutableArray array];
    NSMutableSet *usersToKeep = [NSMutableSet set];
    NSMutableSet *messagesToKeep = [NSMutableSet set];
    
    // make sure that the Set is not mutated while being enumerated
    NSSet *registeredObjects = managedObjectContext.registeredObjects;
    
    // gather objects to keep
    for(NSManagedObject *obj in registeredObjects) {
        if (!obj.isFault) {
            if ([obj isKindOfClass:ZMConversation.class]) {
                ZMConversation *conversation = (ZMConversation *)obj;
                
                if(conversation.shouldNotBeRefreshed) {
                    [conversationsToKeep addObject:conversation];
                    [usersToKeep unionSet:conversation.lastServerSyncedActiveParticipants.set];
                }
            } else if ([obj isKindOfClass:ZMOTRMessage.class]) {
                ZMOTRMessage *message = (ZMOTRMessage *)obj;
                if (![message hasFaultForRelationshipNamed:ZMMessageMissingRecipientsKey] && !message.missingRecipients.isEmpty) {
                    [messagesToKeep addObject:obj];
                }
            }
        }
    }
    [usersToKeep addObject:[ZMUser selfUserInContext:managedObjectContext]];
    
    // turn into a fault
    for(NSManagedObject *obj in registeredObjects) {
        if(!obj.isFault) {
            
            const BOOL isUser = [obj isKindOfClass:ZMUser.class];
            const BOOL isMessage = [obj isKindOfClass:ZMMessage.class];
            const BOOL isConversation = [obj isKindOfClass:ZMConversation.class];
            
            const BOOL isOfTypeToBeRefreshed = isUser || isMessage || isConversation;
            
            if ((isConversation && [conversationsToKeep indexOfObjectIdenticalTo:obj] != NSNotFound) ||
                (isUser && [usersToKeep.allObjects indexOfObjectIdenticalTo:obj] != NSNotFound) ||
                (isMessage && [messagesToKeep.allObjects indexOfObjectIdenticalTo:obj] != NSNotFound) ||
                !isOfTypeToBeRefreshed) {
                continue;
            }
            [managedObjectContext refreshObject:obj mergeChanges:obj.hasChanges];
        }
    }
}

- (BOOL)shouldNotBeRefreshed
{
    static const int HOUR_IN_SEC = 60 * 60;
    static const NSTimeInterval STALENESS = -36 * HOUR_IN_SEC;
    return (self.isFault) || (self.lastModifiedDate == nil) || (self.lastModifiedDate.timeIntervalSinceNow > STALENESS);
}

@end


@implementation ZMConversation (History)


- (void)clearMessageHistory
{
    self.isArchived = YES;
    self.clearedTimeStamp = self.lastServerTimeStamp; // the setter of this deletes all messages
    self.lastReadServerTimeStamp = self.lastServerTimeStamp;
}

- (void)revealClearedConversation
{
    self.isArchived = NO;
}

@end
