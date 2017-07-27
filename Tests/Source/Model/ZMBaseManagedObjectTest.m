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


#import "ZMBaseManagedObjectTest.h"
#import <libkern/OSAtomic.h>
#import <CommonCrypto/CommonCrypto.h>

#import "ZMClientMessage.h"
#import "NSManagedObjectContext+zmessaging.h"
#import "NSManagedObjectContext+zmessaging-Internal.h"
#import "MockModelObjectContextFactory.h"
#import "ZMAssetClientMessage.h"

#import "ZMUser+Internal.h"
#import "ZMConversation+Internal.h"
#import "ZMMessage+Internal.h"
#import "ZMConversation+UnreadCount.h"

#import "NSString+RandomString.h"

@import WireDataModel;

NSString *const ZMPersistedClientIdKey = @"PersistedClientId";


@interface ZMBaseManagedObjectTest ()

@property (nonatomic) ManagedObjectContextDirectory *contextDirectory;
@property (nonatomic) NSTimeInterval originalConversationLastReadTimestampTimerValue; // this will speed up the tests A LOT

@end


@implementation ZMBaseManagedObjectTest

- (BOOL)shouldUseRealKeychain;
{
    return NO;
}

- (BOOL)shouldUseInMemoryStore;
{
    return YES;
}

- (void)performPretendingUiMocIsSyncMoc:(void(^)(void))block;
{
    block();
//    [self.testSession performPretendingUiMocIsSyncMoc:block];
}

- (void)setUp;
{
    [super setUp];
    
    StorageStack *stack = StorageStack.shared;
    stack.createStorageAsInMemory = self.shouldUseInMemoryStore;
    
//
//    self.testSession = [[ZMTestSession alloc] initWithDispatchGroup:self.dispatchGroup];
//    self.testSession.shouldUseInMemoryStore = self.shouldUseInMemoryStore;
//    self.testSession.shouldUseRealKeychain = self.shouldUseRealKeychain;
//    
//    [self performIgnoringZMLogError:^{
//        [self.testSession prepareForTestNamed:self.name];
//    }];
    
    NSString *testName = NSStringFromSelector(self.invocation.selector);
    NSString *methodName = [NSString stringWithFormat:@"setup%@%@", [testName substringToIndex:1].capitalizedString, [testName substringFromIndex:1]];
    SEL selector = NSSelectorFromString(methodName);
    if ([self respondsToSelector:selector]) {
        ZM_SILENCE_CALL_TO_UNKNOWN_SELECTOR([self performSelector:selector]);
    }

    WaitForAllGroupsToBeEmpty(500); // we want the test to get stuck if there is something wrong. Better than random failures
}

- (void)tearDown;
{
    WaitForAllGroupsToBeEmpty(500); // we want the test to get stuck if there is something wrong. Better than random failures
//    [self.testSession tearDown];
    self.contextDirectory = nil;
    [super tearDown];
}

- (NSManagedObjectContext *)uiMOC
{
    return self.contextDirectory.uiContext;
}

- (NSManagedObjectContext *)syncMOC
{
    return self.contextDirectory.syncContext;
}

- (NSManagedObjectContext *)searchMOC
{
    return self.contextDirectory.searchContext;
}

- (void)cleanUpAndVerify {
//    [self.testSession waitAndDeleteAllManagedObjectContexts];
    [self verifyMocksNow];
}

- (void)resetUIandSyncContextsAndResetPersistentStore:(BOOL)resetPersistentStore
{
    resetPersistentStore = YES;
//    [self.testSession resetUIandSyncContextsAndResetPersistentStore:resetPersistentStore];
}


@end


@implementation ZMBaseManagedObjectTest (UserTesting)

- (void)setEmailAddress:(NSString *)emailAddress onUser:(ZMUser *)user;
{
    user.emailAddress = emailAddress;
}

- (void)setPhoneNumber:(NSString *)phoneNumber onUser:(ZMUser *)user;
{
    user.phoneNumber = phoneNumber;
}

@end


@implementation ZMBaseManagedObjectTest (FilesInCache)

- (void)wipeCaches
{
//    [self.testSession wipeCaches];
}

@end


@implementation ZMBaseManagedObjectTest (OTR)

- (UserClient *)createSelfClient
{
    return [self createSelfClientOnMOC:self.uiMOC];
}

- (UserClient *)createSelfClientOnMOC:(NSManagedObjectContext *)moc
{
    __block ZMUser *selfUser = nil;
    
    selfUser = [ZMUser selfUserInContext:moc];
    selfUser.remoteIdentifier = selfUser.remoteIdentifier ?: [NSUUID createUUID];
    UserClient *selfClient = [UserClient insertNewObjectInManagedObjectContext:moc];
    selfClient.remoteIdentifier = [NSString createAlphanumericalString];
    selfClient.user = selfUser;
    
    [moc setPersistentStoreMetadata:selfClient.remoteIdentifier forKey:ZMPersistedClientIdKey];
    
    [self performPretendingUiMocIsSyncMoc:^{
        NSDictionary *payload = @{@"id": selfClient.remoteIdentifier, @"type": @"permanent", @"time": [[NSDate date] transportString]};
        NOT_USED([UserClient createOrUpdateSelfUserClient:payload context:moc]);
    }];
    
    [moc saveOrRollback];
    
    return selfClient;
}

- (UserClient *)createClientForUser:(ZMUser *)user createSessionWithSelfUser:(BOOL)createSessionWithSeflUser
{
    return [self createClientForUser:user createSessionWithSelfUser:createSessionWithSeflUser onMOC:self.uiMOC];
}

- (UserClient *)createClientForUser:(ZMUser *)user createSessionWithSelfUser:(BOOL)createSessionWithSeflUser onMOC:(NSManagedObjectContext *)moc
{
    if(user.remoteIdentifier == nil) {
        user.remoteIdentifier = [NSUUID createUUID];
    }
    UserClient *userClient = [UserClient insertNewObjectInManagedObjectContext:moc];
    userClient.remoteIdentifier = [NSString createAlphanumericalString];
    userClient.user = user;
    
    if (createSessionWithSeflUser) {
        UserClient *selfClient = [ZMUser selfUserInContext:moc].selfClient;
        [self performPretendingUiMocIsSyncMoc:^{
            NSError *error;
            NSString *key = [selfClient.keysStore lastPreKeyAndReturnError:&error];
            NOT_USED([selfClient establishSessionWithClient:userClient usingPreKey:key]);
        }];
    }
    return userClient;
}

- (ZMClientMessage *)createClientTextMessage:(BOOL)encrypted
{
    return [self createClientTextMessage:self.name encrypted:encrypted];
}

- (ZMClientMessage *)createClientTextMessage:(NSString *)text encrypted:(BOOL)encrypted
{
    ZMClientMessage *message = [ZMClientMessage insertNewObjectInManagedObjectContext:self.uiMOC];
    NSUUID *messageNonce = [NSUUID createUUID];
    ZMGenericMessage *textMessage = [ZMGenericMessage messageWithText:text nonce:messageNonce.transportString expiresAfter:nil];
    [message addData:textMessage.data];
    message.isEncrypted = encrypted;
    return message;
}

- (ZMAssetClientMessage *)createImageMessageWithImageData:(NSData *)imageData format:(ZMImageFormat)format processed:(BOOL)processed stored:(BOOL)stored encrypted:(BOOL)encrypted moc:(NSManagedObjectContext *)moc
{
    NSUUID *nonce = [NSUUID createUUID];
    ZMAssetClientMessage *imageMessage = [ZMAssetClientMessage assetClientMessageWithOriginalImageData:imageData nonce:nonce managedObjectContext:moc expiresAfter:0];
    imageMessage.isEncrypted = encrypted;
    
    if(processed) {
        
        CGSize imageSize = [ZMImagePreprocessor sizeOfPrerotatedImageWithData:imageData];
        ZMIImageProperties *properties = [ZMIImageProperties imagePropertiesWithSize:imageSize
                                                                              length:imageData.length
                                                                            mimeType:@"image/jpeg"];
        ZMImageAssetEncryptionKeys *keys = nil;
        if (encrypted) {
            keys = [[ZMImageAssetEncryptionKeys alloc] initWithOtrKey:[NSData zmRandomSHA256Key]
                                                               macKey:[NSData zmRandomSHA256Key]
                                                                  mac:[NSData zmRandomSHA256Key]];
        }
        
        ZMGenericMessage *message = [ZMGenericMessage genericMessageWithMediumImageProperties:properties processedImageProperties:properties encryptionKeys:keys nonce:nonce.transportString format:format expiresAfter:nil];
        [imageMessage addGenericMessage:message];
        
        if (stored) {
            [self.uiMOC.zm_imageAssetCache storeAssetData:nonce format:ZMImageFormatOriginal encrypted:NO data:imageData];
        }
        if (processed) {
            [self.uiMOC.zm_imageAssetCache storeAssetData:nonce format:format encrypted:NO data:imageData];
        }
        if (encrypted) {
            [self.uiMOC.zm_imageAssetCache storeAssetData:nonce format:format encrypted:YES data:imageData];
        }
    }
    return imageMessage;
}

@end


@implementation  ZMBaseManagedObjectTest (SwiftBridgeConversation)

- (void)performChangesSyncConversation:(ZMConversation *)conversation
                            mergeBlock:(void(^)(void))mergeBlock
                           changeBlock:(void(^)(ZMConversation*))changeBlock
{
    BOOL isSyncContext = conversation.managedObjectContext.zm_isSyncContext;
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *syncConv = conversation;
        if (!isSyncContext) {
            NSManagedObjectID *objectID = conversation.objectID;
            syncConv = (id)[self.syncMOC objectWithID:objectID];
        }
        changeBlock(syncConv);
        [self.syncMOC saveOrRollback];
    }];
    if (!isSyncContext) {
        if (mergeBlock) {
            mergeBlock();
        } else {
            [self.uiMOC refreshObject:conversation mergeChanges:YES];
        }
    }
}
- (void)simulateUnreadCount:(NSUInteger)unreadCount forConversation:(nonnull ZMConversation *)conversation mergeBlock:(void(^_Nullable)(void))mergeBlock;
{
    [self performChangesSyncConversation:conversation mergeBlock:mergeBlock changeBlock:^(ZMConversation * syncConv) {
        syncConv.internalEstimatedUnreadCount = [@(unreadCount) intValue];
    }];
}
- (void)simulateUnreadMissedCallInConversation:(nonnull ZMConversation *)conversation mergeBlock:(void(^_Nullable)(void))mergeBlock;
{
    [self performChangesSyncConversation:conversation mergeBlock:mergeBlock changeBlock:^(ZMConversation * syncConv) {
        syncConv.lastUnreadMissedCallDate = [NSDate date];
    }];
}

- (void)simulateUnreadMissedKnockInConversation:(nonnull ZMConversation *)conversation mergeBlock:(void(^_Nullable)(void))mergeBlock;
{
    [self performChangesSyncConversation:conversation mergeBlock:mergeBlock changeBlock:^(ZMConversation * syncConv) {
        syncConv.lastUnreadKnockDate = [NSDate date];
    }];
}

- (void)simulateUnreadCount:(NSUInteger)unreadCount forConversation:(ZMConversation *)conversation;
{
    [self simulateUnreadCount:unreadCount forConversation:conversation mergeBlock:nil];
}

- (void)simulateUnreadMissedCallInConversation:(ZMConversation *)conversation;
{
    [self simulateUnreadMissedCallInConversation:conversation mergeBlock:nil];
}

- (void)simulateUnreadMissedKnockInConversation:(ZMConversation *)conversation;
{
    [self simulateUnreadMissedKnockInConversation:conversation mergeBlock:nil];
}

@end
