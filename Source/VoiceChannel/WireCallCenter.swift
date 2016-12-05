/*
 * Wire
 * Copyright (C) 2016 Wire Swiss GmbH
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import Foundation
import avs

public enum CallClosedReason : Int32 {
    case normal
    case internalError
    case timeout
    case lostMedia
    case unknown
}

public enum CallState : Equatable {
    /// There's no call
    case none
    /// Outgoing call is pending
    case outgoing
    /// Incoming call is pending
    case incoming(video: Bool)
    /// Established call
    case established
    /// Call in process of being terminated
    case terminating(reason: CallClosedReason)
    /// Unknown call state
    case unknown
    
    public static func ==(lhs: CallState, rhs: CallState) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            fallthrough
        case (.outgoing, .outgoing):
            fallthrough
        case (.incoming, .incoming):
            fallthrough
        case (.established, .established):
            fallthrough
        case (.terminating, .terminating):
            fallthrough
        case (.unknown, .unknown):
            return true
        default:
            return false
        }
    }
}

/// MARK - Video State Observer

@objc(AVSVideoReceiveState)
public enum VideoReceiveState : UInt32 {
    /// Sender is not sending video
    case stopped
    /// Sender is sending video
    case started
    /// Sender is sending video but currently has a bad connection
    case badConnection
}

public typealias WireCallCenterObserverToken = NSObjectProtocol

struct WireCallCenterVideoNotification {
    
    static let notificationName = Notification.Name("WireCallCenterVideoNotification")
    static let userInfoKey = notificationName.rawValue
    
    let videoReceiveState : VideoReceiveState
    
    init(videoReceiveState: VideoReceiveState) {
        self.videoReceiveState = videoReceiveState
    }
    
    func post() {
        NotificationCenter.default.post(name: WireCallCenterVideoNotification.notificationName,
                                        object: nil,
                                        userInfo: [WireCallCenterVideoNotification.userInfoKey : self])
    }
}

@objc
public protocol WireCallCenterVideoObserver : class {
    
    func receivingVideoDidChange(state: VideoReceiveState)
    
}

/// MARK - Call center Observer

struct WireCallCenterNotification {
    
    static let notificationName = Notification.Name("WireCallCenterNotification")
    static let userInfoKey = notificationName.rawValue
    
    let callState : CallState
    let conversationId : UUID
    let userId : UUID
    
    init(callState: CallState, conversationId: UUID, userId: UUID) {
        self.callState = callState
        self.conversationId = conversationId
        self.userId = userId
    }
    
    func post() {
        NotificationCenter.default.post(name: WireCallCenterNotification.notificationName,
                                        object: nil,
                                        userInfo: [WireCallCenterNotification.userInfoKey : self])
    }
}

public protocol WireCallCenterObserver : class {
    
    func callCenterDidChange(callState: CallState, conversationId: UUID, userId: UUID)
//    func callCenterMissedCall(conversationId: UUID, userId: UUID, timestamp: Date, video: Bool)
    
}

/// MARK - Call center transport

@objc
public protocol WireCallCenterTransport: class {
    
    func send(data: Data, conversationId: NSUUID, userId: NSUUID, completionHandler:((_ status: Int) -> Void))
    
}

private typealias WireCallMessageToken = UnsafeMutableRawPointer

@objc public class WireCallCenter : NSObject {
    
    private let zmLog = ZMSLog(tag: "calling")
    
    public var transport : WireCallCenterTransport? = nil
    
    deinit {
        wcall_close()
    }
    
    public init(userId: String, clientId: String) {
        
        super.init()
        
        let observer = Unmanaged.passUnretained(self).toOpaque()
        
        let resultValue = wcall_init(
            (userId as NSString).utf8String,
            (clientId as NSString).utf8String,
            { (version, context) in
                if let context = context {
                    _ = Unmanaged<WireCallCenter>.fromOpaque(context).takeUnretainedValue()
                    
                    
                }
            },
            { (token, conversationId, userId, clientId, data, dataLength, context) in
                guard let token = token, let context = context, let conversationId = conversationId, let userId = userId, let clientId = clientId, let data = data else {
                    return EINVAL // invalid argument
                }
                
                let selfReference = Unmanaged<WireCallCenter>.fromOpaque(context).takeUnretainedValue()
                
                return selfReference.send(token: token,
                                          conversationId: String.init(cString: conversationId),
                                          userId: String.init(cString: userId),
                                          clientId: String.init(cString: clientId),
                                          data: data,
                                          dataLength: dataLength)
            },
            { (conversationId, userId, isVideoCall, context) -> Void in
                guard let context = context, let conversationId = conversationId, let userId = userId else {
                    return
                }
                
                let selfReference = Unmanaged<WireCallCenter>.fromOpaque(context).takeUnretainedValue()
                
                selfReference.incoming(conversationId: String.init(cString: conversationId),
                                       userId: String.init(cString: userId),
                                       isVideoCall: isVideoCall != 0)
            },
            { (conversationId, messageTime, userId, isVideoCall, context) in
                guard let context = context, let conversationId = conversationId, let userId = userId else {
                    return
                }
                
                let selfReference = Unmanaged<WireCallCenter>.fromOpaque(context).takeUnretainedValue()
                let timestamp = Date(timeIntervalSince1970: TimeInterval(messageTime))
                
                selfReference.missed(conversationId: String.init(cString: conversationId),
                                     userId: String.init(cString: userId),
                                     timestamp: timestamp,
                                     isVideoCall: isVideoCall != 0)
            },
            { (conversationId, userId, context) in
                guard let context = context, let conversationId = conversationId, let userId = userId else {
                    return
                }
                
                let selfReference = Unmanaged<WireCallCenter>.fromOpaque(context).takeUnretainedValue()
                
                selfReference.established(conversationId: String.init(cString: conversationId),
                                          userId: String.init(cString: userId))
            },
            { (reason, conversationId, userId, metrics, context) in
                guard let context = context, let conversationId = conversationId, let userId = userId else {
                    return
                }
                
                let selfReference = Unmanaged<WireCallCenter>.fromOpaque(context).takeUnretainedValue()
                
                selfReference.closed(conversationId: String.init(cString: conversationId),
                                     userId: String.init(cString: userId),
                                     reason: CallClosedReason(rawValue: reason) ?? .internalError)
            },
            observer)
        
        if resultValue != 0 {
            fatal("Failed to initialise WireCallCenter")
        }
        
        wcall_set_video_state_handler({ (state, _) in
            guard let state = VideoReceiveState(rawValue: state.rawValue) else { return }
            WireCallCenterVideoNotification(videoReceiveState: state).post()
        })
    }
    
    private func send(token: WireCallMessageToken, conversationId: String, userId: String, clientId: String, data: UnsafePointer<UInt8>, dataLength: Int) -> Int32 {
        
        let bytes = UnsafeBufferPointer<UInt8>(start: data, count: dataLength)
        let transformedData = Data(buffer: bytes)
        
        transport?.send(data: transformedData, conversationId: NSUUID(uuidString: conversationId)!, userId: NSUUID(uuidString: userId)!, completionHandler: { status in
            wcall_resp(Int32(status), "", token)
        })
        
        return 0
    }
    
    private func incoming(conversationId: String, userId: String, isVideoCall: Bool) {
        zmLog.debug("incoming call")
        
        WireCallCenterNotification(callState: .incoming(video: isVideoCall), conversationId: UUID(uuidString: conversationId)!, userId: UUID(uuidString: userId)!).post()
    }
    
    private func missed(conversationId: String, userId: String, timestamp: Date, isVideoCall: Bool) {
        zmLog.debug("missed call")
        
        // TODO post notification
    }
    
    private func established(conversationId: String, userId: String) {
        zmLog.debug("established call")
        
        if wcall_is_video_call(conversationId) == 1 {
            wcall_set_video_send_active(conversationId, 1)
        }
        
        WireCallCenterNotification(callState: .established, conversationId: UUID(uuidString: conversationId)!, userId: UUID(uuidString: userId)!).post()
    }
    
    private func closed(conversationId: String, userId: String, reason: CallClosedReason) {
        zmLog.debug("closed call")
        
        WireCallCenterNotification(callState: .terminating(reason: reason), conversationId: UUID(uuidString: conversationId)!, userId: UUID(uuidString: userId)!).post()
    }
    
    // TODO find a better place for this method
    public func received(data: Data, currentTimestamp: Date, serverTimestamp: Date, conversationId: UUID, userId: UUID, clientId: String) {
        data.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
            let currentTime = UInt32(currentTimestamp.timeIntervalSince1970)
            let serverTime = UInt32(serverTimestamp.timeIntervalSince1970)
            
            wcall_recv_msg(bytes, data.count, currentTime, serverTime, conversationId.transportString(), userId.transportString(), clientId)
        }
    }
    
    // MARK - Observer
    
    /// Register observer of the call center call state. This will inform you when there's an incoming call etc.
    public class func addObserver(observer: WireCallCenterObserver) -> WireCallCenterObserverToken  {
        return NotificationCenter.default.addObserver(forName: WireCallCenterNotification.notificationName, object: nil, queue: nil) { (note) in
            if let note = note.userInfo?[WireCallCenterNotification.userInfoKey] as? WireCallCenterNotification {
                observer.callCenterDidChange(callState: note.callState, conversationId: note.conversationId, userId: note.userId)
            }
        }
    }
    
    public class func removeObserver(token: WireCallCenterObserverToken) {
        NotificationCenter.default.removeObserver(token)
    }
    
    /// Register observer of the video state. This will inform you when the remote caller starts, stops sending video.
    public class func addVideoObserver(observer: WireCallCenterVideoObserver) -> WireCallCenterObserverToken {
        return NotificationCenter.default.addObserver(forName: WireCallCenterVideoNotification.notificationName, object: nil, queue: .main) { (note) in
            if let note = note.userInfo?[WireCallCenterVideoNotification.userInfoKey] as? WireCallCenterVideoNotification {
                observer.receivingVideoDidChange(state: note.videoReceiveState)
            }
        }
    }
    
    public class func removeVideoObserver(token: WireCallCenterObserverToken) {
        NotificationCenter.default.removeObserver(token)
    }
    
    // MARK - Call state methods
    
    @objc(answerCallForConversationID:)
    public class func answerCall(conversationId: UUID) -> Bool {
        return wcall_answer(conversationId.transportString()) == 0
    }
    
    @objc(startCallForConversationID:video:)
    public class func startCall(conversationId: UUID, video: Bool) -> Bool {
        return wcall_start(conversationId.transportString(), video ? 1 : 0) == 0
    }
    
    @objc(closeCallForConversationID:)
    public class func closeCall(conversationId: UUID) {
        wcall_end(conversationId.transportString())
        WireCallCenterNotification(callState: .terminating(reason: .normal), conversationId: conversationId, userId: conversationId).post() // FIXME
    }
    
    @objc(ignoreCallForConversationID:)
    public class func ignoreCall(conversationId: UUID) {
        wcall_end(conversationId.transportString())
        WireCallCenterNotification(callState: .terminating(reason: .normal), conversationId: conversationId, userId: conversationId).post() // FIXME
    }
    
    @objc(toogleVideoForConversationID:isActive:)
    public class func toogleVideo(conversationID: UUID, active: Bool) {
        wcall_set_video_send_active(conversationID.transportString(), active ? 1 : 0)
    }
    
    @objc(isVideoCallForConversationID:)
    public class func isVideoCall(conversationId: UUID) -> Bool {
        return wcall_is_video_call(conversationId.transportString()) == 1 ? true : false
    }
 
    public class func callState(conversationId: UUID) -> CallState {
        switch wcall_get_state(conversationId.transportString()) {
        case WCALL_STATE_NONE:
            return .none
        case WCALL_STATE_INCOMING:
            return .incoming(video: false)
        case WCALL_STATE_OUTGOING:
            return .outgoing
        case WCALL_STATE_ESTABLISHED:
            return .established
        case WCALL_STATE_TERMINATING:
            return .terminating(reason: .unknown)
        default:
            return .unknown
        }
    }
}
