// Дерево проекта: одна папка; вложенные папки раскрываются тем же компонентом. FolderListModel сам следит за
// изменениями на диске — новые и удалённые файлы появляются без обновления.
import QtQuick
import Qt.labs.folderlistmodel
import D3R

Column {
    id: node
    required property var app
    required property string dir
    property int depth: 0
    width: parent ? parent.width : 200

    FolderListModel {
        id: fm
        folder: Sys.toUrl(node.dir)
        showDirsFirst: true; showDotAndDotDot: false
        showHidden: node.app.cfg.hidden
        sortCaseSensitive: false
    }

    Repeater {
        model: fm
        Column {
            id: row
            required property string fileName
            required property string filePath
            required property bool fileIsDir
            width: node.width
            readonly property bool open: { void (node.app.treeRev); return node.app.expanded[filePath] === true; }
            readonly property bool current: node.app.curPath === filePath
            readonly property bool junk: /^(build|cmake-build-.*|__pycache__|\.git|\.cache|\.venv|venv|node_modules)$/.test(fileName)

            Rectangle {
                width: parent.width; height: 24; radius: 5
                color: row.current ? Qt.alpha(node.app.pal.sel, 0.4) : rm.containsMouse ? Qt.alpha(node.app.pal.head, 0.9) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
                Text {   // стрелка папки поворачивается при раскрытии
                    x: 6 + node.depth * 14; anchors.verticalCenter: parent.verticalCenter
                    visible: row.fileIsDir
                    font.family: node.app.mono; font.pixelSize: 10; color: node.app.pal.dim
                    text: "▶"; rotation: row.open ? 90 : 0
                    Behavior on rotation { NumberAnimation { duration: node.app.cfg.anim ? 150 : 0; easing.type: Easing.OutCubic } }
                }
                Text {
                    id: ico
                    x: 20 + node.depth * 14; anchors.verticalCenter: parent.verticalCenter
                    font.family: node.app.mono; font.pixelSize: 14
                    color: row.fileIsDir ? node.app.pal.acc : node.app.iconColor(row.fileName)
                    opacity: row.junk ? 0.45 : 1
                    text: row.fileIsDir ? (row.open ? "󰝰" : "󰉋") : node.app.iconFor(row.fileName)
                }
                Text {
                    anchors.left: ico.right; anchors.leftMargin: 7; anchors.right: parent.right; anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                    font.family: node.app.mono; font.pixelSize: 13
                    color: row.current ? node.app.pal.light : row.junk ? node.app.pal.faint : node.app.pal.text
                    text: row.fileName
                }
                MouseArea {
                    id: rm
                    anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: m => {
                        if (m.button === Qt.RightButton) { node.app.treeMenu(row.filePath, row.fileIsDir, mapToItem(null, m.x, m.y)); return; }
                        if (row.fileIsDir) node.app.toggleDir(row.filePath); else node.app.openFile(row.filePath);
                    }
                }
            }
            Loader {   // вложенная папка — тот же компонент, создаётся только когда раскрыта
                width: parent.width
                active: row.fileIsDir && row.open
                visible: active
                Component.onCompleted: setSource("TreeNode.qml", { app: node.app, dir: row.filePath, depth: node.depth + 1 })
            }
        }
    }
}
