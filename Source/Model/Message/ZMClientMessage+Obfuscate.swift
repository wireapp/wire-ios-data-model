//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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

extension ZMClientMessage {
    override open func obfuscate() {
        super.obfuscate()

        guard
            let underlyingMessage = underlyingMessage,
            !underlyingMessage.hasKnock,
            let obfuscatedMessage = underlyingMessage.obfuscatedMessage()
        else {
            return
        }

        deleteContent()

        do {
            let data = try obfuscatedMessage.serializedData()
            try mergeWithExistingData(data)
        } catch {

        }
    }

    @discardableResult
    func mergeWithExistingData(_ data: Data) throws -> ZMGenericMessageData? {
        cachedUnderlyingMessage = nil
        
        let existingMessageData = dataSet
            .compactMap { $0 as? ZMGenericMessageData }
            .first
        
        guard let messageData = existingMessageData else {
            return createNewGenericMessage(with: data)
        }

        try messageData.setProtobuf(data)
        return messageData
    }
    
    private func createNewGenericMessage(with data: Data) -> ZMGenericMessageData? {
        guard let moc = managedObjectContext else { return nil }
        let messageData = ZMGenericMessageData.insertNewObject(in: moc)

        do {
            try messageData.setProtobuf(data)
            messageData.message = self
            return messageData
        } catch {
            moc.delete(messageData)
            return nil
        }
    }
}
