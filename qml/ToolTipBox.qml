// Всплывающая подсказка в стиле D3R (сообщение компилятора над меткой ошибки и т. п.)
import QtQuick

Rectangle {
    id: tip
    required property var app
    property bool show: false
    property string msg: ""
    z: 100
    visible: opacity > 0
    opacity: show ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 120 } }
    width: Math.min(520, t.implicitWidth + 20); height: t.implicitHeight + 12; radius: 6
    color: Qt.alpha(app.pal.head, 0.97)
    border.width: 1; border.color: Qt.alpha(app.pal.acc, 0.5)
    Text {
        id: t
        x: 10; y: 6; width: Math.min(500, implicitWidth)
        wrapMode: Text.Wrap
        font.family: tip.app.cfg.font; font.pixelSize: 12; color: tip.app.pal.text
        text: tip.msg; textFormat: Text.PlainText
    }
}
