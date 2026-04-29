/* eslint-disable /
.pragma library
/ eslint-enable */

var LoggerRef = null;
var sqliteAvailable = false;
var dbPath = "";
var execSql = null;
var _execSqlRaw = null; // actual function from Main.qml
var _queue = [];
var _running = false;


// =====================
// Logger
// =====================
function getLogger() {
  if (LoggerRef) return LoggerRef;

  try {
    LoggerRef = Logger;
  } catch (e) {
    LoggerRef = {
      d: function () {},
      i: function () {},
      e: function () {}
    };
  }

  return LoggerRef;
}


function _processQueue() {
  if (_running) return;
  if (_queue.length === 0) return;

  var job = _queue.shift();
  _running = true;
  getLogger().d("OllamaAssistant", "[QUEUE] START, running=" + _running);
  getLogger().d("OllamaAssistant", "[Storage] [QUEUE] Running query. Remaining: " + _queue.length);

  _execSqlRaw(job.query, function(result, err) {
    _running = false;

    getLogger().d("OllamaAssistant", "[Storage] [QUEUE] Completed query");

    try {
      job.cb && job.cb(result, err);
    } catch (e) {
      getLogger().e("OllamaAssistant", "[Storage] Callback error: " + e);
    }

    _processQueue();
  });
}
// =====================
// Path (JSON fallback)
// =====================
function getStatePath() {
  try {
    if (typeof Settings !== "undefined" && Settings.cacheDir) {
      return Settings.cacheDir + "plugins/ollama-assistant/state.json";
    }
  } catch (e) {}
  return "";
}

// =====================
// Ensure directory
// =====================
function ensureDir(path) {
  if (!path) return;

  try {
    var idx = path.lastIndexOf("/");
    if (idx === -1) return;

    var dir = path.substring(0, idx);
    Quickshell.execDetached(["mkdir", "-p", dir]);
  } catch (e) {
    getLogger().e("OllamaAssistant", "[Storage] Failed to ensure dir: " + e);
  }
}

// =====================
// INIT
// =====================
function init(config, callback) {
  dbPath = config.dbPath;
  _execSqlRaw = config.execSql;
  getLogger().d("OllamaAssistant", "[Storage] Init");
  getLogger().d("OllamaAssistant", "[Storage] dbPath: " + dbPath);
  getLogger().d("OllamaAssistant", "[Storage] execsqlRaw: " + _execSqlRaw);

  if (!_execSqlRaw || !dbPath) {
    sqliteAvailable = false;
    return callback({ sqliteAvailable: false });
  }

  // wrap with queue
  execSql = function(query, cb) {
    _queue.push({ query: query, cb: cb });
    _processQueue();
  };

  // test connection
  execSql("SELECT 1;", function(_, err) {
    if (err) {
      sqliteAvailable = false;
      return callback({ sqliteAvailable: false });
    }

    initSchema(function(schemaErr) {
      if (schemaErr) {
        sqliteAvailable = false;
        return callback({ sqliteAvailable: false });
      }

      sqliteAvailable = true;

      migrateIfNeeded(function(migErr) {
        if (migErr) {
          getLogger().e("OllamaAssistant", "[Storage] Migration failed: " + migErr);
        }
        callback({ sqliteAvailable: true });
      });
    });
  });
}

// =====================
// SCHEMA
// =====================
function initSchema(cb) {
  execSql(`
    CREATE TABLE IF NOT EXISTS conversations (
      id INTEGER PRIMARY KEY,
      data TEXT
    );
  `, function(_, err) {
    if (err) return cb(err);

    execSql(`
      CREATE TABLE IF NOT EXISTS memories (
        conversation_id INTEGER PRIMARY KEY,
        data TEXT
      );
    `, function(_, err2) {
      cb(err2 || null);
    });
  });
}

function migrateIfNeeded(callback) {
  loadFromJson(function(content, err) {
    if (err || !content) return callback(null); // nothing to migrate

    var parsed;
    try {
      parsed = JSON.parse(content);
    } catch (e) {
      return callback("Invalid JSON");
    }

    if (parsed.meta && parsed.meta.migrated) {
      return callback(null); // already done
    }

    insertJsonIntoSqlite(parsed, function(insertErr) {
      if (insertErr) return callback(insertErr);

      // mark migrated
      parsed.meta = parsed.meta || {};
      parsed.meta.migrated = true;

      saveToJson(JSON.stringify(parsed));

      callback(null);
    });
  });
}

function insertJsonIntoSqlite(data, cb) {
  var conversations = data.conversations || {};
  var memoryStore = data.memoryStore || {};

  var keys = Object.keys(conversations);
  var total = keys.length;

  if (total === 0) {
    cb(null);
    return;
  }

  var completed = 0;
  var failed = false;

  function doneOnce(err) {
    if (failed) return;
    failed = true;
    cb(err);
  }

  keys.forEach(function(key) {
    getLogger().d("OllamaAssistant", "[MIGRATE] Inserting conversation: " + key);
    var conv = conversations[key];
    var mem = memoryStore[key] || {};

    var convStr = JSON.stringify(conv).replace(/'/g, "''");
    var memStr = JSON.stringify(mem).replace(/'/g, "''");

    var insertConvQuery =
      "INSERT INTO conversations (id, data) VALUES (" +
      key + ", '" + convStr + "') " +
      "ON CONFLICT(id) DO UPDATE SET data=excluded.data;";

    execSql(insertConvQuery, function(_, err1) {
      if (err1) return doneOnce(err1);
      getLogger().d("OllamaAssistant", "[MIGRATE] Callback after inserting conversation: " + key);
      var insertMemQuery =
        "INSERT INTO memories (conversation_id, data) VALUES (" +
        key + ", '" + memStr + "') " +
        "ON CONFLICT(conversation_id) DO UPDATE SET data=excluded.data;";

      execSql(insertMemQuery, function(_, err2) {
        if (err2) return doneOnce(err2);

        getLogger().d("OllamaAssistant", "[MIGRATE] Callback after inserting memories: " + key);

        completed++;

        if (completed === total && !failed) {
          cb(null);
        }
      });
    });
  });
}
// =====================
// LOAD
// =====================
function loadState(callback) {
  if (!sqliteAvailable) {
    getLogger().e("OllamaAssistant", "[Storage] SQLite not available");
    return callback("", -100);
  }

  loadFromSqlite(callback);
}

function loadFromSqlite(callback) {
  execSql("SELECT id, data FROM conversations;", function(rows, err) {
    if (err) return callback("", err);

    var result = {
      conversations: {},
      memoryStore: {},
      activeConversationIndex: 0
    };

    for (var i = 0; i < rows.length; i++) {
      var parsed = JSON.parse(rows[i].data);
      result.conversations[rows[i].id] = parsed;
    }

    execSql("SELECT conversation_id, data FROM memories;", function(memRows) {

      for (var j = 0; j < memRows.length; j++) {
        result.memoryStore[memRows[j].conversation_id] =
          JSON.parse(memRows[j].data);
      }

      callback(JSON.stringify(result), null);
    });
  });
}

// =====================
// JSON FALLBACK
// =====================
function loadFromJson(callback) {
  var path = getStatePath();

  if (!path) {
    callback("", -1);
    return;
  }

  var file = null;
  var called = false;

  function done(content, error) {
    if (called) return;
    called = true;

    callback(content, error);
    safeDestroy(file);
  }

  try {
    file = Qt.createQmlObject(
      'import Quickshell.Io; FileView { watchChanges: false }',
      Qt.application,
      "StorageFileViewLoad"
    );

    file.path = path;

    file.onLoaded.connect(function () {
      try {
        done(file.text(), null);
      } catch (e) {
        done("", -1);
      }
    });

    file.onLoadFailed.connect(function (error) {
      done("", error);
    });

    file.reload();

  } catch (e) {
    done("", -1);
  }
}

// =====================
// SAVE
// =====================
function saveState(dataStr) {
  if (sqliteAvailable) {
    saveToSqlite(dataStr);
  } else {
    saveToJson(dataStr);
  }
}

function saveToSqlite(dataStr) {
  try {
    var parsed = JSON.parse(dataStr);
    var conversations = parsed.conversations || {};

    for (var key in conversations) {
      var conv = conversations[key];
      var escaped = JSON.stringify(conv).replace(/'/g, "''");

      execSql(`
        INSERT INTO conversations (id, data)
        VALUES (${key}, '${escaped}')
        ON CONFLICT(id) DO UPDATE SET data=excluded.data;
      `, function(){});
    }
    for (var key in memoryStore) {
      var mem = memoryStore[key];
      var escapedMem = JSON.stringify(mem).replace(/'/g, "''");

      execSql(`
        INSERT INTO memories (conversation_id, data)
        VALUES (${key}, '${escapedMem}')
        ON CONFLICT(conversation_id) DO UPDATE SET data=excluded.data;
      `, function(){});
    }

  } catch (e) {
    getLogger().e("Storage", "SQLite save failed: " + e);
    saveToJson(dataStr);
  }
}

function saveToJson(dataStr) {
  var path = getStatePath();
  if (!path) return;

  ensureDir(path);

  var file = Qt.createQmlObject(
    'import Quickshell.Io; FileView { watchChanges: false }',
    Qt.application,
    "StorageFileViewSave"
  );

  file.path = path;
  file.setText(dataStr);

  safeDestroy(file);
}

// =====================
// UTIL
// =====================
function safeDestroy(obj) {
  if (!obj) return;

  try {
    Qt.callLater(function () {
      try { obj.destroy(); } catch (_) {}
    });
  } catch (_) {
    try { obj.destroy(); } catch (_) {}
  }
}