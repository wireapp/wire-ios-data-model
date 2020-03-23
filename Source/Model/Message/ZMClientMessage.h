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


@import WireImages;
#import "ZMMessage+Internal.h"
#import "ZMOTRMessage.h"

@class UserClient;
@class EncryptionSessionsDirectory;
@protocol ZMConversationMessage;

extern NSString * _Nonnull const ZMFailedToCreateEncryptedMessagePayloadString;
extern NSUInteger const ZMClientMessageByteSizeExternalThreshold;
extern NSString * _Nonnull const ZMClientMessageLinkPreviewStateKey;
extern NSString * _Nonnull const ZMClientMessageLinkPreviewKey;


@interface ZMClientMessage : ZMOTRMessage

/// Link Preview state
@property (nonatomic) NSDate * _Nullable updatedTimestamp;

- (void)addData:(NSData * _Nonnull)data;
- (void)deleteContent;

- (BOOL)hasDownloadedImage;

@end
