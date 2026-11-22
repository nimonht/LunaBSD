// The end: restart into the new system, or what went wrong and what to do.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

LPage {
    title: app.installOk ? "Installed" : "Not finished"
    subtitle: app.installOk ? app.distroName + " is installed. Remove the USB stick, then restart the computer."
                            : (app.installMode === "erase" ? "The installer stopped after the disk may already have been erased, as you chose. "
                                                              : "Nothing is lost: the installer removed what it had started on the disk. ")
                              + "The details below say why it stopped; check the internet connection and try again."
    code: app.installOk ? "COMPLETE" : "STOPPED"
    scroll: false
    ready: false

    readonly property string mok: app.installOk ? installer.mokCode(app.resultText) : ""

    ColumnLayout {
        anchors.fill: parent
        spacing: 24

        // Secure Boot: the one thing to do at the first start, step by step
        Panel {
            visible: mok !== ""
            Layout.fillWidth: true
            title: "At the first start: confirm the key"
            tag: "SECURE BOOT"
            RowLayout {
                width: parent.width
                spacing: 28
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        color: app.cInk
                        lineHeight: 1.2
                        text: "Once, a blue screen says \u201cPress any key to perform MOK management\u201d. "
                              + "Secure Boot then stays on."
                    }
                    Repeater {
                        model: ["Press any key", "Choose Enroll MOK, then Continue, then Yes",
                                "Type the code and press Enter", "Choose Reboot"]
                        delegate: RowLayout {
                            spacing: 12
                            Label {
                                text: "0" + (index + 1)
                                color: app.cSoft
                                font.family: app.fMono
                                font.pixelSize: 12
                            }
                            Label {
                                text: modelData
                                color: app.cInk
                            }
                        }
                    }
                }
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: codeText.implicitWidth + 44
                    implicitHeight: codeText.implicitHeight + 28
                    color: app.cInk
                    Label {
                        id: codeText
                        anchors.centerIn: parent
                        text: mok.substr(0, 4) + " " + mok.substr(4)
                        color: app.cPaper
                        font.family: app.fMono
                        font.pixelSize: 30
                        font.letterSpacing: 4
                    }
                    Label {
                        anchors.top: parent.bottom
                        anchors.topMargin: 6
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "TYPE WITHOUT THE SPACE"
                        color: app.cSoft
                        font.pixelSize: 10
                        font.letterSpacing: 1.6
                    }
                }
            }
        }

        Panel {
            Layout.fillWidth: true
            Layout.fillHeight: true
            title: app.installOk ? "Where it starts from" : "What happened"
            accent: app.installOk ? app.cInk : app.cSignal
            ScrollView {
                anchors.fill: parent
                clip: true
                ScrollBar.vertical: LScrollBar {}
                TextArea {
                    readOnly: true
                    wrapMode: TextEdit.Wrap
                    color: app.cInk
                    font.family: app.installOk ? app.fSans : app.fMono
                    font.pixelSize: app.installOk ? 15 : 13
                    selectionColor: app.cInk
                    selectedTextColor: app.cPaper
                    background: null
                    text: app.installOk ? (installer.withoutMok(app.resultText) || "Nothing else to do: restart, and log in with your account.")
                                        : app.resultText + "\n\nFull log: " + installer.logPath()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 18
            Item { Layout.fillWidth: true }
            LButton {
                visible: !app.installOk
                text: "Back to summary"
                onClicked: app.page = app.summaryPage
            }
            LButton {
                visible: installer.mode === "welcome" || installer.mode === "install"
                text: "Keep trying " + app.distroName
                onClicked: Qt.quit()
            }
            LButton {
                kind: "primary"
                text: app.installOk ? "Restart now" : "Power off"
                onClicked: app.installOk ? installer.reboot() : installer.poweroff()
            }
        }
    }
}
