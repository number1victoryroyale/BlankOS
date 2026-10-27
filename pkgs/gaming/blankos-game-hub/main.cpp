// BlankOS Game Hub: one-click installs of Steam, Sober (Roblox), Heroic,
// Lutris and ProtonUp-Qt from Flathub.
//
//   blankos-game-hub               open the hub
//   blankos-game-hub --first-run   open it only on the first login (autostart)
//   blankos-game-hub --self-test   check the setup and the UI, then exit (CI)

#include "flatpak.h"

#include <QCommandLineParser>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QSettings>
#include <QTextStream>
#include <QTimer>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setOrganizationName(QStringLiteral("BlankOS"));
    app.setApplicationName(QStringLiteral("blankos-game-hub"));
    app.setApplicationDisplayName(QStringLiteral("BlankOS Game Hub"));
    app.setDesktopFileName(QStringLiteral("org.blankos.GameHub"));

    QCommandLineParser parser;
    parser.addHelpOption();
    QCommandLineOption firstRun(QStringLiteral("first-run"), QStringLiteral("Only open on the first login."));
    QCommandLineOption selfTest(QStringLiteral("self-test"), QStringLiteral("Check the setup and exit."));
    parser.addOptions({firstRun, selfTest});
    parser.process(app);

    QSettings settings;
    if (parser.isSet(firstRun)) {
        if (settings.value(QStringLiteral("firstRunDone")).toBool()) {
            return 0;
        }
        settings.setValue(QStringLiteral("firstRunDone"), true);
    }

    int failures = parser.isSet(selfTest) ? Flatpak::selfTest() : 0;

    Flatpak flatpak;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("flatpak"), &flatpak);
    engine.loadFromModule("BlankOS.GameHub", "Main");
    if (engine.rootObjects().isEmpty()) {
        QTextStream(stderr) << "FAIL the user interface did not load\n";
        return 1;
    }
    if (parser.isSet(selfTest)) {
        QTextStream(stdout) << "ok user interface\n" << (failures ? "SELF-TEST FAILED\n" : "SELF-TEST OK\n");
        QTimer::singleShot(0, &app, [&app, failures] { app.exit(failures ? 1 : 0); });
    }
    return app.exec();
}
