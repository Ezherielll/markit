# Known Issues

## Assertion `RawKeyboard` — "key down event when no keys are in keysPressed"

**Symptom (debug mode only):** log `EXCEPTION CAUGHT BY SERVICES LIBRARY` —
`Failed assertion: 'event is! RawKeyDownEvent || _keysPressed.isNotEmpty'`
(`package:flutter/src/services/raw_keyboard.dart`), triggered by
`RawKeyDownEvent(Alt Left, modifiers: 0)` on Windows.

**Status:** Framework bug (Flutter), not MarkIt application code — there are no custom
keyboard handlers in `lib/`. Root cause: a prior key-up event was dropped when focus switched
(e.g., Alt-Tab), leaving the framework's internal `_keysPressed` map empty when the next key-down
event arrived. The assertion is only active in debug mode; release and profile builds are
unaffected (no crash — exception caught safely by the services library, application continues).

**References:** flutter/flutter#124301, #125672, #150326 — empty assertion in
`RawKeyboard._keysPressed` when a key-down event arrives (inconsistent Alt/modifier events from OS/driver);
track status in the Flutter repository tracker.

**Mitigation:** No safe application patch exists (internal framework state);
do not override dependencies. Track fixes in future `flutter upgrade` releases.
