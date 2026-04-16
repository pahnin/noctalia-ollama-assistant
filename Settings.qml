import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI
import "Constants.js" as Constants

ColumnLayout {
  id: root

  property var pluginApi: null

  // AI Settings - Local state
  property var editModel: pluginApi?.pluginSettings?.ai?.model || ""
  property string editApiKey: pluginApi?.pluginSettings?.ai?.apiKey
    || pluginApi?.manifest?.metadata?.defaultSettings?.ai?.apiKey
    || ""
  property real editTemperature: pluginApi?.pluginSettings?.ai?.temperature || pluginApi?.manifest?.metadata?.defaultSettings?.ai?.temperature || 0.7
  property string editSystemPrompt: pluginApi?.pluginSettings?.ai?.systemPrompt || pluginApi?.manifest?.metadata?.defaultSettings?.ai?.systemPrompt || ""

  // General Settings
  property int editMaxHistoryLength: pluginApi?.pluginSettings?.maxHistoryLength || pluginApi?.manifest?.metadata?.defaultSettings?.maxHistoryLength || 100

  // Panel Settings (detached, position, height, offset, width)
  property bool editPanelDetached: pluginApi?.pluginSettings?.panelDetached ?? pluginApi?.manifest?.metadata?.panel?.detached ?? true
  property string editPanelPosition: pluginApi?.pluginSettings?.panelPosition || pluginApi?.manifest?.metadata?.panel?.defaultPosition || "right"
  property real editPanelHeightRatio: pluginApi?.pluginSettings?.panelHeightRatio || pluginApi?.manifest?.metadata?.panel?.defaultHeightRatio || 0.85
  property int editPanelWidth: pluginApi?.pluginSettings?.panelWidth ?? 520
  property string editAttachmentStyle: pluginApi?.pluginSettings?.attachmentStyle || "connected"
  property real editScale: pluginApi?.pluginSettings?.scale || pluginApi?.manifest?.metadata?.defaultSettings?.scale || 1

  // OpenAI Compatible specific settings
  property bool editOpenAiLocal: pluginApi?.pluginSettings?.ai?.openaiLocal ?? false
  property string editOpenAiBaseUrl: pluginApi?.pluginSettings?.ai?.openaiBaseUrl || "https://api.openai.com/v1/chat/completions"

  // ==================
  // Panel Settings Section
  // ==================
  NText {
    text: pluginApi?.tr("settings.panelSection")
    pointSize: Style.fontSizeM
    font.weight: Font.Bold
    color: Color.mOnSurface
  }

  NToggle {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.panelDetached")
    description: pluginApi?.tr("settings.panelDetachedDesc")
    checked: root.editPanelDetached
    onToggled: function (checked) {
      root.editPanelDetached = checked
    }
    defaultValue: false
  }

  NComboBox {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.panelPosition")
    description: pluginApi?.tr("settings.panelPositionDesc")
    model:  [
      {
        "key": "left",
        "name": pluginApi?.tr("settings.panelPositionLeft")
      },
      {
        "key": "top",
        "name": pluginApi?.tr("settings.panelPositionTop")
      },
      {
        "key": "bottom",
        "name": pluginApi?.tr("settings.panelPositionBottom")
      },
      {
        "key": "right",
        "name": pluginApi?.tr("settings.panelPositionRight")
      }
    ]
    currentKey: root.editPanelPosition
    onSelected: function (key) {
      root.editPanelPosition = key;
    }
    defaultValue: "bottom"
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS
    NLabel {
      label: pluginApi?.tr("settings.panelHeightRatio") + ": " + (root.editPanelHeightRatio * 100).toFixed(0) + "%"
      description: pluginApi?.tr("settings.panelHeightRatioDesc")
    }
    NSlider {
      Layout.fillWidth: true
      from: 0.3
      to: 1.0
      stepSize: 0.01
      value: root.editPanelHeightRatio
      onValueChanged: root.editPanelHeightRatio = value
    }
    NLabel {
      label: pluginApi?.tr("settings.panelWidth") + ": " + root.editPanelWidth + "px"
      description: pluginApi?.tr("settings.panelWidthDesc")
    }
    NSlider {
      Layout.fillWidth: true
      from: 320
      to: 1200
      stepSize: 1
      value: root.editPanelWidth
      onValueChanged: root.editPanelWidth = value
    }
    NLabel {
      label: pluginApi?.tr("settings.uiScale") + ": " + (root.editScale * 100).toFixed(0) + "%"
      description: pluginApi?.tr("settings.uiScaleDesc")
    }
    NSlider {
      Layout.fillWidth: true
      from: 0.5
      to: 2.0
      stepSize: 0.01
      value: root.editScale
      onValueChanged: root.editScale = value
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM
  }

  // Provider configurations
  readonly property var provider: {
    "name": "OpenAI Compatible",
    "defaultModel": "qwen3.5:9b",
    // requiresKey is dynamic based on "Local" toggle, handled in logic below
    "requiresKey": true,
    "keyUrl": ""
  }

  spacing: Style.marginM

  Component.onCompleted: {
    Logger.i("OllamaAssitant", "Settings UI loaded");
  }

  // ==================
  // AI Settings Section
  // ==================
  NText {
    text: pluginApi?.tr("settings.aiSection")
    pointSize: Style.fontSizeM
    font.weight: Font.Bold
    color: Color.mOnSurface
  }


  // OpenAI Compatible Extras
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NToggle {
      Layout.fillWidth: true
      label: pluginApi?.tr("settings.local")
      description: pluginApi?.tr("settings.localDesc")
      checked: root.editOpenAiLocal
      onToggled: function (checked) {
        root.editOpenAiLocal = checked;
      }
      defaultValue: false
    }

    NTextInput {
      Layout.fillWidth: true
      visible: true
      label: pluginApi?.tr("settings.baseUrl")
      description: pluginApi?.tr("settings.baseUrlDesc")
      text: root.editOpenAiBaseUrl
      placeholderText: "http://localhost:11434/v1/chat/completions"
      onTextChanged: root.editOpenAiBaseUrl = text
    }

    // Note about Base URL and response API
    NText {
      Layout.fillWidth: true
      visible: true
      text: pluginApi?.tr("settings.baseUrlNote") + "https://platform.openai.com/docs/api-reference/chat/create" + pluginApi?.tr("settings.moreInfo")
      color: Color.mOnSurfaceVariant
      pointSize: Style.fontSizeXS
      wrapMode: Text.Wrap
      onLinkActivated: link => Qt.openUrlExternally(link)
    }
  }

  // Model selection
  NTextInput {
    Layout.fillWidth: true
    label: pluginApi?.tr("settings.model")
    description: pluginApi?.tr("settings.modelDesc")
    text: root.editModel
    onTextChanged: {
      root.editModel = (text || "").trim();
    }
    placeholderText: provider?.defaultModel || ""
  }

  // API Key input (hidden for Ollama/Local)
  NTextInput {
    Layout.fillWidth: true
    visible: {
      if root.editOpenAiLocal
        return false;
      return provider?.requiresKey ?? true;
    }
    label: pluginApi?.tr("settings.apiKey")
    description: {
      if (provider && provider.keyUrl) {
        return (pluginApi?.tr("settings.apiKeyDesc")) + ": " + provider.keyUrl;
      }
      return "";
    }
    placeholderText: pluginApi?.tr("settings.apiKeyPlaceholder")
    text: root.editApiKey
    inputMethodHints: Qt.ImhHiddenText
    onTextChanged: {
      root.editApiKey = text;
    }
  }

  // Temperature slider
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NLabel {
      label: pluginApi?.tr("settings.temperature") + ": " + root.editTemperature.toFixed(1)
      description: pluginApi?.tr("settings.temperatureDesc")
    }

    NSlider {
      Layout.fillWidth: true
      from: 0
      to: 2
      stepSize: 0.1
      value: root.editTemperature
      onValueChanged: root.editTemperature = value
    }
  }

  // System prompt
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NLabel {
      label: pluginApi?.tr("settings.systemPrompt")
      description: pluginApi?.tr("settings.systemPromptDesc")
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 80
      color: Color.mSurface
      radius: Style.radiusS
      border.color: Color.mOutline
      border.width: 1

      TextArea {
        anchors.fill: parent
        anchors.margins: Style.marginS
        text: root.editSystemPrompt
        placeholderText: pluginApi?.tr("settings.systemPromptPlaceholder")
        placeholderTextColor: Color.mOnSurfaceVariant
        color: Color.mOnSurface
        font.pointSize: Style.fontSizeS
        wrapMode: TextArea.Wrap
        background: null
        onTextChanged: root.editSystemPrompt = text
      }
    }
  }

  // Max history length
  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NLabel {
      label: (pluginApi?.tr("settings.maxHistory")) + ": " + root.editMaxHistoryLength
      description: pluginApi?.tr("settings.maxHistoryDesc")
    }

    NSlider {
      Layout.fillWidth: true
      from: 10
      to: 500
      stepSize: 10
      value: root.editMaxHistoryLength
      onValueChanged: root.editMaxHistoryLength = value
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM
  }

  // Save function called by the settings dialog
  function saveSettings() {
    if (!pluginApi) {
      Logger.e("OllamaAssitant", "Cannot save settings: pluginApi is null");
      return;
    }

    // Initialize nested objects if needed
    if (!pluginApi.pluginSettings.ai) {
      pluginApi.pluginSettings.ai = {};
    }
    if (!pluginApi.pluginSettings.translator) {
      pluginApi.pluginSettings.translator = {};
    }

    pluginApi.pluginSettings.ai.model = root.editModel;
    pluginApi.pluginSettings.ai.apiKey = root.editApiKey;
    pluginApi.pluginSettings.ai.temperature = root.editTemperature;
    pluginApi.pluginSettings.ai.systemPrompt = root.editSystemPrompt;

    // Save OpenAI Compatible specific settings
    pluginApi.pluginSettings.ai.openaiLocal = root.editOpenAiLocal;
    pluginApi.pluginSettings.ai.openaiBaseUrl = root.editOpenAiBaseUrl;
  

    // Save general settings
    pluginApi.pluginSettings.maxHistoryLength = root.editMaxHistoryLength;

    // Save panel settings
    pluginApi.pluginSettings.panelDetached = root.editPanelDetached;
    pluginApi.pluginSettings.panelPosition = root.editPanelPosition;
    pluginApi.pluginSettings.panelHeightRatio = root.editPanelHeightRatio;
    pluginApi.pluginSettings.panelWidth = root.editPanelWidth;
    pluginApi.pluginSettings.attachmentStyle = root.editAttachmentStyle;
    pluginApi.pluginSettings.scale = root.editScale;

    pluginApi.saveSettings();

    Logger.i("OllamaAssitant", "Settings saved successfully");
  }
}
