#include "sys.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>

#ifdef Q_OS_WIN
#include <windows.h>
#include <psapi.h>
#endif

void hideConsole(QProcess *p)
{
#ifdef Q_OS_WIN
    p->setCreateProcessArgumentsModifier([](QProcess::CreateProcessArguments *a) { a->flags |= CREATE_NO_WINDOW; });
#else
    Q_UNUSED(p)
#endif
}

// папки, которые в проекте не ищем и не показываем в Ctrl+P
static bool junkDir(const QString &n)
{
    static const QRegularExpression re("^(\\.git|\\.vs|\\.vscode|build|cmake-build-.*|out|__pycache__|\\.venv|venv|\\.cache|node_modules)$");
    return re.match(n).hasMatch();
}

static void prepare(QProcess *p, const QString &cwd)
{
    if (!cwd.isEmpty()) p->setWorkingDirectory(cwd);
    p->setProcessChannelMode(QProcess::MergedChannels);
    auto env = QProcessEnvironment::systemEnvironment();
    env.insert("PYTHONIOENCODING", "utf-8");   // print() с русским текстом не падает и приходит в UTF-8
    env.insert("PYTHONUTF8", "1");
    env.insert("PYTHONUNBUFFERED", "1");       // вывод сразу, а не в конце программы
    p->setProcessEnvironment(env);
    hideConsole(p);
}

Sys::Sys(QObject *parent) : QObject(parent)
{
    QDir().mkpath(configDir());
    QDir().mkpath(tempDir());
    refreshPath();
}

QString Sys::home() const { return QDir::homePath(); }
QString Sys::configDir() const { return QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation); }
QString Sys::tempDir() const { return QDir::tempPath() + "/d3r-code"; }
bool Sys::windows() const
{
#ifdef Q_OS_WIN
    return true;
#else
    return false;
#endif
}

QString Sys::toLocal(const QVariant &url) const
{
    const QUrl u = url.toUrl();
    return u.isLocalFile() ? u.toLocalFile() : QDir::fromNativeSeparators(url.toString());
}
QString Sys::toUrl(const QString &path) const { return QUrl::fromLocalFile(path).toString(); }
QString Sys::absolute(const QString &path, const QString &base) const
{
    const QString p = QDir::fromNativeSeparators(path);
    return QDir::cleanPath(QDir::isAbsolutePath(p) ? p : (base.isEmpty() ? QDir::currentPath() : base) + "/" + p);
}

// ── файлы ──
QString Sys::read(const QString &path) const
{
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) return {};
    QByteArray b = f.readAll();
    if (b.startsWith("\xEF\xBB\xBF")) b.remove(0, 3);
    auto dec = QStringDecoder(QStringDecoder::Utf8);
    QString s = dec.decode(b);
    if (dec.hasError()) s = QString::fromLocal8Bit(b);   // старые файлы из Блокнота/Dev-C++ в cp1251
    s.replace("\r\n", "\n");
    s.replace('\r', '\n');
    return s;
}
bool Sys::crlf(const QString &path) const
{
    QFile f(path);
    return f.open(QIODevice::ReadOnly) && f.read(1 << 16).contains("\r\n");
}
bool Sys::write(const QString &path, const QString &text, bool crlf) const
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile f(path);   // пишет во временный файл и подменяет: при сбое старый файл цел
    if (!f.open(QIODevice::WriteOnly)) return false;
    QString t = text;
    if (crlf) t.replace("\n", "\r\n");
    const QByteArray b = t.toUtf8();
    return f.write(b) == b.size() && f.commit();
}
bool Sys::exists(const QString &path) const { return QFileInfo::exists(path); }
bool Sys::isDir(const QString &path) const { return QFileInfo(path).isDir(); }
bool Sys::mkdir(const QString &path) const { return QDir().mkpath(path); }
bool Sys::rename(const QString &from, const QString &to) const
{
    if (QFileInfo::exists(to)) return false;
    return QDir().rename(from, to);
}
bool Sys::trash(const QString &path) const { return QFile::moveToTrash(path); }

QStringList Sys::listFiles(const QString &root, int max) const
{
    QStringList out;
    QStringList stack{root};
    const QDir base(root);
    while (!stack.isEmpty() && out.size() < max) {
        const QString d = stack.takeLast();
        const auto list = QDir(d).entryInfoList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot | QDir::Hidden, QDir::Name);
        for (const QFileInfo &fi : list) {
            if (fi.isDir()) { if (!junkDir(fi.fileName()) && !fi.isSymLink()) stack << fi.filePath(); }
            else if (out.size() < max) out << base.relativeFilePath(fi.filePath());
        }
    }
    out.sort(Qt::CaseInsensitive);
    return out;
}

QVariantList Sys::grep(const QString &root, const QString &query, int max) const
{
    QVariantList hits;
    if (query.isEmpty()) return hits;
    for (const QString &rel : listFiles(root, 6000)) {
        QFile f(root + "/" + rel);
        if (f.size() > 2 * 1024 * 1024 || !f.open(QIODevice::ReadOnly)) continue;
        const QByteArray b = f.readAll();
        if (b.left(8192).contains('\0')) continue;   // двоичный файл
        const QStringList lines = QString::fromUtf8(b).split('\n');
        int inFile = 0;
        for (int i = 0; i < lines.size() && inFile < 50; i++) {
            if (!lines[i].contains(query, Qt::CaseInsensitive)) continue;
            hits << QVariantMap{{"file", rel}, {"line", i + 1}, {"text", lines[i].trimmed().left(200)}};
            inFile++;
            if (hits.size() >= max) return hits;
        }
    }
    return hits;
}

// ── программы ──
void Sys::refreshPath()
{
#ifdef Q_OS_WIN
    // PATH из реестра (машина + пользователь): поставили MinGW/Python через winget — видно без перезапуска редактора
    auto expand = [](QString s) {
        static const QRegularExpression var("%([^%]+)%");
        for (auto m = var.match(s); m.hasMatch(); m = var.match(s)) {
            const QString v = qEnvironmentVariable(m.captured(1).toUtf8());
            s.replace(m.captured(0), v.isEmpty() ? QString("\x01") : v);   // неизвестная переменная — не зациклиться
        }
        return s.remove('\x01');
    };
    QSettings machine("HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment", QSettings::NativeFormat);
    QSettings user("HKEY_CURRENT_USER\\Environment", QSettings::NativeFormat);
    QStringList dirs;
    for (const QString &part : (expand(machine.value("Path").toString()) + ";" + expand(user.value("Path").toString())
                                + ";" + qEnvironmentVariable("PATH")).split(';', Qt::SkipEmptyParts))
        if (!dirs.contains(part, Qt::CaseInsensitive)) dirs << part;
    // где обычно лежат компиляторы, даже если их забыли добавить в PATH
    const QString local = qEnvironmentVariable("LOCALAPPDATA");
    for (const QString &d : {QString("C:/msys64/ucrt64/bin"), QString("C:/msys64/mingw64/bin"), QString("C:/mingw64/bin"),
                             QString("C:/Program Files/LLVM/bin"), QString("C:/Program Files/CMake/bin"), local + "/Microsoft/WinGet/Links"})
        if (QFileInfo(d).isDir() && !dirs.contains(QDir::toNativeSeparators(d), Qt::CaseInsensitive)) dirs << QDir::toNativeSeparators(d);
    qputenv("PATH", dirs.join(';').toLocal8Bit());
#endif
}

QString Sys::findExe(const QString &name) const
{
    return QDir::fromNativeSeparators(QStandardPaths::findExecutable(name));
}

QString Sys::python() const
{
#ifdef Q_OS_WIN
    if (const QString py = findExe("py"); !py.isEmpty()) return py;   // лаунчер python.org
    const QString p = findExe("python");
    return p.contains("WindowsApps", Qt::CaseInsensitive) ? QString() : p;   // заглушка, открывающая Microsoft Store
#else
    return findExe("python3");
#endif
}

QString Sys::decode(Proc &pr, const QByteArray &b)
{
    QString s = pr.dec.decode(b);
    if (pr.dec.hasError()) {   // не UTF-8 — значит, кодовая страница Windows (например, вывод старой программы)
        pr.dec = QStringDecoder(QStringDecoder::Utf8);
        s = QString::fromLocal8Bit(b);
    }
    s.remove('\r');
    return s;
}

int Sys::launch(QProcess *p, const QString &input, bool keepStdin)
{
    p->start();
    if (!p->waitForStarted(10000)) { delete p; return 0; }
    const int id = ++m_next;
    auto *pr = new Proc;
    pr->p = p;
    pr->t.start();
    m_procs.insert(id, pr);
#ifdef Q_OS_WIN
    pr->handle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, DWORD(p->processId()));
#endif
    connect(p, &QProcess::readyReadStandardOutput, this, [this, id, pr] { emit output(id, decode(*pr, pr->p->readAllStandardOutput())); });
    connect(p, &QProcess::finished, this, [this, id, pr](int code, QProcess::ExitStatus st) {
        const QByteArray rest = pr->p->readAllStandardOutput();
        if (!rest.isEmpty()) emit output(id, decode(*pr, rest));
        double peak = -1;
#ifdef Q_OS_WIN
        if (pr->handle) {
            PROCESS_MEMORY_COUNTERS pmc{};
            if (GetProcessMemoryInfo(pr->handle, &pmc, sizeof pmc)) peak = double(pmc.PeakWorkingSetSize) / (1024 * 1024);
            CloseHandle(pr->handle);
        }
#endif
        const double ms = double(pr->t.nsecsElapsed()) / 1e6;
        m_procs.remove(id);
        pr->p->deleteLater();
        delete pr;
        emit finished(id, code, ms, peak, st == QProcess::CrashExit);
    });
    if (!input.isEmpty()) p->write(input.toUtf8());
    if (!keepStdin) p->closeWriteChannel();
    return id;
}

int Sys::start(const QString &program, const QStringList &args, const QString &cwd, const QString &input, bool keepStdin)
{
    auto *p = new QProcess(this);
    prepare(p, cwd);
    p->setProgram(program);
    p->setArguments(args);
    return launch(p, input, keepStdin);
}

int Sys::startShell(const QString &command, const QString &cwd)
{
    auto *p = new QProcess(this);
    prepare(p, cwd);
#ifdef Q_OS_WIN
    // chcp 65001: dir, echo и прочие команды cmd пишут в UTF-8, а не в cp866
    p->setProgram(qEnvironmentVariable("ComSpec", "cmd.exe"));
    p->setNativeArguments("/d /s /c \"chcp 65001>nul & " + command + "\"");
#else
    p->setProgram("/bin/sh");
    p->setArguments({"-c", command});
#endif
    return launch(p, {}, true);
}

void Sys::send(int id, const QString &text)
{
    if (auto *pr = m_procs.value(id)) pr->p->write(text.toUtf8());
}

void Sys::kill(int id)
{
    auto *pr = m_procs.value(id);
    if (!pr) return;
#ifdef Q_OS_WIN
    QProcess k;   // всё дерево: cmd /c программа — убить и программу, а не только cmd
    k.setProgram("taskkill");
    k.setArguments({"/F", "/T", "/PID", QString::number(pr->p->processId())});
    hideConsole(&k);
    k.start();
    k.waitForFinished(3000);
#endif
    pr->p->kill();
}

void Sys::run(const QString &program, const QStringList &args, const QString &cwd, const QJSValue &cb, const QString &input)
{
    auto *p = new QProcess(this);
    prepare(p, cwd);
    p->setProgram(program);
    p->setArguments(args);
    auto done = std::make_shared<bool>(false);
    auto finish = [p, cb, done](int code, const QString &out) mutable {
        if (*done) return;
        *done = true;
        if (cb.isCallable()) cb.call({QJSValue(code), QJSValue(out)});
        p->deleteLater();
    };
    connect(p, &QProcess::finished, this, [p, finish](int code) mutable {
        QByteArray b = p->readAll();
        auto dec = QStringDecoder(QStringDecoder::Utf8);
        QString s = dec.decode(b);
        if (dec.hasError()) s = QString::fromLocal8Bit(b);
        finish(code, s.remove('\r'));
    });
    connect(p, &QProcess::errorOccurred, this, [p, finish](QProcess::ProcessError e) mutable {
        if (e == QProcess::FailedToStart) finish(-1, "не удалось запустить " + p->program());
    });
    p->start();
    if (!input.isEmpty()) p->write(input.toUtf8());
    p->closeWriteChannel();
}
