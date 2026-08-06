/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Minimal Unemployed OS installer slideshow. Calamares' branding.desc
 * requires a `slideshow:` QML with this Presentation/Slide/Timer shape
 * whenever slideshowAPI is set -- confirmed the hard way, via an actual
 * install-to-disk run: leaving slideshowAPI declared with no matching
 * slideshow file is FATAL at Calamares startup ("key not found:
 * slideshow"). Upstream's own example (and CachyOS's, which we borrow
 * calamares from) references image assets we don't have yet (Part II's
 * in-house theme/slideshow is still unstarted -- see README known gaps),
 * so this is a plain color-block placeholder using our own brand colors
 * instead of a missing image, adapted from the same upstream Calamares
 * default show.qml structure (GPL-3.0-or-later, Teo Mrnjavac / Adriaan
 * de Groot).
 */
import QtQuick 2.15;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    function nextSlide() {
        presentation.goToNextSlide();
    }

    Timer {
        id: advanceTimer
        interval: 30000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: nextSlide()
    }

    Slide {
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: "#1E1E2E"

            Text {
                anchors.centerIn: parent
                text: "Unemployed OS"
                color: "#8AADF4"
                font.pixelSize: 32
                font.bold: true
            }
        }
    }

    function onActivate() {
        console.log("QML Component (Unemployed OS slideshow) activated");
        presentation.currentSlide = 0;
    }

    function onLeave() {
        console.log("QML Component (Unemployed OS slideshow) deactivated");
    }
}
