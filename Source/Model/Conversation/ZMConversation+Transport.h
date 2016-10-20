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


#import "ZMConversation.h"

@class ZMUpdateEvent;
typedef NS_ENUM(int, ZMBackendConversationType) {
    ZMConvTypeGroup = 0,
    ZMConvTypeSelf = 1,
    ZMConvOneToOne = 2,
    ZMConvConnection = 3,
};

extern NSString *const ZMConversationInfoOTRMutedValueKey;
extern NSString *const ZMConversationInfoOTRMutedReferenceKey;
extern NSString *const ZMConversationInfoOTRArchivedValueKey;
extern NSString *const ZMConversationInfoOTRArchivedReferenceKey;

@interface ZMConversation (Transport)

- (void)updateLastReadFromPostPayloadEvent:(ZMUpdateEvent *)event;
- (void)updateClearedFromPostPayloadEvent:(ZMUpdateEvent *)event;
- (void)updateWithTransportData:(NSDictionary *)transportData;

- (void)updatePotentialGapSystemMessagesIfNeededWithUsers:(NSSet <ZMUser *>*)users;

/// Pass timeStamp when the timeStamp equals the time of the lastRead / cleared event, otherwise pass nil
- (void)updateSelfStatusFromDictionary:(NSDictionary *)dictionary timeStamp:(NSDate *)timeStamp;

+ (ZMConversationType)conversationTypeFromTransportData:(NSNumber *)transportType;

- (void)unarchiveConversationFromEvent:(ZMUpdateEvent *)event;
- (BOOL)shouldAddEvent:(ZMUpdateEvent *)event;

@end
