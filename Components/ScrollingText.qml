import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

Item {
    id: root
    property alias text: label.text
    property alias font: label.font
    property alias color: label.color
    property int pauseDuration: 2000
    property int scrollSpeed: 35 // ms per pixel

    Layout.fillWidth: true
    Layout.preferredHeight: label.implicitHeight
    clip: true

    readonly property bool overflows: label.implicitWidth > root.width
    readonly property int scrollPx: overflows ? Math.ceil(label.implicitWidth - root.width) : 0

    StyledText {
        id: label
        width: undefined
        elide: Text.ElideNone
    }

    SequentialAnimation {
        running: root.overflows
        loops: Animation.Infinite
        PauseAnimation { duration: root.pauseDuration }
        NumberAnimation {
            target: label
            property: "x"
            from: 0
            to: -root.scrollPx
            duration: Math.max(1000, root.scrollPx * root.scrollSpeed)
            easing.type: Easing.InOutSine
        }
        PauseAnimation { duration: root.pauseDuration }
        PropertyAction { target: label; property: "x"; value: 0 }
    }
}
