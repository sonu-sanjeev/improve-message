# Improve Message & Define Word

Raycast script commands powered by Google Gemini AI:

- **Improve Message** — select text, hit a hotkey, and the improved version replaces it in place
- **Define Word** — select a word, hit a hotkey, and see its definition as a toast popup


## Setup

### 1. Get a free Gemini API key

Go to [aistudio.google.com/apikey](https://aistudio.google.com/apikey) and create a key. It's free.

### 2. Add the script to Raycast

- Open Raycast Settings (Cmd+,)
- Go to **Extensions** → **Script Commands**
- Click **Add Directories** and select the folder containing this script

### 3. Assign hotkeys

- Find "Improve Message" in Raycast Settings → Extensions
- Click on it and set a hotkey (recommended: **Cmd+Shift+I**)
- Find "Define Word" and set a hotkey (recommended: **Cmd+Shift+D**)

### 4. First run

The first time you use it, a dialog will ask for your API key. Paste it in and you're done — the key is securely stored in your macOS Keychain.

## Usage

1. Select any text in any app
2. Press your hotkey (Cmd+Shift+I)
3. Wait for the "tink" sound (processing) followed by "glass" sound (done)
4. The improved text replaces your selection

<video src="https://github.com/user-attachments/assets/75f37749-0e4e-44a2-971f-877a2ee8c6d5" width=300 height=180> </video>

### What it does

- **Short messages** (under 50 words): light fix for grammar, spelling, and punctuation while keeping your tone
- **Longer messages** (50+ words): full rewrite for clarity, professionalism, and flow

## Define Word

1. Select a word or short phrase (up to 10 words) in any app
2. Press your hotkey (Cmd+Shift+D)
3. A toast popup shows the definition
4. Your selected text stays untouched

<video src="https://github.com/user-attachments/assets/c1482948-740c-4df6-8bd6-d90af3d44f1c" width=300 height=180> </video>


## Managing your API key

Your API key is stored in the macOS Keychain. You can manage it from the terminal:

```bash
# View your key
security find-generic-password -s "improve-message" -a "gemini-api-key" -w

# Delete your key (you'll be prompted for a new one on next run)
security delete-generic-password -s "improve-message" -a "gemini-api-key"
```

Or open **Keychain Access.app** and search for "improve-message".

## Requirements

- macOS
- [Raycast](https://raycast.com)
- Python 3
