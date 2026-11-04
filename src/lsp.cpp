#include "lsp.h"
#include "sys.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QProcess>
#include <QQmlEngine>
#include <QUrl>
#include <algorithm>

namespace {

QVariantList span(const QString &label, const QString &part)   // параметр строкой → [начало, конец] в подписи
{
    const int i = label.indexOf(part);
    return i >= 0 ? QVariantList{i, i + int(part.size())} : QVariantList{0, 0};
}

QString text(const QJsonValue &v)   // строка или {value}
{
    if (v.isObject()) return v.toObject().value("value").toString();
    if (v.isArray()) {
        QStringList parts;
        for (const auto &x : v.toArray()) parts << text(x);
        return parts.join("\n\n");
    }
    return v.toString();
}

// правки LSP (строка/столбец в UTF-16 — как и QString) → новый текст; с конца, чтобы позиции не съезжали
QString applyEdits(QString src, QJsonArray edits)
{
    QList<int> starts{0};
    for (int i = 0; i < src.size(); i++) if (src[i] == '\n') starts << i + 1;
    auto pos = [&](const QJsonObject &p) {
        const int line = std::min(p.value("line").toInt(), int(starts.size()) - 1);
        return std::min(int(src.size()), starts[line] + p.value("character").toInt());
    };
    QList<QJsonObject> list;
    for (const auto &e : edits) list << e.toObject();
    std::sort(list.begin(), list.end(), [&](const QJsonObject &a, const QJsonObject &b) {
        return pos(a["range"].toObject()["start"].toObject()) > pos(b["range"].toObject()["start"].toObject());
    });
    for (const auto &e : list) {
        const auto r = e["range"].toObject();
        const int s = pos(r["start"].toObject()), t = pos(r["end"].toObject());
        src.replace(s, t - s, e["newText"].toString());
    }
    return src;
}

QString run(const QString &program, const QStringList &args)   // короткая команда: вывод stdout+stderr
{
    QProcess p;
    p.setProcessChannelMode(QProcess::MergedChannels);
    hideConsole(&p);
    p.start(program, args);
    p.closeWriteChannel();
    p.waitForFinished(10000);
    return QString::fromLocal8Bit(p.readAll());
}

}   // namespace

Lsp::Lsp(Sys *sys, QObject *parent) : QObject(parent), m_sys(sys)
{
    m_clangd = m_sys->findExe("clangd");
    pyStart();
}

Lsp::~Lsp()
{
    for (QProcess *p : {m_cd, m_py}) if (p) { p->kill(); p->waitForFinished(2000); }
}

QStringList Lsp::langs() const
{
    QStringList l;
    if (!m_clangd.isEmpty()) l << "cpp";
    if (m_jedi) l << "python";
    return l;
}

void Lsp::setStd(const QString &s)
{
    if (s == m_std) return;
    m_std = s;
    if (m_cd) { m_cd->kill(); m_cd = nullptr; m_docs.clear(); }   // новый стандарт — новые флаги
    emit stdChanged();
}

void Lsp::restart()
{
    for (QProcess *p : {m_cd, m_py}) if (p) { p->disconnect(this); p->kill(); p->deleteLater(); }
    m_cd = m_py = nullptr;
    m_docs.clear();
    m_jedi = false;
    m_sys->refreshPath();
    m_clangd = m_sys->findExe("clangd");
    pyStart();
    emit langsChanged();
}

// ══════ clangd ══════
bool Lsp::clangd()
{
    if (m_cd && m_cd->state() != QProcess::NotRunning) return true;
    if (m_clangd.isEmpty()) return false;
    QStringList args{"--header-insertion=never", "--background-index", "--log=error", "--completion-style=detailed",
                     "--limit-results=80", "--completion-parse=always"};
    QJsonArray fallback{"-std=" + m_std, "-Wall", "-Wextra"};
    // MinGW: clangd должен знать заголовки g++ — иначе под Windows он ищет заголовки Visual Studio
    if (const QString gpp = m_sys->findExe("g++"); !gpp.isEmpty()) {
        args << "--query-driver=" + gpp;
        const QString machine = run(gpp, {"-dumpmachine"}).trimmed();
        if (machine.contains("mingw")) fallback << "--target=" + machine;
        QProcess p;
        p.setProcessChannelMode(QProcess::MergedChannels);
        hideConsole(&p);
        p.start(gpp, {"-E", "-x", "c++", "-", "-v"});
        p.closeWriteChannel();
        p.waitForFinished(10000);
        bool in = false;
        for (const QString &l : QString::fromLocal8Bit(p.readAll()).split('\n')) {
            if (l.startsWith("#include <...>")) { in = true; continue; }
            if (l.startsWith("End of search list")) break;
            if (in) fallback << "-isystem" << QDir::fromNativeSeparators(QDir::cleanPath(l.trimmed()));
        }
    }
    m_cd = new QProcess(this);
    hideConsole(m_cd);
    m_cd->setProcessChannelMode(QProcess::SeparateChannels);
    m_cd->setStandardErrorFile(QProcess::nullDevice());
    connect(m_cd, &QProcess::readyReadStandardOutput, this, &Lsp::cdRead);
    m_cd->start(m_clangd, args);
    if (!m_cd->waitForStarted(10000)) { m_cd->deleteLater(); m_cd = nullptr; return false; }
    m_cdBuf.clear();
    m_docs.clear();
    const QJsonObject caps{
        {"textDocument", QJsonObject{
            {"completion", QJsonObject{{"completionItem", QJsonObject{{"snippetSupport", false}, {"documentationFormat", QJsonArray{"plaintext"}}}}}},
            {"hover", QJsonObject{{"contentFormat", QJsonArray{"plaintext"}}}},
            {"signatureHelp", QJsonObject{{"signatureInformation", QJsonObject{{"parameterInformation", QJsonObject{{"labelOffsetSupport", true}}}}}}},
            {"documentSymbol", QJsonObject{{"hierarchicalDocumentSymbolSupport", true}}}}}};
    cdRequest("initialize", {{"processId", QCoreApplication::applicationPid()}, {"rootUri", QJsonValue::Null}, {"capabilities", caps},
                             {"initializationOptions", QJsonObject{{"fallbackFlags", fallback}}}}, [](QJsonValue) {});
    cdNotify("initialized", {});
    return true;
}

void Lsp::cdSend(const QJsonObject &msg)
{
    const QByteArray b = QJsonDocument(msg).toJson(QJsonDocument::Compact);
    m_cd->write("Content-Length: " + QByteArray::number(b.size()) + "\r\n\r\n" + b);
}
void Lsp::cdNotify(const QString &method, const QJsonObject &params)
{
    cdSend({{"jsonrpc", "2.0"}, {"method", method}, {"params", params}});
}
void Lsp::cdRequest(const QString &method, const QJsonObject &params, std::function<void(QJsonValue)> done)
{
    const int id = ++m_cdId;
    m_cdWait.insert(id, std::move(done));
    cdSend({{"jsonrpc", "2.0"}, {"id", id}, {"method", method}, {"params", params}});
}

void Lsp::cdRead()
{
    m_cdBuf += m_cd->readAllStandardOutput();
    for (;;) {
        const int h = m_cdBuf.indexOf("\r\n\r\n");
        if (h < 0) return;
        int len = -1;
        for (const QByteArray &l : m_cdBuf.left(h).split('\n'))
            if (l.toLower().startsWith("content-length:")) len = l.mid(15).trimmed().toInt();
        if (len < 0 || m_cdBuf.size() < h + 4 + len) return;
        const QJsonObject msg = QJsonDocument::fromJson(m_cdBuf.mid(h + 4, len)).object();
        m_cdBuf.remove(0, h + 4 + len);
        if (msg.contains("id") && !msg.contains("method")) {
            if (auto f = m_cdWait.take(msg["id"].toInt())) f(msg.value("result"));
        }
    }
}

QString Lsp::sync(const QString &path, const QString &txt)
{
    const QString uri = QUrl::fromLocalFile(path).toString();
    if (!m_docs.contains(uri)) {
        m_docs[uri] = 1;
        cdNotify("textDocument/didOpen", {{"textDocument", QJsonObject{{"uri", uri}, {"languageId", "cpp"}, {"version", 1}, {"text", txt}}}});
    } else {
        const int v = ++m_docs[uri];
        cdNotify("textDocument/didChange", {{"textDocument", QJsonObject{{"uri", uri}, {"version", v}}},
                                            {"contentChanges", QJsonArray{QJsonObject{{"text", txt}}}}});
    }
    return uri;
}

void Lsp::cdAt(const QString &method, const QVariantMap &b, std::function<void(QJsonValue)> done, QJsonObject extra)
{
    const QString uri = sync(b["path"].toString(), b["text"].toString());
    extra["textDocument"] = QJsonObject{{"uri", uri}};
    extra["position"] = QJsonObject{{"line", b["line"].toInt()}, {"character", b["col"].toInt()}};
    cdRequest(method, extra, std::move(done));
}

void Lsp::cppOp(const QString &op, const QVariantMap &b, std::function<void(QVariantMap)> done)
{
    if (op == "complete") {
        cdAt("textDocument/completion", b, [done](QJsonValue r) {
            QJsonArray items = r.isObject() ? r.toObject()["items"].toArray() : r.toArray();
            QList<QJsonObject> list;
            for (const auto &x : items) list << x.toObject();
            std::sort(list.begin(), list.end(), [](const QJsonObject &a, const QJsonObject &c) {
                return a.value("sortText").toString(a["label"].toString()) < c.value("sortText").toString(c["label"].toString());
            });
            QVariantList out;
            for (const auto &it : list) {
                const QJsonObject te = it["textEdit"].toObject();
                const QJsonObject range = te.contains("range") ? te["range"].toObject() : te["insert"].toObject();
                out << QVariantMap{{"label", it["label"].toString().trimmed()},
                                   {"insert", te.isEmpty() ? it.value("insertText").toString(it["label"].toString().trimmed()) : te["newText"].toString()},
                                   {"kind", it["kind"].toInt()}, {"detail", it["detail"].toString()},
                                   {"doc", text(it["documentation"]).left(400)},
                                   {"start", te.isEmpty() ? -1 : range["start"].toObject()["character"].toInt()}};
            }
            done({{"items", out}});
        });
    } else if (op == "signature") {
        cdAt("textDocument/signatureHelp", b, [done](QJsonValue r) {
            const auto sigs = r.toObject()["signatures"].toArray();
            if (sigs.isEmpty()) { done({}); return; }
            const auto o = r.toObject();
            const auto s = sigs[std::clamp(o["activeSignature"].toInt(), 0, int(sigs.size()) - 1)].toObject();
            const QString label = s["label"].toString();
            QVariantList params;
            for (const auto &p : s["parameters"].toArray()) {
                const auto l = p.toObject()["label"];
                params << QVariant(l.isArray() ? QVariantList{l.toArray()[0].toInt(), l.toArray()[1].toInt()} : span(label, l.toString()));
            }
            const int active = s.contains("activeParameter") ? s["activeParameter"].toInt() : o["activeParameter"].toInt();
            done({{"label", label}, {"params", params}, {"active", active}});
        });
    } else if (op == "hover") {
        cdAt("textDocument/hover", b, [done](QJsonValue r) { done({{"text", text(r.toObject()["contents"]).trimmed().left(1500)}}); });
    } else if (op == "definition") {
        cdAt("textDocument/definition", b, [done](QJsonValue r) {
            QJsonObject d = r.isArray() ? r.toArray().first().toObject() : r.toObject();
            if (d.isEmpty()) { done({}); return; }
            const QString uri = d.contains("targetUri") ? d["targetUri"].toString() : d["uri"].toString();
            const auto rng = (d.contains("targetSelectionRange") ? d["targetSelectionRange"] : d["range"]).toObject()["start"].toObject();
            done({{"path", QUrl(uri).toLocalFile()}, {"line", rng["line"].toInt() + 1}, {"col", rng["character"].toInt() + 1}});
        });
    } else if (op == "highlight") {
        cdAt("textDocument/documentHighlight", b, [done](QJsonValue r) {
            QVariantList items;
            for (const auto &h : r.toArray()) {
                const auto rg = h.toObject()["range"].toObject();
                const auto s = rg["start"].toObject(), e = rg["end"].toObject();
                if (s["line"] == e["line"]) items << QVariant(QVariantList{s["line"].toInt(), s["character"].toInt(), e["character"].toInt() - s["character"].toInt()});
            }
            done({{"items", items}});
        });
    } else if (op == "rename") {
        const QString path = b["path"].toString(), txt = b["text"].toString();
        cdAt("textDocument/rename", b, [this, done, path, txt](QJsonValue r) {
            QJsonObject changes = r.toObject()["changes"].toObject();
            for (const auto &d : r.toObject()["documentChanges"].toArray())
                changes[d.toObject()["textDocument"].toObject()["uri"].toString()] = d.toObject()["edits"];
            QVariantMap files;
            for (auto it = changes.begin(); it != changes.end(); ++it) {
                const QString p = QUrl(it.key()).toLocalFile();
                files[p] = applyEdits(QFileInfo(p) == QFileInfo(path) ? txt : m_sys->read(p), it.value().toArray());
            }
            done({{"files", files}});
        }, {{"newName", b["name"].toString()}});
    } else if (op == "symbols") {
        const QString uri = sync(b["path"].toString(), b["text"].toString());
        cdRequest("textDocument/documentSymbol", {{"textDocument", QJsonObject{{"uri", uri}}}}, [done](QJsonValue r) {
            QVariantList out;
            std::function<void(const QJsonArray &, int)> walk = [&](const QJsonArray &items, int depth) {
                for (const auto &x : items) {
                    const auto s = x.toObject();
                    const auto rng = (s.contains("selectionRange") ? s["selectionRange"] : s.contains("location") ? s["location"].toObject()["range"] : s["range"]).toObject();
                    out << QVariantMap{{"name", s["name"].toString()}, {"kind", s["kind"].toInt()},
                                       {"line", rng["start"].toObject()["line"].toInt() + 1}, {"depth", depth}};
                    walk(s["children"].toArray(), depth + 1);
                }
            };
            walk(r.toArray(), 0);
            done({{"items", out}});
        });
    } else done({});
}

// ══════ форматирование: clang-format (C++) ══════
void Lsp::format(const QVariantMap &b, std::function<void(QVariantMap)> done)
{
    if (b["lang"] == "python") {
        if (!m_py) { done({{"error", "нужен Python и black: py -m pip install black"}}); return; }
        const int id = ++m_pyId;
        m_pyWait.insert(id, std::move(done));
        m_py->write(QJsonDocument(QJsonObject{{"id", id}, {"op", "format"}, {"body", QJsonObject::fromVariantMap(b)}}).toJson(QJsonDocument::Compact) + "\n");
        return;
    }
    const QString cf = m_sys->findExe("clang-format");
    if (cf.isEmpty()) { done({{"error", "нет clang-format: поставь MinGW с LLVM (см. README)"}}); return; }
    const QString path = b["path"].toString();
    bool own = false;   // .clang-format рядом с файлом или выше
    for (QDir d = QFileInfo(path).dir(); !path.isEmpty(); ) {
        if (d.exists(".clang-format") || d.exists("_clang-format")) { own = true; break; }
        if (!d.cdUp()) break;
    }
    const QString style = own ? "file" : QString("{BasedOnStyle: LLVM, IndentWidth: %1, ColumnLimit: 110, AllowShortFunctionsOnASingleLine: Empty}")
                                              .arg(b.value("tab", 4).toInt());
    auto *p = new QProcess(this);
    hideConsole(p);
    if (!path.isEmpty()) p->setWorkingDirectory(QFileInfo(path).absolutePath());
    connect(p, &QProcess::finished, this, [p, done](int code) {
        const QString out = QString::fromUtf8(p->readAllStandardOutput());
        const QString err = QString::fromLocal8Bit(p->readAllStandardError()).trimmed();
        p->deleteLater();
        if (code) done({{"error", err.split('\n').last().left(200)}});
        else done({{"text", QString(out).remove('\r')}});
    });
    p->start(cf, {"--assume-filename=" + (path.isEmpty() ? QString("main.cpp") : path), "--style=" + style});
    p->write(b["text"].toString().toUtf8());
    p->closeWriteChannel();
}

// ══════ Python: pyhelper.py (jedi, black, проверка синтаксиса) ══════
void Lsp::pyStart()
{
    const QString py = m_sys->python();
    if (py.isEmpty()) return;
    const QString helper = m_sys->tempDir() + "/pyhelper.py";
    QFile res(":/pyhelper.py");
    if (!res.open(QIODevice::ReadOnly) || !m_sys->write(helper, QString::fromUtf8(res.readAll()))) return;
    m_py = new QProcess(this);
    hideConsole(m_py);
    auto env = QProcessEnvironment::systemEnvironment();
    env.insert("PYTHONIOENCODING", "utf-8");
    m_py->setProcessEnvironment(env);
    m_py->setStandardErrorFile(QProcess::nullDevice());
    connect(m_py, &QProcess::readyReadStandardOutput, this, &Lsp::pyRead);
    connect(m_py, &QProcess::finished, this, [this] {
        for (auto &f : m_pyWait) f({});
        m_pyWait.clear();
        if (m_jedi) { m_jedi = false; emit langsChanged(); }
        if (m_py) m_py->deleteLater();
        m_py = nullptr;
    });
    QStringList args{"-u", helper};
    if (QFileInfo(py).baseName() == "py") args.prepend("-3");   // лаунчер: самый свежий Python 3
    m_py->start(py, args);
}

void Lsp::pyRead()
{
    m_pyBuf += m_py->readAllStandardOutput();
    for (int nl; (nl = m_pyBuf.indexOf('\n')) >= 0; ) {
        const QJsonObject msg = QJsonDocument::fromJson(m_pyBuf.left(nl)).object();
        m_pyBuf.remove(0, nl + 1);
        if (msg.contains("ready")) { m_jedi = msg["jedi"].toBool(); emit langsChanged(); continue; }
        if (auto f = m_pyWait.take(msg["id"].toInt())) f(msg["res"].toObject().toVariantMap());
    }
}

// ══════ вход ══════
void Lsp::call(const QString &op, const QVariantMap &body, std::function<void(QVariantMap)> done)
{
    if (op == "format") { format(body, std::move(done)); return; }
    if (body["lang"] == "python") {
        if (!m_py || (!m_jedi && op != "check")) { done({}); return; }
        const int id = ++m_pyId;
        m_pyWait.insert(id, std::move(done));
        m_py->write(QJsonDocument(QJsonObject{{"id", id}, {"op", op}, {"body", QJsonObject::fromVariantMap(body)}}).toJson(QJsonDocument::Compact) + "\n");
        return;
    }
    if (body["lang"] != "cpp" || !clangd()) { done({}); return; }
    cppOp(op, body, std::move(done));
}

void Lsp::request(const QString &op, const QVariantMap &body, const QJSValue &cb)
{
    call(op, body, [this, cb](QVariantMap r) mutable {
        if (cb.isCallable() && m_engine) cb.call({m_engine->toScriptValue(r)});
    });
}
