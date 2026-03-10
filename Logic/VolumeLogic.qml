import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import qs.Services
import qs.Modules.Plugins

Item {
    id: root

    // --- State Handlers ---
    property string pluginId
    property var pluginData
    property var pluginService

    // Reactive Trigger
    property int stateTrigger: 0
    property var routingOverrides: ({})

    // Persisted State (Authoritative)
    readonly property var deactivatedIds: root.pluginData?.deactivatedIds ?? []
    readonly property bool hideInactive: root.pluginData?.hideInactive ?? false

    // --- Core Master Props ---
    readonly property real masterVolume: AudioService.sink?.audio
        ? Math.round(AudioService.sink.audio.volume * 100)
        : 0
    readonly property bool masterMuted: AudioService.sink?.audio?.muted ?? false

    // --- Reactivity ---
    PwObjectTracker {
        objects: [Pipewire.nodes, Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    Connections {
        target: Pipewire.nodes
        function onValuesChanged() { root.stateTrigger++ }
    }

    Connections {
        target: Pipewire
        function onDefaultAudioSinkChanged() { root.stateTrigger++ }
        function onDefaultAudioSourceChanged() { root.stateTrigger++ }
    }

    Connections {
        target: Mpris.players
        function onValuesChanged() { root.stateTrigger++ }
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: root.stateTrigger++
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.stateTrigger++
    }

    // --- Volume Scroll Logic ---
    property real _scrollAccumulator: 0
    property bool _scrollInProgress: false

    function adjustVolumeByScroll(wheelEvent, reverseScroll = false) {
        if (!AudioService.sink?.audio || root._scrollInProgress) return;

        const delta = wheelEvent.angleDelta.y;
        root._scrollAccumulator += delta;

        if (Math.abs(root._scrollAccumulator) < 120) return;

        let currentVolume = AudioService.sink.audio.volume * 100;
        let maxVol = 115; 
        let step = 5;
        let newVolume;

        const reverse = reverseScroll ? -1 : 1;

        if (root._scrollAccumulator * reverse > 0)
            newVolume = Math.min(maxVol, currentVolume + step);
        else
            newVolume = Math.max(0, currentVolume - step);
        
        AudioService.sink.audio.muted = false;
        AudioService.sink.audio.volume = newVolume / 100;
        
        root._scrollInProgress = true;
        root._scrollAccumulator = 0;
        wheelEvent.accepted = true;
        
        // Reset scroll lock
        Qt.callLater(() => { root._scrollInProgress = false; });
    }

    // --- Logic Functions ---

    function isDeactivated(nodeId) {
        if (!nodeId) return false;
        const list = root.deactivatedIds;
        return Array.isArray(list) && list.includes(nodeId);
    }

    function toggleDeactivation(nodeId) {
        let list = [...root.deactivatedIds];
        const index = list.indexOf(nodeId);
        const deactivating = (index === -1);

        if (deactivating) list.push(nodeId);
        else list.splice(index, 1);

        if (root.pluginService) {
            root.pluginService.savePluginData(root.pluginId, "deactivatedIds", list);
        }

        const node = Pipewire.nodes.values.find(n => n.id == nodeId);
        if (node && node.audio) {
            const isSink = node.isSink;
            node.audio.muted = deactivating;
            
            if (deactivating) {
                const replacement = Pipewire.nodes.values.find(n => 
                    n.audio && n.isSink === isSink && !n.isStream && n.id != nodeId && !list.includes(n.id)
                );
                
                if (replacement) {
                    if (isSink && root.isDefaultSink(node)) root.setDefaultSink(replacement);
                    else if (!isSink && root.isDefaultSource(node)) root.setDefaultSource(replacement);
                    
                    if (isSink) {
                        Pipewire.nodes.values.filter(n => n.isStream && n.audio).forEach(stream => {
                            if (stream.audio.sinkId == nodeId || (stream.properties && stream.properties["node.driver-id"] == nodeId)) {
                                root.moveStream(stream, replacement);
                            }
                        });
                    }
                } else if (isSink && AudioService.sink?.audio) {
                    AudioService.sink.audio.muted = true;
                    Quickshell.execDetached(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "1"]);
                }
                
                Qt.callLater(() => { if (node?.audio) node.audio.muted = true; });
            } else if (isSink && AudioService.sink?.audio) {
                AudioService.sink.audio.muted = false;
                Quickshell.execDetached(["pactl", "set-sink-mute", "@DEFAULT_SINK@", "0"]);
            }
        }
        root.stateTrigger++;
    }

    function toggleHideInactive() {
        if (root.pluginService) {
            root.pluginService.savePluginData(root.pluginId, "hideInactive", !root.hideInactive);
        }
        root.stateTrigger++;
    }

    function getAudioStreams() {
        const nodes = Pipewire.nodes.values.filter(n => 
            n.audio && n.isStream && (n.isSink || n.isSource) && 
            n.name !== "quickshell" && 
            !n.name.toLowerCase().includes("cava")
        );
        return nodes;
    }

    readonly property bool isAnyStreamPlaying: {
        const _ = root.stateTrigger;
        return root.getAudioStreams().some(s => {
            if (s.state !== PwNode.Running) return false;
            const player = root.findMprisPlayer(s);
            if (player) return player.playbackState === 1;
            return true;
        });
    }

    function isDefaultSink(node) {
        const _ = root.stateTrigger;
        const def = Pipewire.defaultAudioSink;
        if (!node || !def || !node.isSink) return false;
        return node.id === def.id || node.name === def.name;
    }

    function isDefaultSource(node) {
        const _ = root.stateTrigger;
        const def = Pipewire.defaultAudioSource;
        if (!node || !def || node.isSink) return false;
        return node.id === def.id || node.name === def.name;
    }

    function isStreamRoutedTo(streamNode, sinkNode) {
        const _ = root.stateTrigger;
        if (!streamNode || !sinkNode || !streamNode.audio) return false;
        
        const sinkId = sinkNode.id;
        const sinkName = sinkNode.name;
        const props = streamNode.properties || {};
        const serial = props["object.serial"] || streamNode.id;
        
        const override = root.routingOverrides[serial];
        if (override !== undefined) return (override == sinkId || override == sinkName);

        const target = props["node.target"];
        const driverId = props["node.driver-id"];
        const currentSinkId = streamNode.audio.sinkId;

        if (driverId != null && driverId == sinkId) return true;
        if (currentSinkId != 0 && currentSinkId == sinkId) return true;
        if (target != null && target !== "" && (target == sinkId || target == sinkName)) return true;

        if (root.isDefaultSink(sinkNode)) {
            const isExplicitlyElsewhere = (target != null && target !== "" && target != sinkId && target != sinkName);
            const isPlayingElsewhere = (driverId != null && driverId != sinkId) || (currentSinkId != 0 && currentSinkId != sinkId);
            if (!isExplicitlyElsewhere && !isPlayingElsewhere) return true;
        }
        return false;
    }

    function getCurrentSinkName(streamNode) {
        const _ = root.stateTrigger;
        if (!streamNode || !streamNode.audio) return "Unknown";
        
        const props = streamNode.properties || {};
        const serial = props["object.serial"] || streamNode.id;
        const override = root.routingOverrides[serial];
        if (override !== undefined) {
            const sink = Pipewire.nodes.values.find(n => n.isSink && (n.id == override || n.name == override));
            if (sink) return AudioService.displayName(sink);
        }

        const target = props["node.target"];
        const driverId = props["node.driver-id"];
        const sinkId = streamNode.audio.sinkId;

        if (target != null && target !== "") {
            const sink = Pipewire.nodes.values.find(n => n.isSink && (n.id == target || n.name == target));
            if (sink) return AudioService.displayName(sink);
        }

        if (driverId != null) {
            const sink = Pipewire.nodes.values.find(n => n.isSink && n.id == driverId);
            if (sink) return AudioService.displayName(sink);
        }

        if (sinkId != 0) {
            const sink = Pipewire.nodes.values.find(n => n.isSink && n.id == sinkId);
            if (sink) return AudioService.displayName(sink);
        }

        const def = Pipewire.defaultAudioSink;
        return def ? AudioService.displayName(def) : "System Default";
    }

    Timer {
        id: delayedTrigger
        interval: 150
        onTriggered: {
            root.stateTrigger++;
            if (interval === 150) {
                interval = 500;
                restart();
            }
        }
    }

    function triggerDelayedUpdates() {
        root.stateTrigger++;
        delayedTrigger.interval = 150;
        delayedTrigger.restart();
    }

    function moveStream(streamNode, sinkNode) {
        if (!streamNode || !sinkNode) return;
        const streamId = streamNode.id;
        const serial = streamNode.properties?.["object.serial"] || streamId;
        const sinkName = sinkNode.name;
        const sinkId = sinkNode.id;

        if (streamNode.properties?.["object.serial"]) {
            Quickshell.execDetached(["pactl", "move-sink-input", streamNode.properties["object.serial"].toString(), sinkName]);
        } else {
            Quickshell.execDetached(["wpctl", "move", streamId.toString(), sinkId.toString()]);
        }
        
        let overrides = root.routingOverrides;
        overrides[serial] = sinkId;
        root.routingOverrides = overrides;
        
        root.triggerDelayedUpdates();
    }

    function setDefaultSink(node) {
        if (!node || !node.name) return;
        Quickshell.execDetached(["pactl", "set-default-sink", node.name]);
        root.routingOverrides = ({});
        root.triggerDelayedUpdates();
    }

    function setDefaultSource(node) {
        if (!node || !node.name) return;
        Quickshell.execDetached(["pactl", "set-default-source", node.name]);
        root.stateTrigger++;
        Qt.callLater(() => { root.stateTrigger++ });
    }

    function findMprisPlayer(node) {
        if (!node || !node.properties) return null;
        const props = node.properties;
        const appName = (props["application.name"] || "").toLowerCase();
        const binary = (props["application.process.binary"] || "").toLowerCase();
        const nodeName = (node.name || "").toLowerCase();
        const nodeDesc = (props["node.description"] || "").toLowerCase();
        
        const players = Mpris.players.values;
        if (players.length === 0) return null;

        // 1. Try exact identity/entry matches
        for (const player of players) {
            const id = player.identity.toLowerCase();
            const entry = player.desktopEntry.toLowerCase();
            if (id === appName || entry === appName || 
                id === binary || entry === binary ||
                id === nodeName || entry === nodeName) return player;
        }
        
        // 2. Try partial/includes matches
        for (const player of players) {
            const id = player.identity.toLowerCase();
            if (appName && (id.includes(appName) || appName.includes(id))) return player;
            if (binary && (id.includes(binary) || binary.includes(id))) return player;
            if (nodeName && (id.includes(nodeName) || nodeName.includes(id))) return player;
            if (nodeDesc && (id.includes(nodeDesc) || nodeDesc.includes(id))) return player;
        }
        return null;
    }

    // --- Helpers for UI Icons ---
    function getSinkIcon(node) {
        if (!node) return "volume_up";
        const name = (node.name || "").toLowerCase();
        const desc = (node.properties?.["node.description"] || "").toLowerCase();
        if (name.includes("headphone") || name.includes("headset") || name.includes("cloud") ||
            desc.includes("headphone") || desc.includes("headset") || desc.includes("cloud")) return "headphones";
        if (name.includes("speaker") || desc.includes("speaker")) return "speaker";
        if (name.includes("hdmi") || name.includes("displayport")) return "monitor";
        return "speaker_group";
    }

    function getSourceIcon(node) {
        if (!node) return "mic";
        const name = (node.name || "").toLowerCase();
        if (name.includes("headset")) return "headset_mic";
        if (name.includes("webcam")) return "videocam";
        return "mic";
    }
}
