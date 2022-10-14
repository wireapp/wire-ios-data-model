//
// Wire
// Copyright (C) 2022 Wire Swiss GmbH
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

import WireProtos

extension CommitBundle {
    func protobufData() throws -> Data {
        return try Proteus_CommitBundle(commitBundle: self).serializedData()
    }
}

extension Proteus_CommitBundle {
    init(commitBundle: CommitBundle) {
        self = Proteus_CommitBundle.with {
            $0.commit = commitBundle.commit.data
            $0.groupInfoBundle = Proteus_GroupInfoBundle(
                publicGroupState: commitBundle.publicGroupState
            )

            if let welcome = commitBundle.welcome {
                $0.welcome = welcome.data
            }
        }
    }
}

extension Proteus_GroupInfoBundle {
    // TODO: (David) update this to use the `PublicGroupState` representation from CC once released
    init(publicGroupState: Bytes) {
        self = Proteus_GroupInfoBundle.with {
            $0.groupInfo = publicGroupState.data
            $0.groupInfoType = .publicGroupState
            $0.ratchetTreeType = .full
        }
    }
}
