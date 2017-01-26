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


#import "NSManagedObjectContext+zmessaging.h"
#import "ZMConversation+Internal.h"
#import "ZMConnection+Internal.h"
#import "ZMNotifications.h"
#import "ZMConversationListDirectory.h"
#import <ZMCDataModel/ZMCDataModel-Swift.h>

@import CoreData;

@interface ZMConversationList ()

@property (nonatomic, weak) NSManagedObjectContext* moc;
@property (nonatomic) NSMutableArray *backingList;
@property (nonatomic, readonly) NSSet *conversationKeysAffectingSorting;
@property (nonatomic) NSPredicate *filteringPredicate;
@property (nonatomic) NSArray *sortDescriptors;
@property (nonatomic, copy) NSString *customDebugDescription;

@end



@implementation ZMConversationList

- (instancetype)init;
{
    Require(NO);
    self = [super init];
    NOT_USED(self);
    return nil;

}

- (instancetype)initWithObjects:(const id [])objects count:(NSUInteger)cnt;
{
    Require(NO);
    self = [super initWithObjects:objects count:cnt];
    NOT_USED(self);
    return nil;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder;
{
    Require(NO);
    self = [super initWithCoder:aDecoder];
    NOT_USED(self);
    return nil;
}

- (instancetype)initWithAllConversations:(NSArray *)conversations filteringPredicate:(NSPredicate *)filteringPredicate moc:(NSManagedObjectContext *)moc debugDescription:(NSString *)debugDescription;
{
    self = [super init];
    if (self) {
        self.moc = moc;
        _identifier = debugDescription;
        self.customDebugDescription = debugDescription;
        self.filteringPredicate = filteringPredicate;
        self.sortDescriptors = [ZMConversation defaultSortDescriptors];
        [self calculateKeysAffectingPredicateAndSort];
        [self createBackingList:conversations];
        [moc.conversationListObserverCenter startObservingList:self];
    }
    return self;
}

- (NSManagedObjectContext *)managedObjectContext
{
    return self.moc;
}

- (void)recreateWithAllConversation:(NSArray *)conversations
{
    [self createBackingList:conversations];
    [self.moc.conversationListObserverCenter recreateSnapshotFor:self];
}

- (void)calculateKeysAffectingPredicateAndSort;
{
    NSMutableSet *keysAffectingSorting = [NSMutableSet set];
    for (NSSortDescriptor *sd in self.sortDescriptors) {
        NSString *key = sd.key;
        if (key != nil) {
            [keysAffectingSorting addObject:key];
        }
    }
    _conversationKeysAffectingSorting = [[keysAffectingSorting copy] setByAddingObject:ZMConversationListIndicatorKey];
}

- (void)createBackingList:(NSArray *)conversations
{
    NSArray *filtered = [conversations filteredArrayUsingPredicate:self.filteringPredicate];
    self.backingList = [[filtered sortedArrayUsingDescriptors:[ZMConversation defaultSortDescriptors]] mutableCopy];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.managedObjectContext.conversationListObserverCenter removeConversationList:self];
}

- (void)sortInsertConversation:(ZMConversation *)conversation
{
    NSUInteger const idx = [self.backingList indexOfObject:conversation
                                             inSortedRange:NSMakeRange(0, self.backingList.count)
                                                   options:NSBinarySearchingInsertionIndex
                                           usingComparator:self.comparator];
    [self.backingList insertObject:conversation atIndex:idx];
}

- (NSComparator)comparator
{
    return ^NSComparisonResult(ZMConversation *c1, ZMConversation* c2){
        if(c1.conversationListIndicator == ZMConversationListIndicatorActiveCall && c2.conversationListIndicator != ZMConversationListIndicatorActiveCall) {
            return NSOrderedAscending;
        } else if(c2.conversationListIndicator == ZMConversationListIndicatorActiveCall && c1.conversationListIndicator != ZMConversationListIndicatorActiveCall) {
            return NSOrderedDescending;
        }

        for (NSSortDescriptor *sd in self.sortDescriptors) {
            NSComparisonResult const r = [sd compareObject:c1 toObject:c2];
            if (r != NSOrderedSame) {
                return r;
            }
        }
        return NSOrderedSame;
    };
}

- (NSUInteger)count;
{
    return self.backingList.count;
}

- (id)objectAtIndex:(NSUInteger)index;
{
    return [self.backingList objectAtIndex:index];
}

- (NSUInteger)indexOfObject:(id)anObject;
{
    return [self.backingList indexOfObjectIdenticalTo:anObject];
}

- (NSString *)shortDescription
{
    return [NSString stringWithFormat:@"<%@: %p> %@ (predicate: %@)", self.class, self, self.customDebugDescription, self.filteringPredicate];
}

- (NSString *)description
{
    return [[[self shortDescription] stringByAppendingString:@"\n"] stringByAppendingString:[super description]];
}

- (void)resort
{
    [self.backingList sortUsingComparator:self.comparator];
}

@end



@implementation ZMConversationList (ZMUpdates)

- (BOOL)predicateMatchesConversation:(ZMConversation *)conversation;
{
    return [self.filteringPredicate evaluateWithObject:conversation];
}

- (BOOL)sortingIsAffectedByConversationKeys:(NSSet *)conversationKeys
{
    return [self.conversationKeysAffectingSorting intersectsSet:conversationKeys];
}

- (void)resortConversation:(ZMConversation *)conversation;
{
    [self.backingList removeObject:conversation];
    [self sortInsertConversation:conversation];
}

- (void)removeConversations:(NSSet *)conversations
{
    [self.backingList removeObjectsInArray:conversations.allObjects];
}

- (void)insertConversations:(NSSet *)conversations
{
    NSMutableSet *conversationsNotInList = [conversations mutableCopy];
    [conversationsNotInList minusSet:[NSSet setWithArray:self.backingList]];
    for(ZMConversation *conversation in conversationsNotInList) {
        [self sortInsertConversation:conversation];
    }
}

@end


@implementation ZMConversationList (UserSession)

+ (void)refetchAllListsInUserSession:(id<ZMManagedObjectContextProvider>)session;
{
    [session.managedObjectContext.conversationListDirectory refetchAllListsInManagedObjectContext:session.managedObjectContext];
}

+ (ZMConversationList *)conversationsIncludingArchivedInUserSession:(id<ZMManagedObjectContextProvider>)session;
{
    VerifyReturnNil(session != nil);
    return [session.managedObjectContext.conversationListDirectory conversationsIncludingArchived];
}

+ (ZMConversationList *)conversationsInUserSession:(id<ZMManagedObjectContextProvider>)session
{
    VerifyReturnNil(session != nil);
    return [session.managedObjectContext.conversationListDirectory unarchivedAndNotCallingConversations];
}

+ (ZMConversationList *)archivedConversationsInUserSession:(id<ZMManagedObjectContextProvider>)session;
{
    VerifyReturnNil(session != nil);
    return [session.managedObjectContext.conversationListDirectory archivedConversations];
}

+ (ZMConversationList *)nonIdleVoiceChannelConversationsInUserSession:(id<ZMManagedObjectContextProvider>)session;
{
    VerifyReturnNil(session != nil);
    return [session.managedObjectContext.conversationListDirectory nonIdleVoiceChannelConversations];
}

+ (ZMConversationList *)activeCallConversationsInUserSession:(id<ZMManagedObjectContextProvider>)session;
{
    VerifyReturnNil(session != nil);
    return [session.managedObjectContext.conversationListDirectory activeCallConversations];
}

+ (ZMConversationList *)pendingConnectionConversationsInUserSession:(id<ZMManagedObjectContextProvider>)session;
{
    VerifyReturnNil(session != nil);
    return [session.managedObjectContext.conversationListDirectory pendingConnectionConversations];
}

+ (ZMConversationList *)clearedConversationsInUserSession:(id<ZMManagedObjectContextProvider>)session;
{
    VerifyReturnNil(session != nil);
    return [session.managedObjectContext.conversationListDirectory clearedConversations];
}

@end
