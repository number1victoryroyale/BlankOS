// BlankOS Game Hub: the game launchers it offers and the Flatpak calls
// that install and start them.
#pragma once

#include <QObject>
#include <QProcess>
#include <QSet>
#include <QString>
#include <QVariantList>

class Flatpak : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList apps READ apps NOTIFY appsChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString busyApp READ busyApp NOTIFY busyChanged)
    Q_PROPERTY(QString log READ log NOTIFY logChanged)
    Q_PROPERTY(bool available READ available CONSTANT)

public:
    explicit Flatpak(QObject *parent = nullptr);

    QVariantList apps() const;
    bool busy() const { return m_process != nullptr; }
    QString busyApp() const { return m_busyApp; }
    QString log() const { return m_log; }
    bool available() const;

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void install(const QString &id);
    Q_INVOKABLE void launch(const QString &id);

    // --self-test: catalog sane, flatpak present, Flathub configured
    static int selfTest();

Q_SIGNALS:
    void appsChanged();
    void busyChanged();
    void logChanged();
    void finished(const QString &id, bool ok);

private:
    void appendLog(const QString &text);

    QSet<QString> m_installed;
    QProcess *m_process = nullptr;
    QString m_busyApp;
    QString m_log;
};
