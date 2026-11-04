// D3R Code для Windows: точка входа. C++-часть (Sys, Lsp, Highlighter) — то, чего QML не умеет сам;
// интерфейс — qml/Code.qml. D3RCode.exe [файл|папка] · --smoke (загрузить окно и выйти) · --selftest (проверка C++-части)
#include "highlighter.h"
#include "lsp.h"
#include "sys.h"

#include <QDir>
#include <QEventLoop>
#include <QFile>
#include <QFontDatabase>
#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QTimer>
#include <cstdio>

namespace {

int failures = 0;
void check(bool ok, const QString &what)
{
    std::printf("%s %s\n", ok ? "ok  " : "FAIL", qPrintable(what));
    std::fflush(stdout);
    if (!ok) failures++;
}

// ждать, пока done() не станет true (или таймаут)
bool wait(const std::function<bool()> &done, int ms)
{
    QEventLoop loop;
    QTimer tick, limit;
    QObject::connect(&tick, &QTimer::timeout, &loop, [&] { if (done()) loop.quit(); });
    QObject::connect(&limit, &QTimer::timeout, &loop, &QEventLoop::quit);
    tick.start(20);
    limit.start(ms);
    if (!done()) loop.exec();
    return done();
}

struct Run { QString out; int code = -999; double ms = 0, peak = 0; bool done = false; };
Run runProc(Sys &sys, int id, int ms = 60000)
{
    Run r;
    auto c1 = QObject::connect(&sys, &Sys::output, [&](int i, const QString &t) { if (i == id) r.out += t; });
    auto c2 = QObject::connect(&sys, &Sys::finished, [&](int i, int code, double t, double peak, bool) {
        if (i == id) { r.code = code; r.ms = t; r.peak = peak; r.done = true; }
    });
    if (id) wait([&] { return r.done; }, ms);
    QObject::disconnect(c1);
    QObject::disconnect(c2);
    return r;
}

int selftest(Sys &sys, Lsp &lsp)
{
    // подсветка: k ключевое слово, f управление, F функция, v переменная, t тип, s строка, n число, m макрос, p препроцессор, c комментарий, e экранирование
    const QString cpp = "int main() { std::cout << \"hi\\n\"; return LIMIT + 0; } // x";
    const QString r = Highlighter::roles("cpp", cpp);
    check(r.mid(0, 3) == "kkk" && r.mid(4, 4) == "FFFF" && r.mid(13, 3) == "ttt" && r.mid(18, 4) == "vvvv", "подсветка C++: тип, функция, std, переменная  " + r);
    check(r.mid(29, 2) == "ee" && r[26] == 's' && r.mid(34, 6) == "ffffff" && r.mid(41, 5) == "mmmmm" && r[49] == 'n' && r.right(4) == "cccc", "подсветка C++: строка, return, макрос, число, комментарий");
    check(Highlighter::roles("cpp", "#include <vector>").startsWith("pppppppp.ssssssss"), "подсветка C++: #include");
    int st = 0;
    Highlighter::roles("cpp", "/* начало", 0, &st);
    check(st == 1 && Highlighter::roles("cpp", "конец */ x", st).startsWith("cccccccc"), "подсветка C++: многострочный комментарий");
    const QString py = Highlighter::roles("python", "def go(n): print(len(n), 'ok')  # c");
    check(py.startsWith("kkk.FF.v") && py.mid(11, 5) == "FFFFF" && py.mid(25, 4) == "ssss" && py.endsWith("ccc"), "подсветка Python  " + py);
    Highlighter::roles("python", "s = \"\"\"начало", 0, &st);
    check(st == 2 && Highlighter::roles("python", "конец\"\"\" + x", st).startsWith("ssssssss"), "подсветка Python: \"\"\"строка\"\"\"");

    // файлы: CRLF и BOM читаются и сохраняются как были
    const QString dir = sys.tempDir() + "/selftest";
    QDir(dir).removeRecursively();
    sys.mkdir(dir + "/src");
    QFile f(dir + "/src/crlf.cpp");
    f.open(QIODevice::WriteOnly);
    f.write("\xEF\xBB\xBFint a;\r\nint b;\r\n");
    f.close();
    check(sys.read(dir + "/src/crlf.cpp") == "int a;\nint b;\n" && sys.crlf(dir + "/src/crlf.cpp"), "чтение: BOM и CRLF");
    check(sys.write(dir + "/src/crlf.cpp", "int c;\n", true), "запись");
    f.open(QIODevice::ReadOnly);
    check(f.readAll() == "int c;\r\n", "запись сохраняет CRLF");
    f.close();
    sys.write(dir + "/build/junk.cpp", "int c;\n");
    check(sys.listFiles(dir) == QStringList{"src/crlf.cpp"}, "список файлов без build/");
    check(sys.grep(dir, "INT C").size() == 1, "поиск по проекту");
    check(!sys.rename(dir + "/src/crlf.cpp", dir + "/build/junk.cpp"), "переименование не затирает файл");

    // процессы
    Run e = runProc(sys, sys.startShell("echo d3r-hello", dir));
    check(e.done && e.code == 0 && e.out.contains("d3r-hello"), "команда через " + QString(sys.windows() ? "cmd" : "sh") + ": " + e.out.trimmed());

    // g++: собрать, запустить с вводом, время и память
    if (const QString gpp = sys.findExe("g++"); !gpp.isEmpty()) {
        sys.write(dir + "/main.cpp", "#include <iostream>\nint main() { int x; std::cin >> x; std::cout << x * 2 << \" привет\" << std::endl; }\n");
        Run b = runProc(sys, sys.start(gpp, {"-std=c++20", "-Wall", "main.cpp", "-o", "main"}, dir), 120000);
        check(b.code == 0, "g++ собирает: " + gpp + " " + b.out.trimmed());
        Run p = runProc(sys, sys.start(dir + "/main", {}, dir, "21\n"));
        check(p.code == 0 && p.out.contains("42 привет") && p.ms > 0, QString("программа: «%1», %2 мс, %3 МБ").arg(p.out.trimmed()).arg(p.ms, 0, 'f', 1).arg(p.peak, 0, 'f', 1));
        if (sys.windows()) check(p.peak > 0, "пиковая память под Windows");
        const int live = sys.start(dir + "/main", {}, dir, {}, true);   // ждёт ввода
        sys.send(live, "5\n");
        Run q = runProc(sys, live);
        check(q.out.contains("10"), "ввод в работающую программу");
    } else std::printf("skip g++ не найден\n");

    // clangd
    if (lsp.langs().contains("cpp")) {
        QVariantMap res;
        bool got = false;
        const QString text = "#include <vector>\nint main() {\n    std::vector<int> v;\n    v.pu\n}\n";
        lsp.call("complete", {{"lang", "cpp"}, {"path", dir + "/t.cpp"}, {"text", text}, {"line", 3}, {"col", 8}}, [&](QVariantMap m) { res = m; got = true; });
        wait([&] { return got; }, 60000);
        QStringList labels;
        for (const auto &i : res["items"].toList()) labels << i.toMap()["label"].toString();
        check(std::any_of(labels.begin(), labels.end(), [](const QString &l) { return l.startsWith("push_back"); }), "clangd: v.pu → " + labels.mid(0, 3).join(", "));
        got = false;
        const QString t2 = "int add(int a, int b) { return a + b; }\nint main() {\n    int total = add(1, 2);\n    return total;\n}\n";
        lsp.call("rename", {{"lang", "cpp"}, {"path", dir + "/r.cpp"}, {"text", t2}, {"line", 2}, {"col", 9}, {"name", "sum"}}, [&](QVariantMap m) { res = m; got = true; });
        wait([&] { return got; }, 30000);
        check(res["files"].toMap().value(dir + "/r.cpp").toString().count("sum") == 2, "clangd: переименование");
    } else std::printf("skip clangd не найден\n");

    if (!sys.findExe("clang-format").isEmpty()) {
        QVariantMap res;
        bool got = false;
        lsp.call("format", {{"lang", "cpp"}, {"path", dir + "/f.cpp"}, {"text", "int main(){return 0;}"}, {"tab", 4}}, [&](QVariantMap m) { res = m; got = true; });
        wait([&] { return got; }, 30000);
        check(res["text"].toString().startsWith("int main() {\n    return 0;\n}"), "clang-format: " + res.value("text", res["error"]).toString().trimmed().replace('\n', ' '));
    } else std::printf("skip clang-format не найден\n");

    if (!sys.python().isEmpty()) {
        wait([&] { return lsp.langs().contains("python"); }, 15000);
        QVariantMap res;
        bool got = false;
        lsp.call("check", {{"lang", "python"}, {"path", "a.py"}, {"text", "if x\n"}}, [&](QVariantMap m) { res = m; got = true; });
        wait([&] { return got; }, 15000);
        check(res["items"].toList().size() == 1, "Python: проверка синтаксиса (" + sys.python() + ")");
    } else std::printf("skip Python не найден\n");

    QDir(dir).removeRecursively();
    std::printf(failures ? "SELFTEST FAILED: %d\n" : "SELFTEST OK\n", failures);
    return failures ? 1 : 0;
}

}   // namespace

int main(int argc, char *argv[])
{
    QCoreApplication::setOrganizationName("D3R");
    QCoreApplication::setApplicationName("D3RCode");
    QGuiApplication app(argc, argv);
    app.setWindowIcon(QIcon(":/icon.png"));
    QFontDatabase::addApplicationFont(":/fonts/FiraCodeNerdFontMono-Regular.ttf");

    Sys sys;
    Lsp lsp(&sys);
    if (app.arguments().contains("--selftest")) return selftest(sys, lsp);

    QQmlApplicationEngine engine;
    sys.setEngine(&engine);
    lsp.setEngine(&engine);
    qmlRegisterSingletonInstance("D3R", 1, 0, "Sys", &sys);
    qmlRegisterSingletonInstance("D3R", 1, 0, "Lsp", &lsp);
    qmlRegisterType<Highlighter>("D3R", 1, 0, "Highlighter");
    engine.load(QUrl("qrc:/Code.qml"));
    if (engine.rootObjects().isEmpty()) return 1;
    return app.exec();
}
