import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Services.Pipewire
import qs.Common
import qs.Services
import qs.Widgets
import "../Logic"

RowLayout {
    id: root
    property var streamNode: null
    property var volLogic: null
    property int stateTrigger: 0

    Layout.fillWidth: true
    spacing: Theme.spacingXS

    StyledText {
        text: "Route to:"
        font.pixelSize: 9
        color: Theme.surfaceVariantText
        Layout.rightMargin: 4
    }

    Repeater {
        model: ScriptModel {
            values: {
                if (!volLogic) return [];
                const _ = root.stateTrigger;
                return Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream && !volLogic.isDeactivated(n.id));
            }
        }

        delegate: Rectangle {
            width: 20
            height: 20
            radius: 10
            color: routeArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"
            border.width: 1
            border.color: (volLogic && volLogic.isStreamRoutedTo(root.streamNode, modelData)) ? Theme.primary : "transparent"

            DankIcon {
                anchors.centerIn: parent
                name: volLogic ? volLogic.getSinkIcon(modelData) : "volume_up"
                size: 12
                color: (volLogic && volLogic.isStreamRoutedTo(root.streamNode, modelData)) ? Theme.primary : Theme.surfaceText
            }
            
            MouseArea {
                id: routeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (volLogic) volLogic.moveStream(root.streamNode, modelData)
                ToolTip.visible: containsMouse
                ToolTip.text: AudioService.displayName(modelData)
                ToolTip.delay: 500
            }
        }
    }

    Item { Layout.fillWidth: true } // Spacer

    StyledText {
        text: (volLogic && streamNode) ? volLogic.getCurrentSinkName(root.streamNode) : ""
        font.pixelSize: 8
        font.weight: Font.Bold
        color: Theme.primary
        Layout.fillWidth: true
        Layout.maximumWidth: 150
        elide: Text.ElideMiddle
        wrapMode: Text.NoWrap
        maximumLineCount: 1
        horizontalAlignment: Text.AlignRight
        Layout.rightMargin: 4
    }
}
