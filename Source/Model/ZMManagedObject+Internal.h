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
@import CoreGraphics;

#import "ZMManagedObject.h"

typedef void(^ObjectsEnumerationBlock)(ZMManagedObject * _Nonnull, BOOL * _Nonnull stop);
extern NSString * _Nonnull const ZMManagedObjectLocallyModifiedDataFieldsKey;



@interface ZMManagedObject (Internal)

+ (nonnull NSString *)entityName; ///< subclasses must implement this
+ (nullable NSString *)sortKey; ///< subclasses must implement this or @c +defaultSortDescriptors
+ (nullable NSString *)remoteIdentifierDataKey; ///< subclasses must implement this
+ (BOOL)hasLocallyModifiedDataFields;

+ (nonnull instancetype)insertNewObjectInManagedObjectContext:(nonnull NSManagedObjectContext *)moc;

/// Whether this object has all data from the backend
@property (nonatomic) BOOL needsToBeUpdatedFromBackend;

/// Handles conversion from and to NSUUID and NSData in CoreData
- (nullable NSUUID *)transientUUIDForKey:(nonnull NSString *)key;
- (void)setTransientUUID:(nullable NSUUID *)newUUID forKey:(nonnull NSString *)key;

/// Handles conversion from and to CGSize and NSData in CoreData
- (CGSize)transientCGSizeForKey:(nonnull NSString *)key;
- (void)setTransientCGSize:(CGSize)size forKey:(nonnull NSString *)key;

/// Defaults to a single sort descriptor based on @c sortKey
+ (nullable NSArray <NSSortDescriptor *> *)defaultSortDescriptors;
/// The order in which objects are updated to / from the backend. ZMSyncOperationSet uses this.
+ (nullable NSArray <NSSortDescriptor *> *)sortDescriptorsForUpdating;
+ (nullable NSPredicate *)predicateForFilteringResults;
+ (nullable NSFetchRequest *)sortedFetchRequest;
+ (nullable NSFetchRequest *)sortedFetchRequestWithPredicate:(nonnull NSPredicate *)predicate;
+ (nullable NSFetchRequest *)sortedFetchRequestWithPredicateFormat:(nonnull NSString *)format, ...;

+ (void)enumerateObjectsInContext:(nonnull NSManagedObjectContext *)moc withBlock:(nonnull ObjectsEnumerationBlock)block;

+ (nullable instancetype)fetchObjectWithRemoteIdentifier:(nonnull NSUUID *)uuid inManagedObjectContext:(nonnull NSManagedObjectContext *)moc;
+ (nullable NSOrderedSet *)fetchObjectsWithRemoteIdentifiers:(nonnull NSOrderedSet <NSUUID *> *)uuids inManagedObjectContext:(nonnull NSManagedObjectContext *)moc;

@end



/// This category is about persistent change tracking.
/// It tracks if changes to objects are made by the UI (and need to be pushed to the backend), or
/// are originating from the server, i.e. a given value is "up to date".
@interface ZMManagedObject (PersistentChangeTracking)

/// The keys that are not to be tracked. Subclasses can / should override this.
@property (nonatomic, readonly, nullable) NSSet *ignoredKeys;

/// Returns a predicate that will match objects which need additional data from the backend.
+ (nullable NSPredicate *)predicateForNeedingToBeUpdatedFromBackend;

/// Returns a predicate that will match objects that have local modifications that need to be pushed to the backend
+ (nullable NSPredicate *)predicateForObjectsThatNeedToBeUpdatedUpstream;

/// Returns a predicate that will match objects that we need to create on the backend
/// For most classes this will be "remoteIdentifier_data == nil"
+ (nullable NSPredicate *)predicateForObjectsThatNeedToBeInsertedUpstream;

/// Returns the key (attributes) that have been locally modified (by the UI).
@property (nonatomic, readonly, nonnull) NSSet *keysThatHaveLocalModifications;

/// Similar to keysThatHaveLocalModifications but allows passing in a snapshot as a dictionary.
/// Used for merging.
- (BOOL)hasLocalModificationsForKey:(nonnull NSString *)key withModifiedFlag:(nullable NSNumber *)n;

/// Removes the given @c keys from the set of keys that have been modified by the UI
- (void)resetLocallyModifiedKeys:(nonnull NSSet *)keys;

/// Adds the given @c keys to the set of keys that have been modified by the UI
- (void)setLocallyModifiedKeys:(nonnull NSSet *)keys;

/// Returns @C YES if the receiver has local modifications for any of the given @c keys
- (BOOL)hasLocalModificationsForKeys:(nonnull NSSet *)keys;
- (BOOL)hasLocalModificationsForKey:(nonnull NSString *)key;


- (nonnull NSArray <NSString *> *)keysTrackedForLocalModifications ZM_REQUIRES_SUPER;
- (void)updateKeysThatHaveLocalModifications ZM_REQUIRES_SUPER;

@end

