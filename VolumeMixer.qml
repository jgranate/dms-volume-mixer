import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "./Logic"
import "./Components"

PluginComponent {
    id: pluginRoot

    popoutWidth: 450

    readonly property int maxStreamVol: {
        const stored = pluginRoot.pluginData?.maxStreamVol;
        if (typeof stored === "number" && stored >= 100)
            return stored;
        return 115;
    }

    readonly property var logic: volLogic

    VolumeLogic {
        id: volLogic
        pluginId: pluginRoot.pluginId
        pluginData: pluginRoot.pluginData
        pluginService: pluginRoot.pluginService
    }

    readonly property color activePillColor: {
        if (!volLogic) return Theme.surfaceText;
        const _ = volLogic.stateTrigger;
        if (volLogic.masterMuted || volLogic.masterVolume === 0)
            return Theme.surfaceVariantText;
        
        if (volLogic.isAnyStreamPlaying)
            return Theme.primary;
            
        return Theme.surfaceText;
    }

    horizontalBarPill: Component {
        Item {
            // Ensure we take up enough space for the layout but allow the MouseArea 
            // to expand to the full pill container size.
            implicitWidth: hPillRow.implicitWidth + Theme.spacingS * 2
            implicitHeight: pluginRoot.barThickness

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onWheel: wheel => volLogic.adjustVolumeByScroll(wheel, pluginRoot.pluginData?.reverseScroll)
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        if (AudioService.sink?.audio)
                            AudioService.sink.audio.muted = !AudioService.sink.audio.muted;
                    }
                }
            }

            RowLayout {
                id: hPillRow
                spacing: Theme.spacingS
                anchors.centerIn: parent
                enabled: false 

                DankIcon {
                    visible: (pluginRoot.pluginData?.pillDisplay ?? "both") !== "percent"
                    name: {
                        if (!volLogic) return "volume_up";
                        if ((pluginRoot.pluginData?.pillIcon ?? "volume") === "mixer")
                            return "tune";
                        if (volLogic.masterMuted || volLogic.masterVolume === 0)
                            return "volume_off";
                        if (volLogic.masterVolume <= 33)
                            return "volume_down";
                        return "volume_up";
                    }
                    size: Theme.barIconSize(pluginRoot.barThickness, -4)
                    color: pluginRoot.activePillColor
                }

                StyledText {
                    visible: (pluginRoot.pluginData?.pillDisplay ?? "both") !== "icon"
                    text: volLogic ? volLogic.masterVolume + "%" : "0%"
                    font.pixelSize: Theme.fontSizeExtraSmall
                    color: pluginRoot.activePillColor
                    font.strikeout: volLogic ? (volLogic.masterMuted || volLogic.masterVolume === 0) : false
                }
            }
        }
    }

    popoutContent: Component {
            PopoutComponent {
            id: popoutContainer
            headerText: "Volume Mixer"
            detailsText: AudioService.displayName(AudioService.sink)
            showCloseButton: false

            Item {
                id: popoutItem
                width: parent.width
                implicitHeight: topSection.height + Theme.spacingM + scrollSection.height
                readonly property string sortOrder: pluginRoot.pluginData?.sortOrder ?? "name_asc"

                Column {
                    id: topSection
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: Theme.spacingM

                    RowLayout {
                        width: parent.width
                        spacing: Theme.spacingS

                        StyledText {
                            text: "Hide Inactive"
                            font.pixelSize: 10
                            font.weight: Font.Medium
                            color: Theme.surfaceVariantText
                        }

                        DankToggle {
                            checked: volLogic ? volLogic.hideInactive : false
                            onToggled: if (volLogic) volLogic.toggleHideInactive()
                        }
                        
                        Item { Layout.fillWidth: true }
                    }

                    Item {
                        id: deviceColumns
                        width: parent.width
                        height: Math.max(outputCol.height, inputCol.height)

                        Column {
                            id: outputCol
                            anchors.left: parent.left
                            width: (parent.width - Theme.spacingM) / 2
                            spacing: Theme.spacingS

                            RowLayout {
                                width: parent.width
                                spacing: Theme.spacingS

                                Item { Layout.preferredWidth: 18 } // Match icon size

                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Outputs"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Bold
                                    color: Theme.primary
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Item { Layout.preferredWidth: 58 } // Match buttons width (28*2 + 2)
                            }

                            Repeater {
                                model: ScriptModel {
                                    values: volLogic ? volLogic.outputNodes : []
                                }

                                delegate: Item {
                                    width: outputCol.width
                                    height: devRowOut.implicitHeight
                                    DeviceRow {
                                        id: devRowOut
                                        width: parent.width
                                        deviceNode: modelData
                                        volLogic: pluginRoot.logic
                                        isSink: true
                                    }
                                }
                            }
                        }

                        Column {
                            id: inputCol
                            anchors.right: parent.right
                            width: (parent.width - Theme.spacingM) / 2
                            spacing: Theme.spacingS

                            RowLayout {
                                visible: AudioService.source !== null
                                width: parent.width
                                spacing: Theme.spacingS

                                Item { Layout.preferredWidth: 18 } // Match icon size

                                StyledText {
                                    Layout.fillWidth: true
                                    text: "Inputs"
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.Bold
                                    color: Theme.primary
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Item { Layout.preferredWidth: 58 } // Match buttons width (28*2 + 2)
                            }

                            Repeater {
                                model: ScriptModel {
                                    values: volLogic ? volLogic.inputNodes : []
                                }

                                delegate: Item {
                                    width: inputCol.width
                                    height: devRowIn.implicitHeight
                                    DeviceRow {
                                        id: devRowIn
                                        width: parent.width
                                        deviceNode: modelData
                                        volLogic: pluginRoot.logic
                                        isSink: false
                                    }
                                }
                            }
                        }
                    }
                }

                DankFlickable {
                    id: scrollSection
                    anchors.top: topSection.bottom
                    anchors.topMargin: Theme.spacingM
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: Math.min(Math.max(scrollColumn.implicitHeight, 100), 400)
                    contentHeight: scrollColumn.implicitHeight
                    clip: true

                    Column {
                        id: scrollColumn
                        width: parent.width
                        spacing: Theme.spacingS
                        bottomPadding: Theme.spacingS

                        Repeater {
                            model: ScriptModel {
                                values: {
                                    if (!volLogic) return [];
                                    const _ = volLogic.stateTrigger;
                                    const nodes = [...volLogic.streamNodes];
                                    const order = pluginRoot.pluginData?.sortOrder ?? "name_asc";
                                    if (order === "none") return nodes;
                                    return nodes.sort((a, b) => {
                                        if (order === "volume_desc")
                                            return (b.audio?.volume ?? 0) - (a.audio?.volume ?? 0);
                                        if (order === "volume_asc")
                                            return (a.audio?.volume ?? 0) - (b.audio?.volume ?? 0);
                                        if (order === "name_desc")
                                            return (b.properties?.["application.name"] ?? "").localeCompare(a.properties?.["application.name"] ?? "");
                                        return (a.properties?.["application.name"] ?? "").localeCompare(b.properties?.["application.name"] ?? "");
                                    });
                                }
                            }

                            delegate: Item {
                                width: scrollColumn.width
                                height: 96
                                StreamTile {
                                    width: parent.width
                                    height: parent.height
                                    streamNode: modelData
                                    volLogic: pluginRoot.logic
                                    maxVolume: pluginRoot.maxStreamVol
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
