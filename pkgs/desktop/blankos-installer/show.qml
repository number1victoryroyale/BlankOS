/* BlankOS installer slideshow: what you get once it's done */
import QtQuick
import calamares.slideshow 1.0

Presentation {
    id: presentation

    function onActivate() { }
    function onLeave() { }

    Timer {
        interval: 9000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    component BlankSlide: Slide {
        property string heading
        property string body
        Rectangle { anchors.fill: parent; color: "#0B0B10" }
        Column {
            anchors.centerIn: parent
            width: parent.width * 0.8
            spacing: 18
            Text {
                width: parent.width
                text: heading
                color: "#A78BFA"
                font.pixelSize: 30
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
            Text {
                width: parent.width
                text: body
                color: "#E8E6F0"
                font.pixelSize: 17
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }

    BlankSlide {
        heading: "Welcome to BlankOS"
        body: "A gaming-first Linux system, built from scratch, with KDE Plasma in BlankOS violet."
    }
    BlankSlide {
        heading: "Your games, one click away"
        body: "The Game Hub installs Steam, Roblox (Sober), Heroic, Lutris and ProtonUp-Qt from Flathub."
    }
    BlankSlide {
        heading: "Windows games and apps"
        body: "Wine with DXVK and VKD3D-Proton runs Windows programs; Steam's Proton does it for you."
    }
    BlankSlide {
        heading: "Play at full speed"
        body: "Add \"gamemoderun mangohud %command%\" to a Steam game for the performance mode and the FPS overlay."
    }
    BlankSlide {
        heading: "Updates"
        body: "Discover (or `pacman -Syu` in Konsole) keeps BlankOS and your Flatpak apps up to date."
    }
}
