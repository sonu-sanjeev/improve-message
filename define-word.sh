#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Define Word
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 📖
# @raycast.packageName Clipboard Tools

# Documentation:
# @raycast.description Look up the definition of a selected word or short phrase using Google Gemini AI.
# @raycast.author sonusanjeev

# ─── Setup Instructions ───────────────────────────────────────────────
# 1. Get a free Gemini API key from https://aistudio.google.com/apikey
# 2. In Raycast: Settings → Extensions → Script Commands → Add Directories
#    → select the folder containing this script
# 3. Assign hotkey Cmd+Shift+D in Raycast command settings
# 4. On first run, a dialog will prompt you for your API key (stored in macOS Keychain)
# ──────────────────────────────────────────────────────────────────────

KEYCHAIN_SERVICE="improve-message"
KEYCHAIN_ACCOUNT="gemini-api-key"

# Reject selections longer than this many words
MAX_WORDS=10

# Max time the tooltip stays visible (seconds). Press Escape to dismiss early.
TOOLTIP_DURATION=60

# --- Load API key from macOS Keychain ---
GEMINI_API_KEY=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null)

# --- Prompt on first run ---
if [ -z "$GEMINI_API_KEY" ]; then
  GEMINI_API_KEY=$(osascript -e 'text returned of (display dialog "Enter your Gemini API key:" & return & return & "Get one free at aistudio.google.com/apikey" default answer "" with title "Define Word Setup" with hidden answer)')

  if [ -z "$GEMINI_API_KEY" ]; then
    afplay /System/Library/Sounds/Basso.aiff &
    echo "No API key provided"
    exit 1
  fi

  security add-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w "$GEMINI_API_KEY"
  echo "API key saved to Keychain ✓"
fi

# --- Copy selected text to clipboard ---
osascript -e 'tell application "System Events" to keystroke "c" using command down'
sleep 0.2
clipboard=$(pbpaste)

if [ -z "$clipboard" ]; then
  afplay /System/Library/Sounds/Basso.aiff &
  echo "No text selected"
  exit 1
fi

# --- Validate selection length ---
word_count=$(echo "$clipboard" | wc -w | tr -d ' ')

if [ "$word_count" -gt "$MAX_WORDS" ]; then
  afplay /System/Library/Sounds/Basso.aiff &
  echo "Select a single word or short phrase"
  exit 1
fi

# --- Audio cue: processing started ---
afplay /System/Library/Sounds/Tink.aiff &

# --- System prompt for dictionary lookup ---
system_prompt="Define the given word in simple, everyday language that a non-native English speaker would understand.

If the word has multiple distinct meanings, list the top 2-3 most common ones numbered.

For each meaning, use this format:
word (part of speech): plain definition
Example: a short sentence using the word naturally
Synonym: a common synonym

Keep each definition to 1 sentence. Use plain words, avoid circular definitions. If you don't recognize the word, say Unknown word. Do not add quotes or preamble."

# --- Build JSON payload ---
json_payload=$(python3 -c "
import json, sys
system = sys.argv[1]
user = sys.stdin.read()
print(json.dumps({
    'contents': [{'parts': [{'text': user}]}],
    'systemInstruction': {'parts': [{'text': system}]},
    'generationConfig': {'temperature': 0.3}
}))
" "$system_prompt" <<< "$clipboard")

# --- Call Gemini API ---
response=$(curl -s -w "\n%{http_code}" \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent" \
  -H "Content-Type: application/json" \
  -H "x-goog-api-key: ${GEMINI_API_KEY}" \
  --data-binary @- <<< "$json_payload")

http_code=$(echo "$response" | tail -1)
body=$(echo "$response" | sed '$d')

if [ "$http_code" -ne 200 ]; then
  error_msg=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
msg = data.get('error', {}).get('message', '')
# Extract retry delay if present
for d in data.get('error', {}).get('details', []):
    if 'retryDelay' in d:
        msg += ' Retry in ' + d['retryDelay'] + '.'
        break
print(msg[:120] if msg else 'Unknown error')
" <<< "$body" 2>/dev/null)
  afplay /System/Library/Sounds/Basso.aiff &
  case "$http_code" in
    429) echo "Rate limited — wait ~1 min and retry. ${error_msg}" ;;
    400) echo "Bad request — ${error_msg}" ;;
    403) echo "API key invalid or unauthorized — ${error_msg}" ;;
    *)   echo "API error (HTTP $http_code) — ${error_msg}" ;;
  esac
  exit 1
fi

# --- Extract definition ---
definition=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
try:
    print(data['candidates'][0]['content']['parts'][0]['text'].strip())
except (KeyError, IndexError):
    print('ERROR: unexpected response', file=sys.stderr)
    sys.exit(1)
" <<< "$body")

if [ $? -ne 0 ] || [ -z "$definition" ]; then
  afplay /System/Library/Sounds/Basso.aiff &
  echo "Failed to get definition"
  exit 1
fi

afplay /System/Library/Sounds/Glass.aiff &

# --- Show definition as a floating tooltip near the cursor ---
osascript -l JavaScript - "$definition" "$TOOLTIP_DURATION" <<'JXAEOF'
function run(argv) {
    ObjC.import('Cocoa');

    var definition = argv[0];
    var duration = parseInt(argv[1]);

    // Activation policy: 1 = Accessory (no dock icon, no menu bar)
    var app = $.NSApplication.sharedApplication;
    app.setActivationPolicy(1);

    // Get mouse position (Cocoa coords: origin at bottom-left)
    var mouseLoc = $.NSEvent.mouseLocation;

    // Tooltip dimensions
    var winWidth = 350;
    var charPerLine = 40;
    var lineHeight = 18;
    var padding = 28;
    var lines = Math.ceil(definition.length / charPerLine);
    var winHeight = Math.max(50, Math.min(lines * lineHeight + padding, 200));

    // Position above cursor, centered horizontally
    var winX = mouseLoc.x - winWidth / 2;
    var winY = mouseLoc.y + 10;

    // Keep on screen
    var screen = $.NSScreen.mainScreen.frame;
    if (winX < 10) winX = 10;
    if (winX + winWidth > screen.size.width - 10) winX = screen.size.width - winWidth - 10;
    if (winY + winHeight > screen.size.height - 10) winY = screen.size.height - winHeight - 10;

    // Create borderless floating window (0 = borderless, 2 = buffered)
    var win = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(
        $.NSMakeRect(winX, winY, winWidth, winHeight), 0, 2, false
    );

    win.setLevel(3); // NSFloatingWindowLevel
    win.setBackgroundColor($.NSColor.blackColor);
    win.setOpaque(false);
    win.setHasShadow(true);

    // Definition text
    var tf = $.NSTextField.alloc.initWithFrame(
        $.NSMakeRect(14, 10, winWidth - 28, winHeight - 20)
    );
    tf.stringValue = $(definition);
    tf.textColor = $.NSColor.whiteColor;
    tf.backgroundColor = $.NSColor.clearColor;
    tf.setBordered(false);
    tf.setEditable(false);
    tf.setSelectable(false);
    tf.font = $.NSFont.systemFontOfSize(13);
    tf.lineBreakMode = $.NSLineBreakByWordWrapping;
    tf.cell.wraps = true;

    win.contentView.addSubview(tf);
    win.makeKeyAndOrderFront(null);
    app.activateIgnoringOtherApps(true);

    // Event loop: dismiss on Escape or after timeout
    var start = Date.now();
    var maxMs = duration * 1000;
    while (Date.now() - start < maxMs) {
        var event = app.nextEventMatchingMaskUntilDateInModeDequeue(
            0xFFFFFFFF,
            $.NSDate.dateWithTimeIntervalSinceNow(0.5),
            $('kCFRunLoopDefaultMode'),
            true
        );
        if (event) {
            if (event.type == 10 && event.keyCode == 53) break; // Escape
            app.sendEvent(event);
        }
    }
    win.close;
}
JXAEOF
