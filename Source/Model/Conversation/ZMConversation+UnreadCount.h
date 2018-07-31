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


@class ZMConversation;
@class ZMMessage;

@interface ZMConversation (UnreadCount)

/// internalEstimatedUnreadCount can only be set from the syncMOC
/// It is calculated by counting the unreadTimeStamps which are managed on the sync context
@property (nonatomic) int64_t internalEstimatedUnreadCount;

/// hasUnreadUnsentMessage is set when a message expires
/// and reset when the visible window changes
@property (nonatomic) BOOL hasUnreadUnsentMessage;

@property (nonatomic, readonly) ZMConversationListIndicator unreadListIndicator;
+ (NSSet *)keyPathsForValuesAffectingUnreadListIndicator;

/// Predicate for conversations that will be considered unread for the purpose of the badge count
+ (NSPredicate *)predicateForConversationConsideredUnread;

/// Predicate for conversations that will be considered unread for the purpose of the back arrow dot
+ ( NSPredicate *)predicateForConversationConsideredUnreadIncludingSilenced;

/// Count of unread conversations (exluding silenced converations)
+ (NSUInteger)unreadConversationCountInContext:(NSManagedObjectContext *)moc;

/// Count of unread conversations (including silenced conversations)
+ (NSUInteger)unreadConversationCountIncludingSilencedInContext:(NSManagedObjectContext *)moc excluding:(ZMConversation *)conversation;

@end


/// use this for testing only
@interface ZMConversation (Internal_UnreadCount)

/// lastUnreadKnockDate can only be set from the syncMOC
/// if this is nil, there is no unread knockMessage
@property (nonatomic) NSDate *lastUnreadKnockDate;
/// lastUnreadMissedCallDate can only be set from the syncMOC
/// if this is nil, there is no unread missed call
@property (nonatomic) NSDate *lastUnreadMissedCallDate;


@property (nonatomic, readonly) BOOL hasUnreadKnock;
@property (nonatomic, readonly) BOOL hasUnreadMissedCall;

@end

