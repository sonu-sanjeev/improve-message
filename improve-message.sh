#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Improve Message
# @raycast.mode silent

# Optional parameters:
# @raycast.icon 💬
# @raycast.packageName Clipboard Tools

# Documentation:
# @raycast.description Polishes clipboard text using Google Gemini AI. Light polish for short messages, professional rewrite for longer ones.
# @raycast.author sonusanjeev

# ─── Setup Instructions ───────────────────────────────────────────────
# 1. Get a free Gemini API key from https://aistudio.google.com/apikey
# 2. Add to your shell config (~/.zshrc):
#      export GEMINI_API_KEY="your-key-here"
# 3. In Raycast: Settings → Extensions → Script Commands → Add Directories
#    → select the folder containing this script
# 4. Assign hotkey Cmd+Shift+I in Raycast command settings
# ──────────────────────────────────────────────────────────────────────

# Messages with fewer words than this get a light polish; others get a full rewrite
WORD_THRESHOLD=50

# --- Load API key from shell config (Raycast runs non-interactive shells) ---
GEMINI_API_KEY=$(grep '^export GEMINI_API_KEY=' "$HOME/.zshrc" | cut -d'"' -f2)

# --- Validate API key ---
if [ -z "$GEMINI_API_KEY" ]; then
  afplay /System/Library/Sounds/Basso.aiff &
  echo "Set GEMINI_API_KEY in your shell config (~/.zshrc)"
  exit 1
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

# --- Audio cue: processing started ---
afplay /System/Library/Sounds/Tink.aiff &

# --- Pick prompt based on word count ---
word_count=$(echo "$clipboard" | wc -w | tr -d ' ')

if [ "$word_count" -lt "$WORD_THRESHOLD" ]; then
  system_prompt="Fix grammar, spelling, and punctuation. Keep the original tone, style, and casualness. Do not add or remove information. Return only the corrected text."
else
  system_prompt="Improve this message for clarity, professionalism, and flow. Fix grammar and spelling. Restructure sentences if needed for better readability. Keep the core meaning intact. Return only the improved text."
fi

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

# --- Extract result ---
improved=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
try:
    print(data['candidates'][0]['content']['parts'][0]['text'].strip())
except (KeyError, IndexError):
    print('ERROR: unexpected response', file=sys.stderr)
    sys.exit(1)
" <<< "$body")

if [ $? -ne 0 ] || [ -z "$improved" ]; then
  afplay /System/Library/Sounds/Basso.aiff &
  echo "Failed to parse API response"
  exit 1
fi

# --- Copy to clipboard and paste back to replace selection ---
echo -n "$improved" | pbcopy
sleep 0.1
osascript -e 'tell application "System Events" to keystroke "v" using command down'
afplay /System/Library/Sounds/Glass.aiff &
echo "Message improved ✓"
