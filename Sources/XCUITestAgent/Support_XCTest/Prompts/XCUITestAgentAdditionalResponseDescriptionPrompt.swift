import Foundation

struct XCUITestAgentAdditionalResponseDescriptionPrompt {
    func make() -> String {
        return """
            JSON fields:
            - description: short summary; mention long delays if used.
            - actions: array of actions (tap, swipe, enterText, typeText, idle, success, failure).
            - elementFrame: required for tap/swipe/enterText/typeText (from hierarchy).
            - text: required for enterText/typeText.
            - swipeDirection: required for swipe (left/right/up/down).
            - delayUntilNextSequence: optional seconds before next sequence.

            Rules:
            1. Follow the test prompt exactly.
            2. If the prompt specifies a target value, select that exact value.
               Use screenshot + hierarchy to locate it; if not visible, swipe/scroll within the correct container to reveal it.
            3. Pickers are not scroll views. Target the picker column itself.
               If the prompt says swipe, you MUST swipe. If prompt is inconclusive, you may tap once; if no change, switch to swipe.
            4. Text entry: use enterText by default unless explicitly told not to. If paste fails, use one typeText with the full string.
            5. Only deviate when the requested action is impossible; explain why in description.
        """
    }
}
