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
            Note on text entry: "enterText" pastes text from the clipboard, which is fast but may not work on custom or secure text fields where the paste menu does not appear. Use "typeText" instead, which taps the element to focus it and then types each character individually by tapping keyboard keys. Prefer "enterText" for standard text fields and "typeText" for secure fields, custom input views, or when paste is not available.
        """
    }
}
