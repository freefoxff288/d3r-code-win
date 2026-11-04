// Подсветка C++ и Python в цветах Visual Studio (тёмная): ключевые слова, управление, функции, переменные, типы,
// строки, числа, макросы, комментарии. Свой лексер по строкам (а не KSyntaxHighlighting — его нет под Windows).
// В QML: Highlighter { document: textEdit.textDocument; lang: "cpp" | "python" | "text" }
#pragma once
#include <QQuickTextDocument>
#include <QSyntaxHighlighter>
#include <QTextCharFormat>

class Highlighter : public QSyntaxHighlighter
{
    Q_OBJECT
    Q_PROPERTY(QQuickTextDocument *document READ quickDocument WRITE setQuickDocument NOTIFY documentChanged)
    Q_PROPERTY(QString lang READ lang WRITE setLang NOTIFY langChanged)
public:
    enum Role { Keyword, Flow, Function, Variable, Type, String, Number, Macro, Preproc, Comment, Operator, Escape, RoleCount };
    explicit Highlighter(QObject *parent = nullptr);

    QQuickTextDocument *quickDocument() const { return m_qdoc; }
    void setQuickDocument(QQuickTextDocument *d);
    QString lang() const { return m_lang; }
    void setLang(const QString &l);

    // для самопроверки: роли символов строки ("k" ключевое слово, "f" функция… "." без цвета)
    static QString roles(const QString &lang, const QString &line, int state = 0, int *outState = nullptr);

signals:
    void documentChanged();
    void langChanged();

protected:
    void highlightBlock(const QString &text) override;

private:
    QQuickTextDocument *m_qdoc = nullptr;
    QString m_lang = "text";
    QTextCharFormat m_fmt[RoleCount];
};
