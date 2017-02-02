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
@import CoreData;
@class ZMConversationList;
@class ZMSharableConversations;
@class NSManagedObjectContext;


@interface ZMConversationListDirectory : NSObject

@property (nonatomic, readonly, nonnull) ZMConversationList* unarchivedConversations; ///< archived, not pending
@property (nonatomic, readonly, nonnull) ZMConversationList* conversationsIncludingArchived; ///< unarchived, not pending,
@property (nonatomic, readonly, nonnull) ZMConversationList* archivedConversations; ///< archived, not pending
@property (nonatomic, readonly, nonnull) ZMConversationList* pendingConnectionConversations; ///< pending
@property (nonatomic, readonly, nonnull) ZMConversationList *clearedConversations; /// conversations with deleted messages (clearedTimestamp is set)

- (nonnull NSArray *)allConversationLists;

/// Refetches all conversation lists
/// Call this when the app re-enters the foreground
- (void)refetchAllListsInManagedObjectContext:(NSManagedObjectContext * _Nonnull)moc;

@end



@interface NSManagedObjectContext (ZMConversationListDirectory)

- (nonnull ZMConversationListDirectory *)conversationListDirectory;

@end
