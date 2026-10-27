#include "flatpak.h"

#include <QStandardPaths>
#include <QTextStream>
#include <QVariantMap>

namespace {

struct App {
    const char *id;
    const char *name;
    const char *summary;
    const char *note;
};

// What the hub offers. All of them come from Flathub.
const App catalog[] = {
    {"com.valvesoftware.Steam", "Steam",
     "Valve's store and game library. Windows games run through Proton.",
     "Turn on Steam Play (Settings, Compatibility) to play Windows games."},
    {"org.vinegarhq.Sober", "Sober (Roblox)",
     "Plays Roblox on Linux by running its Android version.",
     "Unofficial: it can stop working for a while after a Roblox update."},
    {"com.heroicgameslauncher.hgl", "Heroic Games Launcher",
     "Your Epic Games, GOG and Amazon Prime Gaming libraries.", ""},
    {"net.lutris.Lutris", "Lutris",
     "Installs and runs games from Battle.net, EA, Ubisoft, emulators and more.", ""},
    {"net.davidotek.pupgui2", "ProtonUp-Qt",
     "Adds extra Proton and Wine versions (like Proton-GE) to Steam, Heroic and Lutris.", ""},
};

QString flatpakBinary()
{
    return QStandardPaths::findExecutable(QStringLiteral("flatpak"));
}

QString run(const QStringList &args, bool *ok = nullptr)
{
    QProcess p;
    p.start(flatpakBinary(), args);
    const bool done = p.waitForFinished(30000);
    if (ok) {
        *ok = done && p.exitStatus() == QProcess::NormalExit && p.exitCode() == 0;
    }
    return QString::fromUtf8(p.readAllStandardOutput());
}

} // namespace

Flatpak::Flatpak(QObject *parent)
    : QObject(parent)
{
    refresh();
}

bool Flatpak::available() const
{
    return !flatpakBinary().isEmpty();
}

QVariantList Flatpak::apps() const
{
    QVariantList list;
    for (const App &a : catalog) {
        list.append(QVariantMap{
            {QStringLiteral("id"), QString::fromLatin1(a.id)},
            {QStringLiteral("name"), QString::fromUtf8(a.name)},
            {QStringLiteral("summary"), QString::fromUtf8(a.summary)},
            {QStringLiteral("note"), QString::fromUtf8(a.note)},
            {QStringLiteral("installed"), m_installed.contains(QString::fromLatin1(a.id))},
        });
    }
    return list;
}

void Flatpak::refresh()
{
    m_installed.clear();
    if (available()) {
        const QString out = run({QStringLiteral("list"), QStringLiteral("--app"), QStringLiteral("--columns=application")});
        for (const QString &line : out.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
            m_installed.insert(line.trimmed());
        }
    }
    Q_EMIT appsChanged();
}

void Flatpak::appendLog(const QString &text)
{
    m_log += text;
    // keep the visible log short
    if (m_log.size() > 20000) {
        m_log = m_log.right(20000);
    }
    Q_EMIT logChanged();
}

void Flatpak::install(const QString &id)
{
    if (m_process || !available()) {
        return;
    }
    m_busyApp = id;
    m_process = new QProcess(this);
    m_process->setProcessChannelMode(QProcess::MergedChannels);
    connect(m_process, &QProcess::readyRead, this, [this] {
        appendLog(QString::fromUtf8(m_process->readAll()));
    });
    connect(m_process, &QProcess::finished, this, [this, id](int code, QProcess::ExitStatus status) {
        const bool ok = status == QProcess::NormalExit && code == 0;
        appendLog(ok ? tr("\n%1 is installed.\n").arg(id) : tr("\nInstalling %1 failed.\n").arg(id));
        m_process->deleteLater();
        m_process = nullptr;
        m_busyApp.clear();
        Q_EMIT busyChanged();
        refresh();
        Q_EMIT finished(id, ok);
    });
    appendLog(tr("Installing %1 from Flathub...\n").arg(id));
    // system-wide, like Discover; polkit asks for the admin password
    m_process->start(flatpakBinary(), {QStringLiteral("install"), QStringLiteral("--system"), QStringLiteral("--noninteractive"),
                                       QStringLiteral("-y"), QStringLiteral("flathub"), id});
    Q_EMIT busyChanged();
}

void Flatpak::launch(const QString &id)
{
    QProcess::startDetached(flatpakBinary(), {QStringLiteral("run"), id});
}

int Flatpak::selfTest()
{
    QTextStream out(stdout);
    int failures = 0;
    for (const App &a : catalog) {
        out << "app " << a.id << " (" << a.name << ")\n";
    }
    if (flatpakBinary().isEmpty()) {
        out << "FAIL flatpak not found\n";
        return 1;
    }
    bool ok = false;
    const QString remotes = run({QStringLiteral("remotes"), QStringLiteral("--columns=name")}, &ok);
    if (!ok || !remotes.split(QLatin1Char('\n')).contains(QStringLiteral("flathub"))) {
        out << "FAIL the flathub remote is not configured\n";
        failures++;
    } else {
        out << "ok flathub remote\n";
    }
    return failures;
}
