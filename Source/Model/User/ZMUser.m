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
@import WireUtilities;
@import WireCryptobox;
@import WireProtos;
@import WireTransport;
@import Foundation;

#import "ZMManagedObject+Internal.h"
#import "ZMUser+Internal.h"
#import "NSManagedObjectContext+zmessaging.h"
#import "ZMUser+Internal.h"
#import "ZMConnection+Internal.h"
#import "ZMConversation+Internal.h"
#import "NSString+ZMPersonName.h"
#import <CommonCrypto/CommonKeyDerivation.h>
#import <CommonCrypto/CommonCryptoError.h>
#import "NSPredicate+ZMSearch.h"
#import "ZMAddressBookContact.h"
#import <WireDataModel/WireDataModel-Swift.h>


NSString *const SessionObjectIDKey = @"ZMSessionManagedObjectID";
NSString *const ZMUserActiveConversationsKey = @"activeConversations";

static NSString *const ZMPersistedClientIdKey = @"PersistedClientId";

static NSString *const AccentKey = @"accentColorValue";
static NSString *const SelfUserObjectIDAsStringKey = @"SelfUserObjectID";
static NSString *const SelfUserObjectIDKey = @"ZMSelfUserManagedObjectID";

static NSString *const SessionObjectIDAsStringKey = @"SessionObjectID";
static NSString *const SelfUserKey = @"ZMSelfUser";
static NSString *const NormalizedNameKey = @"normalizedName";
static NSString *const NormalizedEmailAddressKey = @"normalizedEmailAddress";
static NSString *const RemoteIdentifierKey = @"remoteIdentifier";

static NSString *const ConversationsCreatedKey = @"conversationsCreated";
static NSString *const ActiveCallConversationsKey = @"activeCallConversations";
static NSString *const ConnectionKey = @"connection";
static NSString *const EmailAddressKey = @"emailAddress";
static NSString *const PhoneNumberKey = @"phoneNumber";
static NSString *const LastServerSyncedActiveConversationsKey = @"lastServerSyncedActiveConversations";
static NSString *const LocalMediumRemoteIdentifierDataKey = @"localMediumRemoteIdentifier_data";
static NSString *const LocalMediumRemoteIdentifierKey = @"localMediumRemoteIdentifier";
static NSString *const LocalSmallProfileRemoteIdentifierKey = @"localSmallProfileRemoteIdentifier";
static NSString *const LocalSmallProfileRemoteIdentifierDataKey = @"localSmallProfileRemoteIdentifier_data";
static NSString *const MediumRemoteIdentifierDataKey = @"mediumRemoteIdentifier_data";
static NSString *const MediumRemoteIdentifierKey = @"mediumRemoteIdentifier";
static NSString *const SmallProfileRemoteIdentifierDataKey = @"smallProfileRemoteIdentifier_data";
static NSString *const SmallProfileRemoteIdentifierKey = @"smallProfileRemoteIdentifier";
static NSString *const NameKey = @"name";
static NSString *const HandleKey = @"handle";
static NSString *const ImageMediumDataKey = @"imageMediumData";
static NSString *const ImageSmallProfileDataKey = @"imageSmallProfileData";
static NSString *const SystemMessagesKey = @"systemMessages";
static NSString *const ShowingUserAddedKey = @"showingUserAdded";
static NSString *const ShowingUserRemovedKey = @"showingUserRemoved";
NSString *const UserClientsKey = @"clients";
static NSString *const ReactionsKey = @"reactions";
static NSString *const AddressBookEntryKey = @"addressBookEntry";
static NSString *const MembershipKey = @"membership";
static NSString *const CreatedTeamsKey = @"createdTeams";

@interface ZMBoxedSelfUser : NSObject

@property (nonatomic, weak) ZMUser *selfUser;

@end



@implementation ZMBoxedSelfUser
@end

@interface ZMBoxedSession : NSObject

@property (nonatomic, weak) ZMSession *session;

@end



@implementation ZMBoxedSession
@end


@implementation ZMSession

@dynamic selfUser;

+ (NSArray *)defaultSortDescriptors;
{
    return nil;
}

+ (NSString *)entityName
{
    return @"Session";
}

+ (BOOL)isTrackingLocalModifications
{
    return NO;
}

@end


@interface ZMUser ()

@property (nonatomic) NSString *normalizedName;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) ZMAccentColor accentColorValue;
@property (nonatomic, copy) NSString *emailAddress;
@property (nonatomic, copy) NSData *imageMediumData;
@property (nonatomic, copy) NSData *imageSmallProfileData;
@property (nonatomic, copy) NSString *phoneNumber;
@property (nonatomic, copy) NSString *normalizedEmailAddress;

@property (nonatomic, readonly) UserClient *selfClient;

@end



@implementation ZMUser


- (BOOL)isSelfUser
{
    return self == [self.class selfUserInContext:self.managedObjectContext];
}

+ (NSString *)entityName;
{
    return @"User";
}

+ (NSString *)sortKey
{
    return NormalizedNameKey;
}

- (void)awakeFromInsert;
{
    [super awakeFromInsert];
    // The UI can never insert users. A newly inserted user will always have to be sync'd
    // with data from the backend. Not that -updateWithTransportData:authoritative: will
    // clear this flag.
    self.needsToBeUpdatedFromBackend = YES;
}

@dynamic accentColorValue;
@dynamic emailAddress;
@dynamic imageMediumData;
@dynamic imageSmallProfileData;
@dynamic name;
@dynamic normalizedEmailAddress;
@dynamic normalizedName;
@dynamic phoneNumber;
@dynamic clients;
@dynamic handle;
@dynamic addressBookEntry;
@dynamic membership;

- (UserClient *)selfClient
{
    NSString *persistedClientId = [self.managedObjectContext persistentStoreMetadataForKey:ZMPersistedClientIdKey];
    if (persistedClientId == nil) {
        return nil;
    }
    return [self.clients.allObjects firstObjectMatchingWithBlock:^BOOL(UserClient *aClient) {
        return [aClient.remoteIdentifier isEqualToString:persistedClientId];
    }];
}

- (NSData *)imageMediumData
{
    return [self imageDataforSize:ProfileImageSizeComplete];
}

- (void)setImageMediumData:(NSData *)imageMediumData
{
    [self setImageData:imageMediumData size:ProfileImageSizeComplete];
}

- (NSData *)imageSmallProfileData
{
    return [self imageDataforSize:ProfileImageSizePreview];
}

- (void)setImageSmallProfileData:(NSData *)imageSmallProfileData
{
    [self setImageData:imageSmallProfileData size:ProfileImageSizePreview];
}

- (NSString *)smallProfileImageCacheKey
{
    return [self imageCacheKeyFor:ProfileImageSizePreview] ?: [self legacyImageCacheKeyFor:ProfileImageSizePreview];
}

- (NSString *)mediumProfileImageCacheKey
{
    return [self imageCacheKeyFor:ProfileImageSizeComplete] ?: [self legacyImageCacheKeyFor:ProfileImageSizeComplete];
}

- (NSString *)imageMediumIdentifier;
{
    NSUUID *uuid = self.localMediumRemoteIdentifier;
    return uuid.UUIDString ?: @"";
}

- (NSString *)imageSmallProfileIdentifier;
{
    NSUUID *uuid = self.localSmallProfileRemoteIdentifier;
    return uuid.UUIDString ?: @"";
}

- (NSString *)displayName;
{
    PersonName *personName = [self.managedObjectContext.zm_displayNameGenerator personNameFor:self];
    return personName.givenName ?: @"";
}

- (NSString *)displayNameInConversation:(ZMConversation *)conversation;
{
    if (conversation == nil) {
        return self.displayName;
    }
    return [self.managedObjectContext.zm_displayNameGenerator displayNameFor:self in:conversation];
}

- (NSString *)initials
{
    PersonName *personName = [self.managedObjectContext.zm_displayNameGenerator personNameFor:self];
    return personName.initials ?: @"";
}

- (ZMConversation *)oneToOneConversation
{
    if (self.isTeamMember) {
        return [ZMConversation fetchOrCreateTeamConversationInManagedObjectContext:self.managedObjectContext
                                                                   withParticipant:self
                                                                              team:self.team];
    } else {
        return self.connection.conversation;
    }
}

- (BOOL)isBot
{
    return [self.handle isEqualToString:ZMUser.annaBotHandle] || [self.handle isEqualToString:ZMUser.ottoBotHandle];
}

- (BOOL)canBeConnected;
{
    return ! self.isConnected && ! self.isPendingApprovalByOtherUser;
}

- (BOOL)isConnected;
{
    return self.connection != nil && self.connection.status == ZMConnectionStatusAccepted;
}

- (NSUInteger)totalCommonConnections
{
    return 0;
}

- (BOOL)isTeamMember
{
    return nil != self.membership;
}

- (BOOL)isGuestInConversation:(ZMConversation *)conversation
{
    // See ZMUser+Teams.swift
    return [self _isGuestIn:conversation];
}

+ (NSSet *)keyPathsForValuesAffectingIsConnected
{
    return [NSSet setWithObjects:ConnectionKey, @"connection.status", nil];
}

- (void)connectWithMessageText:(NSString *)text completionHandler:(dispatch_block_t)handler;
{
    if(self.connection == nil || self.connection.status == ZMConnectionStatusCancelled) {
        ZMConversation *existingConversation;
        if (self.connection.status == ZMConnectionStatusCancelled) {
            existingConversation = self.connection.conversation;
            self.connection = nil;
        }
        self.connection = [ZMConnection insertNewSentConnectionToUser:self existingConversation:existingConversation];
        self.connection.message = text;
    }
    else {
        NOT_USED(text);
        switch (self.connection.status) {
            case ZMConnectionStatusInvalid:
                self.connection.lastUpdateDate = [NSDate date];
                self.connection.status = ZMConnectionStatusSent;
                break;
            case ZMConnectionStatusAccepted:
            case ZMConnectionStatusSent:
            case ZMConnectionStatusCancelled:
                // Do nothing
                break;
            case ZMConnectionStatusPending:
                // We should get the real modified date after syncing with the server, using current date until then.
                self.connection.conversation.lastModifiedDate = [NSDate date];
            case ZMConnectionStatusIgnored:
            case ZMConnectionStatusBlocked:
                self.connection.status = ZMConnectionStatusAccepted;
                if(self.connection.conversation.conversationType == ZMConversationTypeConnection) {
                    self.connection.conversation.conversationType = ZMConversationTypeOneOnOne;
                }
                break;
        }
    }
    if (handler) {
        handler();
    }
}

- (NSString *)connectionRequestMessage;
{
    return self.connection.message;
}

+ (NSSet *)keyPathsForValuesAffectingConnectionRequestMessage {
    return [NSSet setWithObject:@"connection.message"];
}


- (NSSet<UserClient *> *)clientsRequiringUserAttention
{
    NSMutableSet *clientsRequiringUserAttention = [NSMutableSet set];
    
    ZMUser *selfUser = [ZMUser selfUserInContext:self.managedObjectContext];
    
    for (UserClient *userClient in self.clients) {
        if (userClient.needsToNotifyUser && ! [selfUser.selfClient.trustedClients containsObject:userClient]) {
            [clientsRequiringUserAttention addObject:userClient];
        }
    }
    
    return clientsRequiringUserAttention;
}

- (void)refreshData {
    self.needsToBeUpdatedFromBackend = true;
}

@end



@implementation ZMUser (Internal)

@dynamic activeConversations;
@dynamic normalizedName;
@dynamic connection;
@dynamic showingUserAdded;
@dynamic showingUserRemoved;
@dynamic createdTeams;

- (NSSet *)keysTrackedForLocalModifications
{
    if(self.isSelfUser) {
        return [super keysTrackedForLocalModifications];
    }
    else {
        return [NSSet set];
    }
}

- (NSSet *)ignoredKeys;
{
    static NSSet *keys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableSet *ignoredKeys = [[super ignoredKeys] mutableCopy];
        [ignoredKeys addObjectsFromArray:@[
                                           NormalizedNameKey,
                                           ConversationsCreatedKey,
                                           ZMUserActiveConversationsKey,
                                           ActiveCallConversationsKey,
                                           ConnectionKey,
                                           ConversationsCreatedKey,
                                           LastServerSyncedActiveConversationsKey,
                                           LocalMediumRemoteIdentifierDataKey,
                                           LocalSmallProfileRemoteIdentifierDataKey,
                                           NormalizedEmailAddressKey,
                                           NormalizedNameKey,
                                           SystemMessagesKey,
                                           UserClientsKey,
                                           ShowingUserAddedKey,
                                           ShowingUserRemovedKey,
                                           ReactionsKey,
                                           AddressBookEntryKey,
                                           HandleKey, // this is not set on the user directly
                                           MembershipKey,
                                           CreatedTeamsKey
                                           ]];
        keys = [ignoredKeys copy];
    });
    return keys;
}

+ (instancetype)userWithRemoteID:(NSUUID *)UUID createIfNeeded:(BOOL)create inContext:(NSManagedObjectContext *)moc;
{
    // We must only ever call this on the sync context. Otherwise, there's a race condition
    // where the UI and sync contexts could both insert the same user (same UUID) and we'd end up
    // having two duplicates of that user, and we'd have a really hard time recovering from that.
    //
    RequireString(! create || moc.zm_isSyncContext, "Race condition!");
    
    ZMUser *result = [self fetchObjectWithRemoteIdentifier:UUID inManagedObjectContext:moc];
    
    if (result != nil) {
        return result;
    } else if(create) {
        ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:moc];
        user.remoteIdentifier = UUID;
        return user;
    }
    else {
        return nil;
    }
}

+ (nullable instancetype)userWithEmailAddress:(NSString *)emailAddress inContext:(NSManagedObjectContext *)context
{
    RequireString(0 != emailAddress.length, "emailAddress required");
    
    NSFetchRequest *usersWithEmailFetch = [NSFetchRequest fetchRequestWithEntityName:[ZMUser entityName]];
    usersWithEmailFetch.predicate = [NSPredicate predicateWithFormat:@"%K = %@", EmailAddressKey, emailAddress];
    NSArray<ZMUser *> *users = [context executeFetchRequestOrAssert:usersWithEmailFetch];
    
    RequireString(users.count <= 1, "More than one user with the same email address");
    
    if (0 == users.count) {
        return nil;
    }
    else if (1 == users.count) {
        return users.firstObject;
    }
    else {
        return nil;
    }
}

+ (nullable instancetype)userWithPhoneNumber:(NSString *)phoneNumber inContext:(NSManagedObjectContext *)context
{
    RequireString(0 != phoneNumber.length, "phoneNumber required");
    
    NSFetchRequest *usersWithPhoneFetch = [NSFetchRequest fetchRequestWithEntityName:[ZMUser entityName]];
    usersWithPhoneFetch.predicate = [NSPredicate predicateWithFormat:@"%K = %@", PhoneNumberKey, phoneNumber];
    NSArray<ZMUser *> *users = [context executeFetchRequestOrAssert:usersWithPhoneFetch];
    
    RequireString(users.count <= 1, "More than one user with the same phone number");
    
    if (0 == users.count) {
        return nil;
    }
    else if (1 == users.count) {
        return users.firstObject;
    }
    else {
        return nil;
    }
}

+ (NSOrderedSet <ZMUser *> *)usersWithRemoteIDs:(NSOrderedSet <NSUUID *>*)UUIDs inContext:(NSManagedObjectContext *)moc;
{
    return [self fetchObjectsWithRemoteIdentifiers:UUIDs inManagedObjectContext:moc];
}

- (NSUUID *)remoteIdentifier;
{
    return [self transientUUIDForKey:@"remoteIdentifier"];
}

- (void)setRemoteIdentifier:(NSUUID *)remoteIdentifier;
{
    [self setTransientUUID:remoteIdentifier forKey:@"remoteIdentifier"];
}

+ (ZMAccentColor)accentColorFromPayloadValue:(NSNumber *)payloadValue
{
    ZMAccentColor color = (ZMAccentColor) payloadValue.intValue;
    if ((color <= ZMAccentColorUndefined) || (ZMAccentColorMax < color)) {
        color = (ZMAccentColor) (arc4random_uniform(ZMAccentColorMax - 1) + 1);
    }
    return color;
}

- (void)updateWithTransportData:(NSDictionary *)transportData authoritative:(BOOL)authoritative
{
    NSUUID *remoteID = [transportData[@"id"] UUID];
    if (self.remoteIdentifier == nil) {
        self.remoteIdentifier = remoteID;
    } else {
        RequireString([self.remoteIdentifier isEqual:remoteID], "User ids do not match in update: %s vs. %s",
                      remoteID.transportString.UTF8String,
                      self.remoteIdentifier.transportString.UTF8String);
    }

    NSString *name = [transportData optionalStringForKey:@"name"];
    if (name != nil || authoritative) {
        self.name = name;
    }
    
    NSString *handle = [transportData optionalStringForKey:@"handle"];
    if (handle != nil || authoritative) {
        self.handle = handle;
    }
    
    NSString *email = [transportData optionalStringForKey:@"email"];
    if ([transportData objectForKey:@"email"] || authoritative) {
        self.emailAddress = email.stringByRemovingExtremeCombiningCharacters;
    }
    
    NSString *phone = [transportData optionalStringForKey:@"phone"];
    if ([transportData objectForKey:@"phone"] || authoritative) {
        self.phoneNumber = phone.stringByRemovingExtremeCombiningCharacters;
    }
    
    NSNumber *accentId = [transportData optionalNumberForKey:@"accent_id"];
    if (accentId != nil || authoritative) {
        self.accentColorValue = [ZMUser accentColorFromPayloadValue:accentId];
    }
    
    BOOL hasLocalModificationsForLegacyImages = [self hasLocalModificationsForKeys:[NSSet setWithArray:@[ImageMediumDataKey, ImageSmallProfileDataKey, SmallProfileRemoteIdentifierDataKey, MediumRemoteIdentifierDataKey]]];
    NSArray *picture = [transportData optionalArrayForKey:@"picture"];
    if ((picture != nil || authoritative) && !hasLocalModificationsForLegacyImages) {
        [self updateImageWithTransportData:picture];
    }
    
    NSArray *assets = [transportData optionalArrayForKey:@"assets"];
    [self updateAssetDataWith:assets hasLegacyImages:(picture.count > 0 || hasLocalModificationsForLegacyImages) authoritative:authoritative];
    
    // We intentionally ignore the preview data.
    //
    // Need to see if we're changing the resolution, but it's currently way too small
    // to be of any use.
    
    if (authoritative) {
        self.needsToBeUpdatedFromBackend = NO;
    }
    
    [self updatePotentialGapSystemMessagesIfNeeded];
}

- (void)updatePotentialGapSystemMessagesIfNeeded
{
    for (ZMSystemMessage *systemMessage in self.showingUserAdded) {
        [systemMessage updateNeedsUpdatingUsersIfNeeded];
    }
    
    for (ZMSystemMessage *systemMessage in self.showingUserRemoved) {
        [systemMessage updateNeedsUpdatingUsersIfNeeded];
    }
}

- (void)updateImageWithTransportData:(NSArray *)transportData;
{
    if (transportData.count == 0) {
        self.mediumRemoteIdentifier = nil;
        self.smallProfileRemoteIdentifier = nil;
        self.imageMediumData = nil;
        self.imageSmallProfileData = nil;
        return;
    }
    
    for (NSDictionary *picture in transportData) {
        if (! [picture isKindOfClass:[NSDictionary class]]) {
            ZMLogError(@"Invalid picture data in user info.");
            continue;
        }
        NSDictionary *info = [picture dictionaryForKey:@"info"];
        if ([[info stringForKey:@"tag"] isEqualToString:@"medium"]) {
            self.mediumRemoteIdentifier = [picture uuidForKey:@"id"];
        }
        else if ([[info stringForKey:@"tag"] isEqualToString:@"smallProfile"]) {
            self.smallProfileRemoteIdentifier = [picture uuidForKey:@"id"];
        }
    }
}

- (NSDictionary *)pictureDataWithTag:(NSString *)tag inTransportData:(NSDictionary *)transportData
{
    NSArray *pictures = [transportData optionalArrayForKey:@"picture"];
    if (pictures == nil) {
        return nil;
    }
    for (NSDictionary *pictureData in [pictures asDictionaries]) {
        if ([[[pictureData dictionaryForKey:@"info"] stringForKey:@"tag"] isEqualToString:tag]) {
            return pictureData;
        }
    }
    return nil;
}

+ (NSPredicate *)predicateForObjectsThatNeedToBeUpdatedUpstream;
{
    NSPredicate *basePredicate = [super predicateForObjectsThatNeedToBeUpdatedUpstream];
    NSPredicate *needsToBeUpdated = [NSPredicate predicateWithFormat:@"needsToBeUpdatedFromBackend == 0"];
    NSPredicate *nilRemoteIdentifiers = [NSPredicate predicateWithFormat:@"%K == nil && %K == nil", SmallProfileRemoteIdentifierDataKey, MediumRemoteIdentifierDataKey];
    NSPredicate *notNilRemoteIdentifiers = [NSPredicate predicateWithFormat:@"%K != nil && %K != nil", SmallProfileRemoteIdentifierDataKey, MediumRemoteIdentifierDataKey];
    NSPredicate *assetV3RemoteIdentifiers = [NSPredicate predicateWithFormat:@"%K != nil && %K != nil", ZMUser.previewProfileAssetIdentifierKey, ZMUser.completeProfileAssetIdentifierKey];

    NSPredicate *remoteIdentifiers = [NSCompoundPredicate orPredicateWithSubpredicates:@[nilRemoteIdentifiers, notNilRemoteIdentifiers, assetV3RemoteIdentifiers]];
    return [NSCompoundPredicate andPredicateWithSubpredicates:@[basePredicate, needsToBeUpdated, remoteIdentifiers]];
}

- (void)updateWithSearchResultName:(NSString *)name handle:(NSString *)handle;
{
    // We never refetch unconnected users, but when performing a search we
    // might receive updated result and can update existing local users.
    if (name != nil && name != self.name) {
        self.name = name;
    }

    if (handle != nil && handle != self.handle) {
        self.handle = handle;
    }
}

@end


@implementation ZMUser (SelfUser)

+ (NSManagedObjectID *)storedObjectIdForUserInfoKey:(NSString *)objectIdKey persistedMetadataKey:(NSString *)metadataKey inContext:(NSManagedObjectContext *)moc
{
    NSManagedObjectID *moid = moc.userInfo[objectIdKey];
    if (moid == nil) {
        NSString *moidString = [moc persistentStoreMetadataForKey:metadataKey];
        if (moidString != nil) {
            NSURL *moidURL = [NSURL URLWithString:moidString];
            if (moidURL != nil) {
                moid = [moc.persistentStoreCoordinator managedObjectIDForURIRepresentation:moidURL];
                if (moid != nil) {
                    moc.userInfo[objectIdKey] = moid;
                }
            }
        }
    }
    return moid;
}

+ (ZMUser *)obtainCachedSessionById:(NSManagedObjectID *)moid inContext:(NSManagedObjectContext *)moc
{
    ZMUser *selfUser;
    if (moid != nil) {
        // It's ok for this to fail -- it will if the object is not around.
        ZMSession *session = (ZMSession *)[moc existingObjectWithID:moid error:NULL];
        Require((session == nil) || [session isKindOfClass: [ZMSession class]]);
        selfUser = session.selfUser;
    }
    return selfUser;
}

+ (ZMUser *)obtainCachedSelfUserById:(NSManagedObjectID *)moid inContext:(NSManagedObjectContext *)moc
{
    ZMUser *selfUser;
    if (moid != nil) {
        // It's ok for this to fail -- it will if the object is not around.
        NSManagedObject *result = [moc existingObjectWithID:moid error:NULL];
        Require((result == nil) || [result isKindOfClass: [ZMUser class]]);
        selfUser = (ZMUser *)result;
    }
    return selfUser;
}

+ (ZMUser *)createSessionIfNeededInContext:(NSManagedObjectContext *)moc withSelfUser:(ZMUser *)selfUser
{
    //clear old keys
    [moc.userInfo removeObjectForKey:SelfUserObjectIDKey];
    [moc setPersistentStoreMetadata:nil forKey:SelfUserObjectIDAsStringKey];

    NSError *error;

    //if there is no already session object than create one
    ZMSession *session = (ZMSession *)[moc executeFetchRequestOrAssert:[ZMSession sortedFetchRequest]].firstObject;
    if (session == nil) {
        session = [ZMSession insertNewObjectInManagedObjectContext:moc];
        RequireString([moc obtainPermanentIDsForObjects:@[session] error:&error],
                      "Failed to get ID for self user: %lu", (long) error.code);
    }
    
    //if there is already user in session, don't create new
    selfUser = selfUser ?: session.selfUser;
    
    if (selfUser == nil) {
        selfUser = [ZMUser insertNewObjectInManagedObjectContext:moc];
        RequireString([moc obtainPermanentIDsForObjects:@[selfUser] error:&error],
                      "Failed to get ID for self user: %lu", (long) error.code);
    }

    session.selfUser = selfUser;
    
    //store session object id in persistent metadata, so we can retrieve it from other context
    moc.userInfo[SessionObjectIDKey] = session.objectID;
    [moc setPersistentStoreMetadata:session.objectID.URIRepresentation.absoluteString forKey:SessionObjectIDAsStringKey];
    // This needs to be a 'real' save, to make sure we push the metadata:
    RequireString([moc save:&error], "Failed to save self user: %lu", (long) error.code);

    return selfUser;
}

+ (ZMUser *)unboxSelfUserFromContextUserInfo:(NSManagedObjectContext *)moc
{
    ZMBoxedSelfUser *boxed = moc.userInfo[SelfUserKey];
    return boxed.selfUser;
}

+ (void)boxSelfUser:(ZMUser *)selfUser inContextUserInfo:(NSManagedObjectContext *)moc
{
    ZMBoxedSelfUser *boxed = [[ZMBoxedSelfUser alloc] init];
    boxed.selfUser = selfUser;
    moc.userInfo[SelfUserKey] = boxed;
}

+ (BOOL)hasSessionEntityInContext:(NSManagedObjectContext *)moc
{
    //In older client versions there is no Session entity (first model version )...
    return (moc.persistentStoreCoordinator.managedObjectModel.entitiesByName[[ZMSession entityName]] != nil);
}

+ (instancetype)selfUserInContext:(NSManagedObjectContext *)moc;
{
    // This method is a contention point.
    //
    // We're storing the object ID of the session (previously self user) (as a string) inside the store's metadata.
    // The metadata gets persisted, hence we're able to retrieve the session (self user) across launches.
    // Converting the string representation to an instance of NSManagedObjectID is not cheap.
    // We're hence caching the value inside the context's userInfo.
    
    //1. try to get boxed user from user info
    ZMUser *selfUser = [self unboxSelfUserFromContextUserInfo:moc];
    if (selfUser) {
        return selfUser;
    }
    
    // 2. try to get session object id by session key from user info or metadata
    NSManagedObjectID *moid = [self storedObjectIdForUserInfoKey:SessionObjectIDKey persistedMetadataKey:SessionObjectIDAsStringKey inContext:moc];
    if (moid == nil) {
        //3. try to get user object id by user id key from user info or metadata
        moid = [self storedObjectIdForUserInfoKey:SelfUserObjectIDKey persistedMetadataKey:SelfUserObjectIDAsStringKey inContext:moc];
        if (moid != nil) {
            //4. get user by it's object id
            selfUser = [self obtainCachedSelfUserById:moid inContext:moc];
            if (selfUser != nil) {
                //there can be no session object, create one and store self user in it
                (void)[self createSessionIfNeededInContext:moc withSelfUser:selfUser];
            }
        }
    }
    else {
        //4. get user from session by it's object id
        selfUser = [self obtainCachedSessionById:moid inContext:moc];
    }
    
    if (selfUser == nil) {
        //create user and store it's id in metadata by session key
        selfUser = [self createSessionIfNeededInContext:moc withSelfUser:nil];
    }
    //5. box user and store box in user info by user key
    [self boxSelfUser:selfUser inContextUserInfo:moc];
    
    return selfUser;
}

@end


@implementation  ZMUser (Utilities)

+ (ZMUser<ZMEditableUser> *)selfUserInUserSession:(id<ZMManagedObjectContextProvider>)session
{
    VerifyReturnNil(session != nil);
    return [self selfUserInContext:session.managedObjectContext];
}

@end




@implementation ZMUser (Editable)

- (void)setHandle:(NSString *)aHandle {
    [self willChangeValueForKey:HandleKey];
    [self setPrimitiveValue:[aHandle copy] forKey:HandleKey];
    [self didChangeValueForKey:HandleKey];
}

- (void)setName:(NSString *)aName {
    
    [self willChangeValueForKey:NameKey];
    [self setPrimitiveValue:[[aName copy] stringByRemovingExtremeCombiningCharacters] forKey:NameKey];
    [self didChangeValueForKey:NameKey];
    
    self.normalizedName = [self.name normalizedString];
}

- (void)setEmailAddress:(NSString *)anEmailAddress {
    
    [self willChangeValueForKey:EmailAddressKey];
    [self setPrimitiveValue:[anEmailAddress copy] forKey:EmailAddressKey];
    [self didChangeValueForKey:EmailAddressKey];
    
    self.normalizedEmailAddress = [self.emailAddress normalizedEmailaddress];
}

@end





@implementation ZMUser (Connections)


- (BOOL)isBlocked
{
    return self.connection != nil && self.connection.status == ZMConnectionStatusBlocked;
}

+ (NSSet *)keyPathsForValuesAffectingIsBlocked
{
    return [NSSet setWithObjects:ConnectionKey, @"connection.status", nil];
}

- (BOOL)isIgnored
{
    return self.connection != nil && self.connection.status == ZMConnectionStatusIgnored;
}

+ (NSSet *)keyPathsForValuesAffectingIsIgnored
{
    return [NSSet setWithObjects:ConnectionKey, @"connection.status", nil];
}

- (BOOL)isPendingApprovalBySelfUser
{
    return self.connection != nil && (self.connection.status == ZMConnectionStatusPending ||
                                      self.connection.status == ZMConnectionStatusIgnored);
}

+ (NSSet *)keyPathsForValuesAffectingIsPendingApprovalBySelfUser
{
    return [NSSet setWithObjects:ConnectionKey, @"connection.status", nil];
}

- (BOOL)isPendingApprovalByOtherUser
{
    return self.connection != nil && self.connection.status == ZMConnectionStatusSent;
}

+ (NSSet *)keyPathsForValuesAffectingIsPendingApprovalByOtherUser
{
    return [NSSet setWithObjects:ConnectionKey, @"connection.status", nil];
}


- (void)accept;
{
    [self connectWithMessageText:nil completionHandler:nil];
}

- (void)block;
{
    switch (self.connection.status) {
        case ZMConnectionStatusBlocked:
        case ZMConnectionStatusInvalid:
        case ZMConnectionStatusCancelled:
            // do nothing
            break;
            
        case ZMConnectionStatusIgnored:
        case ZMConnectionStatusAccepted:
        case ZMConnectionStatusPending:
        case ZMConnectionStatusSent:
            self.connection.status = ZMConnectionStatusBlocked;
            break;
    };
}

- (void)ignore;
{
    switch (self.connection.status) {
        case ZMConnectionStatusInvalid:
        case ZMConnectionStatusSent:
        case ZMConnectionStatusIgnored:
        case ZMConnectionStatusCancelled:
            // do nothing
            break;
        case ZMConnectionStatusBlocked:
        case ZMConnectionStatusAccepted:
        case ZMConnectionStatusPending:
            self.connection.status = ZMConnectionStatusIgnored;
            break;
            
    };
}

- (void)cancelConnectionRequest
{
    if (self.connection.status == ZMConnectionStatusSent) {
        self.connection.status = ZMConnectionStatusCancelled;
    }
}

- (BOOL)trusted
{
    if (self.clients.count == 0) {
        return false;
    }
    ZMUser *selfUser = [ZMUser selfUserInContext:self.managedObjectContext];
    UserClient *selfClient = selfUser.selfClient;
    __block BOOL hasOnlyTrustedClients = YES;
    [self.clients enumerateObjectsUsingBlock:^(UserClient *client, BOOL * _Nonnull stop) {
        if (client != selfClient && ![selfClient.trustedClients containsObject:client]) {
            hasOnlyTrustedClients = NO;
            *stop = YES;
        }
    }];
    return hasOnlyTrustedClients;
}

- (BOOL)untrusted
{
    ZMUser *selfUser = [ZMUser selfUserInContext:self.managedObjectContext];
    UserClient *selfClient = selfUser.selfClient;
    __block BOOL hasUntrustedClients = NO;
    [self.clients enumerateObjectsUsingBlock:^(UserClient *client, BOOL * _Nonnull stop) {
        if (client != selfClient && ![selfClient.trustedClients containsObject:client]) {
            hasUntrustedClients = YES;
            *stop = YES;
        }
    }];
    return hasUntrustedClients;
}

@end



@implementation ZMUser (ImageData)

- (NSUUID *)mediumRemoteIdentifier;
{
    return [self transientUUIDForKey:@"mediumRemoteIdentifier"];
}

- (void)setMediumRemoteIdentifier:(NSUUID *)remoteIdentifier;
{
    [self setTransientUUID:remoteIdentifier forKey:@"mediumRemoteIdentifier"];
}

- (NSUUID *)smallProfileRemoteIdentifier;
{
    return [self transientUUIDForKey:@"smallProfileRemoteIdentifier"];
}

- (void)setSmallProfileRemoteIdentifier:(NSUUID *)remoteIdentifier;
{
    [self setTransientUUID:remoteIdentifier forKey:@"smallProfileRemoteIdentifier"];
}

- (NSUUID *)localMediumRemoteIdentifier;
{
    return [self transientUUIDForKey:@"localMediumRemoteIdentifier"];
}

- (void)setLocalMediumRemoteIdentifier:(NSUUID *)remoteIdentifier;
{
    [self setTransientUUID:remoteIdentifier forKey:@"localMediumRemoteIdentifier"];
}

- (NSUUID *)localSmallProfileRemoteIdentifier;
{
    return [self transientUUIDForKey:@"localSmallProfileRemoteIdentifier"];
}

- (void)setLocalSmallProfileRemoteIdentifier:(NSUUID *)remoteIdentifier;
{
    [self setTransientUUID:remoteIdentifier forKey:@"localSmallProfileRemoteIdentifier"];
}

+ (NSPredicate *)predicateForMediumImageNeedingToBeUpdatedFromBackend;
{
    return [NSPredicate predicateWithFormat:@"(%K != nil) && (%K == nil)", MediumRemoteIdentifierDataKey, ZMUser.completeProfileAssetIdentifierKey];
}

+ (NSPredicate *)predicateForSmallImageNeedingToBeUpdatedFromBackend;
{
    return [NSPredicate predicateWithFormat:@"(%K != nil) && (%K == nil)", SmallProfileRemoteIdentifierDataKey, ZMUser.previewProfileAssetIdentifierKey];
}

+ (NSPredicate *)predicateForUsersOtherThanSelf
{
    return [NSPredicate predicateWithFormat:@"isSelfUser != YES"];
}

+ (NSPredicate *)predicateForSelfUser
{
    return [NSPredicate predicateWithFormat:@"isSelfUser == YES"];
}

+ (NSPredicate *)predicateForMediumImageDownloadFilter
{
    NSPredicate *localIdIsOld = [NSPredicate predicateWithFormat:@"%K != %K", LocalMediumRemoteIdentifierDataKey, MediumRemoteIdentifierDataKey];
    NSPredicate *selfLocalIdIsOld = [NSCompoundPredicate andPredicateWithSubpredicates:@[[self predicateForSelfUser], localIdIsOld]];
    NSPredicate *imageNotInCache = [NSPredicate predicateWithBlock:^BOOL(ZMUser * _Nonnull user, NSDictionary<NSString *,id> * _Nullable bindings) {
        NOT_USED(bindings);
        return ! user.isSelfUser && user.imageMediumData == nil;
    }];
    
    return [NSCompoundPredicate orPredicateWithSubpredicates:@[selfLocalIdIsOld, imageNotInCache]];
}
+ (NSPredicate *)predicateForSmallImageDownloadFilter
{
    NSPredicate *localIdIsOld = [NSPredicate predicateWithFormat:@"%K != %K", LocalSmallProfileRemoteIdentifierDataKey,
                                 SmallProfileRemoteIdentifierDataKey];
    NSPredicate *selfLocalIdIsOld = [NSCompoundPredicate andPredicateWithSubpredicates:@[[self predicateForSelfUser], localIdIsOld]];
    NSPredicate *imageNotInCache = [NSPredicate predicateWithBlock:^BOOL(ZMUser * _Nonnull user, NSDictionary<NSString *,id> * _Nullable bindings) {
        NOT_USED(bindings);
        return ! user.isSelfUser && user.imageSmallProfileData == nil;
    }];
    
    return [NSCompoundPredicate orPredicateWithSubpredicates:@[selfLocalIdIsOld, imageNotInCache]];
}

@end



@implementation ZMUser (KeyValueValidation)

+ (BOOL)validateName:(NSString **)ioName error:(NSError **)outError
{
    [ExtremeCombiningCharactersValidator validateValue:ioName error:outError];
    if (outError != nil && *outError != nil) {
        return NO;
    }
    
    // The backend limits to 128. We'll fly just a bit below the radar.
    return [ZMStringLengthValidator validateValue:ioName mimimumStringLength:2 maximumSringLength:100 error:outError];
}

+ (BOOL)validateAccentColorValue:(NSNumber **)ioAccent error:(NSError **)outError
{
    return [ZMAccentColorValidator validateValue:ioAccent error:outError];
}

+ (BOOL)validateEmailAddress:(NSString **)ioEmailAddress error:(NSError **)outError
{
    return [ZMEmailAddressValidator validateValue:ioEmailAddress error:outError];
}

+ (BOOL)validatePassword:(NSString **)ioPassword error:(NSError **)outError
{
    return [ZMStringLengthValidator validateValue:ioPassword mimimumStringLength:8 maximumSringLength:120 error:outError];
}

+ (BOOL)validatePhoneNumber:(NSString **)ioPhoneNumber error:(NSError **)outError
{
    if (ioPhoneNumber == NULL || [*ioPhoneNumber length] < 1) {
        return NO;
    }
    else {
        return [ZMPhoneNumberValidator validateValue:ioPhoneNumber error:outError];
    }
}

+ (BOOL)validatePhoneVerificationCode:(NSString **)ioVerificationCode error:(NSError **)outError
{
    if (*ioVerificationCode == nil) {
        return NO;
    }
    else {
        return [ZMStringLengthValidator validateValue:ioVerificationCode
                                  mimimumStringLength:6
                                   maximumSringLength:6
                                                error:outError];
    }
}

- (BOOL)validateValue:(id *)value forKey:(NSString *)key error:(NSError **)error
{
    if (self.isInserted) {
        // Self user gets inserted, no other users will. Ignore this case.
        //We does not need to validate selfUser for now, 'cuase it's not setup yet, i.e. it has empty name at this point
        return YES;
    }
    return [super validateValue:value forKey:key error:error];
}

- (BOOL)validateEmailAddress:(NSString **)ioEmailAddress error:(NSError **)outError
{
    return [ZMUser validateEmailAddress:ioEmailAddress error:outError];
}

- (BOOL)validateName:(NSString **)ioName error:(NSError **)outError
{
    return [ZMUser validateName:ioName error:outError];
}

- (BOOL)validateAccentColorValue:(NSNumber **)ioAccent error:(NSError **)outError
{
    return [ZMUser validateAccentColorValue:ioAccent error:outError];
}



@end




@implementation NSUUID (SelfUser)

- (BOOL)isSelfUserRemoteIdentifierInContext:(NSManagedObjectContext *)moc;
{
    return [[ZMUser selfUserInContext:moc].remoteIdentifier isEqual:self];
}

@end


@implementation ZMUser (Protobuf)

- (ZMUserId *)userId
{
    ZMUserIdBuilder *userIdBuilder = [ZMUserId builder];
    [userIdBuilder setUuid:[self.remoteIdentifier data]];
    return [userIdBuilder build];
}

@end


