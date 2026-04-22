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
    if(backwards) {
      mainInstance.tabBackward();
    } else {
      mainInstance.tabForward();
    }
  }

  property var pluginApi: null

  // SmartPanel properties for detachment and anchoring
  readonly property var geometryPlaceholder: panelContainer
  readonly property string panelPosition: (pluginApi?.pluginSettings?.panelPosition ?? pluginApi?.manifest?.metadata?.panel?.defaultPosition ?? "right")
  readonly property bool _detached: pluginApi?.pluginSettings?.panelDetached ?? pluginApi?.manifest?.metadata?.panel?.detached ?? true

  // Standard attach logic: Attach if not detached.
  // With universal floating mode, we always use SmartPanel's attach logic if not in detached mode.
  // The specific anchoring (connected vs floating) is handled below.
  readonly property bool allowAttach: !_detached

  property int _panelWidth: pluginApi?.pluginSettings?.panelWidth ?? 520
  property real _panelHeightRatio: pluginApi?.pluginSettings?.panelHeightRatio ?? pluginApi?.manifest?.metadata?.panel?.defaultHeightRatio ?? 0.85
  property real contentPreferredWidth: _panelWidth
  property real contentPreferredHeight: screen ? (screen.height * _panelHeightRatio) : 620 * Style.uiScaleRatio

  // Plugin UI scale (per-plugin setting)
  property real uiScale: pluginApi?.pluginSettings?.scale ?? pluginApi?.manifest?.metadata?.defaultSettings?.scale ?? 1

  // Access main instance
  readonly property var mainInstance: pluginApi?.mainInstance
  property bool isGenerating: mainInstance?.isGenerating
  property var convs: mainInstance?.conversations
  property var memoryStore: mainInstance?.memoryStore

  // Calculate anchoring based on position
  readonly property bool panelAnchorTop: panelPosition.startsWith("top")
  readonly property bool panelAnchorBottom: panelPosition.startsWith("bottom")
  readonly property bool panelAnchorLeft: panelPosition.includes("left") || panelPosition === "left"
  readonly property bool panelAnchorRight: panelPosition.includes("right") || panelPosition === "right"
  readonly property bool panelAnchorHCenter: panelPosition === "top" || panelPosition === "bottom"
  readonly property bool panelAnchorVCenter: panelPosition === "left" || panelPosition === "right"


  Component.onCompleted: {
    Logger.i("OllamaAssistant", "Panel initialized");
    Logger.d("OllamaAssistant", "main instance: ", mainInstance);
    Logger.d("OllamaAssistant", "Panel position: ", panelPosition);
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

        RowLayout {
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM
          // Buttons (fixed on left, no stretching)
          Row {
            spacing: Style.marginM

            TabButton {
              width: 33 * panel.uiScale
              height: 33 * panel.uiScale
              icon: "plus"
              tooltipText: "New Chat"
              onClicked: mainInstance.createNewConversation()
            }

            TabButton {
              width: 33 * panel.uiScale
              height: 33 * panel.uiScale
              icon: "trash"
              visible: false
              tooltipText: "Clear Current Chat"
              onClicked: mainInstance.clearMessages()
            }
          }

          // Tabs (takes remaining space)
          Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true

            contentWidth: tabRow.width
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds

            Row {
              id: tabRow
              spacing: Style.marginS

              Repeater {
                model: Object.keys(convs)

                delegate: TabButton {
                  id: tabBtn
                  width: Math.min(implicitWidth * panel.uiScale, 200)
                  height: 33 * panel.uiScale
                  tooltipText: memoryStore[Number(modelData)]?.summary
                  icon: "sparkles"
                  label: "Chat " + (Number(modelData) + 1)
                  isActive: mainInstance.activeConversationIndex === Number(modelData)

                  onClicked: mainInstance.switchConversation(Number(modelData))
                }
              }
            }
          }


          Item {
            anchors.fill: flick
            z: 2
            // pointerEvents: false   // don’t block clicks

            // LEFT fade
            Rectangle {
              width: 50
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.bottom: parent.bottom

              visible: flick.contentX > 0

              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Color.mSurfaceVariant }
                GradientStop { position: 1.0; color: "transparent" }
              }
              MouseArea {
                anchors.fill: parent
                hoverEnabled: true

                onEntered: scrollLeftTimer.start()
                onExited: scrollLeftTimer.stop()
              }
            }

            Timer {
              id: scrollLeftTimer
              interval: 16
              repeat: true
              running: false
              onTriggered: {
                flick.contentX = Math.max(0, flick.contentX - 5)
              }
            }

            // RIGHT fade
            Rectangle {
              width: 50
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom

              visible: flick.contentX < flick.contentWidth - flick.width - 1

              gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Color.mSurfaceVariant }
              }
              MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true

                  onEntered: scrollRightTimer.start()
                  onExited: scrollRightTimer.stop()
              }
            }
            Timer {
              id: scrollRightTimer
              interval: 16
              repeat: true
              running: false
              onTriggered: {
                flick.contentX = Math.min(
                  flick.contentWidth - flick.width,
                  flick.contentX + 5
                )
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
    property string tooltipText: ""

    signal clicked

    implicitWidth: tabButtonContent.implicitWidth + Style.marginM * 2
    implicitHeight: tabButtonContent.implicitHeight + Style.marginS * 2

    color: isActive ? Color.mPrimary : (tabMouseArea.containsMouse ? Color.mHover : "transparent")
    radius: Style.iRadiusS

    RowLayout {
      id: tabButtonContent
      anchors.centerIn: parent
      spacing: Style.marginS
      ToolTip.visible: tabMouseArea.containsMouse
      ToolTip.delay: 750
      ToolTip.text: tabButton.tooltipText

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

