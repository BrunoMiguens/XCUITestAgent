import Foundation

struct XCUITestAgentAdditionalResponseDescriptionPrompt {
    func make() -> String {
        return """
            Explanation of the JSON properties:
            "description" a description of the actions to take. If a longer delay until next action is used, also mention this in the description.
            "actions" is an array (with at least one element) of actions to take. List multiple actions in the array if a simple action needs to be repeated, e.g. when entering keyboard input.
            "actionType" is an enum for type of action to take. can be "tap", "swipe", "enterText", "typeText", "idle", "success" or "failure".
            "elementFrame" the frame (coordinates) of the element to tap as found in the debug view hierarchy (if action is tap, swipe, enterText or typeText).
            "text": the text to enter (if action is enterText or typeText).
            "swipeDirection": the direction to swipe towards (if action is swipe). can be "left", "right", "up" or "down".
            "delayUntilNextSequence" is the expected delay in seconds until next action sequence should be performed (if action is tap, swipe, enterText, typeText or idle), e.g. to take into account delays in presentation or loading states.
            Note on text entry: ALWAYS use "enterText" (clipboard paste) as the default for ALL text fields. Only use "typeText" (character-by-character keyboard typing) if the test description explicitly requests it or as a last resort after "enterText" has already failed on the same field. Do NOT proactively choose "typeText" — it is slower and more error-prone.
            For non-paste fields (custom/hidden inputs): use a SINGLE "typeText" action with the full string after tapping the entry area. Do NOT tap individual keyboard keys or emit one action per digit.
        """
    }
}
