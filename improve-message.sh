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
# 2. In Raycast: Settings → Extensions → Script Commands → Add Directories
#    → select the folder containing this script
# 3. Assign hotkey Cmd+Shift+I in Raycast command settings
# 4. On first run, a dialog will prompt you for your API key (stored in macOS Keychain)
# ──────────────────────────────────────────────────────────────────────

KEYCHAIN_SERVICE="improve-message"
KEYCHAIN_ACCOUNT="gemini-api-key"

# Messages with fewer words than this get a light polish; others get a full rewrite
WORD_THRESHOLD=100

# --- Load API key from macOS Keychain ---
GEMINI_API_KEY=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null)

# --- Prompt on first run ---
if [ -z "$GEMINI_API_KEY" ]; then
  GEMINI_API_KEY=$(osascript -e 'text returned of (display dialog "Enter your Gemini API key:" & return & return & "Get one free at aistudio.google.com/apikey" default answer "" with title "Improve Message Setup" with hidden answer)')

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

# --- Audio cue: processing started ---
afplay /System/Library/Sounds/Tink.aiff &

# --- Pick prompt based on word count ---
word_count=$(echo "$clipboard" | wc -w | tr -d ' ')

if [ "$word_count" -lt "$WORD_THRESHOLD" ]; then
  system_prompt="Fix grammar, spelling, and punctuation. You can rephrase slightly for clarity, but keep the same tone and level of formality. Keep contractions and informal language. Do not add filler phrases or pleasantries. Return only the corrected text."
else
  system_prompt="Improve this message for clarity and flow. Fix grammar and spelling. Tighten wordy sentences and remove redundancy. You can rephrase and restructure where it helps, but keep the author's tone, contractions, and level of formality. Do not add filler phrases, pleasantries, or corporate-sounding language. Return only the improved text."
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
