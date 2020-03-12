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

public protocol CompositeMessageData {
    var items: [CompositeMessageItem] { get }
}

public enum CompositeMessageItem {
    case text(ZMTextMessageData)
    case button(ButtonMessageData)
    
    internal init?(with protoItem: Composite.Item, message: ZMClientMessage) {
        guard let content = protoItem.content else { return nil }
        let itemContent = CompositeMessageItemContent(with: protoItem, message: message)
        switch content {
        case .button:
            self = .button(itemContent)
        case .text:
            self = .text(itemContent)
        }
    }
}

public protocol ButtonMessageData {
    var title: String? { get }
    var state: ButtonMessageState { get }
    func touchAction()
}

public enum ButtonMessageState {
    case unselected
    case selected
    case confirmed
    
    init(from state: ButtonState.State?) {
        guard let state = state else {
            self = .unselected
            return
        }
        self = ButtonMessageState(from: state)
    }
    
    init(from state: ButtonState.State) {
        switch state {
        case .unselected:
            self = .unselected
        case .selected:
            self = .selected
        case .confirmed:
            self = .confirmed
        }
    }
}

extension ZMClientMessage: CompositeMessageData {
    public var items: [CompositeMessageItem] {
        guard let message = underlyingMessage, case .some(.composite) = message.content else {
            return []
        }
        var items = [CompositeMessageItem]()
        for protoItem in message.composite.items {
            guard let compositeMessageItem = CompositeMessageItem(with: protoItem, message: self) else { continue }
            items += [compositeMessageItem]
        }
        return items
    }
}

extension ZMClientMessage: ConversationCompositeMessage {
    public var compositeMessageData: CompositeMessageData? {
        guard case .some(.composite) = underlyingMessage?.content else {
            return nil
        }
        return self
    }
}

fileprivate class CompositeMessageItemContent: NSObject {
    private let parentMessage: ZMClientMessage
    private let item: Composite.Item
    
    private var text: Text? {
        guard case .some(.text) = item.content else { return nil }
        return item.text
    }
    
    private var button: Button? {
        guard case .some(.button) = item.content else { return nil }
        return item.button
    }
    
    init(with item: Composite.Item, message: ZMClientMessage) {
        self.item = item
        self.parentMessage = message
    }
}

extension CompositeMessageItemContent: ZMTextMessageData {
    var messageText: String? {
        return text?.content.removingExtremeCombiningCharacters
    }
    
    var linkPreview: LinkMetadata? {
        return nil
    }
    
    var mentions: [Mention] {
        return Mention.mentions(from: text?.mentions, messageText: messageText, moc: parentMessage.managedObjectContext)
    }
    
    var quote: ZMMessage? {
        return nil
    }
    
    var linkPreviewHasImage: Bool {
        return false
    }
    
    var linkPreviewImageCacheKey: String? {
        return nil
    }
    
    var isQuotingSelf: Bool {
        return false
    }
    
    var hasQuote: Bool {
        return false
    }
    
    func fetchLinkPreviewImageData(with queue: DispatchQueue, completionHandler: @escaping (Data?) -> Void) {
        // no op
    }
    
    func requestLinkPreviewImageDownload() {
        // no op
    }
    
    func editText(_ text: String, mentions: [Mention], fetchLinkPreview: Bool) {
        // no op
    }
}

extension CompositeMessageItemContent: ButtonMessageData {
    var title: String? {
        return button?.text
    }
    
    var state: ButtonMessageState {
        return ButtonMessageState(from: buttonState?.state)
    }
    
    func touchAction() {
        guard let moc = parentMessage.managedObjectContext,
            let buttonId = button?.id,
            let messageId = parentMessage.nonce,
            !hasSelectedButton else { return }

        moc.performGroupedBlock { [weak self] in
            guard let `self` = self else { return }
            let buttonState = self.buttonState ??
                ButtonState.insert(with: buttonId, message: self.parentMessage, inContext: moc)
            buttonState.state = .selected
            self.parentMessage.conversation?.append(buttonActionWithId: buttonId, referenceMessageId: messageId)
            moc.saveOrRollback()
        }
    }
    
    private var hasSelectedButton: Bool {
        return parentMessage.buttonStates?.contains(where: {$0.state == .selected}) ?? false
    }
    
    private var buttonState: ButtonState? {
        guard let button = button else { return nil }

        return parentMessage.buttonStates?.first(where: { buttonState in
            guard let remoteIdentifier = buttonState.remoteIdentifier else { return false }
            return remoteIdentifier == button.id
        })
    }
}
