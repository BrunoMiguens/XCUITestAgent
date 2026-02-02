import Foundation
import XCTest

public struct XCUITestAgentActionPerformer: UITestAgentActionPerformer{
    private let activityScrope: String = "XCUITestAgent"
    private let app: XCUIApplication
    private let logger: UITestAgentLogger

    public init(app: XCUIApplication, logger: UITestAgentLogger = UITestAgentDefaultLogger()) {
        self.app = app
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
                    performEnterTextInteraction(
                        frame: frame,
                        text: text
                    )
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
                let sleepDuration = UInt32(ceil(actionSequence.delayUntilNextSequence ?? 1))
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
        ).press(forDuration: 0.2, thenDragTo: app.coordinate(
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

    fileprivate func performEnterTextInteraction(frame: CGRect, text: String) {
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
            sleep(1)
            // Set clipboard immediately before the long-press to minimise the
            // window in which Universal Clipboard (Handoff) can overwrite it.
            UIPasteboard.general.string = text
            appRelativeCoordinate.press(forDuration: 0.5)
            // Re-assert the clipboard value right before tapping Paste, in case
            // a Handoff sync occurred during the long-press gesture.
            UIPasteboard.general.string = text
            app.menuItems["Paste"].tap(timeout: 3)
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
            appRelativeCoordinate.tap()
            sleep(1)

            for character in text {
                let key = keyName(for: character)
                let keyElement = app.keys[key]
                if keyElement.waitForExistence(timeout: 1) {
                    keyElement.tap()
                } else {
                    logger.warning(category: .actions, "Keyboard key '\(key)' not found, skipping character '\(character)'")
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

    fileprivate func performSwipeInteraction(frame: CGRect, direction: SwipeDirection) {
        XCTContext.runActivity(named: "[\(activityScrope)]: Swiping \(direction) on element at \(frame)") { _ in
            switch direction {
            case .up:
                swipe(
                    app: app,
                    from: CGVector(dx: frame.midX, dy: frame.maxY),
                    to: CGVector(dx: frame.midX, dy: frame.minY)
                )
            case .down:
                swipe(
                    app: app,
                    from: CGVector(dx: frame.midX, dy: frame.minY),
                    to: CGVector(dx: frame.midX, dy: frame.maxY)
                )
            case .left:
                swipe(
                    app: app,
                    from: CGVector(dx: frame.maxX, dy: frame.midY),
                    to: CGVector(dx: frame.minX, dy: frame.midY)
                )
            case .right:
                swipe(
                    app: app,
                    from: CGVector(dx: frame.minX, dy: frame.midY),
                    to: CGVector(dx: frame.maxX, dy: frame.midY)
                )
            }
        }
    }
}

extension XCUIElement {
    fileprivate func tap(timeout: TimeInterval?) {
        if let timeout {
            XCTAssertTrue(waitForExistence(timeout: timeout))
        }
        if isHittable {
            tap()
        } else {
            coordinate(withNormalizedOffset: .zero).tap()
        }
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
