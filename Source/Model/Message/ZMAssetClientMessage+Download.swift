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


import Foundation



extension ZMAssetClientMessage {

    /// Name of notification fired when requesting a download of an image
    public static let imageDownloadNotificationName = NSNotification.Name(rawValue: "ZMAssetClientMessageImageDownloadNotification")
}

extension ZMImageMessage {
    
    public override func requestImageDownload() {
        // V2
        // objects with temp ID on the UI must just have been inserted so no need to download
        guard !self.objectID.isTemporaryID,
            let moc = self.managedObjectContext?.zm_userInterface else { return }
        NotificationInContext(name: ZMAssetClientMessage.imageDownloadNotificationName, context: moc.notificationContext, object: self.objectID).post()
    }
}
