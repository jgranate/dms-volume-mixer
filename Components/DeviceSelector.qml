import QtQuick
import QtQuick.Controls
import Quickshell.Services.Pipewire
import qs.Common
import qs.Services
import qs.Widgets

DankDropdown {
    id: root

    compactMode: true
    emptyText: I18n.tr("No output devices")

    readonly property var sinkEntries: {
        const _ = Pipewire.nodes.values;
        const _sink = AudioService.sink;
        return root.buildEntries();
    }

    function buildEntries() {
        const labelToName = {};
        const nameToLabel = {};
        const labels = [];
        const icons = [];
        for (const node of AudioService.getAvailableSinks()) {
            let label = AudioService.displayName(node) || node.name;
            if (labelToName[label] !== undefined)
                label = label + " (" + node.name + ")";
            labelToName[label] = node.name;
            nameToLabel[node.name] = label;
            labels.push(label);
            icons.push(AudioService.sinkIcon(node));
        }
        return {
            labelToName: labelToName,
            nameToLabel: nameToLabel,
            labels: labels,
            icons: icons
        };
    }

    options: root.sinkEntries.labels
    optionIcons: root.sinkEntries.icons

    property string _activeLabel: ""
    property string _requestedName: ""
    property bool _syncing: false

    function activeLabel() {
        const sink = AudioService.sink;
        if (!sink)
            return "";
        return root.sinkEntries.nameToLabel[sink.name] ?? (AudioService.displayName(sink) || sink.name);
    }

    function syncActive() {
        const sink = AudioService.sink;
        if (sink) {
            root._activeLabel = root.activeLabel();
        } else if (root.sinkEntries.labels.length === 0) {
            root._activeLabel = "";
        }
        root._syncing = true;
        root.currentValue = root._activeLabel;
        root._syncing = false;
        root.checkPendingRequest();
    }

    function checkPendingRequest() {
        if (root._requestedName === "")
            return;
        const sink = AudioService.sink;
        if (sink && sink.name === root._requestedName) {
            root._requestedName = "";
            root.verifyTimer.stop();
        }
    }

    function selectSink(name) {
        if (!name)
            return;
        if (!AudioService.setDefaultSinkByName(name)) {
            ToastService.showError(I18n.tr("Could not switch output device"));
            root.verifyTimer.stop();
            root._requestedName = "";
            root.syncActive();
            return;
        }
        root._requestedName = name;
        root.verifyTimer.restart();
    }

    Timer {
        id: verifyTimer
        interval: 1500
        repeat: false
        onTriggered: {
            const sink = AudioService.sink;
            const matched = root._requestedName !== "" && sink && sink.name === root._requestedName;
            if (!matched)
                ToastService.showError(I18n.tr("Output device change failed"));
            root._requestedName = "";
            root.syncActive();
        }
    }

    Component.onCompleted: root.syncActive()

    Connections {
        target: Pipewire
        function onDefaultAudioSinkChanged() { root.syncActive() }
    }

    onSinkEntriesChanged: root.syncActive()

    onValueChanged: value => {
        if (root._syncing)
            return;
        const name = root.sinkEntries.labelToName[value];
        if (!name) {
            ToastService.showError(I18n.tr("Could not switch output device"));
            root.syncActive();
            return;
        }
        root.selectSink(name);
    }
}
