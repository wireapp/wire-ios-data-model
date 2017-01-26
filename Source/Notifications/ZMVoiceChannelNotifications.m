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

#import "ZMVoiceChannelNotifications+Internal.h"
#import "ZMConversation+Internal.h"
#import "ZMUser+Internal.h"
#import "ZMNotifications+Internal.h"
#import "ZMVoiceChannel+Internal.h"
#import <ZMCDataModel/ZMCDataModel-Swift.h>

static NSString * const ZMVoiceChannelParticipantVoiceGainChangedNotificationName = @"ZMVoiceChannelParticipantVoiceGainChangedNotificationName";


@implementation ZMVoiceChannelParticipantVoiceGainChangedNotification

+ (instancetype)notificationWithConversation:(ZMConversation *)conversation participant:(ZMUser *)user voiceGain:(double)voiceGain;
{
    ZMVoiceChannelParticipantVoiceGainChangedNotification *note = [[self alloc] initWithName:ZMVoiceChannelParticipantVoiceGainChangedNotificationName object:conversation];
    if (note != nil) {
        note.voiceGain = voiceGain;
        note.participant = user;
    }
    return note;
}

+ (void)addObserver:(id<ZMVoiceChannelVoiceGainObserver>)observer;
{
    ZM_ALLOW_MISSING_SELECTOR([[NSNotificationCenter defaultCenter] addObserver:observer selector:@selector(voiceChannelParticipantVoiceGainDidChange:) name:ZMVoiceChannelParticipantVoiceGainChangedNotificationName object:nil]);
}

+ (void)addObserver:(id<ZMVoiceChannelVoiceGainObserver>)observer forVoiceChannel:(ZMVoiceChannel *)voiceChannel;
{
    if (voiceChannel == nil) {
        return;
    }
    ZM_ALLOW_MISSING_SELECTOR([[NSNotificationCenter defaultCenter] addObserver:observer selector:@selector(voiceChannelParticipantVoiceGainDidChange:) name:ZMVoiceChannelParticipantVoiceGainChangedNotificationName object:voiceChannel.conversation]);
}

+ (void)removeObserver:(id<ZMVoiceChannelVoiceGainObserver>)observer;
{
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:ZMVoiceChannelParticipantVoiceGainChangedNotificationName object:nil];
}

- (ZMVoiceChannel *)voiceChannel;
{
    ZMConversation *conversation = self.object;
    return conversation.voiceChannel;
}

@end

