// Sys — всё, что QML сам не умеет: файлы (UTF-8/CRLF/BOM), корзина, поиск по проекту, процессы с замером
// времени и пиковой памяти, поиск компиляторов. В QML — синглтон D3R.Sys. Пути везде с прямыми слешами: C:/Users/...
#pragma once
#include <QElapsedTimer>
#include <QHash>
#include <QJSValue>
#include <QObject>
#include <QProcess>
#include <QStringDecoder>
#include <QVariant>

class QQmlEngine;

class Sys : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString home READ home CONSTANT)
    Q_PROPERTY(QString configDir READ configDir CONSTANT)
    Q_PROPERTY(QString tempDir READ tempDir CONSTANT)
    Q_PROPERTY(bool windows READ windows CONSTANT)
public:
    explicit Sys(QObject *parent = nullptr);
    void setEngine(QQmlEngine *e) { m_engine = e; }

    QString home() const;
    QString configDir() const;
    QString tempDir() const;
    bool windows() const;

    // ── пути ──
    Q_INVOKABLE QString toLocal(const QVariant &url) const;   // file:///C:/x → C:/x
    Q_INVOKABLE QString toUrl(const QString &path) const;     // C:/x → file:///C:/x
    Q_INVOKABLE QString absolute(const QString &path, const QString &base) const;

    // ── файлы ──
    Q_INVOKABLE QString read(const QString &path) const;                  // текст с \n; "" если нет файла
    Q_INVOKABLE bool crlf(const QString &path) const;                     // файл с концами строк Windows?
    Q_INVOKABLE bool write(const QString &path, const QString &text, bool crlf = false) const;   // атомарно
    Q_INVOKABLE bool exists(const QString &path) const;
    Q_INVOKABLE bool isDir(const QString &path) const;
    Q_INVOKABLE bool mkdir(const QString &path) const;
    Q_INVOKABLE bool rename(const QString &from, const QString &to) const;   // не затирает существующее
    Q_INVOKABLE bool trash(const QString &path) const;                     // в корзину
    Q_INVOKABLE QStringList listFiles(const QString &root, int max = 4000) const;            // относительные пути
    Q_INVOKABLE QVariantList grep(const QString &root, const QString &query, int max = 400) const;   // [{file, line, text}]

    // ── программы ──
    Q_INVOKABLE void refreshPath();                         // PATH заново из реестра: после установки g++ без перезапуска
    Q_INVOKABLE QString findExe(const QString &name) const; // полный путь или ""
    Q_INVOKABLE QString python() const;                     // "py" / путь к python.exe, без заглушки Microsoft Store

    // Процесс: вывод приходит сигналом output, конец — finished. input не пуст → подаётся на stdin и stdin закрывается;
    // keepStdin → stdin открыт для send(). Возвращает id (> 0) или 0, если программа не запустилась.
    Q_INVOKABLE int start(const QString &program, const QStringList &args, const QString &cwd,
                          const QString &input = {}, bool keepStdin = false);
    Q_INVOKABLE int startShell(const QString &command, const QString &cwd);   // cmd /c (Linux: sh -c)
    Q_INVOKABLE void send(int id, const QString &text);
    Q_INVOKABLE void kill(int id);                           // вместе с дочерними процессами
    Q_INVOKABLE bool running(int id) const { return m_procs.contains(id); }
    // команда целиком: cb(код, вывод stdout+stderr)
    Q_INVOKABLE void run(const QString &program, const QStringList &args, const QString &cwd, const QJSValue &cb,
                         const QString &input = {});

signals:
    void output(int id, const QString &text);
    void finished(int id, int code, double ms, double peakMB, bool crashed);

private:
    struct Proc {
        QProcess *p = nullptr;
        QElapsedTimer t;
        QStringDecoder dec{QStringDecoder::Utf8};
        void *handle = nullptr;   // Windows: свой HANDLE, чтобы после выхода спросить пиковую память
    };
    int launch(QProcess *p, const QString &input, bool keepStdin);
    QString decode(Proc &pr, const QByteArray &b);
    QHash<int, Proc *> m_procs;
    int m_next = 0;
    QQmlEngine *m_engine = nullptr;
};

void hideConsole(QProcess *p);   // Windows: дочерняя консольная программа без мелькающего чёрного окна
