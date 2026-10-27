import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.ApplicationWindow {
    id: root
    title: "BlankOS Game Hub"
    width: Kirigami.Units.gridUnit * 44
    height: Kirigami.Units.gridUnit * 34

    // BlankOS violet
    readonly property color accent: "#8B5CF6"

    pageStack.initialPage: Kirigami.ScrollablePage {
        title: "Get your games"

        actions: [
            Kirigami.Action {
                text: "Refresh"
                icon.name: "view-refresh"
                enabled: !flatpak.busy
                onTriggered: flatpak.refresh()
            }
        ]

        ColumnLayout {
            spacing: Kirigami.Units.largeSpacing

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: !flatpak.available
                type: Kirigami.MessageType.Error
                text: "Flatpak is not installed, so nothing can be installed from here."
            }

            Controls.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: "Pick what you play. Everything installs from Flathub with one click and updates through Discover."
            }

            Repeater {
                model: flatpak.apps

                delegate: Kirigami.AbstractCard {
                    required property var modelData
                    Layout.fillWidth: true

                    contentItem: RowLayout {
                        spacing: Kirigami.Units.largeSpacing

                        Kirigami.Icon {
                            source: modelData.id
                            fallback: "applications-games"
                            Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                            Layout.preferredHeight: Kirigami.Units.iconSizes.huge
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Kirigami.Heading {
                                level: 3
                                text: modelData.name
                            }
                            Controls.Label {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                text: modelData.summary
                            }
                            Controls.Label {
                                Layout.fillWidth: true
                                visible: modelData.note !== ""
                                wrapMode: Text.WordWrap
                                opacity: 0.7
                                font: Kirigami.Theme.smallFont
                                text: modelData.note
                            }
                        }

                        Controls.BusyIndicator {
                            visible: flatpak.busyApp === modelData.id
                            running: visible
                        }

                        Controls.Button {
                            visible: !modelData.installed
                            enabled: !flatpak.busy && flatpak.available
                            text: "Install"
                            icon.name: "download"
                            palette.button: root.accent
                            onClicked: flatpak.install(modelData.id)
                        }

                        Controls.Button {
                            visible: modelData.installed
                            text: "Play"
                            icon.name: "media-playback-start"
                            onClicked: flatpak.launch(modelData.id)
                        }
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
                visible: flatpak.log !== ""
            }

            Controls.TextArea {
                Layout.fillWidth: true
                Layout.preferredHeight: Kirigami.Units.gridUnit * 8
                visible: flatpak.log !== ""
                readOnly: true
                wrapMode: Text.WrapAnywhere
                font.family: "monospace"
                text: flatpak.log
            }

            Controls.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: "Tips: add \"gamemoderun %command%\" or \"mangohud %command%\" to a Steam game's launch options for the performance mode and the FPS overlay. Windows programs outside Steam run with Wine."
            }
        }
    }
}
