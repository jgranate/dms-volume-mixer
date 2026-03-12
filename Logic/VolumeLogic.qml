import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import qs.Common
import qs.Services

Item {
    id: root

    // --- State Handlers ---
    property string pluginId
    property var pluginData
    property var pluginService

    // Reactive Trigger
    property int stateTrigger: 0
    property var routingOverrides: ({})
    property var _manualMutes: ({})

    function setManualMute(nodeId, isMuted) {
        let mutes = root._manualMutes;
        if (isMuted) mutes[nodeId] = true;
        else delete mutes[nodeId];
        root._manualMutes = mutes;
    }

    // Persisted State (Authoritative)
    readonly property var deactivatedIds: root.pluginData?.deactivatedIds ?? []
    readonly property bool hideInactive: root.pluginData?.hideInactive ?? false

    onHideInactiveChanged: root.refreshNodes()
    onDeactivatedIdsChanged: root.refreshNodes()

    // Cached Filtered Lists
    property var outputNodes: []
    property var inputNodes: []
    property var streamNodes: []
    property var activeOutputNodes: []

    function refreshNodes() {
        const nodes = Pipewire.nodes.values;
        if (!nodes) return;
        
        const currentDeactivated = root.deactivatedIds;
        
        // Main list: Honors hideInactive (deactivated devices stay visible but greyed out if toggle is off)
        root.outputNodes = nodes.filter(n => {
            if (!n.isSink || n.isStream) return false;
            const props = n.properties || {};
            const mediaClass = (props["media.class"] || "").toLowerCase();
            if (mediaClass.includes("video")) return false;
            if (root.hideInactive && currentDeactivated.includes(n.id)) return false;
            return true;
        });

        // Routing strip: ALWAYS hides deactivated devices
        root.activeOutputNodes = nodes.filter(n => {
            if (!n.isSink || n.isStream) return false;
            const props = n.properties || {};
            const mediaClass = (props["media.class"] || "").toLowerCase();
            if (mediaClass.includes("video")) return false;
            if (currentDeactivated.includes(n.id)) return false;
            return true;
        });

        root.inputNodes = nodes.filter(n => {
            const props = n.properties || {};
            const mediaClass = props["media.class"] || "";
            if (mediaClass !== "Audio/Source") return false;
            if (n.isStream) return false;
            if (root.hideInactive && currentDeactivated.includes(n.id)) return false;
            return true;
        });

        root.streamNodes = nodes.filter(n => 
            n.audio && n.isStream && (n.isSink || n.isSource) && 
            n.name !== "quickshell" && 
            !n.name.toLowerCase().includes("cava")
        );
        
        root.stateTrigger++;
    }

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
        function onValuesChanged() { root.refreshNodes() }
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

    // Reactivity and Polling
    Timer {
        id: delayedTrigger
        interval: 150
        onTriggered: {
            root.refreshNodes();
            if (interval === 150) {
                interval = 2000; // Switch to slow polling after the initial burst
                restart();
            }
        }
    }

    // OSD Reset Helper
    Timer {
        id: osdResetTimer
        interval: 1000
        onTriggered: SessionData.suppressOSD = false
    }

    function suppressOSD() {
        SessionData.suppressOSD = true;
        osdResetTimer.restart();
    }

    function triggerDelayedUpdates() {
        root.stateTrigger++;
        delayedTrigger.interval = 150;
        delayedTrigger.restart();
    }

    // Initial load
    Component.onCompleted: root.triggerDelayedUpdates()

    // --- Volume Scroll Logic ---
    property real _scrollAccumulator: 0
    property bool _scrollInProgress: false

    function adjustVolumeByScroll(wheelEvent, reverseScroll = false) {
        if (!AudioService.sink?.audio || root._scrollInProgress) return;

        const delta = wheelEvent.angleDelta.y;
        root._scrollAccumulator += delta;

        if (Math.abs(root._scrollAccumulator) < 120) return;

        // PRECISION: Use Math.round to prevent floating point jitter
        let currentVolume = Math.round(AudioService.sink.audio.volume * 100);
        let maxVol = 115; 
        let step = 5;
        let newVolume;

        const reverse = reverseScroll ? -1 : 1;

        if (root._scrollAccumulator * reverse > 0)
            newVolume = Math.min(maxVol, currentVolume + step);
        else
            newVolume = Math.max(0, currentVolume - step);
        
        // Ensure we land on a clean multiple of the step
        newVolume = Math.round(newVolume / step) * step;

        AudioService.sink.audio.muted = false;
        AudioService.sink.audio.volume = newVolume / 100;
        AudioService.playVolumeChangeSoundIfEnabled();
        
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
                // Find a replacement node that is NOT deactivated and is the same type (sink/source)
                const replacement = (isSink ? root.outputNodes : root.inputNodes).find(n => n.id != nodeId);
                
                if (replacement) {
                    if (isSink && root.isDefaultSink(node)) root.setDefaultSink(replacement);
                    else if (!isSink && root.isDefaultSource(node)) root.setDefaultSource(replacement);
                    
                    if (isSink) {
                        root.streamNodes.forEach(stream => {
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
        root.refreshNodes();
    }

    function toggleHideInactive() {
        if (root.pluginService) {
            root.pluginService.savePluginData(root.pluginId, "hideInactive", !root.hideInactive);
        }
        root.refreshNodes();
    }

    readonly property bool isAnyStreamPlaying: {
        const _ = root.stateTrigger;
        return root.streamNodes.some(s => {
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
        
        // 1. Check local overrides first
        const override = root.routingOverrides[serial];
        if (override !== undefined) return (override == sinkId || override == sinkName);

        // 2. Check explicit targets and drivers
        const target = props["node.target"];
        const driverId = props["node.driver-id"];
        const currentSinkId = streamNode.audio.sinkId;

        // Direct match
        if (driverId != null && driverId == sinkId) return true;
        if (currentSinkId != 0 && currentSinkId == sinkId) return true;
        if (target != null && target !== "" && (target == sinkId || target == sinkName)) return true;

        // 3. Handle Virtual Sinks / Link Chaining
        // If the stream is linked to a node that eventually links to this sink
        // Pipewire often sets node.driver-id to the physical device even if routed through a virtual one.
        
        // 4. Default Routing Logic
        if (root.isDefaultSink(sinkNode)) {
            // It's the default sink. Is this stream EXPLICITLY somewhere else?
            const isExplicitlyElsewhere = (target != null && target !== "" && target != sinkId && target != sinkName);
            const isPlayingElsewhere = (driverId != null && driverId != sinkId) || (currentSinkId != 0 && currentSinkId != sinkId);
            
            if (!isExplicitlyElsewhere && !isPlayingElsewhere) {
                // No explicit target, so it follows the default
                return true;
            }
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

        // Try to find the node by ID or name
        const findSink = (val) => Pipewire.nodes.values.find(n => n.isSink && (n.id == val || n.name == val));

        let sink = findSink(target) || findSink(driverId) || findSink(sinkId);
        if (sink) return AudioService.displayName(sink);

        const def = Pipewire.defaultAudioSink;
        return def ? AudioService.displayName(def) : "System Default";
    }

    function toggleMasterMute() {
        if (!AudioService.sink?.audio) return;
        const isMuting = !AudioService.sink.audio.muted;
        
        if (isMuting) {
            // Global Mute: Mute everything
            root.outputNodes.forEach(node => {
                if (node.audio) node.audio.muted = true;
            });
            AudioService.sink.audio.muted = true;
        } else {
            // Global Unmute: Restore only those that aren't manually muted
            root.outputNodes.forEach(node => {
                if (node.audio) {
                    const isManuallyMuted = !!root._manualMutes[node.id];
                    node.audio.muted = isManuallyMuted;
                }
            });
            AudioService.sink.audio.muted = false;
        }
    }

    // --- Audio Commands ---
    function runAudioCommand(args) {
        Quickshell.execDetached(args);
        root.triggerDelayedUpdates();
    }

    function moveStream(streamNode, sinkNode) {
        if (!streamNode || !sinkNode) return;
        const streamId = streamNode.id;
        const serial = streamNode.properties?.["object.serial"] || streamId;
        const sinkName = sinkNode.name;
        const sinkId = sinkNode.id;

        let cmd = [];
        if (streamNode.properties?.["object.serial"]) {
            cmd = ["pactl", "move-sink-input", streamNode.properties["object.serial"].toString(), sinkName];
        } else {
            cmd = ["wpctl", "move", streamId.toString(), sinkId.toString()];
        }
        
        root.runAudioCommand(cmd);
        
        let overrides = root.routingOverrides;
        overrides[serial] = sinkId;
        root.routingOverrides = overrides;
    }

    function setDefaultSink(node) {
        if (!node || !node.name) return;
        root.runAudioCommand(["pactl", "set-default-sink", node.name]);
        root.routingOverrides = ({});
    }

    function setDefaultSource(node) {
        if (!node || !node.name) return;
        root.runAudioCommand(["pactl", "set-default-source", node.name]);
    }

    function findMprisPlayer(node) {
        if (!node || !node.properties) return null;
        const props = node.properties;
        const nodePid = props["application.process.id"];
        const appName = (props["application.name"] || "").toLowerCase();
        const binary = (props["application.process.binary"] || "").toLowerCase();
        
        const players = Mpris.players.values;
        if (players.length === 0) return null;

        // 1. Try PID matching (Most reliable for multi-instance)
        if (nodePid) {
            for (const player of players) {
                // Bus names often contain the PID: org.mpris.MediaPlayer2.vlc.instance1234
                if (player.busName && player.busName.includes(nodePid.toString())) return player;
            }
        }

        // 2. Try exact identity/entry matches
        for (const player of players) {
            const id = player.identity.toLowerCase();
            const entry = player.desktopEntry.toLowerCase();
            if (id === appName || entry === appName || id === binary || entry === binary) return player;
        }
        
        // 3. Try partial/includes matches
        for (const player of players) {
            const id = player.identity.toLowerCase();
            if (appName && (id.includes(appName) || appName.includes(id))) return player;
            if (binary && (id.includes(binary) || binary.includes(id))) return player;
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
