import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "volumeMixer"

    SelectionSetting {
        settingKey: "pillIcon"
        label: "Pill Icon"
        defaultValue: "volume"
        options: [
            { label: "Volume (Dynamic)", value: "volume" },
            { label: "Mixer",            value: "mixer"  }
        ]
    }

    SelectionSetting {
        settingKey: "pillDisplay"
        label: "Pill Display"
        defaultValue: "both"
        options: [
            { label: "Both", value: "both" },
            { label: "Icon", value: "icon" },
            { label: "Percent", value: "percent" }
        ]
    }

    Column {
        id: deviceSelectorSetting
        width: parent.width
        spacing: Theme.spacingXS

        property bool isInitialized: false
        property bool value: true

        function loadValue() {
            value = root.loadValue("showDeviceSelector", true)
            isInitialized = true
        }

        Component.onCompleted: Qt.callLater(loadValue)

        onValueChanged: {
            if (!isInitialized) return
            root.saveValue("showDeviceSelector", value)
        }

        Item {
            width: parent.width
            height: deviceLabel.implicitHeight

            StyledText {
                id: deviceLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Output Device"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            DankToggle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: deviceSelectorSetting.value
                onToggled: isChecked => deviceSelectorSetting.value = isChecked
            }
        }

        StyledText {
            text: "Display active output device selection"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            width: parent.width
            wrapMode: Text.WordWrap
        }
    }

    Column {
        id: reverseScrollSetting
        width: parent.width
        spacing: Theme.spacingXS

        property bool isInitialized: false
        property bool value: false

        function loadValue() {
            value = root.loadValue("reverseScroll", false)
            isInitialized = true
        }

        Component.onCompleted: Qt.callLater(loadValue)

        onValueChanged: {
            if (!isInitialized) return
            root.saveValue("reverseScroll", value)
        }

        Item {
            width: parent.width
            height: reverseLabel.implicitHeight

            StyledText {
                id: reverseLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Reverse Scroll"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            DankToggle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: reverseScrollSetting.value
                onToggled: isChecked => reverseScrollSetting.value = isChecked
            }
        }

        StyledText {
            text: "Invert the volume scroll direction"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            width: parent.width
            wrapMode: Text.WordWrap
        }
    }

    Column {
        id: hideInactiveSetting
        width: parent.width
        spacing: Theme.spacingXS

        property bool isInitialized: false
        property bool value: false

        function loadValue() {
            value = root.loadValue("hideInactive", false)
            isInitialized = true
        }

        Component.onCompleted: Qt.callLater(loadValue)

        onValueChanged: {
            if (!isInitialized) return
            root.saveValue("hideInactive", value)
        }

        Item {
            width: parent.width
            height: hideInactiveLabel.implicitHeight

            StyledText {
                id: hideInactiveLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Hide Inactive Devices"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            DankToggle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: hideInactiveSetting.value
                onToggled: isChecked => hideInactiveSetting.value = isChecked
            }
        }

        StyledText {
            text: "Hide devices that have been deactivated in the mixer UI"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            width: parent.width
            wrapMode: Text.WordWrap
        }
    }

    SelectionSetting {
        settingKey: "sortOrder"
        label: "Sort Order"
        defaultValue: "name_asc"
        options: [
            { label: "Name (A-Z)", value: "name_asc" },
            { label: "Name (Z-A)", value: "name_desc" },
            { label: "Volume (High-Low)", value: "volume_desc" },
            { label: "Volume (Low-High)", value: "volume_asc" },
            { label: "No Sorting", value: "none" }
        ]
    }

    // --- Hidden Persisted State (Handled by VolumeMixer.qml) ---
    property var deactivatedIds: root.loadValue("deactivatedIds", [])
    property bool hideInactive: root.loadValue("hideInactive", false)

    onDeactivatedIdsChanged: root.saveValue("deactivatedIds", deactivatedIds)
    onHideInactiveChanged: root.saveValue("hideInactive", hideInactive)

    Column {
        id: maxVolSection
        width: parent.width
        spacing: Theme.spacingS

        readonly property int safeLimit: 115
        readonly property int highLimit: 200
        
        property int currentValue: 115
        property bool overdriveEnabled: false
        property bool isInitialized: false

        function loadValue() {
            currentValue = root.loadValue("maxStreamVol", safeLimit)
            overdriveEnabled = root.loadValue("allowOverdrive", false) || (currentValue > safeLimit)
            isInitialized = true
        }

        Component.onCompleted: loadValue()

        onOverdriveEnabledChanged: {
            if (!isInitialized) return
            root.saveValue("allowOverdrive", overdriveEnabled)
            if (!overdriveEnabled && currentValue > safeLimit) {
                currentValue = safeLimit
                root.saveValue("maxStreamVol", safeLimit)
            }
        }

        Item {
            width: parent.width
            height: overdriveLabel.implicitHeight

            StyledText {
                id: overdriveLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Allow Overdrive"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Medium
                color: Theme.surfaceText
            }

            DankToggle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: maxVolSection.overdriveEnabled
                onToggled: isChecked => maxVolSection.overdriveEnabled = isChecked
            }
        }

        StyledText {
            visible: maxVolSection.overdriveEnabled
            text: "WARNING: High volume levels can cause distortion and may damage hardware."
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.error
            width: parent.width
            wrapMode: Text.WordWrap
        }

        StyledText {
            text: "Volume Cap"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            color: Theme.surfaceText
        }

        StyledText {
            text: "Maximum allowed volume for application streams"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            width: parent.width
            wrapMode: Text.WordWrap
        }

        RowLayout {
            width: parent.width
            spacing: Theme.spacingS

            DankActionButton {
                Layout.alignment: Qt.AlignVCenter
                iconName: "replay"
                iconSize: 12
                buttonSize: 20
                enabled: maxVolSection.currentValue !== maxVolSection.safeLimit
                iconColor: enabled ? Theme.primary : Theme.surfaceVariantText
                tooltipText: "Reset to safe limit"
                onClicked: {
                    maxVolSection.currentValue = maxVolSection.safeLimit
                    root.saveValue("maxStreamVol", maxVolSection.safeLimit)
                }
            }

            DankSlider {
                id: maxVolSlider
                Layout.fillWidth: true
                minimum: 100
                maximum: maxVolSection.overdriveEnabled ? maxVolSection.highLimit : maxVolSection.safeLimit
                showValue: true
                unit: "%"
                wheelEnabled: false
                thumbOutlineColor: Theme.withAlpha(Theme.surfaceContainerHighest, Theme.popupTransparency)

                Binding on value {
                    value: maxVolSection.currentValue
                    when: !maxVolSlider.isDragging
                }

                onSliderValueChanged: newValue => {
                    maxVolSection.currentValue = newValue
                    root.saveValue("maxStreamVol", newValue)
                }
            }
        }
    }
}
