import Foundation
import CoreGraphics

public struct LLMClientJSONResponseMapper: LLMClientResponseMapper {
    public enum LLMClientJSONResponseMapperError: Error {
        case decodingError(reason: String)
    }

    private let decoder: JSONDecoder
    private let frameMapper: LLMClientResponseFrameMapper
    private let logger: UITestAgentLogger

    public init(
        decoder: JSONDecoder = JSONDecoder(),
        frameMapper: LLMClientResponseFrameMapper,
        logger: UITestAgentLogger = UITestAgentDefaultLogger()
    ) {
        self.decoder = decoder
        self.frameMapper = frameMapper
        self.logger = logger
    }

    public func map(response: String) throws -> ActionSequence {
        logger.debug(category: .mapping, "Decoding JSON response (\(response.count) chars)")

        let jsonString = extractJSON(from: response) ?? response

        guard let responseData = jsonString.data(using: .utf8) else {
            logger.error(category: .mapping, "Failed to convert response string to UTF-8 data")
            throw LLMClientJSONResponseMapperError.decodingError(
                reason: "Unable to convert response string to data"
            )
        }

        let codedResponse: LLMClientActionSequenceReponse
        do {
            codedResponse = try decoder.decode(
                LLMClientActionSequenceReponse.self,
                from: responseData
            )
        } catch {
            logger.error(category: .mapping, "JSON decoding failed: \(error.localizedDescription). Raw response: \(String(response.prefix(500)))")
            throw error
        }

        let normalizedResponse = normalizeDigitTapSequence(codedResponse)
        if normalizedResponse.actions.count != codedResponse.actions.count {
            logger.info(
                category: .mapping,
                "Normalized digit tap sequence into typeText (actions: \(codedResponse.actions.count) -> \(normalizedResponse.actions.count))"
            )
        }

        logger.debug(category: .mapping, "Decoded response: '\(normalizedResponse.description)' with \(normalizedResponse.actions.count) action(s)")

        let actions = try mapActions(normalizedResponse.actions)
        logger.info(category: .mapping, "Mapped \(actions.count) action(s): \(codedResponse.description)")

        return ActionSequence(
            description: normalizedResponse.description,
            actions: actions,
            delayUntilNextSequence: normalizedResponse.delayUntilNextSequence
        )
    }
}

extension LLMClientJSONResponseMapper {
    /// Attempts to extract a JSON object from a string that may contain surrounding text.
    /// Returns nil if no valid JSON object boundaries are found.
    fileprivate func extractJSON(from string: String) -> String? {
        guard let openIndex = string.firstIndex(of: "{"),
              let closeIndex = string.lastIndex(of: "}") else {
            return nil
        }
        let extracted = String(string[openIndex...closeIndex])
        if extracted == string { return nil }
        logger.debug(category: .mapping, "Extracted JSON object from response with surrounding text")
        return extracted
    }

    fileprivate func normalizeDigitTapSequence(_ response: LLMClientActionSequenceReponse) -> LLMClientActionSequenceReponse {
        let hasTextEntry = response.actions.contains { action in
            action.actionType == .enterText || action.actionType == .typeText
        }
        if hasTextEntry { return response }
        let hasNonTapActions = response.actions.contains { $0.actionType != .tap }
        if hasNonTapActions { return response }

        let digitTapActions = response.actions.filter { action in
            guard action.actionType == .tap,
                  let text = action.text,
                  text.count == 1,
                  text.allSatisfy({ $0.isNumber }) else {
                return false
            }
            return true
        }

        let minimumDigits = 6
        let tapActions = response.actions.filter { $0.actionType == .tap }
        if digitTapActions.count < minimumDigits && tapActions.count < minimumDigits { return response }

        let digitsFromTaps = digitTapActions.compactMap(\.text).joined()
        var textToType = digitsFromTaps
        if textToType.isEmpty {
            if let sequenceText = response.text {
                textToType = sequenceText.filter { $0.isNumber }
            }
        }
        if textToType.isEmpty { return response }
        if digitTapActions.isEmpty {
            let lowerDescription = response.description.lowercased()
            let typingKeywords = ["type", "typing", "digit", "keyboard", "keypad", "enter"]
            let indicatesTyping = typingKeywords.contains { lowerDescription.contains($0) }
            if !indicatesTyping { return response }
        }

        var replaceTapIndices = Set<Int>()
        var focusTapIndex: Int?
        if !digitTapActions.isEmpty {
            let digitTapIndices: [Int] = response.actions.enumerated().compactMap { index, action in
                guard action.actionType == .tap,
                      let text = action.text,
                      text.count == 1,
                      text.allSatisfy({ $0.isNumber }) else {
                    return nil
                }
                return index
            }
            replaceTapIndices = Set(digitTapIndices)
            if let firstDigitIndex = digitTapIndices.min() {
                for index in stride(from: firstDigitIndex - 1, through: 0, by: -1) {
                    if response.actions[index].actionType == .tap {
                        focusTapIndex = index
                        break
                    }
                }
            }
        } else {
            let shouldPreserveLastTap = response.description.lowercased().contains("continue")
            let tapIndices = response.actions.enumerated().compactMap { index, action in
                action.actionType == .tap ? index : nil
            }
            if shouldPreserveLastTap, tapIndices.count > minimumDigits, let lastTapIndex = tapIndices.last {
                replaceTapIndices = Set(tapIndices.dropLast())
                if replaceTapIndices.isEmpty {
                    replaceTapIndices = [lastTapIndex]
                }
            } else {
                replaceTapIndices = Set(tapIndices)
            }
            focusTapIndex = tapIndices.first
        }

        guard let tapFrameIndex = focusTapIndex ?? replaceTapIndices.sorted().first,
              let firstTapFrame = response.actions[tapFrameIndex].elementFrame else { return response }

        var normalizedActions: [LLMClientReponseAction] = []
        var insertedTypeText = false
        for (index, action) in response.actions.enumerated() {
            if replaceTapIndices.contains(index) {
                if !insertedTypeText {
                    normalizedActions.append(LLMClientReponseAction(
                        actionType: .typeText,
                        elementFrame: firstTapFrame,
                        swipeDirection: nil,
                        text: textToType
                    ))
                    insertedTypeText = true
                }
                continue
            }
            normalizedActions.append(action)
        }

        return LLMClientActionSequenceReponse(
            description: response.description,
            actions: normalizedActions,
            delayUntilNextSequence: response.delayUntilNextSequence,
            text: response.text
        )
    }

    fileprivate func mapActions(_ actions: [LLMClientReponseAction]) throws -> [Action] {
        return try actions.map { action in
            switch action.actionType {
            case .tap:
                guard
                    let _elementFrame = action.elementFrame, !_elementFrame.isEmpty
                else {
                    logger.error(category: .mapping, "Invalid tap action: no element frame provided")
                    throw LLMClientJSONResponseMapperError.decodingError(
                        reason: "Invalid tap action (no element frame provided)"
                    )
                }
                let elementFrame = try frameMapper.map(_elementFrame)
                logger.debug(category: .mapping, "Mapped tap action at frame: \(elementFrame)")
                return .tap(elementFrame: elementFrame)

            case .enterText:
                guard let text = action.text, !text.isEmpty else {
                    logger.error(category: .mapping, "Invalid text action: text is nil or empty")
                    throw LLMClientJSONResponseMapperError.decodingError(
                        reason: "Invalid text action (text: nil or empty)"
                    )
                }
                guard
                    let _elementFrame = action.elementFrame, !_elementFrame.isEmpty
                else {
                    logger.error(category: .mapping, "Invalid enter text action: no element frame provided")
                    throw LLMClientJSONResponseMapperError.decodingError(
                        reason: "Invalid enter text action (no element frame provided)"
                    )
                }
                let elementFrame = try frameMapper.map(_elementFrame)
                logger.debug(category: .mapping, "Mapped enterText action: '\(text)' at frame: \(elementFrame)")
                return .enterText(elementFrame: elementFrame, text: text)

            case .typeText:
                guard let text = action.text, !text.isEmpty else {
                    logger.error(category: .mapping, "Invalid typeText action: text is nil or empty")
                    throw LLMClientJSONResponseMapperError.decodingError(
                        reason: "Invalid typeText action (text: nil or empty)"
                    )
                }
                guard
                    let _elementFrame = action.elementFrame, !_elementFrame.isEmpty
                else {
                    logger.error(category: .mapping, "Invalid typeText action: no element frame provided")
                    throw LLMClientJSONResponseMapperError.decodingError(
                        reason: "Invalid typeText action (no element frame provided)"
                    )
                }
                let elementFrame = try frameMapper.map(_elementFrame)
                logger.debug(category: .mapping, "Mapped typeText action: '\(text)' at frame: \(elementFrame)")
                return .typeText(elementFrame: elementFrame, text: text)

            case .swipe:
                guard
                    let _direction = action.swipeDirection,
                    let direction = SwipeDirection(rawValue: _direction.rawValue)
                else {
                    logger.error(category: .mapping, "Invalid swipe action: direction '\(action.swipeDirection?.rawValue ?? "nil")'")
                    throw LLMClientJSONResponseMapperError.decodingError(
                        reason: "Invalid swipe action (swipe direction: \(action.swipeDirection?.rawValue ?? ""))"
                    )
                }
                guard
                    let _elementFrame = action.elementFrame, !_elementFrame.isEmpty
                else {
                    logger.error(category: .mapping, "Invalid swipe action: no element frame provided")
                    throw LLMClientJSONResponseMapperError.decodingError(
                        reason: "Invalid swipe action (no element frame provided)"
                    )
                }
                let elementFrame = try frameMapper.map(_elementFrame)
                logger.debug(category: .mapping, "Mapped swipe action: \(direction) at frame: \(elementFrame)")
                return .swipe(
                    elementFrame: elementFrame,
                    direction: direction
                )

            case .idle:
                logger.debug(category: .mapping, "Mapped idle action")
                return .idle

            case .success:
                logger.info(category: .mapping, "Mapped success action")
                return .success

            case .failure:
                logger.warning(category: .mapping, "Mapped failure action")
                return .failure
            }
        }
    }
}
