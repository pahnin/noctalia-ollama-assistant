# Ollama Assistant Panel Plugin for Noctalia Shell

Forked from the official noctalia plugin as this was assistant only plugin, unlike the original
plugin which also has translation features, this also doesn't support Gemini

For typical usage this is an alternative to using chatgpt, tested using multiple models.
I am getting satisfactory responses with qwen3.5:9b on 16 GB VRAM GPU

## Features

### AI Chat
- **Multiple AI Providers**: Any endpoint compatible with OpenAI API endpoints.
- **Conversation History**: Persistent chat history with configurable length
- **Multiple Conversations**: Similar to ChatGPT web, have different conversations
- **System Prompts**: Customize AI behavior with system instructions
- **Temperature Control**: Adjust response creativity

#### Upcoming
- Condensed history for super long conversations
- Weighted Condensation mechanism to include conversation that user can vote
- Improved history storage ( currently json storage )


## Installation

1. Copy the `ollama-assistant` folder to `~/.config/noctalia/plugins/`
2. Restart Noctalia Shell
3. Enable the plugin in Settings > Plugins
4. Add the bar widget in Settings > Bar

## Configuration

### AI Provider Setup

#### OpenAI Compatible (OpenAI, OpenRouter, Ollama, etc.)
This provider serves as a universal client for any service compatible with the OpenAI Chat API.

**For Local Services (Ollama, LM Studio):**
1. Check "Local Mode" (hides API Key input).
2. Enter your **Base URL** (e.g., `http://localhost:11434/v1/chat/completions`).
3. Ensure your local server is running.


```

When an API key is set via environment variable:
- The settings UI input field will be disabled
- A message "Managed via environment variable" will be shown
- The env var value is used regardless of any value in settings.json

## IPC Commands

Control the plugin from the command line:

```bash
# Toggle panel visibility
qs -c noctalia-shell ipc call plugin:assistant-panel toggle

# Open panel
qs -c noctalia-shell ipc call plugin:assistant-panel open

# Close panel
qs -c noctalia-shell ipc call plugin:assistant-panel close

# Send a message
qs -c noctalia-shell ipc call plugin:assistant-panel send "Hello, how are you?"

# Clear chat history
qs -c noctalia-shell ipc call plugin:assistant-panel clear

# Translate text
qs -c noctalia-shell ipc call plugin:assistant-panel translateText "Hello world" "es"

# Change provider
qs -c noctalia-shell ipc call plugin:assistant-panel setProvider "openai_compatible"

# Change model
qs -c noctalia-shell ipc call plugin:assistant-panel setModel "gpt-4o-mini"
```

## Keybinding Examples

Add to your compositor configuration:

### Hyprland
```conf
bind = SUPER, A, exec, qs -c noctalia-shell ipc call plugin:assistant-panel toggle
```

### Niri
```kdl
binds {
    Mod+A { spawn "qs" "-c" "noctalia-shell" "ipc" "call" "plugin:assistant-panel" "toggle"; }
}
```

## Configuration Options

### AI Settings

| Setting | Description | Default |
|---------|-------------|---------|
| Provider | AI service (Google Gemini, OpenAI Compatible) | Google Gemini |
| Model | Model name (leave empty for provider default) | Per-provider |
| API Key | Provider API key (or use env var) | - |
| Local Mode | Toggle for local inference servers | false |
| Base URL | API Endpoint URL (Required for OpenAI Compatible) | `https://api.openai.com/v1/chat/completions` |
| Temperature | Response creativity (0.0 = focused, 2.0 = creative) | 0.7 |
| System Prompt | Instructions for AI behavior | General assistant |
| Max History Length | Number of messages to keep | 100 |


## License

MIT License - see repository for details.

## Credits

- Forked from Assistant Panel plugin https://github.com/noctalia-dev/noctalia-plugins/tree/main/assistant-panel
- Built for [Noctalia Shell](https://github.com/noctalia-dev/noctalia-shell)
