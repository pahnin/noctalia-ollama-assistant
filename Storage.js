/* eslint-disable /
.pragma library
/ eslint-enable */

var LoggerRef = null;

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

// =====================
// Path
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
    getLogger().e("Storage", "Failed to ensure dir: " + e);
  }
}

// =====================
// Safe destroy helper
// =====================
function safeDestroy(obj) {
  if (!obj) return;

  try {
    Qt.callLater(function () {
      try {
        obj.destroy();
      } catch (e) {
        // ignore
      }
    });
  } catch (e) {
    // fallback if callLater unavailable
    try {
      obj.destroy();
    } catch (_) {}
  }
}

// =====================
// LOAD
// =====================
function loadState(callback) {
  var logger = getLogger();
  var path = getStatePath();

  if (!path) {
    logger.e("Storage", "Invalid cache path");
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
        var content = file.text();
        logger.d("Storage", "State loaded");
        done(content, null);
      } catch (e) {
        logger.e("Storage", "Read error: " + e);
        done("", -1);
      }
    });

    file.onLoadFailed.connect(function (error) {
      logger.d("Storage", "Load failed: " + error);
      done("", error); // preserve behavior (2 = not found)
    });

    file.reload();
  } catch (e) {
    logger.e("Storage", "Load exception: " + e);
    done("", -1);
  }
}

// =====================
// SAVE
// =====================
function saveState(dataStr) {
  var logger = getLogger();
  var path = getStatePath();

  if (!path) {
    logger.e("Storage", "Invalid cache path");
    return;
  }

  var file = null;

  try {
    ensureDir(path);

    file = Qt.createQmlObject(
      'import Quickshell.Io; FileView { watchChanges: false }',
      Qt.application,
      "StorageFileViewSave"
    );

    file.path = path;

    file.setText(dataStr);
    logger.d("Storage", "State saved");

    // defer destroy to avoid race with underlying IO
    safeDestroy(file);

  } catch (e) {
    logger.e("Storage", "Save error: " + e);
    safeDestroy(file);
  }
}