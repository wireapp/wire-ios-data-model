//
//  ZMConnection+Helper.c
//  WireDataModelTests
//
//  Created by Jacob Persson on 07.10.21.
//  Copyright © 2021 Wire Swiss GmbH. All rights reserved.
//

#import "ZMConnection+Helper.h"
#import "ZMUser+Internal.h"

@implementation ZMConnection (Helper)

+ (instancetype)insertNewSentConnectionToUser:(ZMUser *)user existingConversation:(ZMConversation *)conversation
{
    VerifyReturnValue(user.connection == nil, user.connection);
    RequireString(user != nil, "Can not create a connection to <nil> user.");
    ZMConnection *connection = [self insertNewObjectInManagedObjectContext:user.managedObjectContext];
    connection.to = user;
    connection.lastUpdateDate = [NSDate date];
    connection.status = ZMConnectionStatusSent;
    if (conversation == nil) {
        connection.conversation = [ZMConversation insertNewObjectInManagedObjectContext:user.managedObjectContext];

        [connection addWithUser:user];

        connection.conversation.creator = [ZMUser selfUserInContext:user.managedObjectContext];
    }
    else {
        connection.conversation = conversation;
        ///TODO: add user if not exists in participantRoles??
    }
    connection.conversation.conversationType = ZMConversationTypeConnection;
    connection.conversation.lastModifiedDate = connection.lastUpdateDate;
    return connection;
}

+ (instancetype)insertNewSentConnectionToUser:(ZMUser *)user;
{
    return [self insertNewSentConnectionToUser:user existingConversation:nil];
}

@end
