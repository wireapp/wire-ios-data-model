//
// Wire
// Copyright (C) 2021 Wire Swiss GmbH
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

import Foundation

extension ZMConversation {
    public static let ZMConversationUserDefinedNameKey = "userDefinedName"
    public static let ZMConversationArchivedChangedTimeStampKey = "archivedChangedTimestamp"
    public static let ZMConversationSilencedChangedTimeStampKey = "silencedChangedTimestamp"
    public static let ZMConversationParticipantRolesKey = "participantRoles"
    public static let ZMNormalizedUserDefinedNameKey = "normalizedUserDefinedName"
    public static let ZMConversationConversationTypeKey = "conversationType"
    public static let ZMConversationListIndicatorKey = "conversationListIndicator"
    public static let ZMConversationInternalEstimatedUnreadSelfMentionCountKey = "internalEstimatedUnreadSelfMentionCount"
    public static let ZMConversationInternalEstimatedUnreadCountKey = "internalEstimatedUnreadCount"
    public static let ZMConversationInternalEstimatedUnreadSelfReplyCountKey = "internalEstimatedUnreadSelfReplyCount"
    
    static let ZMConversationConnectionKey = "connection"
    static let ZMConversationHasUnreadMissedCallKey = "hasUnreadMissedCall"
    static let ZMConversationHasUnreadUnsentMessageKey = "hasUnreadUnsentMessage"
    static let ZMConversationNeedsToCalculateUnreadMessagesKey = "needsToCalculateUnreadMessages"
    static let ZMConversationIsArchivedKey = "internalIsArchived"
    static let ZMConversationMutedStatusKey = "mutedStatus"
    static let ZMConversationAllMessagesKey = "allMessages"
    static let ZMConversationHiddenMessagesKey = "hiddenMessages"
    static let ZMConversationNonTeamRolesKey = "nonTeamRoles"
    static let ZMConversationHasUnreadKnock = "hasUnreadKnock"
    
    static let ZMIsDimmedKey = "zmIsDimmed"
    static let ZMConversationLastServerTimeStampKey = "lastServerTimeStamp"
    static let ZMConversationLastReadServerTimeStampKey = "lastReadServerTimeStamp"
    static let ZMConversationClearedTimeStampKey = "clearedTimeStamp"
    static let ZMConversationExternalParticipantsStateKey = "externalParticipantsState"
    static let ZMConversationNeedsToDownloadRolesKey = "needsToDownloadRoles"
    static let ZMConversationLegalHoldStatusKey = "legalHoldStatus"
    static let ZMConversationNeedsToVerifyLegalHoldKey = "needsToVerifyLegalHold"
    static let ZMNotificationConversationKey = "ZMNotificationConversationKey"
    static let ZMConversationEstimatedUnreadCountKey = "estimatedUnreadCount"
    static let ZMConversationRemoteIdentifierDataKey = "remoteIdentifier_data"
    static let SecurityLevelKey = "securityLevel"
    static let ZMConversationLabelsKey = "labels"
    static let ZMConversationDomainKey = "domain"

    static let ConnectedUserKey = "connectedUser"
    static let CreatorKey = "creator"
    static let DraftMessageDataKey = "draftMessageData"
    static let DraftMessageNonceKey = "draftMessageNonce"
    static let IsPendingConnectionConversationKey = "isPendingConnectionConversation"
    static let LastModifiedDateKey = "lastModifiedDate"
    static let LastReadMessageKey = "lastReadMessage"
    static let lastEditableMessageKey = "lastEditableMessage"
    static let NeedsToBeUpdatedFromBackendKey = "needsToBeUpdatedFromBackend"
    static let RemoteIdentifierKey = "remoteIdentifier"
    static let TeamRemoteIdentifierKey = "teamRemoteIdentifier"
    static let VoiceChannelKey = "voiceChannel"
    static let VoiceChannelStateKey = "voiceChannelState"

    static let LocalMessageDestructionTimeoutKey = "localMessageDestructionTimeout"
    static let SyncedMessageDestructionTimeoutKey = "syncedMessageDestructionTimeout"
    static let HasReadReceiptsEnabledKey = "hasReadReceiptsEnabled"

    static let LanguageKey = "language"

    static let DownloadedMessageIDsDataKey = "downloadedMessageIDs_data"
    static let LastEventIDDataKey = "lastEventID_data"
    static let ClearedEventIDDataKey = "clearedEventID_data"
    static let ArchivedEventIDDataKey = "archivedEventID_data"
    static let LastReadEventIDDataKey = "lastReadEventID_data"

    static let TeamKey = "team"

    static let AccessModeStringsKey = "accessModeStrings"
    static let AccessRoleStringKey = "accessRoleString"
    
    static let TeamRemoteIdentifierDataKey = "teamRemoteIdentifier_data"
    
    static let ZMConversationLastUnreadKnockDateKey = "lastUnreadKnockDate"
    static let ZMConversationLastUnreadMissedCallDateKey = "lastUnreadMissedCallDate"
    static let ZMConversationLastReadLocalTimestampKey = "lastReadLocalTimestamp"

    static var ZMConversationDefaultLastReadTimestampSaveDelay: TimeInterval = 3.0;

    static let ZMConversationMaxEncodedTextMessageLength: UInt32 = 1500;
    static let ZMConversationMaxTextMessageLength: UInt32 = ZMConversationMaxEncodedTextMessageLength - 50; // Empirically we verified that the encoding adds 44 bytes
    
    public override var ignoredKeys: Set<AnyHashable>? {
            return (super.ignoredKeys ?? Set())
                .union([
                    #keyPath(ZMConversation.connection),
                    #keyPath(ZMConversation.conversationType),
                    #keyPath(ZMConversation.creator),
                    #keyPath(ZMConversation.draftMessageData),
                    #keyPath(ZMConversation.draftMessageNonce),
                    #keyPath(ZMConversation.lastModifiedDate),
                    #keyPath(ZMConversation.normalizedUserDefinedName),
                    #keyPath(ZMConversation.participantRoles),
                    #keyPath(ZMConversation.nonTeamRoles),
                    ZMConversation.VoiceChannelKey,
                    #keyPath(ZMConversation.hasUnreadMissedCall),
                    #keyPath(ZMConversation.hasUnreadUnsentMessage),
                    #keyPath(ZMConversation.needsToCalculateUnreadMessages),
                    #keyPath(ZMConversation.allMessages),
                    #keyPath(ZMConversation.hiddenMessages),
                    #keyPath(ZMConversation.lastServerTimeStamp),
                    #keyPath(ZMConversation.securityLevel),
                    #keyPath(ZMConversation.lastUnreadKnockDate),
                    #keyPath(ZMConversation.lastUnreadMissedCallDate),
                    ZMConversation.ZMConversationLastReadLocalTimestampKey,
                    #keyPath(ZMConversation.internalEstimatedUnreadCount),
                    #keyPath(ZMConversation.internalEstimatedUnreadSelfMentionCount),
                    #keyPath(ZMConversation.internalEstimatedUnreadSelfReplyCount),
                    #keyPath(ZMConversation.internalIsArchived),
                    #keyPath(ZMConversation.mutedStatus),
                    #keyPath(ZMConversation.localMessageDestructionTimeout),
                    #keyPath(ZMConversation.syncedMessageDestructionTimeout),
                    ZMConversation.DownloadedMessageIDsDataKey,
                    ZMConversation.LastEventIDDataKey,
                    ZMConversation.ClearedEventIDDataKey,
                    ZMConversation.ArchivedEventIDDataKey,
                    ZMConversation.LastReadEventIDDataKey,
                    #keyPath(ZMConversation.team),
                    #keyPath(ZMConversation.teamRemoteIdentifier),
                    ZMConversation.TeamRemoteIdentifierDataKey,
                    #keyPath(ZMConversation.accessModeStrings),
                    #keyPath(ZMConversation.accessRoleString),
                    #keyPath(ZMConversation.language),
                    #keyPath(ZMConversation.hasReadReceiptsEnabled),
                    #keyPath(ZMConversation.legalHoldStatus),
                    #keyPath(ZMConversation.needsToVerifyLegalHold),
                    #keyPath(ZMConversation.labels),
                    #keyPath(ZMConversation.needsToDownloadRoles),
                    #keyPath(ZMConversation.isSelfAnActiveMember), // DEPRECATED
                    "lastServerSyncedActiveParticipants", // DEPRECATED
                    #keyPath(ZMConversation.domain)
                ])
    }
}
