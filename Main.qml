import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons 
import qs.Services.UI
import "ProviderLogic.js" as ProviderLogic
import "Constants.js" as Constants
import "Storage.js" as Storage

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


  property string chatInputText: "" // Chat input state - persisted to cache
  property int chatInputCursorPosition: 0 // Chat input cursor position - persisted to cache

  property bool sqliteAvailable: false
  readonly property string sqliteDbPath: {
    if (typeof Settings !== "undefined" && Settings.cacheDir)
      return Settings.cacheDir + "plugins/ollama-assistant/state.db";
    return "";
  }
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

    Storage.init({
      dbPath: sqliteDbPath,
      execSql: function(query, callback) {
        Logger.d("OllamaAssistant", "ExecSQL in main.qml");
        if (!sqliteDbPath) {
          callback(null, "no db path");
          return;
        }

        var dir = sqliteDbPath.substring(0, sqliteDbPath.lastIndexOf("/"));
        Quickshell.execDetached(["mkdir", "-p", dir]);
        var slicedQ = query.slice(0, 100);
        Logger.d("OllamaAssistant", "[SQL] Exec request truncated query:"+ slicedQ);
        Logger.d("OllamaAssistant", "[SQL] Process running: "+ sqliteProcess.running);

        sqliteProcess.buffer = "";
        sqliteProcess.callback = callback;
        Logger.d("OllamaAssistant", "DB path: "+ sqliteDbPath)

        sqliteProcess.command = [
          "sqlite3",
          "-json",
          sqliteDbPath,
          query
        ];
        sqliteProcess.running = true;
      }

    }, function(result) {
      sqliteAvailable = result.sqliteAvailable;

      Storage.loadState(function(content, error) {
        if (error) {
          Logger.e("OllamaAssistant", "Load failed: " + error);
          return;
        }

        var result = ProviderLogic.processLoadedState(content);
        if (!result || result.error) return;

        root.conversations = result.conversations;
        root.activeConversationIndex = result.activeConversationIndex;
        root.messages = root.conversations[root.activeConversationIndex].messages || [];
        root.chatInputText = result.chatInputText;
        root.chatInputCursorPosition = result.chatInputCursorPosition;
        root.memoryStore = result.memoryStore;
      });
    });
  }

  // =====================
  // SQLITE PROCESS
  // =====================
  Process {
    id: sqliteProcess

    property string buffer: ""
    property string errorBuffer: ""
    property var callback: null

    stdout: SplitParser {
      onRead: function (data) {
        sqliteProcess.buffer += data;
      }
    }

    stderr: SplitParser {
      onRead: function (data) {
        sqliteProcess.errorBuffer += data;
      }
    }

    onExited: function (exitCode) {
      var cb = sqliteProcess.callback;
      var output = sqliteProcess.buffer;
      var errOut = sqliteProcess.errorBuffer;

      Logger.d("OllamaAssistant", "SQL Exited. Callback exists?", !!cb);
      var logOutput = output.slice(0, 100);
      Logger.d("OllamaAssistant", "SQL RAW OUTPUT: (truncated)", logOutput);
      if(errOut.trim() !== "") {
        Logger.e("OllamaAssistant", "SQL STDERR:", errOut);
      }
      sqliteProcess.buffer = "";
      sqliteProcess.errorBuffer = "";
      sqliteProcess.callback = null;

      if (!cb) return;

      if (exitCode !== 0) {
        cb(null, errOut || "sqlite failed");
        return;
      }

      try {
        var parsed = output && output.trim() !== ""
          ? JSON.parse(output)
          : [];
        cb(parsed, null);
      } catch (e) {
        cb(null, "parse error");
      }
    }
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
    if (!saveStateQueued)
      return;

    saveStateQueued = false;

    try {
      var dataStr = ProviderLogic.prepareStateForSave(
        root.conversations,
        root.memoryStore,
        root.activeConversationIndex,
        root.chatInputText,
        root.chatInputCursorPosition
      );

      Storage.saveState(dataStr);

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
    Logger.d("OllamaAssistant", "sendMessage called with: " + userMessage);
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
    if (!openaiLocal && (!apiKey || apiKey.trim() === "")) {
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
      Logger.i("OllamaAssistant", "Calling sendChatRequest() for " + provider);
      sendChatRequest();
    } catch(error) {
      Logger.e("OllamaAssistant", "Error calling sendChatRequest");
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

      sendChatRequest();
    }
  }

  // Stop generation
  function stopGeneration() {
    if (!root.isGenerating)
      return;
    Logger.i("OllamaAssistant", "Stopping generation");

    root.isManuallyStopped = true;
    if (chatProcess.running)
      chatProcess.running = false;

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
    id: chatProcess

    property string buffer: ""

    stdout: SplitParser {
      onRead: function (data) {
        chatProcess.handleStreamData(data);
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
        chatProcess.buffer += result.raw;
        try {
          var errorJson = JSON.parse(chatProcess.buffer);
          if (errorJson.error) {
            root.errorMessage = errorJson.error.message || "API error";
          }
          chatProcess.buffer = "";
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

      chatProcess.buffer = "";
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

  function triggerSummarization(convIndex, chunk) {
    var memory = ensureMemory(convIndex);
    var version = memory.version + 1;
    var prompt = ProviderLogic.promptForSummarization(chunk, memory);

    summaryProcess.meta = {
      convIndex: convIndex,
      end: memory.lastSummarizedIndex + chunk.length,
      version: version
    };

    // update ONLY memoryStore
    var updatedMemory = Object.assign({}, root.memoryStore);

    updatedMemory[convIndex] = Object.assign({}, memory, {
      version: version
    });

    root.memoryStore = updatedMemory;

    var commandData = ProviderLogic.buildSummaryCommand(prompt);
    Logger.d("OllamaAssistant", "Summary args: ", commandData.args);
    summaryProcess.buffer = "";
    summaryProcess.command = commandData.args;
    summaryProcess.running = true;
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

  function maybeTriggerSummarization(convIndex) {
    var conv = root.conversations[convIndex];
    var memory = ensureMemory(convIndex);

    var start = memory.lastSummarizedIndex;
    var end = conv.messages.length;

    if (end <= start) return;

    var chunk = conv.messages.slice(start, end);

    triggerSummarization(convIndex, chunk);
  }

  function sendChatRequest() {
    root.requestConversationIndex = root.activeConversationIndex;
    var conv = root.conversations[root.activeConversationIndex];
    var memory = ensureMemory(root.activeConversationIndex);
    var commandData = ProviderLogic.buildChatCommand(
      openaiBaseUrl, apiKey, model, systemPrompt, memory, temperature, conv
    );

    Logger.d("OllamaAssistant", "sendChatRequest: endpoint=" + commandData.url);
    chatProcess.buffer = "";
    chatProcess.command = commandData.args;
    Logger.d("OllamaAssistant", "args=" + commandData.args);

    Logger.i("OllamaAssistant", "sendChatRequest: starting process");
    chatProcess.running = true;
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

    function setModel(modelName: string) {
      if (pluginApi && modelName) {
        pluginApi.pluginSettings.ai.model = modelName;
      }
    }
  }
}
