import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import "ProviderLogic.js" as ProviderLogic
import "Constants.js" as Constants

Item {
  // Internal flag to prevent duplicate error messages
  id: root

  property var pluginApi: null
  property string _responseBuffer: ""

  // AI Chat state
  property var conversations: {}
  property var memoryStore: {}
  property int activeConversationIndex: 0
  property var messages: []
  property bool isGenerating: false
  property string currentResponse: ""
  property string errorMessage: ""
  property bool isManuallyStopped: false
  property int requestConversationIndex: -1

  // Cache directory for state (messages) - use global noctalia cache
  readonly property string cacheDir: typeof Settings !== 'undefined' && Settings.cacheDir ? Settings.cacheDir + "plugins/ollama-assistant/" : ""
  readonly property string stateCachePath: cacheDir + "state.json"

  property string chatInputText: "" // Chat input state - persisted to cache
  property int chatInputCursorPosition: 0 // Chat input cursor position - persisted to cache

  // Provider configurations
  readonly property var provider: {
    "name": "OpenAI Compatible",
    "defaultModel": "qwen3.5:9b",
    // Endpoint is dynamic based on settings (openaiBaseUrl)
    "endpoint": ""
  }

  readonly property string model: {
    var saved = pluginApi?.pluginSettings?.ai?.model;
    if (saved !== undefined && saved !== "")
      return saved;
    return provider?.defaultModel || "";
  }

  readonly property string apiKey: pluginApi?.pluginSettings?.ai?.apiKey || ""

  // OpenAI Compatible Settings
  readonly property string systemPrompt: pluginApi?.pluginSettings?.ai?.systemPrompt || ""
  readonly property real temperature: pluginApi?.pluginSettings?.ai?.temperature || 0.7
  readonly property bool openaiLocal: pluginApi?.pluginSettings?.ai?.openaiLocal ?? true
  readonly property string openaiBaseUrl: {
    var url = pluginApi?.pluginSettings?.ai?.openaiBaseUrl || "";
    if (url === "")
      if (openaiLocal)
        return "http://localhost:11434/v1/chat/completions";
      else
        return "https://api.openai.com/v1/chat/completions";
    return url;
  }

  Component.onCompleted: {
    Logger.d("OllamaAssistant", "Plugin initialized");
    // State loading is handled by FileView onLoaded
    ensureCacheDir();
  }

  // Ensure cache directory exists
  function ensureCacheDir() {
    if (cacheDir) {
      Quickshell.execDetached(["mkdir", "-p", cacheDir]);
    }
  }

  // FileView for state cache (messages)
  FileView {
    id: stateCacheFile
    path: root.stateCachePath
    watchChanges: false

    onLoaded: {
      loadStateFromCache();
    }

    onLoadFailed: function (error) {
      if (error === 2) {
        // File doesn't exist, start fresh
        Logger.d("OllamaAssistant", "No cache file found, starting fresh");
      } else {
        Logger.e("OllamaAssistant", "Failed to load state cache: " + error);
      }
    }
  }

  // Load state from cache file
  function loadStateFromCache() {
    var content = stateCacheFile.text();
    Logger.d("OllamaAssistant", "before calling processLoadedState");
    var result = ProviderLogic.processLoadedState(content);

    if (!result) {
      Logger.d("OllamaAssistant", "Empty cache file, starting fresh");
      return;
    }

    if (result.error) {
      Logger.e("OllamaAssistant", "Failed to parse state cache: " + result.error);
      return;
    }

    root.conversations = result.conversations;
    root.activeConversationIndex = result.activeConversationIndex;
    root.messages = root.conversations[root.activeConversationIndex].messages || [];
    root.chatInputText = result.chatInputText;
    root.chatInputCursorPosition = result.chatInputCursorPosition;
    root.memoryStore = result.memoryStore; 
    Logger.d("OllamaAssistant", "Loaded " + root.messages.length + " messages from cache");
  }

  // Debounced save timer
  Timer {
    id: saveStateTimer
    interval: 500
    onTriggered: performSaveState()
  }

  property bool saveStateQueued: false

  function saveState() {
    saveStateQueued = true;
    saveStateTimer.restart();
  }

  function performSaveState() {
    if (!saveStateQueued || !cacheDir)
      return;
    saveStateQueued = false;

    try {
      ensureCacheDir();

      var maxHistory = pluginApi?.pluginSettings?.maxHistoryLength || 100;
      var dataStr = ProviderLogic.prepareStateForSave(
        root.conversations,
        root.memoryStore,
        root.activeConversationIndex,
        root.chatInputText,
        root.chatInputCursorPosition
      );

      stateCacheFile.setText(dataStr);
    } catch (e) {
      Logger.e("OllamaAssistant", "Failed to save state cache: " + e);
    }
  }

  function createNewConversation() {
      if (!root.conversations) {
          root.conversations = {};
      }

      // generate next index
      var keys = Object.keys(root.conversations);
      var newIndex = keys.length > 0 ? Math.max(...keys.map(Number)) + 1 : 0;
      var updated = Object.assign({}, root.conversations);
      updated[newIndex] = {
        messages: []
      };

      root.memoryStore[newIndex] = {
        summary: "",
        facts: [],
        lastSummarizedIndex: 0,
        version: 0
      };

      root.conversations = updated;
      root.activeConversationIndex = newIndex;
      root.messages = [];

      saveState();
  }

  function switchConversation(index) {
      if (!root.conversations) return;
      if (!root.conversations[index]) {
          root.conversations[index] = [];
      }

      root.activeConversationIndex = index;
      root.messages = root.conversations[index].messages;
  }

  // navigation functions
  function tabForward() {
    if (!root.conversations || root.activeConversationIndex === -1)
      return;

    var indices = Object.keys(root.conversations).map(Number);
    if (indices.length === 0)
      return;

    var newIndex = (root.activeConversationIndex + 1) % indices.length;
    switchConversation(indices[newIndex]);
  }

  function tabBackward() {
    if (!root.conversations || root.activeConversationIndex === -1)
      return;

    var indices = Object.keys(root.conversations).map(Number);
    if (indices.length === 0)
      return;

    var newIndex = (root.activeConversationIndex - 1 + indices.length) % indices.length;
    switchConversation(indices[newIndex]);
  }

  function addMessage(role, content) {
    if (!root.conversations) {
      root.conversations = {};
    }

    // choose target conversation
    var index = root.requestConversationIndex > -1
      ? root.requestConversationIndex
      : root.activeConversationIndex;

    var conv = root.conversations[index];

    var newMessage = {
      id: Date.now().toString(),
      role: role,
      content: content,
      timestamp: new Date().toISOString()
    };

    var newMessages = conv.messages.slice();
    newMessages.push(newMessage);

    var updatedConversations = Object.assign({}, root.conversations);

    updatedConversations[index] = Object.assign({}, conv, {
      messages: newMessages
    });

    root.conversations = updatedConversations;

    // update UI binding ONLY if active
    if (index === root.activeConversationIndex) {
      root.messages = newMessages;
    }
    
    saveState();
    return newMessage;
  }

  // Clear chat history
  function clearMessages() {
    root.messages = [];

    var index = root.activeConversationIndex;

    var updatedConversations = Object.assign({}, root.conversations);
    updatedConversations[index] = { messages: [] };
    root.conversations = updatedConversations;

    saveState();
  }

  // Send a message to the AI
  function sendMessage(userMessage) {
    Logger.i("OllamaAssistant", "sendMessage called with: " + userMessage);
    if (!userMessage || userMessage.trim() === "") {
      Logger.i("OllamaAssistant", "sendMessage: empty message, abort");
      return;
    }
    if (root.isGenerating) {
      Logger.i("OllamaAssistant", "sendMessage: already generating, abort");
      return;
    }

    // Check API key for non-local providers
    // For OpenAI Compatible, check apiKey only if NOT local
    var requiresKey = true;
    if (openaiLocal) {
      requiresKey = false;
    }

    if (requiresKey && (!apiKey || apiKey.trim() === "")) {
      root.errorMessage = pluginApi?.tr("errors.noApiKey");
      Logger.e("OllamaAssistant", "sendMessage: missing API key");
      ToastService.showError(root.errorMessage);
      return;
    }

    Logger.i("OllamaAssistant", "Adding user message and starting generation");
    addMessage("user", userMessage.trim());

    root.isGenerating = true;
    root.isManuallyStopped = false;
    root.currentResponse = "";
    root.errorMessage = "";

    try {
      Logger.i("OllamaAssistant", "Calling sendOpenAIRequest() for " + provider);
      sendOpenAIRequest();
    } catch(error) {
      Logger.e("OllamaAssistant", "Error calling sendOpenAIRequest");
      root.errorMessage = error.message || "Unknown error";
      Logger.e("OllamaAssistant", "Error: " + root.errorMessage);
      root.isGenerating = false;
    }
  }

  // Edit a message and regenerate from there
  function editMessage(id, newContent) {
    if (root.isGenerating)
      return;
    if (!newContent || newContent.trim() === "")
      return;
    var index = -1;
    for (var i = 0; i < root.messages.length; i++) {
      if (root.messages[i].id === id) {
        index = i;
        break;
      }
    }

    if (index === -1)
      return;

    // Truncate history to this message (exclusive)
    root.messages = root.messages.slice(0, index);
    root.conversations[root.activeConversationIndex] = root.conversations[root.activeConversationIndex].slice(0, index);

    // Add the updated message as a new user message
    sendMessage(newContent);
  }

  // Regenerate the last assistant response
  function regenerateLastResponse() {
    if (root.isGenerating)
      return;
    if (root.messages.length < 2)
      return;

    // Find and remove the last assistant message
    var lastIndex = -1;
    for (var i = root.messages.length - 1; i >= 0; i--) {
      if (root.messages[i].role === "assistant") {
        lastIndex = i;
        break;
      }
    }

    if (lastIndex >= 0) {
      root.messages = root.messages.slice(0, lastIndex);
      saveState();

      root.isGenerating = true;
      root.currentResponse = "";
      root.errorMessage = "";

      sendOpenAIRequest();
    }
  }

  // Stop generation
  function stopGeneration() {
    if (!root.isGenerating)
      return;
    Logger.i("OllamaAssistant", "Stopping generation");

    root.isManuallyStopped = true;
    if (openaiProcess.running)
      openaiProcess.running = false;

    root.isGenerating = false;
    // If we have a partial response, add it to chat history
    if (root.currentResponse.trim() !== "") {
      root.addMessage("assistant", root.currentResponse.trim());
    }
    root.currentResponse = "";
  }

  // =====================
  // OpenAI API Compatible ( ollama )
  // =====================
  Process {
    id: openaiProcess

    property string buffer: ""

    stdout: SplitParser {
      onRead: function (data) {
        openaiProcess.handleStreamData(data);
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        if (text && text.trim() !== "") {
          Logger.e("OllamaAssistant", "OpenAI stderr: " + text);
        } else {
          Logger.i("OllamaAssistant", "OpenAI stream finished");
        }
      }
    }

    function handleStreamData(data) {
      var result = ProviderLogic.parseOpenAIStream(data);
      if (!result)
        return;

      if (result.content) {
        root.currentResponse += result.content;
      } else if (result.error) {
        Logger.e("OllamaAssistant", "OpenAI stream error: " + result.error);
      } else if (result.raw) {
        openaiProcess.buffer += result.raw;
        try {
          var errorJson = JSON.parse(openaiProcess.buffer);
          if (errorJson.error) {
            root.errorMessage = errorJson.error.message || "API error";
          }
          openaiProcess.buffer = "";
        } catch (e) {
          // Incomplete JSON, keep buffering
        }
      }
    }

    onExited: function (exitCode, exitStatus) {
      if (root.isManuallyStopped) {
        root.isManuallyStopped = false;
        return;
      }

      root.isGenerating = false;

      if (exitCode !== 0 && root.currentResponse === "") {
        if (root.errorMessage === "") {
          if (openaiLocal) {
            root.errorMessage = pluginApi?.tr("errors.localNotRunning");
          } else {
            root.errorMessage = pluginApi?.tr("errors.requestFailed");
          }
        }
        return;
      }

      if (root.currentResponse.trim() !== "") {
        root.addMessage("assistant", root.currentResponse.trim());
        root.maybeTriggerSummarization(root.requestConversationIndex);
      }
      root.chatInputText = ""; // Ensure input is cleared after successful generation
      root.chatInputCursorPosition = 0;
      root.requestConversationIndex = -1;
      root.saveState();

      openaiProcess.buffer = "";
    }
  }

  Process {
    id: summaryProcess

    property var meta: null
    property string buffer: ""

    stdout: SplitParser {
      onRead: function(data) {
        summaryProcess.handleData(data);
      }
    }

    function handleData(data) {
      buffer += data;
      
      try {
        var outer = JSON.parse(buffer);
        buffer = "";

        var content = outer?.choices?.[0]?.message?.content;

        if (!content) {
          Logger.e("OllamaAssistant", "Summary parse: missing content");
          return;
        }

        try {
          var inner = ProviderLogic.extractJson(content);
          if (!inner) {
            Logger.e("OllamaAssistant", "Failed to extract JSON:", content);
            return;
          }
          Logger.d("OllamaAssistant", "Summary parse inner:", inner);
          root.applySummaryUpdate(inner, meta);
        } catch (e) {
          Logger.e("OllamaAssistant", "Summary inner JSON parse failed: " + e + " content=" + content);
        }
      } catch (e) {
        // wait for full JSON
      }
    }
  }

  function ensureMemory(index) {
    var memory = root.memoryStore[index];

    if (!memory) {
      memory = {
        summary: "",
        facts: [],
        lastSummarizedIndex: 0,
        version: 0
      };
    } else {
      if (!memory.facts) memory.facts = [];
      if (!memory.summary) memory.summary = "";
      if (!memory.lastSummarizedIndex) memory.lastSummarizedIndex = 0;
      if (!memory.version) memory.version = 0;
    }

    var updatedMemory = Object.assign({}, root.memoryStore);
    updatedMemory[index] = memory;
    root.memoryStore = updatedMemory;

    return memory;
  }

  function updateMemHelper(convIndex, version, memory) {
    var updatedMemory = Object.assign({}, root.memoryStore);

    updatedMemory[convIndex] = Object.assign({}, memory, {
      version: version
    });

    root.memoryStore = updatedMemory;
  }

  function triggerSummarization(convIndex, chunk) {
    var memory = ensureMemory(convIndex);
    var version = memory.version + 1;
    var prompt = `
Update memory with strong prioritization:

- Preserve important concepts, decisions, and corrections.
- De-prioritize small talk, repetition, and minor clarifications.
- If something is repeated or emphasized, increase its importance.
- Prefer durable knowledge over transient discussion.
You may discard less important details if needed.

  Existing summary:
  ${memory.summary}

  Existing facts:
  ${memory.facts.join("\n")}

  New messages:
  ${safeStringify(chunk)}

Return ONLY valid JSON.
Do NOT use markdown.
Do NOT wrap in \`\`\` blocks.
Do NOT include explanations.

Output must be strictly parseable by JSON.parse.

Schema (example):
{
  "summary": "short concise summary",
  "facts": ["fact 1", "fact 2"]
}
    `;

    summaryProcess.meta = {
      convIndex: convIndex,
      end: memory.lastSummarizedIndex + chunk.length,
      version: version
    };

    // update ONLY memoryStore
    updateMemHelper(convIndex, version, memory);

    var commandData = ProviderLogic.buildSummaryCommand(prompt);
    Logger.d("OllamaAssistant", "Summary args: ", commandData.args);
    summaryProcess.buffer = "";
    summaryProcess.command = commandData.args;
    summaryProcess.running = true;
  }

  function safeStringify(obj) {
    return JSON.stringify(obj).replace(/```/g, "'''");
  }

  function applySummaryUpdate(result, meta) {
    var memory = root.memoryStore[meta.convIndex];
    if (!memory) return;

    if (meta.version !== memory.version) {
      return; // stale
    }

    Logger.d("OllamaAssistant",  "summary" +result.summary);
    Logger.d("OllamaAssistant",  "facts" + result.facts);
    Logger.d("OllamaAssistant",  "version"  + meta.version);
 
    if (typeof result.facts === "string") {
      result.facts = result.facts.split(",").map(f => f.trim());
    }
    var updatedMemory = Object.assign({}, root.memoryStore);

    updatedMemory[meta.convIndex] = Object.assign({}, memory, {
      summary: result.summary,
      facts: result.facts,
      lastSummarizedIndex: meta.end
    });

    root.memoryStore = updatedMemory;
    saveState();
  }

  function buildContext(index) {
    var conv = root.conversations[index];
    var memory = ensureMemory(index);

    var history = [];

    if (memory.summary) {
      history.push({
        role: "system",
        content: "Summary:\n" + memory.summary
      });
    }

    if (memory.facts.length > 0) {
      history.push({
        role: "system",
        content: "Facts:\n- " + memory.facts.join("\n- ")
      });
    }

    history = history.concat(conv.messages.slice(-2));

    return history;
  }

  function maybeTriggerSummarization(convIndex) {
    var conv = root.conversations[convIndex];
    var memory = ensureMemory(convIndex);

    var start = memory.lastSummarizedIndex;
    var end = conv.messages.length;

    if (end <= start) return;

    var chunk = conv.messages.slice(start, end);

    triggerSummarization(convIndex, chunk);
  }

  function sendOpenAIRequest() {
    root.requestConversationIndex = root.activeConversationIndex;
    var conv = root.conversations[root.activeConversationIndex];
    var history = buildContext(root.activeConversationIndex);
    var commandData = ProviderLogic.buildOpenAICommand(openaiBaseUrl, apiKey, model, systemPrompt, history, temperature);

    Logger.i("OllamaAssistant", "sendOpenAIRequest: endpoint=" + commandData.url);
    openaiProcess.buffer = "";
    openaiProcess.command = commandData.args;
    Logger.d("OllamaAssistant", "args=" + commandData.args);

    Logger.i("OllamaAssistant", "sendOpenAIRequest: starting process");
    openaiProcess.running = true;
  }


  // =====================
  // IPC Handlers
  // =====================
  IpcHandler {
    target: "plugin:ollama-assistant"

    function toggle() {
      if (pluginApi) {
        pluginApi.withCurrentScreen(function (screen) {
          pluginApi.togglePanel(screen);
        });
      }
    }

    function open() {
      if (pluginApi) {
        pluginApi.withCurrentScreen(function (screen) {
          pluginApi.openPanel(screen);
        });
      }
    }

    function close() {
      if (pluginApi) {
        pluginApi.withCurrentScreen(function (screen) {
          pluginApi.closePanel(screen);
        });
      }
    }

    function send(message: string) {
      if (message && message.trim() !== "") {
        root.sendMessage(message);
        ToastService.showNotice(pluginApi?.tr("toast.messageSent"));
      }
    }

    function clear() {
      root.clearMessages();
      ToastService.showNotice(pluginApi?.tr("toast.historyCleared"));
    }

    function translateText(text: string, targetLang: string) {
      if (text && text.trim() !== "") {
        root.translate(text, targetLang || root.targetLanguage);
      }
    }


    function setModel(modelName: string) {
      if (pluginApi && modelName) {
        pluginApi.pluginSettings.ai.model = modelName;
      }
    }
  }
}
