.pragma library

// ===================================
// AI Provider Logic
// ===================================

function buildOpenAICommand(endpointUrl, apiKey, model, systemPrompt, history, temperature) {
  var messages = [];

  if (systemPrompt && systemPrompt.trim() !== "") {
    messages.push({
      "role": "system",
      "content": systemPrompt
    });
  }

  // Add conversation history
  for (var i = 0; i < history.length; i++) {
    messages.push({
      role: history[i].role,
      content: history[i].content
    });
  }

  var payload = {
    "model": model,
    "messages": messages,
    "temperature": temperature,
    "stream": true
  };

  var args = ["curl", "-s", "-S", "--no-buffer", "-X", "POST", "-H", "Content-Type: application/json"];

  if (apiKey && apiKey.trim() !== "") {
    args.push("-H", "Authorization: Bearer " + apiKey);
  }

  args.push("-d", JSON.stringify(payload));
  args.push(endpointUrl);

  return {
    "url": endpointUrl,
    "payload": JSON.stringify(payload),
    "args": args
  };
}

function parseOpenAIStream(data) {
  if (!data)
    return null;
  var line = data.trim();
  if (line === "")
    return null;

  if (line.startsWith("data: ")) {
    var jsonStr = line.substring(6).trim();
    if (jsonStr === "[DONE]")
      return {
        done: true
      };

    try {
      var json = JSON.parse(jsonStr);
      if (json.choices && json.choices[0]) {
        if (json.choices[0].delta && json.choices[0].delta.content) {
          return {
            content: json.choices[0].delta.content
          };
        } else if (json.choices[0].message && json.choices[0].message.content) {
          return {
            content: json.choices[0].message.content
          };
        }
      }
    } catch (e) {
      return {
        error: "Error parsing SSE JSON: " + e
      };
    }
  } else {
    return {
      raw: line
    };
  }
  return null;
}

function extractJson(content) {
  if (!content) return null;

  // remove ```json ... ``` or ``` ... ```
  content = content.trim();

  if (content.startsWith("```")) {
    content = content
      .replace(/^```[a-zA-Z]*\n?/, "")
      .replace(/```$/, "")
      .trim();
  }

  // try parsing directly
  try {
    return JSON.parse(content);
  } catch (_) {}

  // fallback: extract first {...}
  var match = content.match(/\{[\s\S]*\}/);
  if (match) {
    try {
      return JSON.parse(match[0]);
    } catch (_) {}
  }

  return null;
}

function buildSummaryCommand(prompt) {
  var payload = {
    model: "qwen3.5:9b",
    messages: [
      { role: "user", content: prompt }
    ],
    stream: false
  };

  var args = [
    "curl", "-s", "-X", "POST",
    "-H", "Content-Type: application/json",
    "-d", JSON.stringify(payload),
    "http://localhost:11434/v1/chat/completions"
  ];

  return {
    args: args
  };
}


// ===================================
// State Management
// ===================================

function processLoadedState(content) {
  if (!content || content.trim() === "") {
    return null;
  }

  try {
    var cached = JSON.parse(content);

    var normalizedConversations = {};
    var memoryStore = {};
    var cachedMemory = cached.memoryStore || {};

    for (var key in cached.conversations) {
      var conv = cached.conversations[key];

      normalizedConversations[key] = {
        messages: conv.messages || []
      };

      memoryStore[key] = Object.assign({
        summary: "",
        facts: [],
        lastSummarizedIndex: 0,
        version: 0
      }, cachedMemory[key] || {});
    }

    return {
      conversations: normalizedConversations,
      memoryStore: memoryStore,
      activeConversationIndex: cached.activeConversationIndex || 0,
      chatInputText: cached.chatInputText || "",
      chatInputCursorPosition: cached.chatInputCursorPosition || 0
    };

  } catch (e) {
    return { error: e.toString() };
  }
}

function prepareStateForSave(
  conversations,
  memoryStore,
  activeConversationIndex,
  chatInputText,
  chatInputCursorPosition
) {

  return JSON.stringify({
    conversations: conversations,
    memoryStore: memoryStore,
    activeConversationIndex: activeConversationIndex,
    chatInputText: chatInputText || "",
    chatInputCursorPosition: chatInputCursorPosition || 0,
    timestamp: Math.floor(Date.now() / 1000)
  }, null, 2);
}
