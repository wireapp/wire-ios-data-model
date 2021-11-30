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

extension NSManagedObjectContext {

    // This function setup the user info on the context, the session and self user must be initialised before end.
    func setupLocalCachedSessionAndSelfUser() {
        let request = ZMSession.sortedFetchRequest()

        guard let session = fetchOrAssert(request: request).first as? ZMSession else { return }

        userInfo[ZMUser.sessionObjectIDKey] = session.objectID
        ZMUser.boxSelfUser(session.selfUser, inContextUserInfo: self)
    }
    
}
