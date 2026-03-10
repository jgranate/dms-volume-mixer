import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Services.Pipewire
import qs.Common
import qs.Services
import qs.Widgets
import "../Logic"

StyledRect {
    id: root
    property var streamNode: null
    property var volLogic: null
    property int maxVolume: 115

    width: parent.width
    height: 96
    radius: Theme.cornerRadius
    color: Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency)

    PwObjectTracker {
        objects: streamNode ? [streamNode] : []
    }

    readonly property var mprisPlayer: (volLogic && streamNode) ? volLogic.findMprisPlayer(streamNode) : null
    
    readonly property bool shouldShowMetadata: {
        if (!volLogic || !streamNode || !mprisPlayer) return false;
        const allStreams = volLogic.getAudioStreams();
        const appName = (streamNode.properties?.["application.name"] || "").toLowerCase();
        const appStreams = allStreams.filter(s => (s.properties?.["application.name"] || "").toLowerCase() === appName);
        
        if (appStreams.length > 1) {
            const runningStreams = appStreams.filter(s => s.state === PwNode.Running);
            if (runningStreams.length > 1) return false;
            if (streamNode.state === PwNode.Running) return true;
            return false;
        }
        
        if (streamNode.state === PwNode.Running) return true;
        const anyRunning = appStreams.some(s => s.state === PwNode.Running);
        if (!anyRunning && appStreams.length > 0) return appStreams[0].id === streamNode.id;
        return false;
    }

    readonly property bool isStreamPlaying: {
        if (!volLogic || !streamNode) return false;
        const _ = volLogic.stateTrigger;
        if (mprisPlayer) return mprisPlayer.playbackState === 1;
        return streamNode.state === PwNode.Running;
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Theme.spacingS
        spacing: Theme.spacingM

        AppIconRenderer {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            Layout.alignment: Qt.AlignVCenter
            iconSize: 48
            iconValue: {
                if (!streamNode) return "material:volume_up";
                const props = streamNode.properties || {};
                
                // If it's a recording stream, show a mic icon
                if (streamNode.isSource) return "material:mic";

                return props["application.icon-name"] 
                    || props["window.icon"]
                    || props["application.process.binary"]
                    || props["node.name"]
                    || "material:volume_up"
            }
            fallbackText: {
                if (!streamNode) return "?";
                const name = (streamNode.properties?.["application.name"] || streamNode.name || "?")[0];
                return name.toUpperCase();
            }
            opacity: (streamNode?.audio?.muted || !root.isStreamPlaying) ? 0.5 : 1.0
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            // --- LINE 1: Title ---
            ScrollingText {
                text: {
                    if (!streamNode) return "";
                    const app = AudioService.displayName(streamNode);
                    if (root.shouldShowMetadata && root.mprisPlayer?.trackTitle)
                        return root.mprisPlayer.trackTitle;

                    const props = streamNode.properties || {};
                    const media = props["media.name"];
                    if (media && media !== "Playback" && media !== app) return media;
                    
                    const desc = props["node.description"];
                    if (desc && desc !== app && desc !== "Playback") return desc;
                    
                    return app;
                }
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: root.isStreamPlaying ? Theme.surfaceText : Theme.surfaceVariantText
            }

            // --- LINE 2: Artist & Volume ---
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingM

                ScrollingText {
                    visible: !!(streamNode && (AudioService.displayName(streamNode) !== (root.shouldShowMetadata && root.mprisPlayer?.trackTitle ? root.mprisPlayer.trackTitle : "") || (root.shouldShowMetadata && root.mprisPlayer?.trackArtist)))
                    text: {
                        if (!streamNode) return "";
                        const app = AudioService.displayName(streamNode);
                        if (root.shouldShowMetadata && root.mprisPlayer?.trackArtist)
                            return root.mprisPlayer.trackArtist + " (" + app + ")";
                        return app;
                    }
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    scrollSpeed: 40
                }

                DankSlider {
                    id: streamSlider
                    Layout.preferredWidth: 100
                    Layout.preferredHeight: 24
                    minimum: 0
                    maximum: root.maxVolume
                    showValue: true
                    unit: "%"

                    readonly property real actualVolumePercent: streamNode?.audio ? Math.round(streamNode.audio.volume * 100) : 0
                    value: streamNode?.audio ? Math.min(root.maxVolume, Math.round(streamNode.audio.volume * 100)) : 0
                    valueOverride: actualVolumePercent

                    onSliderValueChanged: newValue => {
                        if (streamNode?.audio) {
                            SessionData.suppressOSD = true;
                            streamNode.audio.volume = newValue / 100;
                            if (newValue > 0 && streamNode.audio.muted)
                                streamNode.audio.muted = false;
                            AudioService.playVolumeChangeSoundIfEnabled();
                        }
                    }
                }

                DankActionButton {
                    iconName: streamNode?.audio?.muted ? "volume_off" : "volume_up"
                    iconColor: streamNode?.audio?.muted ? Theme.error : Theme.surfaceText
                    buttonSize: 24
                    iconSize: 14
                    onClicked: {
                        if (streamNode?.audio) {
                            SessionData.suppressOSD = true;
                            streamNode.audio.muted = !streamNode.audio.muted;
                            AudioService.playVolumeChangeSoundIfEnabled();
                        }
                    }
                }
            }

            // --- LINE 3: Routing ---
            RoutingStrip {
                visible: !!(root.streamNode && root.streamNode.isSink)
                streamNode: root.streamNode
                volLogic: root.volLogic
                stateTrigger: root.volLogic ? root.volLogic.stateTrigger : 0
            }
        }
    }
}
