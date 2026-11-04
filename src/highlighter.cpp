#include "highlighter.h"

#include <QSet>
#include <algorithm>
#include <functional>

namespace {

using Paint = std::function<void(int start, int len, int role)>;

const QSet<QString> cppFlow = {"if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue", "return",
                               "goto", "try", "catch", "throw", "co_await", "co_return", "co_yield"};
const QSet<QString> cppKw = {"alignas", "alignof", "and", "asm", "auto", "bitand", "bitor", "bool", "char", "char8_t", "char16_t",
    "char32_t", "class", "compl", "concept", "const", "consteval", "constexpr", "constinit", "const_cast", "decltype", "delete",
    "double", "dynamic_cast", "enum", "explicit", "export", "extern", "false", "final", "float", "friend", "inline", "int", "long",
    "mutable", "namespace", "new", "noexcept", "not", "nullptr", "operator", "or", "override", "private", "protected", "public",
    "register", "reinterpret_cast", "requires", "short", "signed", "sizeof", "static", "static_assert", "static_cast", "struct",
    "template", "this", "thread_local", "true", "typedef", "typeid", "typename", "union", "unsigned", "using", "virtual", "void",
    "volatile", "wchar_t", "xor", "size_t"};
const QSet<QString> cppStd = {"std", "string", "string_view", "vector", "array", "map", "unordered_map", "set", "unordered_set",
    "multimap", "multiset", "list", "deque", "queue", "priority_queue", "stack", "pair", "tuple", "optional", "variant", "any",
    "function", "shared_ptr", "unique_ptr", "weak_ptr", "ostream", "istream", "iostream", "ifstream", "ofstream", "fstream",
    "stringstream", "istringstream", "ostringstream", "thread", "mutex", "atomic", "span", "bitset", "complex", "regex", "chrono"};
const QSet<QString> pyFlow = {"if", "elif", "else", "for", "while", "try", "except", "finally", "with", "return", "yield", "break",
                              "continue", "pass", "raise", "assert", "async", "await", "match", "case"};
const QSet<QString> pyKw = {"def", "class", "import", "from", "as", "in", "is", "not", "and", "or", "lambda", "global", "nonlocal",
                            "del", "None", "True", "False", "self", "cls"};
const QSet<QString> pyTypes = {"int", "str", "float", "bool", "list", "dict", "set", "tuple", "bytes", "object", "type", "range",
                               "frozenset", "complex", "Exception", "ValueError", "TypeError", "KeyError", "IndexError"};

bool isId0(QChar c) { return c.isLetter() || c == '_'; }
bool isId(QChar c) { return c.isLetterOrNumber() || c == '_'; }
bool allCaps(const QString &w)
{
    bool letter = false;
    for (QChar c : w) { if (c.isLower()) return false; if (c.isLetter()) letter = true; }
    return letter && w.size() >= 2;
}
bool capitalized(const QString &w) { return w[0].isUpper() && std::any_of(w.begin(), w.end(), [](QChar c) { return c.isLower(); }); }
int skipSpace(const QString &t, int i) { while (i < t.size() && t[i].isSpace()) i++; return i; }
bool isOp(QChar c) { return QStringLiteral("+-*/%=<>!&|^~?:").contains(c); }

// строка в кавычках q с i (на кавычке); экранирование \x — отдельным цветом. Возвращает индекс после строки.
int quoted(const QString &t, int i, QChar q, const Paint &paint)
{
    const int s = i++;
    QList<int> esc;
    while (i < t.size() && t[i] != q) {
        if (t[i] == '\\' && i + 1 < t.size()) { esc << i; i += 2; continue; }
        i++;
    }
    if (i < t.size()) i++;
    paint(s, i - s, Highlighter::String);   // сначала строка целиком, поверх — экранирование
    for (int e : esc) paint(e, 2, Highlighter::Escape);
    return i;
}

int lexCpp(const QString &t, int state, const Paint &paint)
{
    int i = 0;
    if (state == 1) {   // продолжение /* … */
        const int e = t.indexOf("*/");
        if (e < 0) { paint(0, t.size(), Highlighter::Comment); return 1; }
        paint(0, e + 2, Highlighter::Comment);
        i = e + 2;
    }
    // препроцессор: #include <…>, #define ИМЯ …
    if (const int h = skipSpace(t, i); h < t.size() && t[h] == '#') {
        int j = skipSpace(t, h + 1);
        while (j < t.size() && isId(t[j])) j++;
        paint(h, j - h, Highlighter::Preproc);
        if (t.mid(h).contains(QLatin1String("include"))) {
            const int a = skipSpace(t, j);
            if (a < t.size() && (t[a] == '<' || t[a] == '"')) {
                const int b = t.indexOf(t[a] == '<' ? '>' : '"', a + 1);
                paint(a, (b < 0 ? t.size() : b + 1) - a, Highlighter::String);
                return 0;
            }
        }
        i = j;
    }
    while (i < t.size()) {
        const QChar c = t[i];
        if (c.isSpace()) { i++; continue; }
        if (t.mid(i, 2) == "//") { paint(i, t.size() - i, Highlighter::Comment); return 0; }
        if (t.mid(i, 2) == "/*") {
            const int e = t.indexOf("*/", i + 2);
            if (e < 0) { paint(i, t.size() - i, Highlighter::Comment); return 1; }
            paint(i, e + 2 - i, Highlighter::Comment); i = e + 2; continue;
        }
        if (c == 'R' && t.mid(i + 1, 1) == "\"") {   // R"(сырая строка)" — в пределах строки
            const int open = t.indexOf('(', i + 2);
            const QString close = ")" + t.mid(i + 2, open - i - 2) + "\"";
            const int e = open < 0 ? -1 : t.indexOf(close, open);
            const int end = e < 0 ? t.size() : e + close.size();
            paint(i, end - i, Highlighter::String); i = end; continue;
        }
        if (c == '"' || c == '\'') { i = quoted(t, i, c, paint); continue; }
        if (c.isDigit() || (c == '.' && i + 1 < t.size() && t[i + 1].isDigit())) {
            int j = i + 1;
            while (j < t.size() && (isId(t[j]) || t[j] == '.' || t[j] == '\'' ||
                                    ((t[j] == '+' || t[j] == '-') && (t[j - 1] == 'e' || t[j - 1] == 'E')))) j++;
            paint(i, j - i, Highlighter::Number); i = j; continue;
        }
        if (isId0(c)) {
            int j = i + 1;
            while (j < t.size() && isId(t[j])) j++;
            const QString w = t.mid(i, j - i);
            const int n = skipSpace(t, j);
            int role;
            if (cppFlow.contains(w)) role = Highlighter::Flow;
            else if (cppKw.contains(w)) role = Highlighter::Keyword;
            else if (t.mid(n, 2) == "::" || cppStd.contains(w)) role = Highlighter::Type;
            else if (n < t.size() && t[n] == '(') role = Highlighter::Function;
            else if (allCaps(w)) role = Highlighter::Macro;
            else if (capitalized(w)) role = Highlighter::Type;
            else role = Highlighter::Variable;
            paint(i, j - i, role); i = j; continue;
        }
        if (isOp(c)) paint(i, 1, Highlighter::Operator);
        i++;
    }
    return 0;
}

// Python: состояние 2 — внутри """…""", 3 — внутри '''…'''
int lexPy(const QString &t, int state, const Paint &paint)
{
    int i = 0;
    if (state == 2 || state == 3) {
        const QString q = state == 2 ? "\"\"\"" : "'''";
        const int e = t.indexOf(q);
        if (e < 0) { paint(0, t.size(), Highlighter::String); return state; }
        paint(0, e + 3, Highlighter::String);
        i = e + 3;
    }
    QString prev;   // предыдущее слово: после def — функция, после class — тип
    while (i < t.size()) {
        const QChar c = t[i];
        if (c.isSpace()) { i++; continue; }
        if (c == '#') { paint(i, t.size() - i, Highlighter::Comment); return 0; }
        int p = i;   // префикс строки: r, b, f, rb, f…
        while (p < t.size() && p - i < 2 && QStringLiteral("rbfuRBFU").contains(t[p])) p++;
        if (p < t.size() && (t[p] == '"' || t[p] == '\'')) {
            const QChar q = t[p];
            if (t.mid(p, 3) == QString(3, q)) {
                const int e = t.indexOf(QString(3, q), p + 3);
                if (e < 0) { paint(i, t.size() - i, Highlighter::String); return q == '"' ? 2 : 3; }
                paint(i, e + 3 - i, Highlighter::String); i = e + 3; prev.clear(); continue;
            }
            if (p > i) paint(i, p - i, Highlighter::String);
            i = quoted(t, p, q, paint); prev.clear(); continue;
        }
        if (c == '@') {   // декоратор
            int j = i + 1;
            while (j < t.size() && (isId(t[j]) || t[j] == '.')) j++;
            paint(i, j - i, Highlighter::Function); i = j; continue;
        }
        if (c.isDigit() || (c == '.' && i + 1 < t.size() && t[i + 1].isDigit())) {
            int j = i + 1;
            while (j < t.size() && (isId(t[j]) || t[j] == '.')) j++;
            paint(i, j - i, Highlighter::Number); i = j; continue;
        }
        if (isId0(c)) {
            int j = i + 1;
            while (j < t.size() && isId(t[j])) j++;
            const QString w = t.mid(i, j - i);
            const int n = skipSpace(t, j);
            int role;
            if (prev == "def") role = Highlighter::Function;
            else if (prev == "class") role = Highlighter::Type;
            else if (pyFlow.contains(w)) role = Highlighter::Flow;
            else if (pyKw.contains(w)) role = Highlighter::Keyword;
            else if (n < t.size() && t[n] == '(') role = pyTypes.contains(w) || capitalized(w) ? Highlighter::Type : Highlighter::Function;
            else if (pyTypes.contains(w) || capitalized(w)) role = Highlighter::Type;
            else if (allCaps(w)) role = Highlighter::Macro;
            else role = Highlighter::Variable;
            paint(i, j - i, role); prev = w; i = j; continue;
        }
        if (isOp(c)) paint(i, 1, Highlighter::Operator);
        prev.clear();
        i++;
    }
    return 0;
}

int lex(const QString &lang, const QString &t, int state, const Paint &paint)
{
    if (lang == "cpp") return lexCpp(t, state, paint);
    if (lang == "python") return lexPy(t, state, paint);
    return 0;
}

}   // namespace

Highlighter::Highlighter(QObject *parent) : QSyntaxHighlighter(parent)
{
    // палитра Visual Studio (тёмная) — как в D3R Code для Linux
    const char *colors[RoleCount] = {"#569cd6", "#d8a0df", "#dcdcaa", "#9cdcfe", "#4ec9b0", "#d69d85",
                                     "#b5cea8", "#beb7ff", "#9b9b9b", "#57a64a", "#b4b4b4", "#ffd68f"};
    for (int r = 0; r < RoleCount; r++) m_fmt[r].setForeground(QColor(colors[r]));
    m_fmt[Comment].setFontItalic(true);
}

void Highlighter::setQuickDocument(QQuickTextDocument *d)
{
    if (d == m_qdoc) return;
    m_qdoc = d;
    setDocument(d ? d->textDocument() : nullptr);
    emit documentChanged();
}

void Highlighter::setLang(const QString &l)
{
    if (l == m_lang) return;
    m_lang = l;
    rehighlight();
    emit langChanged();
}

void Highlighter::highlightBlock(const QString &text)
{
    const int prev = qMax(0, previousBlockState());
    setCurrentBlockState(lex(m_lang, text, prev, [this](int s, int n, int r) { setFormat(s, n, m_fmt[r]); }));
}

QString Highlighter::roles(const QString &lang, const QString &line, int state, int *outState)
{
    QString out(line.size(), '.');
    const char *code = "kfFvtsnmpcoe";   // Keyword Flow Function Variable Type String Number Macro Preproc Comment Operator Escape
    const int st = lex(lang, line, state, [&](int s, int n, int r) { for (int i = s; i < s + n && i < out.size(); i++) out[i] = QChar(code[r]); });
    if (outState) *outState = st;
    return out;
}
