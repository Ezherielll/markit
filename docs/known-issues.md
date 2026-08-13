# Known Issues

## Assertion `RawKeyboard` — "key down event when no keys are in keysPressed"

**Gejala (debug only):** log `EXCEPTION CAUGHT BY SERVICES LIBRARY` —
`Failed assertion: 'event is! RawKeyDownEvent || _keysPressed.isNotEmpty'`
(`package:flutter/src/services/raw_keyboard.dart`), dipicu
`RawKeyDownEvent(Alt Left, modifiers: 0)` di Windows.

**Status:** framework bug (Flutter), bukan kode MarkIt — tidak ada handler
keyboard di `lib/`. Penyebab: key-up sebelumnya hilang saat fokus berpindah
(mis. Alt-Tab), sehingga `_keysPressed` internal framework kosong saat key-down
berikutnya tiba. Assertion hanya aktif di mode debug; release/profile tidak
terpengaruh (tidak crash — error sudah ditangkap services library, app lanjut).

**Referensi:** flutter/flutter#124301, #125672, #150326 — assertion
`RawKeyboard._keysPressed` kosong saat key-down tiba (event Alt/modifier
inkonsisten dari OS/driver); pantau status di tracker Flutter.

**Mitigasi:** tidak ada patch app yang aman (state internal framework);
jangan override dependency. Pantau fix di `flutter upgrade`.
