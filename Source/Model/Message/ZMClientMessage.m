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


@import WireSystem;
@import WireUtilities;
@import WireTransport;
@import WireProtos;
@import CoreGraphics;
@import ImageIO;
@import MobileCoreServices;
@import WireCryptobox;

#import "ZMClientMessage.h"
#import "ZMConversation+Internal.h"
#import "ZMConversation+Transport.h"
#import "ZMUpdateEvent+WireDataModel.h"
#import "ZMGenericMessage+UpdateEvent.h"

#import "ZMGenericMessageData.h"
#import "ZMUser+Internal.h"
#import "ZMOTRMessage.h"
#import "ZMGenericMessage+External.h"
#import <WireDataModel/WireDataModel-Swift.h>

static NSString * const ClientMessageDataSetKey = @"dataSet";
static NSString * const ClientMessageGenericMessageKey = @"genericMessage";
static NSString * const ClientMessageUpdateTimestamp = @"updatedTimestamp";

NSString * const ZMClientMessageLinkPreviewStateKey = @"linkPreviewState";
NSString * const ZMClientMessageLinkPreviewKey = @"linkPreview";
NSString * const ZMFailedToCreateEncryptedMessagePayloadString = @"💣";
// From https://github.com/wearezeta/generic-message-proto:
// "If payload is smaller then 256KB then OM can be sent directly"
// Just to be sure we set the limit lower, to 128KB (base 10)
NSUInteger const ZMClientMessageByteSizeExternalThreshold = 128000;

@interface ZMClientMessage()

@property (nonatomic) ZMGenericMessage *genericMessage;

@end

@interface ZMClientMessage (ZMKnockMessageData) <ZMKnockMessageData>

@end

@interface ZMClientMessage (ZMLocationMessageData) <ZMLocationMessageData>

@end

@interface ZMClientMessage (ZMTextMessageData) <ZMTextMessageData>

@end

@implementation ZMClientMessage

@dynamic updatedTimestamp;

@synthesize genericMessage = _genericMessage;

- (void)awakeFromInsert;
{
    [super awakeFromInsert];
    self.nonce = nil;
}

+ (NSString *)entityName;
{
    return @"ClientMessage";
}

- (NSSet *)ignoredKeys
{
    return [[super ignoredKeys] setByAddingObject:ClientMessageUpdateTimestamp];
}

- (NSDate *)updatedAt
{
    return self.updatedTimestamp;
}

- (void)addData:(NSData *)data
{
    if (data == nil) {
        return;
    }
    
    ZMGenericMessageData *messageData = [self mergeWithExistingData:data];
    [self setGenericMessage:self.genericMessageFromDataSet];
    
    if (self.nonce == nil) {
        self.nonce = [NSUUID uuidWithTransportString:messageData.genericMessage.messageId];
    }
    
    [self updateCategoryCache];
    [self setLocallyModifiedKeys:[NSSet setWithObject:ClientMessageDataSetKey]];
}

- (ZMGenericMessage *)genericMessage
{
    if (_genericMessage == nil) {
        _genericMessage = [self genericMessageFromDataSet] ?: (ZMGenericMessage *)[NSNull null];
    }
    if (_genericMessage == (ZMGenericMessage *)[NSNull null]) {
        return nil;
    }
    return _genericMessage;
}

- (ZMGenericMessageData *)mergeWithExistingData:(NSData *)data
{
    _genericMessage = nil;
    ZMGenericMessageData *existingMessageData = [self.dataSet firstObject];
    
    if (existingMessageData != nil) {
        existingMessageData.data = data;        
        return existingMessageData;
    }
    else {
        ZMGenericMessageData *messageData = [NSEntityDescription insertNewObjectForEntityForName:[ZMGenericMessageData entityName] inManagedObjectContext:self.managedObjectContext];
        messageData.data = data;
        messageData.message = self;
        return messageData;
    }
}

- (void)setGenericMessage:(ZMGenericMessage *)genericMessage
{
    if ([genericMessage knownMessage] && genericMessage.imageAssetData == nil) {
        _genericMessage = genericMessage;
    }
}

- (void)awakeFromFetch
{
    [super awakeFromFetch];
    _genericMessage = nil;
}

- (void)awakeFromSnapshotEvents:(NSSnapshotEventType)flags
{
    [super awakeFromSnapshotEvents:flags];
    _genericMessage = nil;
}

- (void)didTurnIntoFault
{
    [super didTurnIntoFault];
    _genericMessage = nil;
}

- (ZMGenericMessage *)genericMessageFromDataSet
{
    NSArray <ZMGenericMessage *> *filteredMessages = [[self.dataSet.array mapWithBlock:^ZMGenericMessage *(ZMGenericMessageData *data) {
        return data.genericMessage;
    }] filterWithBlock:^BOOL(ZMGenericMessage *message) {
        return [message knownMessage] && message.imageAssetData == nil;
    }];

    if (0 == filteredMessages.count) {
        return nil;
    }
    
    ZMGenericMessageBuilder *builder = ZMGenericMessage.builder;
    for (ZMGenericMessage *message in filteredMessages) {
        [builder mergeFrom:message];
    }
    
    return builder.build;
}

+ (NSSet *)keyPathsForValuesAffectingGenericMessage
{
    return [NSSet setWithObject:ClientMessageDataSetKey];
}

- (void)updateWithGenericMessage:(ZMGenericMessage *)message updateEvent:(ZMUpdateEvent *__unused)updateEvent
{
    [self addData:message.data];
    [self updateNormalizedText];
}

- (void)deleteContent
{
    _genericMessage = nil;
    self.dataSet = [NSOrderedSet orderedSet];
    self.normalizedText = nil;
    self.genericMessage = nil;
}

- (void)removeMessageClearingSender:(BOOL)clearingSender
{
    [self deleteContent];
    [super removeMessageClearingSender:clearingSender];
}

- (void)expire
{
    if (self.genericMessage.hasEdited) {
        // Fetch original message
        NSUUID *originalID = [NSUUID uuidWithTransportString:self.genericMessage.edited.replacingMessageId];
        ZMMessage *originalMessage = [ZMMessage fetchMessageWithNonce:originalID forConversation:self.conversation inManagedObjectContext:self.managedObjectContext];
        
        // Replace the nonce with the original
        // This way if we get a delete from a different device while we are waiting for the response it will delete this message
        self.nonce = originalID;
        
        // delete the original message - we do not care about the old one anymore
        [self.managedObjectContext deleteObject:originalMessage];
    }
    [super expire];
}

- (void)resend
{
    if (self.genericMessage.hasEdited) {
        NOT_USED([ZMMessage edit:self newText:self.textMessageData.messageText]);
    } else {
        [super resend];
    }
}

- (id<ZMTextMessageData>)textMessageData
{
    if (self.genericMessage.textData != nil) {
        return self;
    }
    return nil;
}

- (id<ZMImageMessageData>)imageMessageData
{
    return nil;
}

- (id<ZMKnockMessageData>)knockMessageData
{
    if (self.genericMessage.knockData != nil) {
        return self;
    }
    return nil;
}

- (id<ZMFileMessageData>)fileMessageData
{
    return nil;
}

- (id<ZMLocationMessageData>)locationMessageData
{
    if (self.genericMessage.locationData != nil) {
        return self;
    }
    return nil;
}

- (void)updateWithPostPayload:(NSDictionary *)payload updatedKeys:(__unused NSSet *)updatedKeys
{
    // we don't want to update the conversation if the message is a confirmation message
    if (self.genericMessage.hasConfirmation || self.genericMessage.hasReaction)
    {
        return;
    }
    if (self.genericMessage.hasDeleted) {
        NSUUID *originalID = [NSUUID uuidWithTransportString:self.genericMessage.deleted.messageId];
        ZMMessage *original = [ZMMessage fetchMessageWithNonce:originalID forConversation:self.conversation inManagedObjectContext:self.managedObjectContext];
        original.sender = nil;
        original.senderClientID = nil;
    } else if (self.genericMessage.hasEdited) {
        NSUUID *nonce = [self nonceFromPostPayload:payload];
        if (nonce != nil && ![self.nonce isEqual:nonce]) {
            ZMLogWarn(@"send message response nonce does not match");
            return;
        }
        NSDate *serverTimestamp = [payload dateForKey:@"time"];
        if (serverTimestamp != nil) {
            self.updatedTimestamp = serverTimestamp;
        }
        NSUUID *originalID = [NSUUID uuidWithTransportString:self.genericMessage.edited.replacingMessageId];
        ZMMessage *original = [ZMMessage fetchMessageWithNonce:originalID forConversation:self.conversation inManagedObjectContext:self.managedObjectContext];
        [original removeMessageClearingSender:NO];
    } else {
        [super updateWithPostPayload:payload updatedKeys:nil];
    }
}

+ (NSPredicate *)predicateForObjectsThatNeedToBeInsertedUpstream
{
    NSPredicate *encryptedNotSynced = [NSPredicate predicateWithFormat:@"%K == FALSE", DeliveredKey];
    NSPredicate *notExpired = [NSPredicate predicateWithFormat:@"%K == 0", ZMMessageIsExpiredKey];
    return [NSCompoundPredicate andPredicateWithSubpredicates:@[encryptedNotSynced, notExpired]];
}

- (void)markAsSent
{
    [super markAsSent];
    if (self.linkPreviewState == ZMLinkPreviewStateUploaded) {
        self.linkPreviewState = ZMLinkPreviewStateDone;
    }
    [self setObfuscationTimerIfNeeded];
}

- (void)setObfuscationTimerIfNeeded
{
    if (!self.isEphemeral) {
        return;
    }
    if (self.genericMessage.textData != nil && self.genericMessage.linkPreviews.count > 0 &&
        self.linkPreviewState != ZMLinkPreviewStateDone)
    {
        // If we have link previews and they are not sent yet, we wait until they are sent
        return;
    }
    [self startDestructionIfNeeded];
}

- (BOOL)hasDownloadedImage
{
    if (nil != self.textMessageData && nil != self.textMessageData.linkPreview) {
        return [self.managedObjectContext.zm_imageAssetCache assetData:self.nonce format:ZMImageFormatMedium encrypted:NO] != nil // processed or downloaded
        || [self.managedObjectContext.zm_imageAssetCache assetData:self.nonce format:ZMImageFormatOriginal encrypted:NO] != nil; // original
    }
    return false;
}

@end


@implementation ZMClientMessage (ZMKnockMessage)

@end

#pragma mark - ZMLocationMessageData

@implementation ZMClientMessage (ZMLocationMessageData)

- (float)latitude
{
    return self.genericMessage.locationData.latitude;
}

- (float)longitude
{
    return self.genericMessage.locationData.longitude;
}

- (NSString *)name
{
    return self.genericMessage.locationData.name.stringByRemovingExtremeCombiningCharacters;
}

- (int32_t)zoomLevel
{
    return self.genericMessage.locationData.zoom ?: 0;
}

@end


@implementation ZMClientMessage (ZMTextMessageData)

- (NSString *)messageText
{
    return self.genericMessage.textData.content.stringByRemovingExtremeCombiningCharacters;
}

- (BOOL)isEdited
{
    return self.genericMessage.hasEdited;
}

@end



@implementation ZMClientMessage (Ephemeral)

- (BOOL)isEphemeral
{
    return self.destructionDate != nil || self.genericMessage.hasEphemeral || self.isObfuscated;
}

- (NSTimeInterval)deletionTimeout
{
    if (self.isEphemeral) {
        return self.genericMessage.ephemeral.expireAfterMillis/1000;
    }
    return -1;
}

- (void)obfuscate;
{
    [super obfuscate];
    if (self.genericMessage.knockData == nil) {
        ZMGenericMessage *obfuscatedMessage = [self.genericMessage obfuscatedMessage];
        [self deleteContent];
        if (obfuscatedMessage != nil) {
            [self mergeWithExistingData:obfuscatedMessage.data];
            [self setGenericMessage:self.genericMessageFromDataSet];
        }
    }
}

@end



