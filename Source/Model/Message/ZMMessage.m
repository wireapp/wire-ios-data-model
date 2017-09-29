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
@import WireProtos;
@import MobileCoreServices;
@import ImageIO;


#import "ZMMessage+Internal.h"
#import "ZMConversation.h"
#import "ZMUser+Internal.h"
#import "NSManagedObjectContext+zmessaging.h"
#import "ZMConversation+Internal.h"
#import "ZMConversation+Timestamps.h"
#import "ZMConversation+Transport.h"

#import "ZMConversation+UnreadCount.h"
#import "ZMUpdateEvent+WireDataModel.h"
#import "ZMClientMessage.h"

#import <WireDataModel/WireDataModel-Swift.h>


static NSTimeInterval ZMDefaultMessageExpirationTime = 30;

NSString * const ZMMessageEventIDDataKey = @"eventID_data";
NSString * const ZMMessageIsEncryptedKey = @"isEncrypted";
NSString * const ZMMessageIsPlainTextKey = @"isPlainText";
NSString * const ZMMessageIsExpiredKey = @"isExpired";
NSString * const ZMMessageMissingRecipientsKey = @"missingRecipients";
NSString * const ZMMessageServerTimestampKey = @"serverTimestamp";
NSString * const ZMMessageImageTypeKey = @"imageType";
NSString * const ZMMessageIsAnimatedGifKey = @"isAnimatedGIF";
NSString * const ZMMessageMediumRemoteIdentifierDataKey = @"mediumRemoteIdentifier_data";
NSString * const ZMMessageMediumRemoteIdentifierKey = @"mediumRemoteIdentifier";
NSString * const ZMMessageOriginalDataProcessedKey = @"originalDataProcessed";
NSString * const ZMMessageMediumDataLoadedKey = @"mediumDataLoaded";
NSString * const ZMMessageOriginalSizeDataKey = @"originalSize_data";
NSString * const ZMMessageOriginalSizeKey = @"originalSize";
NSString * const ZMMessageConversationKey = @"visibleInConversation";
NSString * const ZMMessageExpirationDateKey = @"expirationDate";
NSString * const ZMMessageNameKey = @"name";
NSString * const ZMMessageNeedsToBeUpdatedFromBackendKey = @"needsToBeUpdatedFromBackend";
NSString * const ZMMessageNonceDataKey = @"nonce_data";
NSString * const ZMMessageSenderKey = @"sender";
NSString * const ZMMessageSystemMessageTypeKey = @"systemMessageType";
NSString * const ZMMessageSystemMessageClientsKey = @"clients";
NSString * const ZMMessageTextKey = @"text";
NSString * const ZMMessageUserIDsKey = @"users_ids";
NSString * const ZMMessageUsersKey = @"users";
NSString * const ZMMessageClientsKey = @"clients";
NSString * const ZMMessageAddedUsersKey = @"addedUsers";
NSString * const ZMMessageRemovedUsersKey = @"removedUsers";
NSString * const ZMMessageNeedsUpdatingUsersKey = @"needsUpdatingUsers";
NSString * const ZMMessageHiddenInConversationKey = @"hiddenInConversation";
NSString * const ZMMessageSenderClientIDKey = @"senderClientID";
NSString * const ZMMessageReactionKey = @"reactions";
NSString * const ZMMessageConfirmationKey = @"confirmations";
NSString * const ZMMessageDestructionDateKey = @"destructionDate";
NSString * const ZMMessageIsObfuscatedKey = @"isObfuscated";
NSString * const ZMMessageCachedCategoryKey = @"cachedCategory";
NSString * const ZMMessageNormalizedTextKey = @"normalizedText";
NSString * const ZMMessageDeliveryStateKey = @"deliveryState";
NSString * const ZMMessageDurationKey = @"duration";
NSString * const ZMMessageChildMessagesKey = @"childMessages";
NSString * const ZMMessageParentMessageKey = @"parentMessage";


@interface ZMMessage ()

+ (ZMConversation *)conversationForUpdateEvent:(ZMUpdateEvent *)event inContext:(NSManagedObjectContext *)context prefetchResult:(ZMFetchRequestBatchResult *)prefetchResult;

// isUpdatingExistingMessage parameter means that update event updates already existing message (i.e. for image messages)
// it will affect updating serverTimestamp and messages sorting
- (void)updateWithUpdateEvent:(ZMUpdateEvent *)event forConversation:(ZMConversation *)conversation isUpdatingExistingMessage:(BOOL)isUpdate;

- (void)updateWithTimestamp:(NSDate *)serverTimestamp senderUUID:(NSUUID *)senderUUID forConversation:(ZMConversation *)conversation isUpdatingExistingMessage:(BOOL)isUpdate;

@property (nonatomic) NSSet *missingRecipients;

@end;



@interface ZMMessage (CoreDataForward)

@property (nonatomic) BOOL isExpired;
@property (nonatomic) NSDate *expirationDate;
@property (nonatomic) NSDate *destructionDate;
@property (nonatomic) BOOL isObfuscated;

@end


@interface ZMImageMessage (CoreDataForward)

@property (nonatomic) NSData *primitiveMediumData;

@end



@implementation ZMMessage

@dynamic missingRecipients;
@dynamic isExpired;
@dynamic expirationDate;
@dynamic destructionDate;
@dynamic senderClientID;
@dynamic reactions;
@dynamic confirmations;
@dynamic isObfuscated;
@dynamic normalizedText;

+ (instancetype)createOrUpdateMessageFromUpdateEvent:(ZMUpdateEvent *)updateEvent
                              inManagedObjectContext:(NSManagedObjectContext *)moc
{
    ZMMessage *message = [self createOrUpdateMessageFromUpdateEvent:updateEvent inManagedObjectContext:moc prefetchResult:nil];
    [message updateCategoryCache];
    return message;
}

+ (BOOL)isDataAnimatedGIF:(NSData *)data
{
    if(data.length == 0) {
        return NO;
    }
    BOOL isAnimated = NO;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef) data, NULL);
    VerifyReturnValue(source != NULL, NO);
    NSString *type = CFBridgingRelease(CGImageSourceGetType(source));
    if(UTTypeConformsTo((__bridge CFStringRef) type, kUTTypeGIF)) {
        isAnimated = CGImageSourceGetCount(source) > 1;
    }
    CFRelease(source);
    return isAnimated;
}

- (BOOL)isUnreadMessage
{
    return (self.conversation != nil) && (self.conversation.lastReadServerTimeStamp != nil) && (self.serverTimestamp != nil) && ([self.serverTimestamp compare:self.conversation.lastReadServerTimeStamp] == NSOrderedDescending);
}

- (BOOL)shouldGenerateUnreadCount
{
    return YES;
}

- (BOOL)shouldUpdateLastModifiedDate
{
    return YES;
}

+ (NSPredicate *)predicateForObjectsThatNeedToBeUpdatedUpstream;
{
    return [NSPredicate predicateWithValue:NO];
}

+ (NSString *)remoteIdentifierKey;
{
    return ZMMessageNonceDataKey;
}

+ (NSString *)entityName;
{
    return @"Message";
}

+ (NSString *)sortKey;
{
    return ZMMessageNonceDataKey;
}

+ (void)setDefaultExpirationTime:(NSTimeInterval)defaultExpiration
{
    ZMDefaultMessageExpirationTime = defaultExpiration;
}

+ (NSTimeInterval)defaultExpirationTime
{
    return ZMDefaultMessageExpirationTime;
}

+ (void)resetDefaultExpirationTime
{
    ZMDefaultMessageExpirationTime = ZMTransportRequestDefaultExpirationInterval;
}

- (void)resend;
{
    self.isExpired = NO;
    [self setExpirationDate];
    [self prepareToSend];
}

- (void)setExpirationDate
{
    self.expirationDate = [NSDate dateWithTimeIntervalSinceNow:[self.class defaultExpirationTime]];
}

- (void)removeExpirationDate;
{
    self.expirationDate = nil;
}

- (void)markAsSent
{
    self.isExpired = NO;
}

- (ZMClientMessage *)confirmReception
{
    ZMGenericMessage *genericMessage = [ZMGenericMessage messageWithConfirmation:self.nonce.transportString type:ZMConfirmationTypeDELIVERED nonce:[NSUUID UUID].transportString];
    return [self.conversation appendGenericMessage:genericMessage expires:NO hidden:YES];
}

- (void)expire;
{
    self.isExpired = YES;
    [self removeExpirationDate];
    self.conversation.hasUnreadUnsentMessage = YES;
}

- (void)updateTimestamp:(NSDate *)timestamp isUpdatingExistingMessage:(BOOL)isUpdate
{
    if (isUpdate) {
        self.serverTimestamp = [NSDate lastestOfDate:self.serverTimestamp and:timestamp];
    } else if (timestamp != nil) {
        self.serverTimestamp = timestamp;
    }
}

+ (NSSet *)keyPathsForValuesAffectingDeliveryState;
{
    return [NSMutableSet setWithObjects: ZMMessageIsExpiredKey, ZMMessageConfirmationKey, nil];
}

- (void)awakeFromInsert;
{
    [super awakeFromInsert];
    self.nonce = [[NSUUID alloc] init];
    self.serverTimestamp = [self dateIgnoringNanoSeconds];
}

- (NSDate *)dateIgnoringNanoSeconds
{
    double currentMilliseconds = floor([[NSDate date] timeIntervalSince1970]*1000);
    return [NSDate dateWithTimeIntervalSince1970:(currentMilliseconds/1000)];
}


- (NSUUID *)nonce;
{
    return [self transientUUIDForKey:@"nonce"];
}

- (void)setNonce:(NSUUID *)nonce;
{
    [self setTransientUUID:nonce forKey:@"nonce"];
}

+ (NSArray *)defaultSortDescriptors;
{
    static NSArray *sd;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSSortDescriptor *serverTimestamp = [NSSortDescriptor sortDescriptorWithKey:ZMMessageServerTimestampKey ascending:YES];
        sd = @[serverTimestamp];
    });
    return sd;
}

- (NSComparisonResult)compare:(ZMMessage *)other;
{
    for (NSSortDescriptor *sd in [[self class] defaultSortDescriptors]) {
        NSComparisonResult r = [sd compareObject:self toObject:other];
        if (r != NSOrderedSame) {
            return r;
        }
    }
    return NSOrderedSame;
}

- (void)updateWithUpdateEvent:(ZMUpdateEvent *)event forConversation:(ZMConversation *)conversation isUpdatingExistingMessage:(BOOL)isUpdate;
{
    [self updateWithTimestamp:event.timeStamp senderUUID:event.senderUUID forConversation:conversation isUpdatingExistingMessage:isUpdate];
}

- (void)updateWithTimestamp:(NSDate *)serverTimestamp senderUUID:(NSUUID *)senderUUID forConversation:(ZMConversation *)conversation isUpdatingExistingMessage:(BOOL)isUpdate;
{
    [self updateTimestamp:serverTimestamp isUpdatingExistingMessage:isUpdate];

    if (self.managedObjectContext != conversation.managedObjectContext) {
        conversation = [ZMConversation conversationWithRemoteID:conversation.remoteIdentifier createIfNeeded:NO inContext:self.managedObjectContext];
    }
    
    self.visibleInConversation = conversation;
    ZMUser *sender = [ZMUser userWithRemoteID:senderUUID createIfNeeded:YES inContext:self.managedObjectContext];
    if (sender != nil && !sender.isZombieObject && self.managedObjectContext == sender.managedObjectContext) {
        self.sender = sender;
    } else {
        ZMLogError(@"Sender is nil or from a different context than message. \n Sender is zombie %@: %@ \n Message: %@", @(sender.isZombieObject), sender, self);
    }
    
    if (self.sender.isSelfUser) {
        // if the message was sent by the selfUser we don't want to send a lastRead event, since we consider this message to be already read
        [self.conversation updateLastReadServerTimeStampIfNeededWithTimeStamp:self.serverTimestamp andSync:NO];
    }
    [conversation updateWithMessage:self timeStamp:serverTimestamp];
}

+ (ZMConversation *)conversationForUpdateEvent:(ZMUpdateEvent *)event inContext:(NSManagedObjectContext *)moc prefetchResult:(ZMFetchRequestBatchResult *)prefetchResult
{
    NSUUID *conversationUUID = event.conversationUUID;
    
    VerifyReturnNil(conversationUUID != nil);
    
    if (nil != prefetchResult.conversationsByRemoteIdentifier[conversationUUID]) {
        return prefetchResult.conversationsByRemoteIdentifier[conversationUUID];
    }
    
    return [ZMConversation conversationWithRemoteID:conversationUUID createIfNeeded:YES inContext:moc];
}

- (void)removeMessageClearingSender:(BOOL)clearingSender
{
    self.hiddenInConversation = self.conversation;
    self.visibleInConversation = nil;
    [self clearAllReactions];

    if (clearingSender) {
        self.sender = nil;
        self.senderClientID = nil;
    }
}

+ (void)removeMessageWithRemotelyHiddenMessage:(ZMMessageHide *)hiddenMessage fromUser:(ZMUser *)user inManagedObjectContext:(NSManagedObjectContext *)moc;
{
    ZMUser *selfUser = [ZMUser selfUserInContext:moc];
    if(user != selfUser) {
        return;
    }
    
    NSUUID *conversationID = [NSUUID uuidWithTransportString:hiddenMessage.conversationId];
    ZMConversation *conversation = [ZMConversation conversationWithRemoteID:conversationID createIfNeeded:NO inContext:moc];
    
    NSUUID *messageID = [NSUUID uuidWithTransportString:hiddenMessage.messageId];
    ZMMessage *message = [ZMMessage fetchMessageWithNonce:messageID forConversation:conversation inManagedObjectContext:moc];
    
    // To avoid reinserting when receiving an edit we delete the message locally
    if (message != nil) {
        [message removeMessageClearingSender:YES];
        [moc deleteObject:message];
    }
}

+ (void)addReaction:(ZMReaction *)reaction senderID:(NSUUID *)senderID conversation:(ZMConversation *)conversation inManagedObjectContext:(NSManagedObjectContext *)moc;
{
    ZMUser *user = [ZMUser fetchObjectWithRemoteIdentifier:senderID inManagedObjectContext:moc];
    NSUUID *nonce = [NSUUID uuidWithTransportString:reaction.messageId];
    ZMMessage *localMessage = [ZMMessage fetchMessageWithNonce:nonce
                                               forConversation:conversation
                                        inManagedObjectContext:moc];
    
    [localMessage addReaction:reaction.emoji forUser:user];
    [localMessage updateCategoryCache];
}

+ (void)removeMessageWithRemotelyDeletedMessage:(ZMMessageDelete *)deletedMessage inConversation:(ZMConversation *)conversation senderID:(NSUUID *)senderID inManagedObjectContext:(NSManagedObjectContext *)moc;
{
    NSUUID *messageID = [NSUUID uuidWithTransportString:deletedMessage.messageId];
    ZMMessage *message = [ZMMessage fetchMessageWithNonce:messageID forConversation:conversation inManagedObjectContext:moc];

    // We need to cascade delete the pending delivery confirmation messages for the message being deleted
    [message removePendingDeliveryReceipts];
    
    // Only the sender of the original message can delete it
    if (![senderID isEqual:message.sender.remoteIdentifier] && !message.isEphemeral) {
        return;
    }

    ZMUser *selfUser = [ZMUser selfUserInContext:moc];

    // Only clients other than self should see the system message
    if (nil != message && ![senderID isEqual:selfUser.remoteIdentifier] && !message.isEphemeral) {
        [conversation appendDeletedForEveryoneSystemMessageAt:message.serverTimestamp sender:message.sender];
    }
    // If we receive a delete for an ephemeral message that was not originally sent by the selfUser, we need to stop the deletion timer
    if (nil != message && message.isEphemeral && ![message.sender.remoteIdentifier isEqual:selfUser.remoteIdentifier]) {
        [message removeMessageClearingSender:YES];
        [self stopDeletionTimerForMessage:message];
    } else {
        [message removeMessageClearingSender:YES];
        [message updateCategoryCache];
    }
}

+ (void)stopDeletionTimerForMessage:(ZMMessage *)message
{
    NSManagedObjectContext *uiMOC = message.managedObjectContext;
    if (!uiMOC.zm_isUserInterfaceContext) {
        uiMOC = uiMOC.zm_userInterfaceContext;
    }
    NSManagedObjectID *messageID = message.objectID;
    [uiMOC performGroupedBlock:^{
        NSError *error;
        ZMMessage *uiMessage = [uiMOC existingObjectWithID:messageID error:&error];
        if (error != nil || uiMessage == nil) {
            return;
        }
        [uiMOC.zm_messageDeletionTimer stopTimerForMessage:uiMessage];
    }];
}

- (void)removePendingDeliveryReceipts
{
    // Pending receipt can exist only in new inserted messages since it is deleted locally after it is sent to the backend
    NSFetchRequest *requestForInsertedMessages = [ZMClientMessage sortedFetchRequestWithPredicate:[ZMClientMessage predicateForObjectsThatNeedToBeInsertedUpstream]];
    NSArray *possibleMatches = [self.managedObjectContext executeFetchRequestOrAssert:requestForInsertedMessages];
    
    NSArray *confirmationReceipts = [possibleMatches filterWithBlock:^BOOL(ZMClientMessage *candidateConfirmationReceipt) {
        if (candidateConfirmationReceipt.genericMessage.hasConfirmation &&
            candidateConfirmationReceipt.genericMessage.confirmation.hasMessageId &&
            [candidateConfirmationReceipt.genericMessage.confirmation.messageId isEqual:self.nonce.transportString]) {
            return YES;
        }
        return NO;
    }];
    
    NSAssert(confirmationReceipts.count <= 1, @"More than one confirmation receipt");
    
    for (ZMClientMessage *confirmationReceipt in confirmationReceipts) {
        [self.managedObjectContext deleteObject:confirmationReceipt];
    }
}

+ (ZMMessage *)clearedMessageForRemotelyEditedMessage:(ZMGenericMessage *)genericEditMessage inConversation:(ZMConversation *)conversation senderID:(NSUUID *)senderID inManagedObjectContext:(NSManagedObjectContext *)moc;
{
    if (!genericEditMessage.hasEdited) {
        return nil;
    }
    NSUUID *messageID = [NSUUID uuidWithTransportString:genericEditMessage.edited.replacingMessageId];
    ZMMessage *message = [ZMMessage fetchMessageWithNonce:messageID forConversation:conversation inManagedObjectContext:moc];
    
    // Only the sender of the original message can edit it
    if (message == nil  || message.isZombieObject || ![senderID isEqual:message.sender.remoteIdentifier]) {
        return nil;
    }

    // We do not want to clear the sender in case of an edit, as the message will still be visible
    [message removeMessageClearingSender:NO];
    return message;
}


- (NSUUID *)nonceFromPostPayload:(NSDictionary *)payload
{
    ZMUpdateEventType eventType = [ZMUpdateEvent updateEventTypeForEventTypeString:[payload optionalStringForKey:@"type"]];
    switch (eventType) {
            
        case ZMUpdateEventConversationMessageAdd:
        case ZMUpdateEventConversationKnock:
            return [[payload dictionaryForKey:@"data"] uuidForKey:@"nonce"];

        case ZMUpdateEventConversationClientMessageAdd:
        case ZMUpdateEventConversationOtrMessageAdd:
        {
            //if event is otr message then payload should be already decrypted and should contain generic message data
            NSString *base64Content = [payload stringForKey:@"data"];
            ZMGenericMessage *message;
            @try {
                message = [ZMGenericMessage messageWithBase64String:base64Content];
            }
            @catch(NSException *e) {
                ZMLogError(@"Cannot create message from protobuffer: %@ event payload: %@", e, payload);
                return nil;
            }
            return [NSUUID uuidWithTransportString:message.messageId];
        }
            
        default:
            return nil;
    }
}

- (void)updateWithPostPayload:(NSDictionary *)payload updatedKeys:(__unused NSSet *)updatedKeys
{
    NSUUID *nonce = [self nonceFromPostPayload:payload];
    if (nonce != nil && ![self.nonce isEqual:nonce]) {
        ZMLogWarn(@"send message response nonce does not match");
        return;
    }
    
    BOOL updatedTimestamp = NO;
    NSDate *timestamp = [payload dateForKey:@"time"];
    if (timestamp == nil) {
        ZMLogWarn(@"No time in message post response from backend.");
    } else if( ! [timestamp isEqualToDate:self.serverTimestamp]) {
        self.serverTimestamp = timestamp;
        updatedTimestamp = YES;
    }
    [self.conversation updateLastReadServerTimeStampIfNeededWithTimeStamp:timestamp andSync:NO];
    [self.conversation updateLastServerTimeStampIfNeeded:timestamp];
    [self.conversation updateLastModifiedDateIfNeeded:timestamp];
    if (updatedTimestamp) {
        [self.conversation resortMessagesWithUpdatedMessage:self];
    }
}

- (NSString *)shortDebugDescription;
{
    // This will make "seconds since" easier to read:
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.usesGroupingSeparator = YES;
    
    return [NSString stringWithFormat:@"<%@: %p> id: %@, conversation: %@, nonce: %@, sender: %@, server timestamp: %@",
            self.class, self,
            self.objectID.URIRepresentation.lastPathComponent,
            self.conversation.objectID.URIRepresentation.lastPathComponent,
            [self.nonce.UUIDString.lowercaseString substringToIndex:4],
            self.sender.objectID.URIRepresentation.lastPathComponent,
            [formatter stringFromNumber:@(self.serverTimestamp.timeIntervalSinceNow)]
            ];
}

+ (instancetype)fetchMessageWithNonce:(NSUUID *)nonce forConversation:(ZMConversation *)conversation inManagedObjectContext:(NSManagedObjectContext *)moc
{
    return [self fetchMessageWithNonce:nonce forConversation:conversation inManagedObjectContext:moc prefetchResult:nil];
}


+ (instancetype)fetchMessageWithNonce:(NSUUID *)nonce forConversation:(ZMConversation *)conversation inManagedObjectContext:(NSManagedObjectContext *)moc prefetchResult:(ZMFetchRequestBatchResult *)prefetchResult
{
    NSSet <ZMMessage *>* prefetchedMessages = prefetchResult.messagesByNonce[nonce];
    
    if (nil != prefetchedMessages) {
        for (ZMMessage *prefetchedMessage in prefetchedMessages) {
            if ([prefetchedMessage isKindOfClass:[self class]]) {
                return prefetchedMessage;
            }
        }
    }
    
    NSEntityDescription *entity = moc.persistentStoreCoordinator.managedObjectModel.entitiesByName[self.entityName];
    NSPredicate *noncePredicate = [NSPredicate predicateWithFormat:@"%K == %@", ZMMessageNonceDataKey, [nonce data]];
    
    BOOL checkedAllHiddenMessages = NO;
    BOOL checkedAllVisibleMessage = NO;

    if (![conversation hasFaultForRelationshipNamed:ZMConversationMessagesKey]) {
        checkedAllVisibleMessage = YES;
        for (ZMMessage *message in conversation.messages) {
            if (message.isFault) {
                checkedAllVisibleMessage = NO;
            } else if ([message.entity isKindOfEntity:entity] && [noncePredicate evaluateWithObject:message]) {
                return (id) message;
            }
        }
    }
    
    if (![conversation hasFaultForRelationshipNamed:ZMConversationHiddenMessagesKey]) {
        checkedAllHiddenMessages = YES;
        for (ZMMessage *message in conversation.hiddenMessages) {
            if (message.isFault) {
                checkedAllHiddenMessages = NO;
            } else if ([message.entity isKindOfEntity:entity] && [noncePredicate evaluateWithObject:message]) {
                return (id) message;
            }
        }
    }

    if (checkedAllVisibleMessage && checkedAllHiddenMessages) {
        return nil;
    }

    NSPredicate *conversationPredicate = [NSPredicate predicateWithFormat:@"%K == %@ OR %K == %@", ZMMessageConversationKey, conversation.objectID, ZMMessageHiddenInConversationKey, conversation.objectID];
    
    NSPredicate *predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[noncePredicate, conversationPredicate]];
    NSFetchRequest *fetchRequest = [self.class sortedFetchRequestWithPredicate:predicate];
    fetchRequest.fetchLimit = 2;
    fetchRequest.includesSubentities = YES;
    
    NSArray* fetchResult = [moc executeFetchRequestOrAssert:fetchRequest];
    VerifyString([fetchResult count] <= 1, "More than one message with the same nonce in the same conversation");
    return fetchResult.firstObject;
}


+ (NSPredicate *)predicateForMessagesThatWillExpire;
{
    return [NSPredicate predicateWithFormat:@"%K == 0 && %K != NIL",
            ZMMessageIsExpiredKey,
            ZMMessageExpirationDateKey];
}


+ (BOOL)doesEventTypeGenerateMessage:(ZMUpdateEventType)type;
{
    return
        (type == ZMUpdateEventConversationAssetAdd) ||
        (type == ZMUpdateEventConversationMessageAdd) ||
        (type == ZMUpdateEventConversationClientMessageAdd) ||
        (type == ZMUpdateEventConversationOtrMessageAdd) ||
        (type == ZMUpdateEventConversationOtrAssetAdd) ||
        (type == ZMUpdateEventConversationKnock) ||
        [ZMSystemMessage doesEventTypeGenerateSystemMessage:type];
}


+ (instancetype)createOrUpdateMessageFromUpdateEvent:(ZMUpdateEvent *__unused)updateEvent
                              inManagedObjectContext:(NSManagedObjectContext *__unused)moc
                                      prefetchResult:(__unused ZMFetchRequestBatchResult *)prefetchResult
{
    NSAssert(FALSE, @"Subclasses should override this method: [%@ %@]", NSStringFromClass(self), NSStringFromSelector(_cmd));
    return nil;
}

+ (NSPredicate *)predicateForMessageInConversation:(ZMConversation *)conversation withNonces:(NSSet<NSUUID *> *)nonces;
{
    NSPredicate *conversationPredicate = [NSPredicate predicateWithFormat:@"%K == %@ OR %K == %@", ZMMessageConversationKey, conversation.objectID, ZMMessageHiddenInConversationKey, conversation.objectID];
    NSSet *noncesData = [nonces mapWithBlock:^NSData*(NSUUID *uuid) {
        return uuid.data;
    }];
    NSPredicate *noncePredicate = [NSPredicate predicateWithFormat:@"%K IN %@", noncesData]; // FIXME? How can this work at all?
    return [NSCompoundPredicate andPredicateWithSubpredicates:@[conversationPredicate, noncePredicate]];
}

@end



@implementation ZMMessage (PersistentChangeTracking)

+ (NSPredicate *)predicateForObjectsThatNeedToBeInsertedUpstream;
{
    return [NSPredicate predicateWithValue:NO];
}

- (NSSet *)ignoredKeys;
{
    static NSSet *ignoredKeys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSSet *keys = [super ignoredKeys];
        NSArray *newKeys = @[
                             ZMMessageConversationKey,
                             ZMMessageExpirationDateKey,
                             ZMMessageImageTypeKey,
                             ZMMessageIsAnimatedGifKey,
                             ZMMessageMediumRemoteIdentifierDataKey,
                             ZMMessageNameKey,
                             ZMMessageNonceDataKey,
                             ZMMessageOriginalDataProcessedKey,
                             ZMMessageOriginalSizeDataKey,
                             ZMMessageSenderKey,
                             ZMMessageServerTimestampKey,
                             ZMMessageSystemMessageTypeKey,
                             ZMMessageTextKey,
                             ZMMessageUserIDsKey,
                             ZMMessageEventIDDataKey,
                             ZMMessageUsersKey,
                             ZMMessageClientsKey,
                             ZMMessageIsEncryptedKey,
                             ZMMessageIsPlainTextKey,
                             ZMMessageHiddenInConversationKey,
                             ZMMessageMissingRecipientsKey,
                             ZMMessageMediumDataLoadedKey,
                             ZMMessageAddedUsersKey,
                             ZMMessageRemovedUsersKey,
                             ZMMessageNeedsUpdatingUsersKey,
                             ZMMessageSenderClientIDKey,
                             ZMMessageConfirmationKey,
                             ZMMessageReactionKey,
                             ZMMessageDestructionDateKey,
                             ZMMessageIsObfuscatedKey,
                             ZMMessageCachedCategoryKey,
                             ZMMessageNormalizedTextKey,
                             ZMMessageDurationKey,
                             ZMMessageChildMessagesKey,
                             ZMMessageParentMessageKey
                             ];
        ignoredKeys = [keys setByAddingObjectsFromArray:newKeys];
    });
    return ignoredKeys;
}

@end



#pragma mark - Text message

@implementation ZMTextMessage

@dynamic text;

+ (NSString *)entityName;
{
    return @"TextMessage";
}

- (NSString *)shortDebugDescription;
{
    return [[super shortDebugDescription] stringByAppendingFormat:@", \'%@\'", self.text];
}

+ (instancetype)createOrUpdateMessageFromUpdateEvent:(ZMUpdateEvent *)updateEvent
                              inManagedObjectContext:(NSManagedObjectContext *)moc
                                      prefetchResult:(ZMFetchRequestBatchResult *)prefetchResult
{
    NSDictionary *eventData = [updateEvent.payload dictionaryForKey:@"data"];
    NSString *text = [eventData stringForKey:@"content"];
    NSUUID *nonce = [eventData uuidForKey:@"nonce"];
    
    VerifyReturnNil(nonce != nil);
    
    ZMConversation *conversation = [self conversationForUpdateEvent:updateEvent inContext:moc prefetchResult:prefetchResult];
    VerifyReturnNil(conversation != nil);
    
    ZMClientMessage *preExistingClientMessage = [ZMClientMessage fetchMessageWithNonce:nonce
                                                                       forConversation:conversation
                                                                inManagedObjectContext:moc
                                                                        prefetchResult:prefetchResult];
    if(preExistingClientMessage != nil) {
        preExistingClientMessage.isPlainText = YES;
        return nil;
    }
    
    ZMTextMessage *message = [ZMTextMessage fetchMessageWithNonce:nonce
                                                  forConversation:conversation
                                           inManagedObjectContext:moc
                                               prefetchResult:prefetchResult];
    if(message == nil) {
        message = [ZMTextMessage insertNewObjectInManagedObjectContext:moc];
    }
    
    message.isPlainText = YES;
    message.isEncrypted = NO;
    message.nonce = nonce;
    [message updateWithUpdateEvent:updateEvent forConversation:conversation isUpdatingExistingMessage:NO];
    message.text = text;
    
    return message;
}

- (NSString *)messageText
{
    return self.text;
}

- (LinkPreview *)linkPreview
{
    return nil;
}

- (id<ZMTextMessageData>)textMessageData
{
    return self;
}

- (NSData *)imageData
{
    return nil;
}

- (BOOL)hasImageData
{
    return NO;
}

- (NSString *)imageDataIdentifier
{
    return nil;
}

- (void)removeMessageClearingSender:(BOOL)clearingSender
{
    self.text = nil;
    [super removeMessageClearingSender:clearingSender];
}

- (ZMDeliveryState)deliveryState
{
    return ZMDeliveryStateDelivered;
}

@end





# pragma mark - Knock message

@implementation ZMKnockMessage

+ (NSString *)entityName;
{
    return @"KnockMessage";
}

+ (instancetype)createOrUpdateMessageFromUpdateEvent:(ZMUpdateEvent __unused *)updateEvent
                              inManagedObjectContext:(NSManagedObjectContext __unused *)moc
                                      prefetchResult:(ZMFetchRequestBatchResult __unused *)prefetchResult
{
    return nil;
}

- (id<ZMKnockMessageData>)knockMessageData
{
    return self;
}

@end



# pragma mark - System message

@implementation ZMSystemMessage

@dynamic text;

+ (NSString *)entityName;
{
    return @"SystemMessage";
}

@dynamic systemMessageType;
@dynamic users;
@dynamic clients;
@dynamic addedUsers;
@dynamic removedUsers;
@dynamic needsUpdatingUsers;
@dynamic duration;
@dynamic childMessages;
@dynamic parentMessage;

+ (instancetype)createOrUpdateMessageFromUpdateEvent:(ZMUpdateEvent *)updateEvent
                              inManagedObjectContext:(NSManagedObjectContext *)moc
                                      prefetchResult:(ZMFetchRequestBatchResult *)prefetchResult
{
    ZMSystemMessageType type = [self.class systemMessageTypeFromEventType:updateEvent.type];
    if(type == ZMSystemMessageTypeInvalid) {
        return nil;
    }
    
    ZMConversation *conversation = [self conversationForUpdateEvent:updateEvent inContext:moc prefetchResult:prefetchResult];
    VerifyReturnNil(conversation != nil);
    
    if ((conversation.conversationType != ZMConversationTypeGroup) &&
        ((updateEvent.type == ZMUpdateEventConversationMemberJoin) ||
         (updateEvent.type == ZMUpdateEventConversationMemberLeave) ||
         (updateEvent.type == ZMUpdateEventConversationMemberUpdate) ||
         (updateEvent.type == ZMUpdateEventConversationMessageAdd) ||
         (updateEvent.type == ZMUpdateEventConversationClientMessageAdd) ||
         (updateEvent.type == ZMUpdateEventConversationOtrMessageAdd) ||
         (updateEvent.type == ZMUpdateEventConversationOtrAssetAdd)
         ))
    {
        return nil;
    }
    
    if (type == ZMSystemMessageTypeMissedCall)
    {
        NSString *reason = [[updateEvent.payload dictionaryForKey:@"data"] optionalStringForKey:@"reason"];

        // When we cancel a call we placed before it connected we already insert the missed call system message
        // locally and ignore the update event. (This whole logic can be removed once group calls are on v3).
        BOOL selfReason = [[ZMUser selfUserInContext:moc].remoteIdentifier isEqual:updateEvent.senderUUID];
        if (![reason isEqualToString:@"missed"] || selfReason) {
            return nil;
        }
    }
    
    NSMutableSet *usersSet = [NSMutableSet set];
    for(NSString *userId in [[updateEvent.payload dictionaryForKey:@"data"] optionalArrayForKey:@"user_ids"])
    {
        ZMUser *user = [ZMUser userWithRemoteID:[NSUUID uuidWithTransportString:userId] createIfNeeded:YES inContext:moc];
        [usersSet addObject:user];
    }
    
    ZMSystemMessage *message = [ZMSystemMessage insertNewObjectInManagedObjectContext:moc];
    message.systemMessageType = type;
    message.visibleInConversation = conversation;
    
    [message updateWithUpdateEvent:updateEvent forConversation:conversation isUpdatingExistingMessage:NO];
    
    if (![usersSet isEqual:[NSSet setWithObject:message.sender]]) {
        [usersSet removeObject:message.sender];
    }
    message.users = usersSet;

    NSString *messageText = [[updateEvent.payload dictionaryForKey:@"data"] optionalStringForKey:@"message"];
    NSString *name = [[updateEvent.payload dictionaryForKey:@"data"] optionalStringForKey:@"name"];
    if (messageText != nil) {
        message.text = messageText.stringByRemovingExtremeCombiningCharacters;
    }
    else if (name != nil) {
        message.text = name.stringByRemovingExtremeCombiningCharacters;
    }

    message.isEncrypted = NO;
    message.isPlainText = YES;
    
    if (type == ZMSystemMessageTypeParticipantsAdded || type == ZMSystemMessageTypeParticipantsRemoved) {
        [conversation insertOrUpdateSecurityVerificationMessageAfterParticipantsChange:message];
    }
    
    return message;
}

- (ZMDeliveryState)deliveryState
{
    // SystemMessages are either from the BE or inserted on device
    return ZMDeliveryStateDelivered;
}

- (NSDictionary<NSString *,NSArray<ZMUser *> *> *)usersReaction
{
    return [NSDictionary dictionary];
}

+ (ZMSystemMessage *)fetchLatestPotentialGapSystemMessageInConversation:(ZMConversation *)conversation
{
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:[self entityName]];
    request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:ZMMessageServerTimestampKey ascending:NO]];
    request.fetchBatchSize = 1;
    request.predicate = [self predicateForPotentialGapSystemMessagesNeedingUpdatingUsersInConversation:conversation];
    NSArray *result = [conversation.managedObjectContext executeFetchRequestOrAssert:request];
    return result.firstObject;
}

+ (NSPredicate *)predicateForPotentialGapSystemMessagesNeedingUpdatingUsersInConversation:(ZMConversation *)conversation
{
    NSPredicate *conversationPredicate = [NSPredicate predicateWithFormat:@"%K == %@", ZMMessageConversationKey, conversation];
    NSPredicate *missingMessagesTypePredicate = [NSPredicate predicateWithFormat:@"%K == %@", ZMMessageSystemMessageTypeKey, @(ZMSystemMessageTypePotentialGap)];
    NSPredicate *needsUpdatingUsersPredicate = [NSPredicate predicateWithFormat:@"%K == YES", ZMMessageNeedsUpdatingUsersKey];
    return [NSCompoundPredicate andPredicateWithSubpredicates:@[conversationPredicate, missingMessagesTypePredicate, needsUpdatingUsersPredicate]];
}

+ (NSPredicate *)predicateForSystemMessagesInsertedLocally
{
    return [NSPredicate predicateWithBlock:^BOOL(ZMSystemMessage *msg, id ZM_UNUSED bindings) {
        if (![msg isKindOfClass:[ZMSystemMessage class]]){
            return NO;
        }
        switch (msg.systemMessageType) {
            case ZMSystemMessageTypeNewClient:
            case ZMSystemMessageTypePotentialGap:
            case ZMSystemMessageTypeIgnoredClient:
            case ZMSystemMessageTypePerformedCall:
            case ZMSystemMessageTypeUsingNewDevice:
            case ZMSystemMessageTypeDecryptionFailed:
            case ZMSystemMessageTypeReactivatedDevice:
            case ZMSystemMessageTypeConversationIsSecure:
            case ZMSystemMessageTypeMessageDeletedForEveryone:
            case ZMSystemMessageTypeDecryptionFailed_RemoteIdentityChanged:
            case ZMSystemMessageTypeTeamMemberLeave:
                return YES;
            case ZMSystemMessageTypeInvalid:
            case ZMSystemMessageTypeConversationNameChanged:
            case ZMSystemMessageTypeConnectionRequest:
            case ZMSystemMessageTypeConnectionUpdate:
            case ZMSystemMessageTypeNewConversation:
            case ZMSystemMessageTypeParticipantsAdded:
            case ZMSystemMessageTypeParticipantsRemoved:
            case ZMSystemMessageTypeMissedCall:
                return NO;
        }
    }];
}

- (void)updateNeedsUpdatingUsersIfNeeded
{
    if (self.systemMessageType == ZMSystemMessageTypePotentialGap && self.needsUpdatingUsers == YES) {
        BOOL (^matchUnfetchedUserBlock)(ZMUser *) = ^BOOL(ZMUser *user) {
            return user.name == nil;
        };
        
        self.needsUpdatingUsers = [self.addedUsers anyObjectMatchingWithBlock:matchUnfetchedUserBlock] ||
                                  [self.removedUsers anyObjectMatchingWithBlock:matchUnfetchedUserBlock];
    }
}

+ (ZMSystemMessageType)systemMessageTypeFromEventType:(ZMUpdateEventType)type
{
    NSNumber *number = self.eventTypeToSystemMessageTypeMap[@(type)];
    if(number == nil) {
        return ZMSystemMessageTypeInvalid;
    }
    else {
        return (ZMSystemMessageType) number.integerValue;
    }
}

+ (BOOL)doesEventTypeGenerateSystemMessage:(ZMUpdateEventType)type;
{
    return [self.eventTypeToSystemMessageTypeMap.allKeys containsObject:@(type)];
}

+ (NSDictionary *)eventTypeToSystemMessageTypeMap   
{
    return @{
             @(ZMUpdateEventConversationMemberJoin) : @(ZMSystemMessageTypeParticipantsAdded),
             @(ZMUpdateEventConversationMemberLeave) : @(ZMSystemMessageTypeParticipantsRemoved),
             @(ZMUpdateEventConversationRename) : @(ZMSystemMessageTypeConversationNameChanged),
             @(ZMUpdateEventConversationConnectRequest) : @(ZMSystemMessageTypeConnectionRequest),
             @(ZMUpdateEventConversationVoiceChannelDeactivate) : @(ZMSystemMessageTypeMissedCall)
             };
}

- (id<ZMSystemMessageData>)systemMessageData
{
    return self;
}

- (BOOL)shouldUpdateLastModifiedDate
{
    switch (self.systemMessageType) {
        case ZMSystemMessageTypeParticipantsRemoved:
        case ZMSystemMessageTypeConversationNameChanged:
            return NO;

        default:
            return YES;
    }
}

- (BOOL)shouldGenerateUnreadCount;
{
    return self.systemMessageType == ZMSystemMessageTypeMissedCall;
}

- (NSDate *)lastChildMessageDate
{
    NSDate *date = self.serverTimestamp;
    for (ZMSystemMessage *message in self.childMessages) {
        if ([message.serverTimestamp compare:date] == NSOrderedDescending) {
            date = message.serverTimestamp;
        }
    }
    return date;
}


@end




@implementation ZMMessage (Ephemeral)


- (BOOL)startDestructionIfNeeded
{
    if (self.destructionDate != nil || !self.isEphemeral) {
        return NO;
    }
    BOOL isSelfUser = self.sender.isSelfUser;
    if (isSelfUser && self.managedObjectContext.zm_isSyncContext) {
        self.destructionDate = [NSDate dateWithTimeIntervalSinceNow:self.deletionTimeout];
        ZMMessageDestructionTimer *timer = self.managedObjectContext.zm_messageObfuscationTimer;
        [timer startObfuscationTimerWithMessage:self timeout:self.deletionTimeout];
        return YES;
    }
    else if (!isSelfUser && self.managedObjectContext.zm_isUserInterfaceContext){
        ZMMessageDestructionTimer *timer = self.managedObjectContext.zm_messageDeletionTimer;
        NSTimeInterval matchedTimeInterval = [timer startDeletionTimerWithMessage:self timeout:self.deletionTimeout];
        self.destructionDate = [NSDate dateWithTimeIntervalSinceNow:matchedTimeInterval];
        return YES;
    }
    return NO;
}

- (void)obfuscate;
{
    self.isObfuscated = true;
    self.destructionDate = nil;
}

- (void)deleteEphemeral;
{
    if (self.conversation.conversationType != ZMConversationTypeGroup) {
        self.destructionDate = nil;
    }
    [ZMMessage deleteForEveryone:self];
    self.isObfuscated = NO;
}

+ (NSFetchRequest *)fetchRequestForEphemeralMessagesThatNeedToBeDeleted
{
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:self.entityName];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"%K != nil AND %K != nil AND %K == FALSE",
                              ZMMessageDestructionDateKey,          // If it has a destructionDate, the timer did not fire in time
                              ZMMessageSenderKey,                   // As soon as the message is deleted, we would delete the sender
                              ZMMessageIsObfuscatedKey];            // If the message is obfuscated, we don't need to obfuscate it again
    return fetchRequest;
}

+ (void)deleteOldEphemeralMessages:(NSManagedObjectContext *)context
{
    NSFetchRequest *request = [self fetchRequestForEphemeralMessagesThatNeedToBeDeleted];
    NSArray *messages = [context executeFetchRequestOrAssert:request];

    for (ZMMessage *message in messages) {
        NSTimeInterval timeToDeletion = [message.destructionDate timeIntervalSinceNow];
        if (timeToDeletion > 0) {
            // The timer has not run out yet, we want to start a timer with the remaining time
            [message restartDeletionTimer:timeToDeletion];
        } else {
            // The timer has run out, we want to delete the message or obfuscate if we are the sender
            if (message.sender.isSelfUser) {
                // message needs to be obfuscated
                [message obfuscate];
            } else {
                [message deleteEphemeral];
            }
        }
    }
}

- (void)restartDeletionTimer:(NSTimeInterval)remainingTime
{
    NSManagedObjectContext *uiContext = self.managedObjectContext;
    if (!uiContext.zm_isUserInterfaceContext) {
        uiContext = self.managedObjectContext.zm_userInterfaceContext;
    }
    [uiContext performGroupedBlock:^{
        NSError *error;
        ZMMessage *message = [uiContext existingObjectWithID:self.objectID error:&error];
        if (error == nil && message != nil) {
            NOT_USED([uiContext.zm_messageDeletionTimer startDeletionTimerWithMessage:message timeout:remainingTime]);
        }
    }];
}


@end

