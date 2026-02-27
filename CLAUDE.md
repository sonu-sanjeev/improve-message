# improve-message

Raycast script command that improves selected text using Google Gemini AI. Triggered via hotkey (Cmd+Shift+I), it copies the selected text, sends it to Gemini, and pastes the improved version back in place.

## How it works

- `improve-message.sh` — improves selected text in place
  - Short messages (<50 words): light grammar/spelling/punctuation fix, preserving tone
  - Longer messages (>=50 words): full rewrite for clarity, professionalism, and flow
- `define-word.sh` — looks up the definition of a selected word or short phrase
  - Shows definition as a Raycast compact toast (does not modify the selected text)
  - Rejects selections longer than 10 words
- Both scripts use `gemini-2.5-flash-lite` model with temperature 0.3
- Both share the same API key stored in macOS Keychain
- macOS-only: relies on `pbcopy`/`pbpaste`, `osascript`, and `afplay` for sound cues

## Requirements

- macOS with Raycast installed
- Gemini API key (prompted on first run, stored in macOS Keychain)
- Python 3 (used for JSON construction and response parsing)
- `curl` for API calls

## Sound cues

- Tink: processing started
- Glass: success
- Basso: error
