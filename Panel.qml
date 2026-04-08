import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
  id: panel
  Keys.onPressed: handleKeyPress

  function handleKeyPress(event) {
    if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
      // Shift+Tab -> previous
      panel.cycleTab(true);
      event.accepted = true;
    } else if (event.key === Qt.Key_Tab && !event.modifiers) {
      // Tab -> next
      panel.cycleTab(false);
      event.accepted = true;
    }
  }
  // Cycle tabs programmatically (called by child views when Tab is pressed)
  function cycleTab(backwards) {
    // TODO: re implement once conversations are implemented
  }

  property var pluginApi: null

  // SmartPanel properties for detachment and anchoring
  readonly property var geometryPlaceholder: panelContainer
  readonly property string _panelPosition: (pluginApi?.pluginSettings?.panelPosition ?? pluginApi?.manifest?.metadata?.panel?.defaultPosition ?? "right")
  readonly property bool _detached: pluginApi?.pluginSettings?.panelDetached ?? pluginApi?.manifest?.metadata?.panel?.detached ?? true
  readonly property string _attachmentStyle: pluginApi?.pluginSettings?.attachmentStyle || "connected"
  readonly property bool _isFloatingAttached: !_detached && _attachmentStyle === "floating"

  // Standard attach logic: Attach if not detached.
  // With universal floating mode, we always use SmartPanel's attach logic if not in detached mode.
  // The specific anchoring (connected vs floating) is handled below.
  readonly property bool allowAttach: !_detached

  // Anchor Logic Breakdown:
  // 1. Detached: Only Left/Center/Right supported. No Top/Bottom anchors.
  // 2. Attached Connected: Standard anchors on the respective side.
  // 3. Attached Floating:
  //    - Left/Right: Anchor to side + Vertical Center (Drawer).
  //    - Top/Bottom: Anchor to edge + Horizontal Center (Drawer).

  readonly property bool panelAnchorRight: !_detached ? _panelPosition === "right" : (_panelPosition === "right")
  readonly property bool panelAnchorLeft: !_detached ? _panelPosition === "left" : (_panelPosition === "left")

  // Horizontal Center:
  // - Detached Center (Standard)
  // - Attached Floating Top or Bottom (Vertical Drawer)
  readonly property bool panelAnchorHorizontalCenter: (_detached && _panelPosition === "center") || (_isFloatingAttached && (_panelPosition === "top" || _panelPosition === "bottom"))

  // Vertical Center:
  // - Detached Left/Right (Standard Detached Side behavior, if defined by shell)
  // - Attached Floating Left or Right (Side Drawer)
  readonly property bool panelAnchorVerticalCenter: _detached || (_isFloatingAttached && (_panelPosition === "left" || _panelPosition === "right"))

  // Top/Bottom:
  // - Only valid in Attached mode
  readonly property bool panelAnchorTop: !_detached && _panelPosition === "top"
  readonly property bool panelAnchorBottom: !_detached && _panelPosition === "bottom"

  property int _panelWidth: pluginApi?.pluginSettings?.panelWidth ?? 520
  property real _panelHeightRatio: pluginApi?.pluginSettings?.panelHeightRatio ?? pluginApi?.manifest?.metadata?.panel?.defaultHeightRatio ?? 0.85
  property real contentPreferredWidth: _panelWidth
  property real contentPreferredHeight: screen ? (screen.height * _panelHeightRatio) : 620 * Style.uiScaleRatio

  // Plugin UI scale (per-plugin setting)
  property real uiScale: pluginApi?.pluginSettings?.scale ?? pluginApi?.manifest?.metadata?.defaultSettings?.scale ?? 1

  anchors.fill: parent

  // Access main instance
  readonly property var mainInstance: pluginApi?.mainInstance
  property bool isGenerating: mainInstance?.isGenerating


  Component.onCompleted: {
    Logger.i("OllamaAssistant", "Panel initialized");
    Logger.d("OllamaAssistant", "main instance: ", mainInstance);
  }

  // Focus input when panel is shown and AI tab is active
  onVisibleChanged: {
    if (visible) {
      // Delay to ensure child is ready
      Qt.callLater(function () {
        aiChatViewRef.focusInput();
      });
    }
  }

  onIsGeneratingChanged: {
    if (visible) {
      Qt.callLater(function () {
        aiChatViewRef.focusInput();
      });
    }
  }

  Rectangle {
    id: panelContainer
    width: contentPreferredWidth
    height: contentPreferredHeight
    color: "transparent"
    // Center mode: use anchors only
    anchors.horizontalCenter: (_detached && _panelPosition === "center" && parent) ? parent.horizontalCenter : undefined
    anchors.verticalCenter: (_detached && _panelPosition === "center" && parent) ? parent.verticalCenter : undefined
    // Left/right mode: no anchors, only x/y
    // ...no horizontal offset logic...
    y: (_detached && (_panelPosition === "left" || _panelPosition === "right")) ? (panel.height - contentPreferredHeight) / 2 : 0

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginM

      // Tab bar
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: tabRow.implicitHeight + Style.marginS * 3
        color: Color.mSurfaceVariant
        radius: Style.radiusM
        // Scaled host for tab row so top bar scales with plugin `uiScale`.
        Flickable {
          id: flick
          anchors.fill: parent
          anchors.margins: Style.marginM
          contentWidth: tabRow.width
          clip: true
          flickableDirection: Flickable.HorizontalFlick
          boundsBehavior: Flickable.StopAtBounds
          // interactive: true
          property real s: panel.uiScale

          ListModel {
            id: tabsModel
            // default elements
            // 1. Current node
            // 2. new tab button
            // 3. clear all button

            // new nodes are to be inserted before the new tab button
            ListElement { idStr: "currentNode"; label: "Current Node"; icon: "sparkles"; active: true }
            ListElement { idStr: "newNode"; label: "New Tab"; icon: "plus" }
            ListElement { idStr: "deleteAll"; label: "Clear All"; icon: "trash" }
          }

          Row {
            id: tabRow
            height: implicitHeight
            spacing: Style.marginS
            Repeater {
              model: tabsModel
              id: tabRowRepeater

              delegate: TabButton {
                width: Math.min(implicitWidth * panel.uiScale , 200)
                height: 33 * panel.uiScale
                icon: model.icon
                label: model.idStr === "currentNode" ? "Chat" : ""
                isActive: model.active
                // TODO: currently the state processing stores all the conversations in single messsages history
                // Need to redesign state management to support multiple conversations and then
                // implement injecting nodes dynamically into tabsModel and implement switching between conversations
                // onClicked: {
                //  panel.activeTab = model.idStr;
                //  if (mainInstance) {
                //    mainInstance.activeTab = model.idStr;
                //    mainInstance.saveState();
                //  }
                //}
              }
            }
          }
        }
      }

      // Content area (wrapped to respect per-plugin UI scale)
      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Color.mSurfaceVariant
        radius: Style.radiusL
        clip: true

        // Container that will host scaled content. We keep the Rectangle size
        // unchanged (so panel dimensions remain governed by panel settings),
        // and scale the inner content while sizing it to parent/scale so it fits.
        Item {
          anchors.fill: parent

          property real s: panel.uiScale

          // The inner content has unscaled size parent.size / s so that when
          // scaled by `s` it exactly fits the parent Rectangle without overflow.
          Item {
            id: scaledContent
            width: parent.width / (parent.s || 1)
            height: parent.height / (parent.s || 1)
            scale: parent.s || 1
            anchors.centerIn: parent
            transformOrigin: Item.Center

            // AI Chat Tab
            AiChatView {
              id: aiChatViewRef
              anchors.fill: parent
              anchors.margins: Style.marginM
              pluginApi: panel.pluginApi
              mainInstance: panel.mainInstance
              onRequestTabCycleForward: panel.cycleTab(false)
              onRequestTabCycleBackward: panel.cycleTab(true)
            }
          }
        }
      }
    }
  }

  // Tab Button Component
  component TabButton: Rectangle {
    id: tabButton

    property string icon: ""
    property string label: ""
    property bool isActive: false

    signal clicked

    implicitWidth: tabButtonContent.implicitWidth + Style.marginM * 2
    implicitHeight: tabButtonContent.implicitHeight + Style.marginS * 2

    color: isActive ? Color.mPrimary : (tabMouseArea.containsMouse ? Color.mHover : "transparent")
    radius: Style.iRadiusS

    RowLayout {
      id: tabButtonContent
      anchors.centerIn: parent
      spacing: Style.marginS

      NIcon {
        icon: tabButton.icon
        color: tabButton.isActive ? Color.mOnPrimary : Color.mOnSurfaceVariant
        pointSize: Style.fontSizeM
      }

      NText {
        text: tabButton.label
        color: tabButton.isActive ? Color.mOnPrimary : Color.mOnSurfaceVariant
        pointSize: Style.fontSizeS
        font.weight: tabButton.isActive ? Font.Medium : Font.Normal
      }
    }

    MouseArea {
      id: tabMouseArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tabButton.clicked()
    }
  }
}
