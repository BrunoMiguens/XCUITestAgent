import Foundation
import XCTest

public struct XCUITestAgentActionPerformer: UITestAgentActionPerformer{
    private let activityScrope: String = "XCUITestAgent"
    private let app: XCUIApplication
    private let logger: UITestAgentLogger
    private let configuration: XCUITestAgentConfiguration.ActionConfiguration

    public init(
        app: XCUIApplication,
        configuration: XCUITestAgentConfiguration.ActionConfiguration = XCUITestAgentConfiguration.ActionConfiguration(),
        logger: UITestAgentLogger = UITestAgentDefaultLogger()
    ) {
        self.app = app
        self.configuration = configuration
        self.logger = logger
    }

    public func reportCost(_ cost: LLMClientCost) {
        let formattedCost = String(format: "$%.6f", cost.totalCost)
        let tokens = "\(cost.usage.promptTokens) prompt + \(cost.usage.completionTokens) completion"
        logger.info(category: .actions, "Cost: \(formattedCost) (\(cost.model), \(tokens))")
        XCTContext.runActivity(named: "[\(activityScrope)]: Cost: \(formattedCost) (\(cost.model), \(tokens))") { _ in }
    }

    public func reportTotalCost(_ totalCost: Double, callCount: Int) {
        let formattedCost = String(format: "$%.6f", totalCost)
        logger.info(category: .actions, "Total cost: \(formattedCost) across \(callCount) call(s)")
        XCTContext.runActivity(named: "[\(activityScrope)]: Total cost: \(formattedCost) across \(callCount) call(s)") { _ in }
    }

    public func perform(_ actionSequence: ActionSequence) {
        logger.info(category: .actions, "Performing sequence: \(actionSequence.description)")
        XCTContext.runActivity(named: "[\(activityScrope)]: \(actionSequence.description)") { _ in
            var shouldSleep = true
            for action in actionSequence.actions {
                switch action {
                case .tap(let elementFrame):
                    logger.debug(category: .actions, "Executing tap at frame: \(elementFrame)")
                    performTapInteraction(frame: elementFrame)
                case .enterText(let frame, let text):
                    logger.debug(category: .actions, "Executing enterText '\(text)' at frame: \(frame)")
                    switch configuration.textEntryStrategy {
                    case .typeTextOnly:
                        performTypeTextInteraction(frame: frame, text: text)
                    case .enterTextOnly:
                        performEnterTextInteraction(
                            frame: frame,
                            text: text,
                            allowFallback: false
                        )
                    case .enterTextFirst:
                        performEnterTextInteraction(
                            frame: frame,
                            text: text,
                            allowFallback: true
                        )
                    }
                case .typeText(let frame, let text):
                    logger.debug(category: .actions, "Executing typeText '\(text)' at frame: \(frame)")
                    performTypeTextInteraction(
                        frame: frame,
                        text: text
                    )
                case .swipe(let frame, let direction):
                    logger.debug(category: .actions, "Executing swipe \(direction) at frame: \(frame)")
                    performSwipeInteraction(
                        frame: frame,
                        direction: direction
                    )
                case .idle:
                    logger.debug(category: .actions, "Executing idle (no-op)")
                case .success:
                    logger.info(category: .actions, "Test marked as SUCCESS")
                    shouldSleep = false
                case .failure:
                    logger.error(category: .actions, "Test marked as FAILURE: \(actionSequence.description)")
                    XCTFail(actionSequence.description)
                }
            }
            if shouldSleep {
                let sleepDuration = UInt32(ceil(actionSequence.delayUntilNextSequence ?? configuration.defaultSequenceDelay))
                logger.debug(category: .actions, "Sleeping for \(sleepDuration) second(s) before next sequence")
                XCTContext.runActivity(named: "[\(activityScrope)]: Waiting \(sleepDuration) seconds...") { _ in
                    _ = sleep(sleepDuration)
                }
            }
        }
    }

    private func swipe(app: XCUIApplication, from: CGVector, to: CGVector) {
        app.coordinate(
            withNormalizedOffset: normalizedCoordinate(
                from,
                relativeTo: app
            )
        ).press(forDuration: configuration.swipePressDuration, thenDragTo: app.coordinate(
            withNormalizedOffset: normalizedCoordinate(
                to,
                relativeTo: app
            )
        ))
    }
}

// MARK: - Interactions

extension XCUITestAgentActionPerformer {
    fileprivate func performTapInteraction(frame: CGRect) {
        guard
            let coordinate = vectorFromCenterOfFrame(frame)
        else {
            logger.warning(category: .actions, "Could not compute center of frame for tap: \(frame)")
            return
        }
        XCTContext.runActivity(named: "[\(activityScrope)]: Tapping coordinate \(coordinate)") { _ in
            app.coordinate(
                withNormalizedOffset: normalizedCoordinate(
                    coordinate,
                    relativeTo: app
                )
            ).tap()
        }
    }

    fileprivate func performEnterTextInteraction(frame: CGRect, text: String, allowFallback: Bool) {
        guard
            let coordinate = vectorFromCenterOfFrame(frame)
        else {
            logger.warning(category: .actions, "Could not compute center of frame for enterText: \(frame)")
            return
        }
        XCTContext.runActivity(named: "[\(activityScrope)]: Entering text \(text) into element at \(coordinate)") { _ in
            let appRelativeCoordinate = app.coordinate(
                withNormalizedOffset: normalizedCoordinate(
                    coordinate,
                    relativeTo: app
                )
            )
            appRelativeCoordinate.tap()
            if configuration.enterTextInitialDelay > 0 {
                _ = sleep(UInt32(ceil(configuration.enterTextInitialDelay)))
            }
            // Set clipboard immediately before the long-press to minimise the
            // window in which Universal Clipboard (Handoff) can overwrite it.
            UIPasteboard.general.string = text
            appRelativeCoordinate.press(forDuration: 0.5)
            // Re-assert the clipboard value right before tapping Paste, in case
            // a Handoff sync occurred during the long-press gesture.
            UIPasteboard.general.string = text
            let pasteMenuItem = app.menuItems["Paste"]
            let didPaste = pasteMenuItem.tap(timeout: configuration.pasteMenuTimeout)
            if !didPaste {
                logger.warning(category: .actions, "Paste menu item not found after \(configuration.pasteMenuTimeout)s")
                if allowFallback {
                    logger.info(category: .actions, "Falling back to typeText for text entry")
                    performTypeTextInteraction(frame: frame, text: text)
                }
            }
        }
    }

    fileprivate func performTypeTextInteraction(frame: CGRect, text: String) {
        guard
            let coordinate = vectorFromCenterOfFrame(frame)
        else {
            logger.warning(category: .actions, "Could not compute center of frame for typeText: \(frame)")
            return
        }
        XCTContext.runActivity(named: "[\(activityScrope)]: Typing text '\(text)' into element at \(coordinate)") { _ in
            let appRelativeCoordinate = app.coordinate(
                withNormalizedOffset: normalizedCoordinate(
                    coordinate,
                    relativeTo: app
                )
            )
            let targetElement = elementAtPoint(coordinate)
            if shouldSkipTapForTypeText(targetFrame: frame) {
                logger.debug(category: .actions, "Skipping pre-tap for typeText; target overlaps keyboard keys")
            } else {
                appRelativeCoordinate.tap()
                if configuration.typeTextInitialDelay > 0 {
                    _ = sleep(UInt32(ceil(configuration.typeTextInitialDelay)))
                }
            }

            let keyboard = app.keyboards.element
            var keyboardVisible = (keyboard.exists && keyboard.isHittable) || keyboard.waitForExistence(timeout: 0.5)
            if !keyboardVisible {
                appRelativeCoordinate.tap()
                keyboardVisible = keyboard.waitForExistence(timeout: 0.5) && keyboard.isHittable
            }
            if !keyboardVisible {
                if let targetElement {
                    logger.warning(category: .actions, "Keyboard not visible; falling back to element.typeText for full string")
                    targetElement.typeText(text)
                } else {
                    logger.warning(category: .actions, "Keyboard not visible and no target element; skipping typeText")
                }
                return
            }

            var index = text.startIndex
            while index < text.endIndex {
                let character = text[index]
                let key = keyName(for: character)
                let keyElement = app.keys[key]
                if keyElement.waitForExistence(timeout: 1) {
                    if keyElement.isHittable {
                        keyElement.tap()
                        index = text.index(after: index)
                    } else {
                        let remaining = String(text[index...])
                        if let targetElement {
                            logger.warning(category: .actions, "Keyboard key '\(key)' not hittable; falling back to element.typeText for remaining text")
                            targetElement.typeText(remaining)
                        } else {
                            logger.warning(category: .actions, "Keyboard key '\(key)' not hittable and no target element; skipping remaining text")
                        }
                        return
                    }
                } else {
                    logger.warning(category: .actions, "Keyboard key '\(key)' not found, skipping character '\(character)'")
                    index = text.index(after: index)
                }
            }
        }
    }

    fileprivate func keyName(for character: Character) -> String {
        switch character {
        case " ":
            return "space"
        case "\n":
            return "Return"
        default:
            return String(character)
        }
    }

    fileprivate func shouldSkipTapForTypeText(targetFrame: CGRect) -> Bool {
        let keyboard = app.keyboards.element
        guard keyboard.exists else { return false }

        for key in app.keys.allElementsBoundByIndex {
            if key.frame.intersects(targetFrame) {
                return true
            }
        }
        return false
    }

    fileprivate func elementAtPoint(_ point: CGVector) -> XCUIElement? {
        let target = CGPoint(x: point.dx, y: point.dy)
        var bestElement: XCUIElement?
        var bestArea: CGFloat = .greatestFiniteMagnitude

        for element in app.descendants(matching: .any).allElementsBoundByIndex {
            let frame = element.frame
            guard frame.contains(target) else { continue }
            let area = frame.width * frame.height
            if area < bestArea {
                bestArea = area
                bestElement = element
            }
        }
        return bestElement
    }

    fileprivate func performSwipeInteraction(frame: CGRect, direction: SwipeDirection) {
        XCTContext.runActivity(named: "[\(activityScrope)]: Swiping \(direction) on element at \(frame)") { _ in
            switch direction {
            case .up:
                let points = swipePoints(for: frame, direction: .up)
                swipe(app: app, from: points.start, to: points.end)
            case .down:
                let points = swipePoints(for: frame, direction: .down)
                swipe(app: app, from: points.start, to: points.end)
            case .left:
                let points = swipePoints(for: frame, direction: .left)
                swipe(app: app, from: points.start, to: points.end)
            case .right:
                let points = swipePoints(for: frame, direction: .right)
                swipe(app: app, from: points.start, to: points.end)
            }
        }
    }

    fileprivate func swipePoints(for frame: CGRect, direction: SwipeDirection) -> (start: CGVector, end: CGVector) {
        let insetX = safeInset(length: frame.width)
        let insetY = safeInset(length: frame.height)

        switch direction {
        case .up:
            return (
                CGVector(dx: frame.midX, dy: frame.maxY - insetY),
                CGVector(dx: frame.midX, dy: frame.minY + insetY)
            )
        case .down:
            return (
                CGVector(dx: frame.midX, dy: frame.minY + insetY),
                CGVector(dx: frame.midX, dy: frame.maxY - insetY)
            )
        case .left:
            return (
                CGVector(dx: frame.maxX - insetX, dy: frame.midY),
                CGVector(dx: frame.minX + insetX, dy: frame.midY)
            )
        case .right:
            return (
                CGVector(dx: frame.minX + insetX, dy: frame.midY),
                CGVector(dx: frame.maxX - insetX, dy: frame.midY)
            )
        }
    }

    fileprivate func safeInset(length: CGFloat) -> CGFloat {
        guard length > 0 else { return 0 }
        let rawInset = length * configuration.swipeInsetRatio
        let maxInset = max(0, length / 2 - 1)
        return min(rawInset, maxInset)
    }
}

extension XCUIElement {
    fileprivate func tap(timeout: TimeInterval?) -> Bool {
        if let timeout, !waitForExistence(timeout: timeout) {
            return false
        }
        if isHittable {
            tap()
        } else {
            coordinate(withNormalizedOffset: .zero).tap()
        }
        return true
    }
}

// MARK: - Coordinate mapping

fileprivate func vectorFromCenterOfFrame(_ frame: CGRect) -> CGVector? {
    // Calculate the center point in CGPoint form
    let centerX = Double(frame.minX + frame.width / 2)
    let centerY = Double(frame.minY + frame.height / 2)

    // Return the difference from the origin (0,0) as CGVector
    return CGVector(dx: centerX, dy: centerY)
}

fileprivate func normalizedCoordinate(_ coordinate: CGVector, relativeTo app: XCUIApplication) -> CGVector {
    let maxX = app.frame.maxX
    let maxY = app.frame.maxY
    return CGVector(
        dx: coordinate.dx / maxX,
        dy: coordinate.dy / maxY
    )
}
