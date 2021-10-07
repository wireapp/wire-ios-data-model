//
//  ZMConnection+Helper.h
//  WireDataModelTests
//
//  Created by Jacob Persson on 07.10.21.
//  Copyright © 2021 Wire Swiss GmbH. All rights reserved.
//

#import <WireDataModel/WireDataModel.h>

@class ZMUser;
@class ZMConversation;

NS_ASSUME_NONNULL_BEGIN

@interface ZMConnection (Helper)

+ (instancetype)insertNewSentConnectionToUser:(ZMUser *)user;
+ (instancetype)insertNewSentConnectionToUser:(ZMUser *)user existingConversation:(ZMConversation * _Nullable)conversation;

@end

NS_ASSUME_NONNULL_END
