// Lsp — автодополнение и всё «умное»: C++ через clangd (LSP по stdin/stdout, запускается при первом C++-файле),
// Python через помощника pyhelper.py (jedi; работает, если установлен Python). Ответы — в тех же формах, что у моста
// lsp.py в D3R Code для Linux, поэтому Editor.qml общий:
//   complete  → {items: [{label, insert, kind, detail, doc, start}]}
//   signature → {label, params: [[начало, конец]…], active}     hover → {text}
//   definition→ {path, line, col} (с 1)                          highlight → {items: [[строка, столбец, длина]…]}
//   rename {name} → {files: {путь: новый текст}}                 symbols → {items: [{name, kind, line, depth}]}
//   format {tab} → {text} | {error}                              check (Python) → {items: [{line, col, sev, msg}]}
#pragma once
#include <QHash>
#include <QJSValue>
#include <QJsonObject>
#include <QObject>
#include <QVariant>
#include <functional>

class QProcess;
class QQmlEngine;
class Sys;

class Lsp : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QStringList langs READ langs NOTIFY langsChanged)   // "cpp", "python" — что сейчас умеет
    Q_PROPERTY(QString std READ std WRITE setStd NOTIFY stdChanged)
public:
    Lsp(Sys *sys, QObject *parent = nullptr);
    ~Lsp() override;
    void setEngine(QQmlEngine *e) { m_engine = e; }

    QStringList langs() const;
    QString std() const { return m_std; }
    void setStd(const QString &s);

    Q_INVOKABLE void request(const QString &op, const QVariantMap &body, const QJSValue &cb);
    Q_INVOKABLE void restart();   // поставили clangd/Python — перезапустить без перезапуска редактора

    // для самопроверки и C++: тот же запрос с C++-колбэком
    void call(const QString &op, const QVariantMap &body, std::function<void(QVariantMap)> done);

signals:
    void langsChanged();
    void stdChanged();

private:
    // clangd
    bool clangd();   // запустить, если ещё нет
    void cdSend(const QJsonObject &msg);
    void cdNotify(const QString &method, const QJsonObject &params);
    void cdRequest(const QString &method, const QJsonObject &params, std::function<void(QJsonValue)> done);
    void cdRead();
    QString sync(const QString &path, const QString &text);
    void cdAt(const QString &method, const QVariantMap &b, std::function<void(QJsonValue)> done, QJsonObject extra = {});
    void cppOp(const QString &op, const QVariantMap &b, std::function<void(QVariantMap)> done);
    void format(const QVariantMap &b, std::function<void(QVariantMap)> done);

    // Python
    void pyStart();
    void pyRead();

    Sys *m_sys;
    QQmlEngine *m_engine = nullptr;
    QString m_std = "c++20";
    QString m_clangd;   // путь, если найден

    QProcess *m_cd = nullptr;
    QByteArray m_cdBuf;
    int m_cdId = 0;
    QHash<int, std::function<void(QJsonValue)>> m_cdWait;
    QHash<QString, int> m_docs;   // uri → версия

    QProcess *m_py = nullptr;
    QByteArray m_pyBuf;
    int m_pyId = 0;
    bool m_jedi = false;
    QHash<int, std::function<void(QVariantMap)>> m_pyWait;
};
