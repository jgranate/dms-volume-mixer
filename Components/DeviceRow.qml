import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Common
import qs.Services
import qs.Widgets
import "../Logic"

ColumnLayout {
    id: root
    property var deviceNode: null
    property var volLogic: null
    property bool isSink: true

    width: parent.width
    spacing: 2
    opacity: (volLogic && deviceNode) ? (volLogic.isDeactivated(deviceNode.id) ? 0.4 : 1.0) : 1.0

    readonly property bool isDefault: {
        if (!volLogic || !deviceNode) return false;
        return isSink ? volLogic.isDefaultSink(deviceNode) : volLogic.isDefaultSource(deviceNode)
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingS

        DankIcon {
            name: {
                if (!deviceNode || !deviceNode.audio) return isSink ? "volume_up" : "mic";
                if (deviceNode.audio.muted) return isSink ? "volume_off" : "mic_off";
                if (!volLogic) return isSink ? "volume_up" : "mic";
                return isSink ? volLogic.getSinkIcon(deviceNode) : volLogic.getSourceIcon(deviceNode);
            }
            size: 18
            color: (volLogic && deviceNode && (volLogic.isDeactivated(deviceNode.id) || !root.isDefault)) 
                ? Theme.surfaceVariantText 
                : (deviceNode?.audio?.muted ? Theme.error : Theme.primary)
            Layout.alignment: Qt.AlignVCenter
        }

        DankSlider {
            id: deviceSlider
            Layout.fillWidth: true
            height: 32
            minimum: 0
            maximum: 100
            enabled: !!(volLogic && deviceNode && !volLogic.isDeactivated(deviceNode.id))
            value: (deviceNode && deviceNode.audio) ? Math.round(deviceNode.audio.volume * 100) : 0
            showValue: true
            unit: "%"
            thumbOutlineColor: Theme.surfaceVariant

            onSliderValueChanged: newValue => {
                if (deviceNode?.audio) {
                    deviceNode.audio.volume = newValue / 100;
                    if (isSink && newValue > 0 && deviceNode.audio.muted)
                        deviceNode.audio.muted = false;
                    AudioService.playVolumeChangeSoundIfEnabled();
                }
            }
        }
        
        RowLayout {
            spacing: 2
            
            DankActionButton {
                iconName: (volLogic && deviceNode && volLogic.isDeactivated(deviceNode.id)) ? "visibility_off" : "visibility"
                iconColor: (volLogic && deviceNode && volLogic.isDeactivated(deviceNode.id)) ? Theme.surfaceVariantText : Theme.primary
                buttonSize: 28
                iconSize: 14
                tooltipText: (volLogic && deviceNode && volLogic.isDeactivated(deviceNode.id)) ? "Activate device" : "Deactivate device"
                onClicked: {
                    if (volLogic && deviceNode) {
                        if (deviceNode.audio) {
                            deviceNode.audio.muted = !volLogic.isDeactivated(deviceNode.id);
                        }
                        volLogic.toggleDeactivation(deviceNode.id);
                    }
                }
            }

            DankActionButton {
                iconName: {
                    if (isSink) return (deviceNode?.audio?.muted ?? true) ? "volume_off" : "volume_up";
                    return (deviceNode?.audio?.muted ?? true) ? "mic_off" : "mic";
                }
                iconColor: (volLogic && deviceNode && (volLogic.isDeactivated(deviceNode.id) || !root.isDefault)) 
                    ? Theme.surfaceVariantText 
                    : (deviceNode?.audio?.muted ? Theme.error : Theme.primary)
                buttonSize: 28
                iconSize: 16
                enabled: !!(volLogic && deviceNode && !volLogic.isDeactivated(deviceNode.id))
                onClicked: {
                    if (deviceNode?.audio) {
                        const newMute = !deviceNode.audio.muted;
                        deviceNode.audio.muted = newMute;
                        if (volLogic) volLogic.setManualMute(deviceNode.id, newMute);
                    }
                }
            }
        }
    }

    StyledText {
        text: deviceNode ? AudioService.displayName(deviceNode) : "Unknown Device"
        font.pixelSize: 10
        color: (volLogic && deviceNode && (volLogic.isDeactivated(deviceNode.id) || !root.isDefault)) ? Theme.surfaceVariantText : Theme.primary
        font.weight: root.isDefault ? Font.Bold : Font.Normal
        elide: Text.ElideMiddle
        Layout.fillWidth: true
        Layout.leftMargin: 36
        
        MouseArea {
            anchors.fill: parent
            enabled: !!(volLogic && deviceNode && !volLogic.isDeactivated(deviceNode.id))
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            propagateComposedEvents: false
            onClicked: mouse => {
                if (volLogic && deviceNode) {
                    if (isSink) volLogic.setDefaultSink(deviceNode);
                    else volLogic.setDefaultSource(deviceNode);
                }
                mouse.accepted = true;
            }
            ToolTip.visible: containsMouse
            ToolTip.text: deviceNode ? AudioService.displayName(deviceNode) : ""
            ToolTip.delay: 500
        }
    }
}
