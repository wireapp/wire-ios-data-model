//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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

@objc
public protocol UserConnectionType: NSObjectProtocol {
 
    var isPendingApprovalByOtherUser: Bool { get }
    
}

@objc
public protocol UserType: NSObjectProtocol {
    
    /// The full name
    var name: String? { get }

    /// The given name / first name e.g. "John" for "John Smith"
    var displayName: String { get }
    
    /// The "@name" handle
    var handle: String? { get }
    
    /// The initials e.g. "JS" for "John Smith"
    var initials: String? { get }

    /// Email for the user
    var emailAddress: String? { get }

    /// Whether this is the self user
    var isSelfUser: Bool { get }
    
    /// The availability of the user
    var availability: Availability { get set }
    
    /// Wether or not the availability should be display for the user
    var shouldHideAvailability: Bool { get }
    
    /// The name of the team the user belongs to.
    var teamName: String? { get }
    
    /// Whether this is the member of a team
    var isTeamMember: Bool { get }

    /// The role (and permissions) e.g. partner, member, admin, owner
    var teamRole: TeamRole { get }
    
    /// Whether this is a service user (bot)
    var isServiceUser: Bool { get }

    /// Whether this uses uses SSO.
    var usesCompanyLogin: Bool { get }
    
    /// Is YES if we can send a connection request to this user.
    var isConnected: Bool { get }

    /// The one-to-one conversation with this user.
    var oneToOneConversation: ZMConversation? { get }

    /// Whether the user is blocked.
    var isBlocked: Bool { get }

    /// Whether the user is expired.
    var isExpired: Bool { get }

    /// Whether the user is pending connection approval from the self user.
    var isPendingApprovalBySelfUser: Bool { get }

    /// Whether the user is pending connection approval from another user.
    var isPendingApprovalByOtherUser: Bool { get }

    /// Whether the user can be connected by the self user.
    var canBeConnected: Bool { get }
    
    /// Whether the account of the user is deleted
    var isAccountDeleted: Bool { get }
    
    /// Wheater the user is under legal hold
    var isUnderLegalHold: Bool { get }

    var accentColorValue: ZMAccentColor { get }

    /// Whether the user is a wireless user.
    var isWirelessUser: Bool { get }
    
    /// The time remaining before the user expires.
    var expiresAfter: TimeInterval { get }
    
    /// Message text if there's a pending connection request
    var connectionRequestMessage: String? { get }
    
    var smallProfileImageCacheKey: String? { get }
    var mediumProfileImageCacheKey: String? { get }
    
    var previewImageData: Data? { get }
    var completeImageData: Data? { get }
    
    /// Whether read receipts are enabled for this user.
    var readReceiptsEnabled: Bool { get }
    
    /// The extended metadata for this user, provided by SCIM.
    var richProfile: [UserRichProfileField] { get }
    
    /// Used to trigger rich profile download from backend
    var needsRichProfileUpdate: Bool { get set }
    
    /// Conversations the user is a currently a participant of
    var activeConversations: Set<ZMConversation> { get }
    
    /// All clients belonging to the user
    var allClients: [UserClientType] { get }
    
    func requestPreviewProfileImage()
    func requestCompleteProfileImage()
    
    /// Whether this user is a guest in a conversation
    func isGuest(in conversation: ZMConversation) -> Bool
    
    /// Fetch a profile image with the given size on the given queue
    func imageData(for size: ProfileImageSize, queue: DispatchQueue, completion: @escaping (_ imageData: Data?) -> Void)
    
    /// Request a refresh of the user data from the backend.
    /// This is useful for non-connected user, that we will otherwise never re-fetch
    func refreshData()
    
    /// Sends a connection request to the given user. May be a no-op, eg. if we're already connected.
    /// A ZMUserChangeNotification with the searchUser as object will be sent notifiying about the connection status change
    /// You should stop from observing the searchUser and start observing the user from there on
    func connect(message: String)
    
    /// Determines whether the user profile is managed by Wire or other services (SCIM)
    var managedByWire: Bool { get }
    
    // MARK: - Permissions
    
    /// Whether the user can create conversations.
    @objc
    func canCreateConversation(type: ZMConversationType) -> Bool
    
    /// Whether the user can create services
    var canCreateService: Bool { get }
    
    /// Whether the user can administate the team
    var canManageTeam: Bool { get }

    /// Whether the user can access the private company information of the other given user.
    func canAccessCompanyInformation(of user: UserType) -> Bool
    
    /// Whether the user can add services to the conversation
    @objc(canAddServiceToConversation:)
    func canAddService(to conversation: ZMConversation) -> Bool
    
    /// Whether the user can remove services from the conversation
    @objc(canRemoveServiceFromConversation:)
    func canRemoveService(from conversation: ZMConversation) -> Bool

    /// Whether the user can add another user to the conversation.
    @objc(canAddUserToConversation:)
    func canAddUser(to conversation: ZMConversation) -> Bool

    /// Whether the user can remove another user from the conversation.
    @objc(canRemoveUserFromConversation:)
    func canRemoveUser(from conversation: ZMConversation) -> Bool
    
    /// Whether the user can delete the conversation
    @objc(canDeleteConversation:)
    func canDeleteConversation(_ conversation: ZMConversation) -> Bool

    /// Wheter the user can modify roles of members in the conversation.
    @objc(canModifyOtherMemberInConversation:)
    func canModifyOtherMember(in conversation: ZMConversation) -> Bool
    
    /// Whether the user can toggle the read receipts setting in the conversation.
    @objc(canModifyReadReceiptSettingsInConversation:)
    func canModifyReadReceiptSettings(in conversation: ZMConversation) -> Bool
    
    /// Whether the user can toggle the emphemeral setting in the conversation.
    @objc(canModifyEphemeralSettingsInConversation:)
    func canModifyEphemeralSettings(in conversation: ZMConversation) -> Bool
    
    /// Whether the user can change the notification level setting in the conversation.
    @objc(canModifyNotificationSettingsInConversation:)
    func canModifyNotificationSettings(in conversation: ZMConversation) -> Bool
    
    /// Whether the user can toggle the access level setting in the conversation.
    @objc(canModifyAccessControlSettingsInConversation:)
    func canModifyAccessControlSettings(in conversation: ZMConversation) -> Bool
    
    /// Whether the user can update the title of the conversation.
    @objc(canModifyTitleInConversation:)
    func canModifyTitle(in conversation: ZMConversation) -> Bool

    /// Whether the user can leave the conversation.
    @objc(canLeave:)
    func canLeave(_ conversation: ZMConversation) -> Bool

    /// Whether the user is group admin in the conversation.
    @objc(isGroupAdminInConversation:)
    func isGroupAdmin(in conversation: ZMConversation) -> Bool
}
