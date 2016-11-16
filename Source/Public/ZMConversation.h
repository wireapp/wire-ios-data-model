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


@import ZMCSystem;

#import "ZMManagedObject.h"
#import "ZMMessage.h"
#import "ZMManagedObjectContextProvider.h"


@class ZMUser;
@class ZMMessage;
@class ZMTextMessage;
@class ZMImageMessage;
@class ZMKnockMessage;
@class ZMConversationList;
@class ZMFileMetadata;
@class ZMLocationData;
@class LinkPreview;

@protocol ZMConversationMessage;

typedef NS_ENUM(int16_t, ZMConversationType) {
    ZMConversationTypeInvalid = 0,

    ZMConversationTypeSelf,
    ZMConversationTypeOneOnOne,
    ZMConversationTypeGroup,
    ZMConversationTypeConnection, // Incoming & outgoing connection request
};

/// The current indicator to be shown for a conversation in the conversation list.
typedef NS_ENUM(int16_t, ZMConversationListIndicator) {
    ZMConversationListIndicatorInvalid = 0,
    ZMConversationListIndicatorNone,
    ZMConversationListIndicatorUnreadMessages,
    ZMConversationListIndicatorKnock,
    ZMConversationListIndicatorMissedCall,
    ZMConversationListIndicatorExpiredMessage,
    ZMConversationListIndicatorActiveCall, ///< Ringing or talking in call.
    ZMConversationListIndicatorInactiveCall, ///< Other people are having a call but you are not in it.
    ZMConversationListIndicatorPending
};


extern NSString * _Null_unspecified const ZMConversationFailedToDecryptMessageNotificationName;
extern NSString * _Null_unspecified const ZMIsDimmedKey; ///< Specifies that a range in an attributed string should be displayed dimmed.
extern NSString * _Null_unspecified const ZMConversationIsVerifiedNotificationName;


@interface ZMConversation : ZMManagedObject

@property (nonatomic, copy, nullable) NSString *userDefinedName;
@property (nonatomic, readonly, nonnull) NSString *displayName;

@property (readonly, nonatomic) ZMConversationType conversationType;
@property (readonly, nonatomic, nonnull) NSDate *lastModifiedDate;
@property (readonly, nonatomic, nonnull) NSOrderedSet *messages;
@property (readonly, nonatomic, nonnull) NSOrderedSet<ZMUser *> *activeParticipants;
@property (readonly, nonatomic, nonnull) ZMUser *creator;
@property (nonatomic, readonly) BOOL isPendingConnectionConversation;
@property (nonatomic, readonly) NSUInteger estimatedUnreadCount;
@property (nonatomic, readonly) ZMConversationListIndicator conversationListIndicator;
@property (nonatomic, readonly) BOOL hasDraftMessageText;
@property (nonatomic, copy, nullable) NSString *draftMessageText;

/// This is read only. Use -setVisibleWindowFromMessage:toMessage: to update this.
/// This will return @c nil if the last read message has not yet been sync'd to this device, or if the conversation has no last read message.
@property (nonatomic, readonly, nullable) ZMMessage *lastReadMessage;

@property (nonatomic) BOOL isSilenced;
@property (nonatomic) BOOL isMuted DEPRECATED_ATTRIBUTE;
@property (nonatomic) BOOL isArchived;

/// True only if every active client in this conversation is trusted by self client
@property (nonatomic, getter=trusted) BOOL isTrusted;

/// If true the conversation might still be trusted / ignored
@property (nonatomic, readonly) BOOL hasUntrustedClients;

/// returns whether the user is allowed to write to this conversation
@property (nonatomic, readonly) BOOL isReadOnly;


/// For group conversation this will be nil, for one to one or connection conversation this will be the other user
@property (nonatomic, readonly, nullable) ZMUser *connectedUser;

/// Defines the time interval until an inserted messages is deleted / "self-destructs" on all clients
/// Use [updateMessageDestructionTimeout:(ZMConversationMessageDestructionTimeout)timeout] for setting it
/// Or import the internal header for testing
@property (nonatomic, readonly) NSTimeInterval messageDestructionTimeout;

- (void)addParticipant:(nonnull ZMUser *)participant;
- (void)removeParticipant:(nonnull ZMUser *)participant;

/// This method loads messages in a window when there are visible messages
- (void)setVisibleWindowFromMessage:(nullable ZMMessage *)oldestMessage toMessage:(nullable ZMMessage *)newestMessage;

/// completes a pending lastRead save, e.g. when leaving the conversation view
- (void)savePendingLastRead;

- (nonnull id<ZMConversationMessage>)appendKnock;

+ (nonnull instancetype)insertGroupConversationIntoUserSession:(nonnull id<ZMManagedObjectContextProvider> )session withParticipants:(nonnull NSArray<ZMUser *> *)participants;
/// If that conversation exists, it is returned, @c nil otherwise.
+ (nullable instancetype)existingOneOnOneConversationWithUser:(nonnull ZMUser *)otherUser inUserSession:(nonnull id<ZMManagedObjectContextProvider> )session;

/// It's safe to pass @c nil. Returns @c nil if no message was inserted.
- (nullable id <ZMConversationMessage>)appendMessageWithText:(nullable NSString *)text;

/// The given URL must be a file URL. It's safe to pass @c nil. Returns @c nil if no message was inserted.
- (nullable id<ZMConversationMessage>)appendMessageWithImageAtURL:(nonnull NSURL *)fileURL;
/// The given data must be compressed image dat, e.g. JPEG data. It's safe to pass @c nil. Returns @c nil if no message was inserted.
- (nullable id<ZMConversationMessage>)appendMessageWithImageData:(nonnull NSData *)imageData;
- (nullable id<ZMConversationMessage>)appendMessageWithImageData:(nonnull NSData *)imageData version3:(BOOL)version3;
/// Appends a file. see ZMFileMetaData, ZMAudioMetaData, ZMVideoMetaData.
- (nullable id<ZMConversationMessage>)appendMessageWithFileMetadata:(nonnull ZMFileMetadata *)fileMetadata;
- (nullable id<ZMConversationMessage>)appendMessageWithFileMetadata:(nonnull ZMFileMetadata *)fileMetadata version3:(BOOL)version3;

/// Appends a location, see @c LocationData.
- (nullable id<ZMConversationMessage>)appendMessageWithLocationData:(nonnull ZMLocationData *)locationData;

/// Resend last non sent messages
- (void)resendLastUnsentMessages;

@end

@interface ZMConversation (History)

/// This will reset the message history to the last message in the conversation.
- (void)clearMessageHistory;

/// UI should call this method on opening cleared conversation.
- (void)revealClearedConversation;

@end



@interface ZMConversation (Connections)

/// The message that was sent as part of the connection request.
@property (nonatomic, copy, readonly, nonnull) NSString *connectionMessage;

@end


