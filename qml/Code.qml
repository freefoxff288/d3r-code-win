// D3R Code для Windows — редактор кода в стиле D3R: C++ и Python, проекты, подсветка, консоль, проверка ошибок на лету.
// Всё, чего QML не умеет сам (процессы, файлы, clangd, подсветка), — C++-синглтоны Sys и Lsp и тип Highlighter (src/).
// Клавиши (полный список — F1):
//   Ctrl+N/O/S/Shift+S/W — новый, открыть, сохранить, сохранить как, закрыть · Ctrl+Shift+O — папка · Ctrl+Shift+N — проект
//   Ctrl+Tab, Alt+1..9 — вкладки · Ctrl+P — быстрый переход к файлу · Ctrl+G — к строке · Ctrl+F/H — поиск/замена
//   Ctrl+/ — комментарий · Ctrl+Shift+D — дублировать · Ctrl+Shift+K — удалить строку · Alt+↑/↓ — двигать строки
//   Ctrl+D / Alt+клик — ещё курсор · F9 — свернуть блок · F12 / Ctrl+клик — к определению · F2 — переименовать
//   Shift+Alt+F — форматировать · Ctrl+Shift+F — поиск по проекту · Ctrl+Shift+E — структура файла · слово+Tab — шаблон
//   F5 — запустить · Ctrl+Shift+R — ввод и аргументы · Ctrl+Shift+B — собрать · Shift+F5 — стоп · Ctrl+J — консоль · F8 — ошибка
import QtQuick
import QtQuick.Window
import QtQuick.Dialogs
import QtCore
import D3R
import "themes.js" as T

Window {
    id: win
    width: 1280; height: 800; minimumWidth: 640; minimumHeight: 400
    visible: true
    color: "transparent"
    flags: Qt.Window | Qt.FramelessWindowHint
    title: (curEd ? (curEd.dirty ? "● " : "") + curEd.name + " — " : "") + "D3R Code"

    readonly property string mono: "FiraCode Nerd Font Mono"
    // шрифты для кода: [семейство, подпись]; Nerd-версия первой (в ней значки), показываются только установленные
    readonly property var codeFonts: {
        const all = Qt.fontFamilies(), seen = {}, out = [];
        for (const f of [["FiraCode Nerd Font Mono", "Fira Code"], ["Fira Code", "Fira Code"], ["JetBrainsMono Nerd Font Mono", "JetBrains Mono"],
                         ["JetBrains Mono", "JetBrains Mono"], ["CaskaydiaCove Nerd Font Mono", "Cascadia Code"], ["Cascadia Code", "Cascadia Code"],
                         ["Hack Nerd Font Mono", "Hack"], ["Hack", "Hack"], ["Iosevka Nerd Font Mono", "Iosevka"], ["VictorMono Nerd Font Mono", "Victor Mono"],
                         ["SauceCodePro Nerd Font Mono", "Source Code Pro"], ["Source Code Pro", "Source Code Pro"], ["UbuntuMono Nerd Font Mono", "Ubuntu Mono"],
                         ["GeistMono Nerd Font Mono", "Geist Mono"], ["CommitMono Nerd Font Mono", "Commit Mono"], ["0xProto Nerd Font Mono", "0xProto"],
                         ["Intel One Mono", "Intel One"], ["MesloLGS Nerd Font Mono", "Meslo"], ["FantasqueSansM Nerd Font Mono", "Fantasque"],
                         ["Cascadia Mono", "Cascadia Mono"], ["Consolas", "Consolas"], ["Lucida Console", "Lucida Console"], ["Courier New", "Courier New"],
                         ["DejaVu Sans Mono", "DejaVu"], ["Liberation Mono", "Liberation"]])
            if (!seen[f[1]] && all.indexOf(f[0]) >= 0) { seen[f[1]] = true; out.push(f); }
        return out;
    }
    readonly property string home: Sys.home
    readonly property string exe: Sys.windows ? ".exe" : ""
    readonly property bool maxed: visibility === Window.Maximized || visibility === Window.FullScreen
    // пути — с прямыми слешами: C:/Users/... (так их отдаёт Qt); корень диска «C:/»
    function short(p) { return p && p.startsWith(home) ? "~" + p.slice(home.length) : (p || ""); }
    function dirOf(p) { const d = p.replace(/\/[^\/]*$/, ""); return /^[A-Za-z]:$/.test(d) ? d + "/" : d || "/"; }
    function baseName(p) { return p.replace(/\/+$/, "").split("/").pop() || p; }
    function stem(p) { return baseName(p).replace(/\.[^.]*$/, ""); }
    function join(d, n) { return d.endsWith("/") ? d + n : d + "/" + n; }
    function inside(p, dir) { return !!dir && (Sys.windows ? p.toLowerCase().startsWith(dir.toLowerCase() + "/") : p.startsWith(dir + "/")); }

    // ── настройки: ~/.config/d3r-code.conf ──
    Settings {
        id: settingsObj
        location: Sys.toUrl(Sys.configDir + "/d3r-code.ini")
        property string theme: "wired"
        property string font: "FiraCode Nerd Font Mono"
        property int fontSize: 15
        property int uiSize: 13
        property int tabWidth: 4
        property bool wrap: false
        property bool lineNumbers: true
        property bool curLine: true
        property bool autoClose: true
        property bool liveCheck: true
        property bool complete: true
        property bool hidden: false
        property bool anim: true
        property bool scanlines: true
        property real opacity: 0.97
        property string std: "c++20"
        property int sideW: 260
        property bool sideOpen: true
        property int termH: 240
        property string project: ""
        property string recent: "[]"
        property string session: "[]"
        property int sessionCur: 0
        property string expanded: "{}"
        property bool autoSave: true
        property string sideTab: "files"      // files | outline
        property string runIO: "{}"           // ввод и аргументы запуска: {программа: {input, args, on}}
    }
    readonly property alias cfg: settingsObj

    // ── тема ──
    readonly property string themeId: cfg.theme
    readonly property var th: T.list.find(t => t.id === themeId) || T.list[0]
    Item {   // палитра; цвета перетекают при смене темы
        id: palItem
        property color bg: win.th.bg;       Behavior on bg { enabled: cfg.anim; ColorAnimation { duration: 500 } }
        property color panel: win.th.panel; Behavior on panel { enabled: cfg.anim; ColorAnimation { duration: 500 } }
        property color head: win.th.head;   Behavior on head { enabled: cfg.anim; ColorAnimation { duration: 500 } }
        property color btn: win.th.btn;     Behavior on btn { enabled: cfg.anim; ColorAnimation { duration: 500 } }
        property color text: win.th.text;   Behavior on text { enabled: cfg.anim; ColorAnimation { duration: 500 } }
        property color dim: win.th.dim;     Behavior on dim { enabled: cfg.anim; ColorAnimation { duration: 500 } }
        property color acc: win.th.acc;     Behavior on acc { enabled: cfg.anim; ColorAnimation { duration: 500 } }
        property color light: win.th.light; Behavior on light { enabled: cfg.anim; ColorAnimation { duration: 500 } }
        property color sel: win.th.sel;     Behavior on sel { enabled: cfg.anim; ColorAnimation { duration: 500 } }
        readonly property color faint: Qt.alpha(dim, 0.6)
    }
    readonly property alias pal: palItem
    readonly property color red: "#e8607e"
    readonly property color green: "#7fd88f"
    readonly property color yellow: "#e8b85e"

    // ── значки файлов (Nerd Font) ──
    function iconFor(n) {
        const e = n.toLowerCase().split(".").pop();
        if (n === "CMakeLists.txt" || e === "cmake") return "\u{E794}";
        if (n === ".gitignore") return "\u{F02A2}";
        const cpp = "\u{E61D}", py = "\u{F0320}";
        return ({ cpp: cpp, cc: cpp, cxx: cpp, c: "\u{E61E}", h: cpp, hpp: cpp, hh: cpp, py: py, md: "\u{F0354}", json: "\u{F0626}",
                  sh: "\u{F018D}", txt: "\u{F0219}", toml: "\u{F107B}", yml: "\u{F107B}", yaml: "\u{F107B}", qml: "\u{F031E}", js: "\u{F031E}",
                  html: "\u{F031D}", css: "\u{F031C}", png: "\u{F021F}", jpg: "\u{F021F}" })[e] || "\u{F0224}";
    }
    function iconColor(n) {
        const e = n.toLowerCase().split(".").pop();
        return e === "py" ? pal.light : /^(cpp|cc|cxx|c|h|hpp|hh)$/.test(e) ? pal.acc : n === "CMakeLists.txt" ? win.yellow : pal.dim;
    }

    // ══════ документы ══════
    ListModel { id: docs }     // {path, title}
    property int cur: -1
    readonly property var curEd: cur >= 0 && cur < docs.count ? editors.itemAt(cur) : null
    readonly property string curPath: curEd ? curEd.path : ""
    property int untitled: 0
    function openFile(p, line, col) {
        for (let i = 0; i < docs.count; i++) if (docs.get(i).path === p) { cur = i; if (line) Qt.callLater(() => curEd.gotoLine(line, col)); focusEd(); return; }
        docs.append({ path: p, title: baseName(p) });
        cur = docs.count - 1;
        if (line) Qt.callLater(() => curEd.gotoLine(line, col));
        saveSession(); focusEd();
        Qt.callLater(() => check(curEd));
    }
    function newFile() { untitled++; docs.append({ path: "", title: "untitled-" + untitled }); cur = docs.count - 1; focusEd(); }
    function closeDoc(i, force) {
        const e = editors.itemAt(i);
        if (!e) return;
        if (e.dirty && !force) {
            ask("Сохранить «" + e.name + "»?", "Изменения в файле ещё не сохранены.", [
                ["Сохранить", () => saveDoc(i, ok => { if (ok) closeDoc(i, true); }), true],
                ["Не сохранять", () => closeDoc(i, true)], ["Отмена", () => {}]]);
            return;
        }
        docs.remove(i);
        if (cur >= docs.count || i < cur) cur = docs.count ? Math.max(0, cur - 1) : -1;
        saveSession(); focusEd();
    }
    function saveDoc(i, done) {
        const e = editors.itemAt(i);
        if (!e) return;
        if (!e.path) { saveAs(i, done); return; }
        e.save(ok => {
            if (ok) { flashSaved(); check(e); if (e.name === "CMakeLists.txt") scanProject(); }
            else toast("не удалось записать " + short(e.path), "error");
            if (done) done(ok);
        });
    }
    property var saveAsCb: null
    property int saveAsIdx: -1
    function saveAs(i, done) {
        saveAsIdx = i; saveAsCb = done || null;
        saveDlg.currentFolder = Sys.toUrl(cfg.project || home);
        saveDlg.open();
    }
    function saveAll(done) {
        const dirty = [];
        for (let i = 0; i < docs.count; i++) { const e = editors.itemAt(i); if (e && e.dirty && e.path) dirty.push(i); }
        let left = dirty.length;
        if (!left) { if (done) done(); return; }
        for (const i of dirty) saveDoc(i, () => { if (--left === 0 && done) done(); });
    }
    function saveSession() {
        const l = []; for (let i = 0; i < docs.count; i++) if (docs.get(i).path) l.push(docs.get(i).path);
        cfg.session = JSON.stringify(l); cfg.sessionCur = Math.max(0, cur);
    }
    onCurChanged: { if (cfg.anim) switchFx.restart(); saveSession(); Qt.callLater(focusEd); if (cfg.autoSave) saveAll(); outlineTimer.restart(); }
    onActiveChanged: if (!active && cfg.autoSave) saveAll()   // автосохранение: ушли в другое окно
    function focusEd() { if (curEd) curEd.area.forceActiveFocus(); }
    function zoom(d) { cfg.fontSize = d === 0 ? 15 : Math.max(9, Math.min(32, cfg.fontSize + d)); }

    // ══════ проект ══════
    property var expanded: ({})
    property int treeRev: 0
    property string cmakeExe: ""            // имя цели из CMakeLists.txt; "" — проекта CMake нет
    function toggleDir(p) { expanded[p] = !expanded[p]; treeRev++; cfg.expanded = JSON.stringify(expanded); }
    function openProject(dir) {
        dir = dir.length > 3 ? dir.replace(/\/+$/, "") : dir;
        cfg.project = dir;
        const r = JSON.parse(cfg.recent).filter(x => x !== dir); r.unshift(dir);
        cfg.recent = JSON.stringify(r.slice(0, 8));
        cfg.sideOpen = true;
        scanProject();
        if (!con.busy) con.cwd = dir;
    }
    function scanProject() {   // CMake-проект? имя цели — для запуска build/<цель>.exe
        const m = cfg.project ? Sys.read(join(cfg.project, "CMakeLists.txt")).match(/add_executable\s*\(\s*([\w.+-]+)/) : null;
        cmakeExe = m ? m[1] : "";
    }

    // ══════ инструменты: g++, clangd, clang-format, cmake, python — где лежат ══════
    property var tools: ({})
    function findTools() {
        Sys.refreshPath();
        tools = { gpp: Sys.findExe("g++"), clangd: Sys.findExe("clangd"), clangFormat: Sys.findExe("clang-format"),
                  cmake: Sys.findExe("cmake"), ninja: Sys.findExe("ninja"), make: Sys.findExe("mingw32-make"), python: Sys.python() };
    }
    function refreshTools() {   // поставили компилятор — подхватить без перезапуска
        findTools(); Lsp.restart();
        con.say("── инструменты ──\n" + [["g++", tools.gpp], ["clangd", tools.clangd], ["clang-format", tools.clangFormat], ["cmake", tools.cmake], ["python", tools.python]]
                  .map(t => "  " + t[0].padEnd(13) + (t[1] || "не найден")).join("\n") + "\n");
        termPanel.open = true;
    }
    readonly property string installHint: "winget install -e --id BrechtSanders.WinLibs.POSIX.UCRT.LLVM"

    // ══════ проверка ошибок на лету: g++ -fsyntax-only / разбор Python ══════
    Timer { id: checkTimer; interval: 1200; onTriggered: win.check(win.curEd) }
    function check(e) {
        if (!e) return;
        if (!cfg.liveCheck || (e.lang !== "cpp" && e.lang !== "python")) { e.diags = []; return; }
        const seq = (e.checkSeq = (e.checkSeq || 0) + 1);
        if (e.lang === "python") {
            Lsp.request("check", { lang: "python", path: e.path || e.name, text: e.text }, r => { if (seq === e.checkSeq) e.diags = r.items || []; });
            return;
        }
        if (!tools.gpp) { e.diags = []; return; }
        // копия текста во временной папке: проверяется то, что на экране, а не то, что на диске
        const dir = Sys.tempDir + "/check-" + (e.uid || (e.uid = Math.random().toString(36).slice(2, 8)));
        const tmp = dir + "/" + e.name, src = e.path ? dirOf(e.path) : (cfg.project || home), root = cfg.project || src;
        if (!Sys.write(tmp, e.text)) return;
        Sys.run(tools.gpp, ["-x", "c++", "-std=" + cfg.std, "-fsyntax-only", "-Wall", "-Wextra", "-fdiagnostics-plain-output", "-fno-diagnostics-color",
                            "-I.", "-Iinclude", "-I" + root, "-I" + root + "/include", "-I" + root + "/src", tmp], src, (code, out) => {
            if (seq !== e.checkSeq) return;   // пока проверяли, текст уже поменялся
            const d = [], want = tmp.toLowerCase();
            for (const l of out.split("\n")) {
                const m = l.replace(/\\/g, "/").match(/^(.*?):(\d+):(\d+): (fatal error|error|warning): (.*)$/);
                if (m && m[1].toLowerCase() === want) d.push({ line: +m[2], col: +m[3], sev: m[4] === "warning" ? "warning" : "error", msg: m[5] });
            }
            e.diags = d;
        });
    }
    function nextProblem() {
        const e = curEd; if (!e || !e.diags.length) return;
        const l = e.diags.map(d => d.line).sort((a, b) => a - b), n = l.find(x => x > e.curLine) || l[0];
        const d = e.diags.find(x => x.line === n);
        e.gotoLine(d.line, d.col);
    }

    // ══════ запуск и сборка во встроенной консоли: шаги по очереди (собрать → запустить), без шелла посередине ══════
    property string runRoot: ""             // откуда запускали: от неё считаются пути в ошибках консоли
    function runKey(e) { return e && e.lang === "cpp" && cmakeExe && cfg.project && inside(e.path, cfg.project) ? cfg.project : e ? e.path : ""; }
    function ioFor(k) { try { return JSON.parse(cfg.runIO)[k] || { input: "", args: "", on: true }; } catch (x) { return { input: "", args: "", on: true }; } }
    function setIO(k, v) { let m = {}; try { m = JSON.parse(cfg.runIO); } catch (x) {} m[k] = v; cfg.runIO = JSON.stringify(m); }
    function splitArgs(s) {   // аргументы как в cmd: пробелы делят, "в кавычках" — одним
        const out = [], re = /"([^"]*)"|(\S+)/g; let m;
        while ((m = re.exec(s || ""))) out.push(m[1] !== undefined ? m[1] : m[2]);
        return out;
    }
    function missing(what) {
        con.say("\n✕ не найден " + what + ". Поставь (PowerShell / cmd):\n    " + installHint +
                  (what === "cmake" ? "\n    winget install -e --id Kitware.CMake" : what === "python" ? "\n    winget install -e --id Python.Python.3.13" : "") +
                  "\n  потом настройки → инструменты → «обновить».\n");
        termPanel.open = true;
    }
    function run(buildOnly) {
        const e = curEd;
        if (!e) return;
        if (!e.path) { toast("сначала сохрани файл (Ctrl+S)", "warn"); return; }
        if (con.busy) { stop(); }
        saveAll(() => {
            const root = cfg.project && inside(e.path, cfg.project) ? cfg.project : dirOf(e.path);
            const io = ioFor(runKey(e)), useIn = !buildOnly && io.on && io.input !== "";
            const args = splitArgs(io.args), input = useIn ? (io.input.endsWith("\n") ? io.input : io.input + "\n") : "";
            const prog = (exe, pre) => ({ prog: exe, args: (pre || []).concat(args), input: input, keep: !useIn, main: true });
            const steps = [];
            let what = e.name;
            if (e.lang === "cpp" && cmakeExe && root === cfg.project) {
                if (!tools.cmake) { missing("cmake"); return; }
                what = cmakeExe + " (cmake)";
                if (!Sys.exists(root + "/build/CMakeCache.txt")) {
                    const gen = tools.ninja ? ["-G", "Ninja"] : tools.make ? ["-G", "MinGW Makefiles"] : [];
                    steps.push({ prog: tools.cmake, args: ["-S", ".", "-B", "build", "-DCMAKE_BUILD_TYPE=Debug", "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"].concat(gen) });
                }
                steps.push({ prog: tools.cmake, args: ["--build", "build", "-j"] });
                if (!buildOnly) steps.push(Object.assign(prog(""), { exeOf: () => ["/build/", "/build/Debug/"].map(d => root + d + cmakeExe + exe).find(Sys.exists) || "" }));
            } else if (e.lang === "cpp") {
                if (/\.(h|hh|hpp|hxx)$/i.test(e.name)) { toast("это заголовок — запусти файл с main()", "warn"); return; }
                if (!tools.gpp) { missing("g++"); return; }
                const out = "build/" + stem(e.path) + exe;
                Sys.mkdir(root + "/build");
                steps.push({ prog: tools.gpp, args: ["-std=" + cfg.std, "-Wall", "-Wextra", "-g", e.path.slice(root.length + 1), "-o", out] });
                if (!buildOnly) steps.push(prog(root + "/" + out));
            } else if (e.lang === "python") {
                if (buildOnly) { check(e); toast("python не собирается — проверка синтаксиса запущена", "info"); return; }
                if (!tools.python) { missing("python"); return; }
                steps.push(prog(tools.python, (/(^|[\\/])py(\.exe)?$/i.test(tools.python) ? ["-3"] : []).concat(["-u", e.path.slice(root.length + 1)])));
            } else if (/\.(bat|cmd)$/i.test(e.name)) steps.push(Object.assign(prog(""), { shell: '"' + e.path.replace(/\//g, "\\") + '"' }));
            else { toast("не знаю, как запустить " + e.name, "warn"); return; }
            runRoot = root;
            con.clear();
            con.cwd = root;
            con.say("── d3r // " + (buildOnly ? "build" : "run") + " " + what + (useIn ? " · ввод из сохранённого" : "") + " ──\n");
            con.queue = steps;
            con.next();
            termPanel.open = true;
            runFx.restart();
            if (!useIn && !buildOnly) Qt.callLater(() => conInput.input.forceActiveFocus());   // чтобы сразу вводить в std::cin / input()
        });
    }
    function stop() { con.queue = []; if (con.busy) Sys.kill(con.procId); }

    // ── консоль: вывод процессов и команды cmd ──
    QtObject {
        id: con
        property int procId: 0
        readonly property bool busy: procId !== 0
        property string cwd: cfg.project || win.home
        property var queue: []
        property bool mainStep: false
        function say(t) {
            const a = conText;
            a.insert(a.length, t);
            if (a.length > 300000) a.remove(0, a.length - 200000);
            Qt.callLater(() => conFlick.contentY = Math.max(0, conFlick.contentHeight - conFlick.height));
        }
        function clear() { conText.text = ""; }
        function next() {
            const st = queue[0];
            if (!st) return;
            queue = queue.slice(1);
            mainStep = !!st.main;
            if (st.shell !== undefined) { procId = Sys.startShell(st.shell, cwd); return; }
            const p = st.exeOf ? st.exeOf() : st.prog;
            if (!p) { say("✕ не нашёл, что запускать (собралось ли?)\n"); queue = []; return; }
            if (!st.main) say("› " + baseName(p).replace(/\.exe$/i, "") + " " + st.args.join(" ") + "\n");
            procId = Sys.start(p, st.args, cwd, st.input || "", !!st.keep);
            if (!procId) { say("✕ не запустился: " + p + "\n"); queue = []; }
        }
        function command(t) {   // строка из поля ввода
            if (busy) { say(t + "\n"); Sys.send(procId, t + "\n"); return; }
            const c = t.trim();
            if (!c) return;
            say("\n" + short(cwd) + "> " + c + "\n");
            if (/^(cls|clear)$/i.test(c)) { clear(); return; }
            const cd = c.match(/^cd(?:\s+\/d)?\s+(.+)$/i);
            if (cd) {
                const d = Sys.absolute(cd[1].replace(/^"|"$/g, "").replace(/\\/g, "/").replace(/^~/, home), cwd);
                if (Sys.isDir(d)) cwd = d; else say("нет такой папки: " + d + "\n");
                return;
            }
            mainStep = false;
            procId = Sys.startShell(c, cwd);
        }
    }
    Connections {
        target: Sys
        function onOutput(id, t) { if (id === con.procId) con.say(t); }
        function onFinished(id, code, ms, peak, crashed) {
            if (id !== con.procId) return;
            con.procId = 0;
            if (code === 0 && con.queue.length) { con.next(); return; }
            if (con.mainStep || code !== 0)
                con.say("\n── exit " + code + (crashed ? " (упала)" : "") + (con.mainStep ? " · " + Math.round(ms) + " мс" + (peak > 0 ? " · " + peak.toFixed(1) + " МБ" : "") : "") + " ──\n");
            con.queue = [];
        }
    }

    // ══════ сообщения и вопросы ══════
    function toast(msg, kind) { toastBox.msg = msg; toastBox.kind = kind || "info"; toastFx.restart(); }
    property var askData: null
    function ask(title, text, buttons) { askData = { title: title, text: text, buttons: buttons }; }
    property var promptData: null
    function prompt(title, value, cb) { promptData = { title: title, value: value, cb: cb }; Qt.callLater(() => { promptField.input.text = value; promptField.input.selectAll(); promptField.input.forceActiveFocus(); }); }
    function flashSaved() { savedFx.restart(); }
    TextEdit { id: clipBridge; visible: false }
    function copyText(t) { clipBridge.text = t; clipBridge.selectAll(); clipBridge.copy(); toast("скопировано", "info"); }

    // ══════ меню дерева: новый файл/папка, переименовать, удалить (в корзину) ══════
    function treeMenu(p, isDir, pos) {
        const dir = isDir ? p : dirOf(p);
        menu.show(pos, [
            ["󰝒  Новый файл", () => prompt("Новый файл в " + short(dir), "", n => createFile(dir + "/" + n))],
            ["󰉗  Новая папка", () => prompt("Новая папка в " + short(dir), "", n => { if (Sys.mkdir(join(dir, n))) { win.expanded[dir] = true; win.treeRev++; } else toast("не получилось создать папку", "error"); })],
            ["󰑕  Переименовать", () => prompt("Новое имя", baseName(p), n => {
                const np = join(dirOf(p), n);
                if (!Sys.rename(p, np)) { toast("не получилось: «" + n + "» уже есть или файл занят", "warn"); return; }
                {
                    for (let i = 0; i < docs.count; i++) {   // открытые файлы (и всё внутри переименованной папки) — на новые пути
                        const dp = docs.get(i).path;
                        if (dp === p || inside(dp, p)) { docs.setProperty(i, "path", np + dp.slice(p.length)); docs.setProperty(i, "title", win.baseName(np + dp.slice(p.length))); }
                    }
                    win.saveSession(); win.treeRev++;
                }
            })],
            ["󰆏  Копировать путь", () => copyText(p)],
            ["\u{F018D}  Открыть в консоли", () => { if (!con.busy) con.cwd = dir; termPanel.open = true; conInput.input.forceActiveFocus(); }],
            ["󰩺  В корзину", () => ask("Удалить «" + baseName(p) + "»?", "Файл попадёт в корзину — его можно будет вернуть.", [
                ["В корзину", () => {
                    if (!Sys.trash(p)) { toast("не получилось удалить — файл занят?", "error"); return; }
                    for (let i = docs.count - 1; i >= 0; i--) if (docs.get(i).path === p || inside(docs.get(i).path, p)) closeDoc(i, true);
                    win.treeRev++;
                }, true],
                ["Отмена", () => {}]])]
        ]);
    }
    function createFile(p) {
        if (Sys.exists(p)) { toast("«" + baseName(p) + "» уже есть", "warn"); openFile(p); return; }
        if (!Sys.write(p, "")) { toast("не получилось создать файл", "error"); return; }
        win.expanded[dirOf(p)] = true; win.treeRev++; openFile(p);
    }

    // ══════ новый проект ══════
    function createProject(name, kind, where) {
        name = name.trim().replace(/[^\w.-]+/g, "_");
        if (!name) { toast("нужно имя проекта", "warn"); return; }
        const dir = join(where.replace(/\\/g, "/").replace(/^~/, home).replace(/\/+$/, "") || home, name);
        const files = kind === "cpp" ? [
            ["CMakeLists.txt", "cmake_minimum_required(VERSION 3.20)\nproject(" + name + " CXX)\n\nset(CMAKE_CXX_STANDARD " + cfg.std.replace(/\D/g, "") +
             ")\nset(CMAKE_CXX_STANDARD_REQUIRED ON)\nset(CMAKE_EXPORT_COMPILE_COMMANDS ON)\n\nadd_executable(" + name + " main.cpp)\nif(MSVC)\n    target_compile_options(" + name + " PRIVATE /W4 /utf-8)\nelse()\n    target_compile_options(" + name + " PRIVATE -Wall -Wextra)\nendif()\n"],
            ["main.cpp", "#include <iostream>\n\nint main() {\n    std::cout << \"present day, present time\" << std::endl;\n    return 0;\n}\n"],
            [".gitignore", "build/\n.vs/\n"]
        ] : [
            ["main.py", "def main():\n    print(\"present day, present time\")\n\n\nif __name__ == \"__main__\":\n    main()\n"],
            [".gitignore", "__pycache__/\n.venv/\n"]
        ];
        if (Sys.exists(dir)) { toast("папка " + short(dir) + " уже есть — выбери другое имя", "warn"); return; }
        for (const f of files) if (!Sys.write(dir + "/" + f[0], f[1])) { toast("не получилось записать " + f[0], "error"); return; }
        newProj.open = false;
        openProject(dir);
        openFile(dir + "/" + (kind === "cpp" ? "main.cpp" : "main.py"), kind === "cpp" ? 4 : 2);
        toast("проект " + name + " создан · F5 — запустить", "info");
    }

    // ══════ автодополнение: C++ через clangd, Python через jedi — синглтон Lsp (src/lsp.cpp) ══════
    function canComplete(lang) { return cfg.complete && Lsp.langs.indexOf(lang) >= 0; }
    function lsp(op, body, cb) { Lsp.request(op, body, cb); return true; }   // op: complete, signature, hover, definition, rename, symbols, format, check
    Binding { target: Lsp; property: "std"; value: cfg.std }
    function edBody(e, pos) { const lc = e.lspPos(pos); return { lang: e.lang, path: e.path, text: e.text, line: lc[0], col: lc[1] }; }
    function gotoDef(e, pos) {   // F12 / Ctrl+клик
        if (!e || !canComplete(e.lang)) { toast("переход к определению — для C++ и Python", "warn"); return; }
        lsp("definition", edBody(e, pos), r => {
            if (r.path) openFile(r.path, r.line, r.col);
            else toast(r.error ? r.error : "определение не найдено", "warn");
        });
    }
    function renameSymbol() {   // F2: имя меняется во всех файлах, где оно встречается
        const e = curEd;
        if (!e || !canComplete(e.lang)) { toast("переименование — для C++ и Python", "warn"); return; }
        const w = e.wordAt(e.area.cursorPosition), old = e.area.text.slice(w[0], w[1]);
        if (!old) { toast("поставь курсор на имя", "warn"); return; }
        prompt("Переименовать «" + old + "» в", old, n => {
            if (n === old) return;
            if (!/^[A-Za-z_]\w*$/.test(n)) { toast("так назвать нельзя: " + n, "warn"); return; }
            saveAll(() => lsp("rename", Object.assign(edBody(e, w[0]), { name: n }), r => {
                const files = r.files || {}, paths = Object.keys(files);
                if (!paths.length) { toast(r.error || "здесь нечего переименовать", "warn"); return; }
                for (const p of paths) {
                    let open = false;
                    for (let i = 0; i < docs.count; i++) if (docs.get(i).path === p) { editors.itemAt(i).setText(files[p]); open = true; }
                    if (!open) Sys.write(p, files[p], Sys.crlf(p));
                }
                toast("«" + old + "» → «" + n + "» · файлов: " + paths.length, "info");
            }));
        });
    }
    function formatDoc() {   // Shift+Alt+F: clang-format для C++, black/ruff/autopep8 для Python
        const e = curEd;
        if (!e || (e.lang !== "cpp" && e.lang !== "python")) { toast("форматирование — для C++ и Python", "warn"); return; }
        if (!lsp("format", { lang: e.lang, path: e.path, text: e.text, tab: cfg.tabWidth }, r => {
            if (r.error) { toast(r.error, "error"); return; }
            if (r.text === e.text) { toast("уже аккуратно", "info"); return; }
            e.setText(r.text); toast("отформатировано", "info");
        })) {}
    }

    // ── структура файла (боковая панель): функции и классы от clangd/jedi ──
    property var outline: []
    property string outlineFor: ""
    Timer { id: outlineTimer; interval: 500; onTriggered: win.refreshOutline() }
    function refreshOutline() {
        const e = curEd;
        if (cfg.sideTab !== "outline" || !cfg.sideOpen || !e || !canComplete(e.lang)) { outline = []; outlineFor = e ? e.path : ""; return; }
        const p = e.path;
        lsp("symbols", { lang: e.lang, path: p, text: e.text }, r => { if (win.curEd === e) { win.outline = r.items || []; win.outlineFor = p; } });
    }

    // ── поиск по проекту (Ctrl+Shift+F) ──
    property var hits: []                   // [{file, line, text}]
    property string hitsFor: ""
    readonly property string searchRoot: cfg.project || (curEd && curEd.path ? dirOf(curEd.path) : home)
    Timer { id: searchTimer; interval: 250; onTriggered: win.searchProject(searchField.input.text) }
    function searchProject(q) {
        if (!q) { hits = []; hitsFor = ""; return; }
        hits = Sys.grep(searchRoot, q, 400).map(h => ({ file: h.file, line: h.line, text: h.text.trim().slice(0, 200) }));
        hitsFor = q;
    }
    function openHit(h) {
        searchBox.open = false;
        openFile(join(searchRoot, h.file), h.line);
        Qt.callLater(() => { const e = win.curEd; if (!e) return; const ls = e.starts[e.lineOf(e.area.cursorPosition)], i = e.area.text.slice(ls, e.lineEnd(e.lineOf(ls))).toLowerCase().indexOf(win.hitsFor.toLowerCase());
                             if (i >= 0) e.area.select(ls + i, ls + i + win.hitsFor.length); });
    }

    // ── ошибки в консоли: Ctrl+клик по «main.cpp:12:5», «C:\\x\\main.cpp:12:5» или «File "x.py", line 3» ──
    function openFromTerm(line) {
        line = line.replace(/\\/g, "/");
        const m = line.match(/((?:[A-Za-z]:\/)?[\w.\/~+ -]*[\w+-]\.(?:cpp|cc|cxx|c\+\+|c|hpp|hh|hxx|h|py|pyw|txt|cmake))(?::|\()(\d+)(?:[:,](\d+))?/i) ||
                  line.match(/File "([^"]+)", line (\d+)()/);
        if (!m) { toast("в этой строке нет ссылки на файл", "warn"); return; }
        let f = m[1].trim().replace(/^~/, home);
        if (!/^[A-Za-z]:\//.test(f) && !f.startsWith("/")) f = join(runRoot || con.cwd || cfg.project || home, f);
        openFile(f, +m[2], +(m[3] || 1));
    }

    // ══════ быстрый переход к файлу (Ctrl+P) ══════
    property var allFiles: []
    function quickOpen() {
        if (!cfg.project) { openDlg.open(); return; }
        quick.open = true; quickField.input.text = ""; quickField.input.forceActiveFocus();
        allFiles = Sys.listFiles(cfg.project, 4000);
    }
    function fuzzy(q, s) {   // все буквы запроса по порядку; чем плотнее, тем выше
        q = q.toLowerCase(); const t = s.toLowerCase();
        let i = 0, score = 0, last = -1;
        for (const c of q) { const j = t.indexOf(c, i); if (j < 0) return -1; score += j - last; last = j; i = j + 1; }
        return score + (t.endsWith(q) ? -50 : 0) + s.length * 0.1;
    }

    Component.onCompleted: {
        try { expanded = JSON.parse(cfg.expanded); } catch (e) { expanded = {}; }
        const a = Qt.application.arguments, i = a.indexOf("--");
        const args = i >= 0 ? a.slice(i + 1) : a.slice(1);
        const shotI = args.indexOf("--shot");
        if (shotI >= 0) { shot.file = args[shotI + 1]; args.splice(shotI, 2); shot.start(); }
        const actI = args.indexOf("--act");   // самопроверка: открыть панели перед снимком
        if (actI >= 0) { shot.acts = args[actI + 1].split(","); args.splice(actI, 2); }
        if (args.indexOf("--smoke") >= 0) smoke.start();
        findTools();
        if (cfg.project) scanProject();
        for (const p of JSON.parse(cfg.session)) if (Sys.exists(p)) docs.append({ path: p, title: baseName(p) });
        cur = docs.count ? Math.min(cfg.sessionCur, docs.count - 1) : -1;
        for (const p of args) {   // d3r-code <файл|папка>
            if (!p || p.startsWith("-")) continue;
            const ap = Sys.absolute(p.replace(/\\/g, "/"), "");
            if (/\.\w+$/.test(ap) || ap.endsWith("CMakeLists.txt")) openFile(ap); else openProject(ap);
        }
        appear.start();
        Qt.callLater(() => check(curEd));
    }
    onClosing: c => {
        let dirty = 0;
        for (let k = 0; k < docs.count; k++) if (editors.itemAt(k) && editors.itemAt(k).dirty) dirty++;
        if (!dirty || quitting) { saveSession(); return; }
        c.accepted = false;
        ask("Выйти без сохранения?", "Несохранённых файлов: " + dirty + ".", [
            ["Сохранить всё", () => win.saveAll(() => { win.quitting = true; win.close(); }), true],
            ["Выйти", () => { win.quitting = true; win.close(); }], ["Отмена", () => {}]]);
    }
    property bool quitting: false
    Timer { id: smoke; interval: 8000; onTriggered: { console.log("SMOKE OK"); win.quitting = true; Qt.quit(); } }   // --smoke: окно поднялось без ошибок
    Timer {   // --shot файл: снимок окна для самопроверки
        id: shot; property string file; property var acts: []; interval: 2500
        readonly property var actions: ({ settings: () => setMenu.open = true, theme: () => themeMenu.open = true, help: () => help.open = true,
            find: () => { findBar.show(true); findField.input.text = "sum"; }, run: () => win.run(false), term: () => termPanel.open = true,
            newproj: () => newProj.show("cpp"), complete: () => { win.curEd.gotoLine(4, 999); win.curEd.maybeComplete(true); }, quick: () => win.quickOpen(), menu: () => win.treeMenu(cfg.project, true, Qt.point(80, 120)),
            sig: () => { win.curEd.gotoLine(10, 22); win.curEd.requestSig(); },
            runio: () => { win.setIO(win.runKey(win.curEd), { input: "21\n", args: "", on: true }); win.run(false); },
            fold: () => { win.curEd.foldAll(); }, outline: () => { cfg.sideTab = "outline"; win.refreshOutline(); },
            search: () => { searchBox.show(); searchField.input.text = "int"; }, io: () => ioBox.show(),
            multi: () => { win.curEd.gotoLine(2, 5); win.curEd.addNextMatch(); win.curEd.addNextMatch(); win.curEd.addNextMatch(); },
            occ: () => { win.curEd.gotoLine(6, 10); },
            hover: () => { win.curEd.requestHover(win.curEd.starts[3] + 6, 200, 120); } })
        onTriggered: {
            if (acts.length) { for (const a of acts) actions[a](); acts = []; interval = 3500; start(); return; }
            body.grabToImage(r => { r.saveToFile(file); Qt.quit(); });
        }
    }

    // ══════ горячие клавиши ══════
    readonly property bool edFocus: !!curEd && curEd.area.activeFocus
    Shortcut { sequence: "Ctrl+N"; onActivated: win.newFile() }
    Shortcut { sequence: "Ctrl+O"; onActivated: { openDlg.currentFolder = Sys.toUrl(cfg.project || win.home); openDlg.open(); } }
    Shortcut { sequence: "Ctrl+Shift+O"; onActivated: { folderDlg.currentFolder = Sys.toUrl(cfg.project ? win.dirOf(cfg.project) : win.home); folderDlg.open(); } }
    Shortcut { sequence: "Ctrl+Shift+N"; onActivated: newProj.show() }
    Shortcut { sequence: "Ctrl+S"; onActivated: if (win.cur >= 0) win.saveDoc(win.cur) }
    Shortcut { sequence: "Ctrl+Shift+S"; onActivated: if (win.cur >= 0) win.saveAs(win.cur) }
    Shortcut { sequence: "Ctrl+W"; onActivated: if (win.cur >= 0) win.closeDoc(win.cur) }
    Shortcut { sequence: "Ctrl+Tab"; onActivated: if (docs.count) win.cur = (win.cur + 1) % docs.count }
    Shortcut { sequence: "Ctrl+Shift+Tab"; onActivated: if (docs.count) win.cur = (win.cur - 1 + docs.count) % docs.count }
    Repeater { model: 9; Item { required property int index; Shortcut { sequence: "Alt+" + (index + 1); onActivated: if (index < docs.count) win.cur = index } } }
    Shortcut { sequence: "Ctrl+B"; onActivated: cfg.sideOpen = !cfg.sideOpen }
    Shortcut { sequences: ["Ctrl+J", "Ctrl+`"]; onActivated: { termPanel.open = !termPanel.open; if (termPanel.open) Qt.callLater(() => conInput.input.forceActiveFocus()); else win.focusEd(); } }
    Shortcut { sequence: "F5"; onActivated: win.run(false) }
    Shortcut { sequence: "Ctrl+Shift+B"; onActivated: win.run(true) }
    Shortcut { sequence: "Shift+F5"; onActivated: win.stop() }
    Shortcut { sequence: "Ctrl+F"; onActivated: findBar.show(false) }
    Shortcut { sequence: "Ctrl+H"; onActivated: findBar.show(true) }
    Shortcut { sequence: "F3"; onActivated: if (win.curEd) win.curEd.findNext(false) }
    Shortcut { sequence: "Shift+F3"; onActivated: if (win.curEd) win.curEd.findNext(true) }
    Shortcut { sequence: "Ctrl+G"; onActivated: if (win.curEd) { gotoBox.open = true; gotoField.input.text = ""; gotoField.input.forceActiveFocus(); } }
    Shortcut { sequence: "Ctrl+P"; onActivated: win.quickOpen() }
    Shortcut { sequence: "Ctrl+Shift+F"; onActivated: searchBox.show() }
    Shortcut { sequence: "Ctrl+Shift+R"; onActivated: ioBox.show() }
    Shortcut { sequence: "Ctrl+Shift+E"; onActivated: { cfg.sideOpen = true; cfg.sideTab = cfg.sideTab === "outline" ? "files" : "outline"; win.refreshOutline(); } }
    Shortcut { sequences: ["Ctrl+=", "Ctrl++"]; onActivated: win.zoom(1) }
    Shortcut { sequence: "Ctrl+-"; onActivated: win.zoom(-1) }
    Shortcut { sequence: "Ctrl+0"; onActivated: win.zoom(0) }
    Shortcut { sequence: "F8"; onActivated: win.nextProblem() }
    Shortcut { sequence: "Ctrl+,"; onActivated: { themeMenu.open = false; setMenu.open = !setMenu.open; } }
    Shortcut { sequence: "F1"; onActivated: help.open = !help.open }
    Shortcut { sequence: "F11"; onActivated: win.visibility === Window.FullScreen ? win.showNormal() : win.showFullScreen() }
    Shortcut { sequence: "Escape"; enabled: win.anyPopup; onActivated: win.closePopups() }
    // правка кода — только когда фокус в редакторе (иначе Ctrl+D в поле поиска испортил бы файл)
    Shortcut { sequence: "Ctrl+/"; enabled: win.edFocus; onActivated: win.curEd.toggleComment() }
    Shortcut { sequence: "Ctrl+Shift+D"; enabled: win.edFocus; onActivated: win.curEd.duplicate() }
    Shortcut { sequence: "Ctrl+D"; enabled: win.edFocus; onActivated: win.curEd.addNextMatch() }
    Shortcut { sequence: "F9"; enabled: win.edFocus; onActivated: win.curEd.toggleFold() }
    Shortcut { sequence: "Ctrl+F9"; enabled: win.edFocus; onActivated: win.curEd.foldAll() }
    Shortcut { sequence: "Shift+F9"; enabled: win.edFocus; onActivated: win.curEd.unfoldAll() }
    Shortcut { sequence: "F12"; enabled: win.edFocus; onActivated: win.gotoDef(win.curEd, win.curEd.area.cursorPosition) }
    Shortcut { sequence: "F2"; enabled: win.edFocus; onActivated: win.renameSymbol() }
    Shortcut { sequence: "Shift+Alt+F"; enabled: !!win.curEd; onActivated: win.formatDoc() }
    Shortcut { sequence: "Ctrl+Shift+Space"; enabled: win.edFocus; onActivated: win.curEd.requestSig() }
    Shortcut { sequence: "Ctrl+Shift+K"; enabled: win.edFocus; onActivated: win.curEd.deleteLine() }
    Shortcut { sequence: "Alt+Up"; enabled: win.edFocus; onActivated: win.curEd.moveLines(-1) }
    Shortcut { sequence: "Alt+Down"; enabled: win.edFocus; onActivated: win.curEd.moveLines(1) }
    Shortcut { sequence: "Ctrl+L"; enabled: win.edFocus; onActivated: win.curEd.selectLine() }
    Shortcut { sequence: "Ctrl+]"; enabled: win.edFocus; onActivated: win.curEd.indent(1) }
    Shortcut { sequence: "Ctrl+["; enabled: win.edFocus; onActivated: win.curEd.indent(-1) }
    Shortcut { sequence: "Ctrl+Return"; enabled: win.edFocus; onActivated: win.curEd.openLine(false) }
    Shortcut { sequence: "Ctrl+Shift+Return"; enabled: win.edFocus; onActivated: win.curEd.openLine(true) }
    Shortcut { sequence: "Ctrl+Y"; enabled: win.edFocus; onActivated: win.curEd.area.redo() }
    Shortcut { sequences: ["Ctrl+Space", "Ctrl+I"]; enabled: win.edFocus; onActivated: win.curEd.maybeComplete(true) }

    readonly property bool anyPopup: setMenu.open || themeMenu.open || quick.open || gotoBox.open || help.open || newProj.open || menu.open || searchBox.open || ioBox.open || !!askData || !!promptData || findBar.open
    function closePopups() {
        if (askData) { askData = null; return; }
        if (promptData) { promptData = null; return; }
        if (menu.open) { menu.open = false; return; }
        setMenu.open = themeMenu.open = quick.open = gotoBox.open = help.open = newProj.open = searchBox.open = ioBox.open = false;
        if (findBar.open) { findBar.open = false; if (curEd) curEd.query = ""; }
        focusEd();
    }

    // ══════ диалоги файлов (системные) ══════
    FileDialog { id: openDlg; title: "Открыть файл"; fileMode: FileDialog.OpenFiles
                 onAccepted: { for (const u of selectedFiles) win.openFile(Sys.toLocal(u)); } }
    FileDialog {
        id: saveDlg; title: "Сохранить как"; fileMode: FileDialog.SaveFile
        onAccepted: {
            const p = Sys.toLocal(selectedFile), i = win.saveAsIdx;
            docs.setProperty(i, "path", p); docs.setProperty(i, "title", win.baseName(p));
            win.saveDoc(i, win.saveAsCb); win.saveSession();
        }
    }
    FolderDialog { id: folderDlg; title: "Открыть папку проекта"; onAccepted: win.openProject(Sys.toLocal(selectedFolder)) }

    // ══════ элементы интерфейса ══════
    component Glyph: Text { font.family: win.mono; color: pal.text; verticalAlignment: Text.AlignVCenter }
    component HeadBtn: Rectangle {
        id: hb
        property string glyph
        property string tip
        property bool on: false
        property color tint: pal.light
        signal clicked()
        width: 28; height: 24; radius: 5
        color: on ? Qt.alpha(pal.sel, 0.4) : hbm.containsMouse ? Qt.alpha(pal.head, 0.95) : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
        Glyph { anchors.centerIn: parent; font.pixelSize: 14; text: hb.glyph; color: hb.on || hbm.containsMouse ? hb.tint : pal.dim
                scale: hbm.pressed ? 0.85 : 1; Behavior on scale { NumberAnimation { duration: 90 } } }
        MouseArea { id: hbm; anchors.fill: parent; hoverEnabled: true; onClicked: hb.clicked() }
        ToolTipBox { app: win; show: hbm.containsMouse && hb.tip !== "" && tipDelay.done; msg: hb.tip; y: hb.height + 6; x: Math.min(0, -width / 2 + hb.width / 2) }
        Timer { id: tipDelay; property bool done: false; interval: 600; running: hbm.containsMouse; onRunningChanged: if (!running) done = false; onTriggered: done = true }
    }
    component Btn: Rectangle {   // кнопка с текстом
        id: bt
        property string label
        property bool accent: false
        signal clicked()
        implicitWidth: btt.implicitWidth + 24; height: 30; radius: 6
        color: accent ? (btm.containsMouse ? pal.acc : Qt.alpha(pal.sel, 0.85)) : btm.containsMouse ? Qt.alpha(pal.btn, 0.95) : Qt.alpha(pal.head, 0.9)
        border.width: 1; border.color: Qt.alpha(pal.acc, btm.containsMouse ? 0.8 : 0.35)
        Behavior on color { ColorAnimation { duration: 120 } }
        scale: btm.pressed ? 0.96 : 1; Behavior on scale { NumberAnimation { duration: 90 } }
        Text { id: btt; anchors.centerIn: parent; font.family: win.mono; font.pixelSize: cfg.uiSize; color: bt.accent ? pal.text : pal.text; text: bt.label }
        MouseArea { id: btm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: bt.clicked() }
    }
    component Field: Rectangle {
        id: fd
        property alias input: ti
        property string hint
        signal accepted()
        signal escaped()
        signal changed(string t)
        signal upPressed()
        signal downPressed()
        signal shiftEnter()
        height: 30; radius: 6
        color: Qt.alpha(pal.head, 0.9)
        border.width: 1; border.color: Qt.alpha(pal.acc, ti.activeFocus ? 0.75 : 0.25)
        Behavior on border.color { ColorAnimation { duration: 150 } }
        TextInput {
            id: ti
            anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter; clip: true
            font.family: win.mono; font.pixelSize: cfg.uiSize; color: pal.text
            selectionColor: pal.sel; selectedTextColor: pal.text; selectByMouse: true
            onAccepted: fd.accepted()
            onTextChanged: fd.changed(text)
            Keys.onEscapePressed: { fd.escaped(); win.closePopups(); }
            Keys.onUpPressed: fd.upPressed()
            Keys.onDownPressed: fd.downPressed()
            Keys.onPressed: e => { if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && (e.modifiers & Qt.ShiftModifier)) { fd.shiftEnter(); e.accepted = true; } }
            Text { visible: !ti.text; anchors.verticalCenter: parent.verticalCenter; font: ti.font; color: pal.faint; text: fd.hint }
        }
    }
    component Row2: Item {
        property string label
        width: parent.width; height: 30
        Text { anchors.verticalCenter: parent.verticalCenter; font.family: win.mono; font.pixelSize: cfg.uiSize - 1; color: pal.dim; text: "› " + parent.label }
    }
    component Toggle: Rectangle {
        id: tg
        property bool checked
        signal toggled(bool v)
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        width: 34; height: 16; radius: 8
        color: checked ? Qt.alpha(pal.sel, 0.8) : Qt.alpha(pal.head, 0.95)
        border.width: 1; border.color: Qt.alpha(pal.acc, 0.4)
        Rectangle { width: 10; height: 10; radius: 5; y: 3; x: tg.checked ? 21 : 3; color: tg.checked ? pal.text : pal.dim
                    Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } } }
        MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: tg.toggled(!tg.checked) }
    }
    component Stepper: Row {   // − значение +
        id: stp
        property int value; property int from: 0; property int to: 100; property string suffix: ""
        signal moved(int v)
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 6
        HeadBtn { glyph: "−"; width: 22; height: 20; onClicked: stp.moved(Math.max(stp.from, stp.value - 1)) }
        Text { width: 44; horizontalAlignment: Text.AlignHCenter; anchors.verticalCenter: parent.verticalCenter
               font.family: win.mono; font.pixelSize: cfg.uiSize; color: pal.light; text: stp.value + stp.suffix }
        HeadBtn { glyph: "+"; width: 22; height: 20; onClicked: stp.moved(Math.min(stp.to, stp.value + 1)) }
    }
    component Chips: Row {   // выбор одного из списка
        id: ch
        property var options: []    // [[значение, подпись]]
        property var value
        signal picked(var v)
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; spacing: 4
        Repeater {
            model: ch.options
            Rectangle {
                required property var modelData
                readonly property bool on: ch.value === modelData[0]
                width: ct.implicitWidth + 14; height: 20; radius: 4
                color: on ? Qt.alpha(pal.sel, 0.6) : cm.containsMouse ? Qt.alpha(pal.btn, 0.9) : Qt.alpha(pal.head, 0.9)
                border.width: 1; border.color: Qt.alpha(pal.acc, on ? 0.7 : 0.25)
                Text { id: ct; anchors.centerIn: parent; font.family: win.mono; font.pixelSize: cfg.uiSize - 2; color: parent.on ? pal.light : pal.text; text: parent.modelData[1] }
                MouseArea { id: cm; anchors.fill: parent; hoverEnabled: true; onClicked: ch.picked(parent.modelData[0]) }
            }
        }
    }
    component Pop: Rectangle {   // всплывающая панель: появляется с лёгким увеличением
        id: pp
        property bool open: false
        default property alias content: inner.data
        visible: opacity > 0.01
        opacity: open ? 1 : 0
        scale: open ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: cfg.anim ? 140 : 0 } }
        Behavior on scale { NumberAnimation { duration: cfg.anim ? 180 : 0; easing.type: Easing.OutCubic } }
        radius: 9; z: 50
        color: Qt.alpha(pal.bg, 0.98)
        border.width: 1; border.color: Qt.alpha(pal.acc, 0.5)
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: w => w.accepted = true }   // клики не проваливаются под панель
        Item { id: inner; anchors.fill: parent; anchors.margins: 14 }
    }

    // ══════ окно ══════
    Rectangle {
        id: body
        anchors.fill: parent; anchors.margins: win.maxed ? 0 : 6
        radius: win.maxed ? 0 : 11
        color: Qt.alpha(pal.bg, cfg.opacity)
        border.width: 1; border.color: Qt.alpha(pal.acc, 0.4)
        clip: true
        transform: Scale { id: sc; origin.y: 20; yScale: 1 }
        ParallelAnimation {
            id: appear
            NumberAnimation { target: body; property: "opacity"; from: 0; to: 1; duration: 160 }
            NumberAnimation { target: sc; property: "yScale"; from: cfg.anim ? 0.04 : 1; to: 1; duration: cfg.anim ? 280 : 0; easing.type: Easing.OutBack }
        }

        DropArea {   // файлы и папки можно бросить в окно
            anchors.fill: parent
            onDropped: d => { for (const u of d.urls) { const p = Sys.toLocal(u); if (!Sys.isDir(p)) win.openFile(p); else win.openProject(p); } }
        }

        // ── заголовок: бренд · вкладки · кнопки ──
        Item {
            id: bar
            width: parent.width; height: 40
            MouseArea { anchors.fill: parent; onPressed: win.startSystemMove(); onDoubleClicked: win.maxed ? win.showNormal() : win.showMaximized() }
            Text {
                id: brand
                x: 16; anchors.verticalCenter: parent.verticalCenter
                font.family: win.mono; font.pixelSize: 13; textFormat: Text.StyledText; color: pal.dim
                text: "<b><font color='" + pal.acc + "'>D3R</font></b> // code"
            }
            ListView {
                id: tabRow
                x: brand.x + brand.width + 18; y: 6; height: 34
                width: winBtns.x - x - 12
                orientation: ListView.Horizontal; spacing: 3; clip: true; interactive: false
                model: docs
                currentIndex: win.cur
                onCurrentIndexChanged: Qt.callLater(() => positionViewAtIndex(currentIndex, ListView.Contain))
                WheelHandler { onWheel: e => tabRow.contentX = Math.max(tabRow.originX, Math.min(tabRow.originX + tabRow.contentWidth - tabRow.width, tabRow.contentX - (e.angleDelta.y || e.angleDelta.x) * 0.8)) }
                add: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: cfg.anim ? 180 : 0 }
                                  NumberAnimation { property: "scale"; from: 0.8; to: 1; duration: cfg.anim ? 220 : 0; easing.type: Easing.OutBack } }
                displaced: Transition { NumberAnimation { property: "x"; duration: cfg.anim ? 200 : 0; easing.type: Easing.OutCubic } }
                delegate: Rectangle {
                    id: tab
                    required property int index
                    required property string title
                    required property string path
                    readonly property bool active: index === win.cur
                    readonly property var ed: { void (editors.count); return editors.itemAt(index); }
                    readonly property bool dirty: !!ed && ed.dirty
                    readonly property int errs: ed ? ed.diags.filter(d => d.sev === "error").length : 0
                    width: Math.min(220, Math.max(110, tt.implicitWidth + 64)); height: 34; radius: 8
                    color: active ? pal.panel : tm.containsMouse ? Qt.alpha(pal.head, 0.8) : "transparent"
                    Behavior on color { ColorAnimation { duration: 140 } }
                    Rectangle {   // полоска сверху у активной
                        x: 10; width: parent.width - 20; height: 2; radius: 1; color: pal.acc
                        opacity: tab.active ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 160 } }
                    }
                    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 8; color: parent.color; visible: tab.active }
                    Text { id: ti; x: 10; anchors.verticalCenter: parent.verticalCenter; font.family: win.mono; font.pixelSize: 14
                           color: win.iconColor(tab.title); text: win.iconFor(tab.title) }
                    Text {
                        id: tt
                        anchors.left: ti.right; anchors.leftMargin: 7; anchors.right: xb.left; anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideMiddle
                        font.family: win.mono; font.pixelSize: cfg.uiSize
                        color: tab.errs ? win.red : tab.active ? pal.light : pal.dim
                        text: tab.title
                    }
                    Text {   // ● несохранён / × закрыть
                        id: xb
                        anchors.right: parent.right; anchors.rightMargin: 10; anchors.verticalCenter: parent.verticalCenter
                        font.family: win.mono; font.pixelSize: tab.dirty && !xm.containsMouse ? 10 : 15
                        color: xm.containsMouse ? win.red : tab.dirty ? pal.light : pal.faint
                        text: tab.dirty && !xm.containsMouse ? "●" : "×"
                        opacity: tab.dirty || tab.active || tm.containsMouse ? 1 : 0
                        MouseArea { id: xm; anchors.fill: parent; anchors.margins: -6; hoverEnabled: true; onClicked: win.closeDoc(tab.index) }
                    }
                    MouseArea {
                        id: tm; anchors.fill: parent; z: -1; hoverEnabled: true; acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        onClicked: m => m.button === Qt.MiddleButton ? win.closeDoc(tab.index) : win.cur = tab.index
                    }
                }
                footer: Item {
                    width: 34; height: 34
                    Glyph { anchors.centerIn: parent; text: "+"; font.pixelSize: 17; color: pm.containsMouse ? pal.light : pal.faint }
                    MouseArea { id: pm; anchors.fill: parent; hoverEnabled: true; onClicked: win.newFile() }
                }
            }
            Row {
                id: winBtns
                anchors.right: parent.right; anchors.rightMargin: 10; height: parent.height; spacing: 3
                HeadBtn { id: runBtn; anchors.verticalCenter: parent.verticalCenter; glyph: "\u{F040A}"; tint: pal.light; tip: "запустить · F5"; onClicked: win.run(false) }
                HeadBtn { anchors.verticalCenter: parent.verticalCenter; glyph: "󰣪"; tip: "собрать · Ctrl+Shift+B"; onClicked: win.run(true) }
                HeadBtn { anchors.verticalCenter: parent.verticalCenter; glyph: "\u{F030C}"; on: ioBox.open || (!!win.curEd && win.ioFor(win.runKey(win.curEd)).on && win.ioFor(win.runKey(win.curEd)).input !== "" && cfg.runIO !== "")
                          tip: "ввод и аргументы · Ctrl+Shift+R"; onClicked: ioBox.open ? win.closePopups() : ioBox.show() }
                HeadBtn { anchors.verticalCenter: parent.verticalCenter; glyph: "\u{F04DB}"; tint: win.red; tip: "стоп · Shift+F5"; onClicked: win.stop() }
                Item { width: 8; height: 1 }
                HeadBtn { anchors.verticalCenter: parent.verticalCenter; glyph: "󰙅"; on: cfg.sideOpen; tip: "проект · Ctrl+B"; onClicked: cfg.sideOpen = !cfg.sideOpen }
                HeadBtn { anchors.verticalCenter: parent.verticalCenter; glyph: "\u{F018D}"; on: termPanel.open; tip: "консоль · Ctrl+J"; onClicked: termPanel.open = !termPanel.open }
                HeadBtn { anchors.verticalCenter: parent.verticalCenter; glyph: "\u{F0349}"; on: findBar.open; tip: "поиск · Ctrl+F"; onClicked: findBar.open ? win.closePopups() : findBar.show(false) }
                HeadBtn { anchors.verticalCenter: parent.verticalCenter; glyph: "\u{F0968}"; on: searchBox.open; tip: "поиск по проекту · Ctrl+Shift+F"; onClicked: searchBox.open ? win.closePopups() : searchBox.show() }
                HeadBtn { id: themeBtn; anchors.verticalCenter: parent.verticalCenter; glyph: "󰏘"; on: themeMenu.open; tip: "тема"; onClicked: { setMenu.open = false; themeMenu.open = !themeMenu.open; } }
                HeadBtn { id: setBtn; anchors.verticalCenter: parent.verticalCenter; glyph: "󰒓"; on: setMenu.open; tip: "настройки · Ctrl+,"; onClicked: { themeMenu.open = false; setMenu.open = !setMenu.open; } }
                HeadBtn { anchors.verticalCenter: parent.verticalCenter; glyph: "?"; on: help.open; tip: "клавиши · F1"; onClicked: help.open = !help.open }
                Item { width: 8; height: 1 }
                HeadBtn { anchors.verticalCenter: parent.verticalCenter; glyph: "─"; onClicked: win.showMinimized() }
                HeadBtn { anchors.verticalCenter: parent.verticalCenter; glyph: "▢"; onClicked: win.maxed ? win.showNormal() : win.showMaximized() }
                HeadBtn { anchors.verticalCenter: parent.verticalCenter; glyph: "✕"; tint: win.red; onClicked: win.close() }
            }
            SequentialAnimation {   // запуск: кнопка вспыхивает
                id: runFx
                NumberAnimation { target: runBtn; property: "scale"; to: 1.35; duration: 90 }
                NumberAnimation { target: runBtn; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack }
            }
        }
        Rectangle { y: bar.height; x: 12; width: parent.width - 24; height: 1; color: Qt.alpha(pal.acc, 0.3) }

        // ── середина: проект слева, редактор, консоль снизу ──
        Item {
            id: mid
            y: bar.height + 1; width: parent.width; height: parent.height - y - status.height

            // проект
            Item {
                id: side
                width: cfg.sideOpen ? cfg.sideW : 0; height: parent.height; clip: true
                Behavior on width { enabled: cfg.anim && !sideDrag.pressed; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                Rectangle { anchors.fill: parent; color: Qt.alpha(pal.panel, 0.55) }
                Item {
                    width: cfg.sideW; height: parent.height
                    Row {   // вкладки панели: файлы проекта / структура текущего файла
                        x: 8; y: 6; spacing: 2
                        Repeater {
                            model: [["files", "\u{F0645}  файлы"], ["outline", "\u{F0169}  структура"]]
                            Rectangle {
                                required property var modelData
                                readonly property bool on: cfg.sideTab === modelData[0]
                                width: stt.implicitWidth + 16; height: 24; radius: 5
                                color: on ? Qt.alpha(pal.sel, 0.4) : stm.containsMouse ? Qt.alpha(pal.head, 0.95) : "transparent"
                                Text { id: stt; anchors.centerIn: parent; font.family: win.mono; font.pixelSize: cfg.uiSize - 2; color: parent.on ? pal.light : pal.dim; text: parent.modelData[1] }
                                MouseArea { id: stm; anchors.fill: parent; hoverEnabled: true; onClicked: { cfg.sideTab = parent.modelData[0]; win.refreshOutline(); } }
                            }
                        }
                    }
                    Item {
                        width: parent.width; height: parent.height - 34; y: 34
                        visible: cfg.sideTab === "outline"
                        Text {
                            x: 14; y: 4; width: parent.width - 28; elide: Text.ElideMiddle
                            font.family: win.mono; font.pixelSize: cfg.uiSize - 1; font.bold: true; color: pal.light
                            text: win.curEd ? win.curEd.name : "нет файла"
                        }
                        ListView {
                            id: outlineList
                            x: 6; y: 28; width: parent.width - 12; height: parent.height - y - 6
                            clip: true; boundsBehavior: Flickable.StopAtBounds
                            model: win.outline
                            readonly property int here: { const e = win.curEd; if (!e) return -1; let k = -1; for (let i = 0; i < win.outline.length; i++) if (win.outline[i].line <= e.curLine) k = i; return k; }
                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                readonly property var k: ({ 5: ["C", pal.acc], 23: ["S", pal.acc], 10: ["E", pal.acc], 3: ["N", pal.dim], 2: ["N", pal.dim],
                                                            6: ["m", pal.light], 9: ["m", pal.light], 12: ["f", pal.light], 8: ["v", pal.text], 13: ["v", pal.text],
                                                            14: ["c", pal.text], 22: ["e", pal.text] })[modelData.kind] || ["·", pal.dim]
                                width: outlineList.width; height: 24; radius: 5
                                color: index === outlineList.here ? Qt.alpha(pal.sel, 0.4) : olm.containsMouse ? Qt.alpha(pal.head, 0.9) : "transparent"
                                Rectangle {
                                    x: 6 + parent.modelData.depth * 14; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 4
                                    color: Qt.alpha(parent.k[1], 0.15); border.width: 1; border.color: Qt.alpha(parent.k[1], 0.5)
                                    Text { anchors.centerIn: parent; font.family: win.mono; font.pixelSize: 10; font.bold: true; color: parent.parent.k[1]; text: parent.parent.k[0] }
                                }
                                Text {
                                    x: 28 + parent.modelData.depth * 14; anchors.verticalCenter: parent.verticalCenter; width: parent.width - x - 40; elide: Text.ElideRight
                                    font.family: win.mono; font.pixelSize: cfg.uiSize - 1; color: index === outlineList.here ? pal.light : pal.text; text: parent.modelData.name
                                }
                                Text { anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                                       font.family: win.mono; font.pixelSize: cfg.uiSize - 3; color: pal.faint; text: parent.modelData.line }
                                MouseArea { id: olm; anchors.fill: parent; hoverEnabled: true; onClicked: if (win.curEd) win.curEd.gotoLine(parent.modelData.line) }
                            }
                        }
                        Text {
                            visible: !win.outline.length; x: 14; y: 34; width: parent.width - 28; wrapMode: Text.Wrap
                            font.family: win.mono; font.pixelSize: cfg.uiSize - 2; color: pal.faint
                            text: !win.curEd ? "открой файл" : win.canComplete(win.curEd.lang) ? "функций и классов пока нет" : "структура — для C++ и Python (нужны clangd / jedi)"
                        }
                    }
                    Item {
                    width: parent.width; height: parent.height
                    visible: cfg.sideTab !== "outline"
                    Text {
                        x: 14; y: 38; width: parent.width - 70; elide: Text.ElideMiddle
                        font.family: win.mono; font.pixelSize: cfg.uiSize - 1; font.bold: true; color: pal.light
                        text: cfg.project ? win.baseName(cfg.project).toUpperCase() : "НЕТ ПРОЕКТА"
                    }
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: 8; y: 34; spacing: 2
                        HeadBtn { glyph: "󰝒"; tip: "новый файл"; visible: !!cfg.project; onClicked: win.prompt("Новый файл в проекте", "", n => win.createFile(cfg.project + "/" + n)) }
                        HeadBtn { glyph: "󰉋"; tip: "открыть папку · Ctrl+Shift+O"; onClicked: folderDlg.open() }
                        HeadBtn { glyph: "󰘦"; tip: "свернуть всё"; visible: !!cfg.project; onClicked: { win.expanded = {}; win.treeRev++; cfg.expanded = "{}"; } }
                    }
                    Text {
                        x: 14; y: 58; width: parent.width - 28; elide: Text.ElideMiddle
                        font.family: win.mono; font.pixelSize: cfg.uiSize - 3; color: pal.faint
                        text: win.short(cfg.project) + (win.cmakeExe ? "  · cmake" : "")
                    }
                    Flickable {
                        id: treeFlick
                        x: 6; y: 80; width: parent.width - 12; height: parent.height - y - 6
                        contentHeight: treeLoader.height; clip: true; boundsBehavior: Flickable.StopAtBounds
                        Loader {
                            id: treeLoader
                            width: treeFlick.width
                            active: !!cfg.project
                            sourceComponent: Component { TreeNode { app: win; dir: cfg.project } }
                        }
                        Column {   // без проекта — кнопки
                            visible: !cfg.project; width: parent.width; spacing: 8; topPadding: 20
                            Btn { anchors.horizontalCenter: parent.horizontalCenter; label: "󰉋  открыть папку"; onClicked: folderDlg.open() }
                            Btn { anchors.horizontalCenter: parent.horizontalCenter; label: "󰐕  новый проект"; accent: true; onClicked: newProj.show() }
                        }
                    }
                    }
                }
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Qt.alpha(pal.acc, 0.2) }
            }
            MouseArea {   // ширину панели проекта можно тянуть
                id: sideDrag
                x: side.width - 3; width: 6; height: parent.height; visible: cfg.sideOpen
                cursorShape: Qt.SizeHorCursor
                onPositionChanged: m => { if (pressed) cfg.sideW = Math.max(160, Math.min(520, mapToItem(mid, m.x, 0).x)); }
            }

            Item {
                id: work
                x: side.width; width: parent.width - x; height: parent.height
                clip: true

                // редакторы: все живут (история правок у каждого своя), виден текущий
                Item {
                    id: edArea
                    width: parent.width; height: parent.height - termPanel.height
                    Repeater {
                        id: editors
                        model: docs
                        Editor {
                            required property var model
                            required property int index
                            app: win
                            path: model.path
                            title: model.title
                            width: edArea.width; height: edArea.height
                            visible: index === win.cur
                            onEdited: if (index === win.cur) { checkTimer.restart(); if (cfg.sideTab === "outline") outlineTimer.restart(); }
                        }
                    }
                    // смена вкладки: редактор слегка выезжает
                    ParallelAnimation {
                        id: switchFx
                        NumberAnimation { target: edArea; property: "opacity"; from: 0.35; to: 1; duration: 180 }
                        NumberAnimation { target: edShift; property: "x"; from: 14; to: 0; duration: 220; easing.type: Easing.OutCubic }
                    }
                    transform: Translate { id: edShift }

                    // ── приветствие, когда ничего не открыто ──
                    Item {
                        anchors.fill: parent
                        visible: docs.count === 0
                        Column {
                            anchors.centerIn: parent; spacing: 18; width: Math.min(parent.width - 60, 640)
                            Text {
                                width: parent.width; horizontalAlignment: Text.AlignHCenter
                                font.family: win.mono; font.pixelSize: 44; font.bold: true; textFormat: Text.StyledText; color: pal.dim
                                text: "<font color='" + pal.acc + "'>D3R</font> // code"
                            }
                            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; font.family: win.mono; font.pixelSize: cfg.uiSize; color: pal.faint
                                   text: "let's all love lain · c++ · python" }
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter; spacing: 10; topPadding: 10
                                Btn { label: "\u{E61D}  проект C++"; accent: true; onClicked: newProj.show("cpp") }
                                Btn { label: "\u{F0320}  проект Python"; accent: true; onClicked: newProj.show("python") }
                                Btn { label: "󰉋  папка"; onClicked: folderDlg.open() }
                                Btn { label: "󰈔  файл"; onClicked: openDlg.open() }
                            }
                            Text { visible: JSON.parse(cfg.recent).length > 0; topPadding: 14; font.family: win.mono; font.pixelSize: cfg.uiSize - 1; color: pal.dim; text: "› недавние проекты" }
                            Column {
                                width: parent.width; spacing: 2
                                Repeater {
                                    model: JSON.parse(cfg.recent)
                                    Rectangle {
                                        required property string modelData
                                        width: parent.width; height: 28; radius: 6
                                        color: rcm.containsMouse ? Qt.alpha(pal.head, 0.9) : "transparent"
                                        Text { x: 12; anchors.verticalCenter: parent.verticalCenter; font.family: win.mono; font.pixelSize: cfg.uiSize
                                               textFormat: Text.StyledText; color: pal.text
                                               text: "<font color='" + pal.acc + "'>󰉋</font>  " + win.baseName(parent.modelData) + "  <font color='" + pal.faint + "'>" + win.short(parent.modelData) + "</font>" }
                                        MouseArea { id: rcm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.openProject(parent.modelData) }
                                    }
                                }
                            }
                            Text { topPadding: 10; width: parent.width; horizontalAlignment: Text.AlignHCenter; font.family: win.mono; font.pixelSize: cfg.uiSize - 2; color: pal.faint
                                   text: "F1 — все клавиши · Ctrl+P — найти файл · F5 — запустить" }
                        }
                    }
                }

                // ── поиск и замена ──
                Rectangle {
                    id: findBar
                    property bool open: false
                    property bool repl: false
                    function show(r) {
                        if (!win.curEd) return;
                        win.curEd.unfoldAll();   // искать и в свёрнутом
                        repl = r; open = true;
                        if (win.curEd.selLen > 0 && win.curEd.area.selectedText.indexOf("\n") < 0) findField.input.text = win.curEd.area.selectedText;
                        findField.input.forceActiveFocus(); findField.input.selectAll();
                    }
                    anchors.right: parent.right; anchors.rightMargin: 18
                    y: open ? 8 : -height - 10
                    Behavior on y { NumberAnimation { duration: cfg.anim ? 200 : 0; easing.type: Easing.OutCubic } }
                    width: 470; height: repl ? 84 : 46; radius: 9; z: 40
                    Behavior on height { NumberAnimation { duration: cfg.anim ? 150 : 0 } }
                    color: Qt.alpha(pal.bg, 0.98); border.width: 1; border.color: Qt.alpha(pal.acc, 0.5)
                    clip: true
                    Field {
                        id: findField
                        x: 8; y: 8; width: parent.width - 170; hint: "найти"
                        onChanged: t => { if (win.curEd) win.curEd.query = t; }
                        onAccepted: if (win.curEd) win.curEd.findNext(false)
                        onShiftEnter: if (win.curEd) win.curEd.findNext(true)
                    }
                    Text {
                        x: findField.x + findField.width + 8; y: 8; height: 30; verticalAlignment: Text.AlignVCenter
                        font.family: win.mono; font.pixelSize: cfg.uiSize - 2; color: win.curEd && win.curEd.query && !win.curEd.matches.length ? win.red : pal.dim
                        text: !win.curEd || !win.curEd.query ? "" : win.curEd.matches.length ? (win.curEd.matchIndex + 1 || "–") + "/" + win.curEd.matches.length : "нет"
                    }
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: 6; y: 11; spacing: 1
                        HeadBtn { glyph: "Aa"; on: !!win.curEd && win.curEd.matchCase; tip: "учитывать регистр"; onClicked: win.curEd.matchCase = !win.curEd.matchCase }
                        HeadBtn { glyph: "↑"; tip: "назад · Shift+Enter"; onClicked: win.curEd.findNext(true) }
                        HeadBtn { glyph: "↓"; tip: "дальше · Enter"; onClicked: win.curEd.findNext(false) }
                        HeadBtn { glyph: "✕"; onClicked: win.closePopups() }
                    }
                    Field { id: replField; x: 8; y: 46; width: parent.width - 170; hint: "заменить на"; visible: findBar.repl
                            onAccepted: win.curEd.replaceOne(input.text) }
                    Row {
                        visible: findBar.repl; anchors.right: parent.right; anchors.rightMargin: 8; y: 46; spacing: 4
                        Btn { label: "1"; height: 30; onClicked: win.curEd.replaceOne(replField.input.text) }
                        Btn { label: "все"; height: 30; onClicked: { const n = win.curEd.replaceAll(replField.input.text); win.toast("заменено: " + n, "info"); } }
                    }
                }

                // ── консоль снизу: вывод программы и сборки, внизу — строка ввода (в программу или команда cmd) ──
                Item {
                    id: termPanel
                    property bool open: false
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: open ? cfg.termH : 0
                    clip: true
                    Behavior on height { enabled: cfg.anim && !termDrag.pressed; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Rectangle { width: parent.width; height: 1; color: Qt.alpha(pal.acc, 0.3) }
                    Rectangle { y: 1; width: parent.width; height: parent.height - 1; color: Qt.alpha(pal.bg, 0.6) }
                    Text {
                        x: 14; y: 6; font.family: win.mono; font.pixelSize: cfg.uiSize - 2; textFormat: Text.StyledText; color: pal.dim
                        text: "<b><font color='" + pal.acc + "'>CONSOLE</font></b> // " + win.short(con.cwd) + (con.busy ? "<font color='" + win.green + "'>   ● работает</font>" : "") +
                              "<font color='" + pal.faint + "'>   · Ctrl+клик по ошибке — к строке</font>"
                    }
                    Row {
                        anchors.right: parent.right; anchors.rightMargin: 8; y: 2; spacing: 2
                        HeadBtn { glyph: "\u{F04DB}"; tint: win.red; visible: con.busy; tip: "стоп · Shift+F5"; onClicked: win.stop() }
                        HeadBtn { glyph: "󰆏"; tip: "копировать всё"; onClicked: win.copyText(conText.text) }
                        HeadBtn { glyph: "󰃢"; tip: "очистить"; onClicked: con.clear() }
                        HeadBtn { glyph: "✕"; tip: "скрыть · Ctrl+J"; onClicked: { termPanel.open = false; win.focusEd(); } }
                    }
                    Flickable {
                        id: conFlick
                        x: 12; y: 28; width: parent.width - 20; height: cfg.termH - 28 - 40
                        clip: true; contentHeight: conText.height; boundsBehavior: Flickable.StopAtBounds
                        TextEdit {
                            id: conText
                            width: conFlick.width
                            readOnly: true; selectByMouse: true; wrapMode: TextEdit.WrapAnywhere; textFormat: TextEdit.PlainText
                            font.family: win.mono; font.pixelSize: Math.max(10, cfg.fontSize - 2); color: pal.text
                            selectionColor: pal.sel; selectedTextColor: pal.text
                            TapHandler {
                                acceptedModifiers: Qt.ControlModifier
                                onTapped: ev => {
                                    const pos = conText.positionAt(ev.position.x, ev.position.y), t = conText.text;
                                    win.openFromTerm(t.slice(t.lastIndexOf("\n", pos - 1) + 1, (t.indexOf("\n", pos) + 1 || t.length + 1) - 1));
                                }
                            }
                        }
                        WheelHandler { onWheel: ev => conFlick.flick(0, ev.angleDelta.y * 8) }
                    }
                    Field {
                        id: conInput
                        x: 8; width: parent.width - 16; y: cfg.termH - 36; height: 28
                        hint: con.busy ? "ввод для программы · Enter — отправить" : "команда (cmd): dir, git status, pip install … · Enter"
                        property var hist: []
                        property int hi: 0
                        onAccepted: {
                            const t = input.text;
                            if (!con.busy && t.trim()) { hist = hist.filter(x => x !== t).concat([t]).slice(-50); }
                            hi = hist.length;
                            input.text = "";
                            con.command(t);
                        }
                        onUpPressed: if (!con.busy && hi > 0) input.text = hist[--hi]
                        onDownPressed: if (!con.busy) { hi = Math.min(hist.length, hi + 1); input.text = hist[hi] || ""; }
                        Keys.onPressed: e => { if ((e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_J) { termPanel.open = false; win.focusEd(); e.accepted = true; } }
                    }
                }
                MouseArea {   // высоту консоли можно тянуть
                    id: termDrag
                    anchors.bottom: termPanel.top; anchors.bottomMargin: -3; width: parent.width; height: 6
                    visible: termPanel.open; cursorShape: Qt.SizeVerCursor
                    onPositionChanged: m => { if (pressed) cfg.termH = Math.max(100, Math.min(work.height - 120, work.height - mapToItem(work, 0, m.y).y)); }
                }
            }
        }

        // ── строка состояния ──
        Rectangle {
            id: status
            anchors.bottom: parent.bottom; width: parent.width; height: 28
            color: Qt.alpha(pal.panel, 0.7)
            Rectangle { width: parent.width; height: 1; color: Qt.alpha(pal.acc, 0.25) }
            readonly property var e: win.curEd
            readonly property int errs: e ? e.diags.filter(d => d.sev === "error").length : 0
            readonly property int warns: e ? e.diags.length - errs : 0
            readonly property var here: e ? e.diagAt[e.curLine] : null
            Row {
                x: 12; height: parent.height; spacing: 16
                Repeater {
                    model: status.e ? [
                        ["<font color='" + pal.acc + "'>" + (status.e.lang === "cpp" ? "\u{E61D} C++" : status.e.lang === "python" ? "\u{F0320} Python" : "\u{F0219} text") + "</font>", null],
                        ["Ln <font color='" + pal.light + "'>" + status.e.curLine + "</font>, Col <font color='" + pal.light + "'>" + status.e.curCol + "</font>", () => gotoBox.open = true],
                        ["строк <font color='" + pal.light + "'>" + status.e.lineCount + "</font>", null],
                        ["символов <font color='" + pal.light + "'>" + status.e.text.length.toLocaleString(Qt.locale("ru_RU"), "f", 0) + "</font>", null],
                        status.e.selLen ? ["выделено <font color='" + pal.light + "'>" + status.e.selLen + "</font>", null] : null,
                        cfg.liveCheck && (status.e.lang === "cpp" || status.e.lang === "python")
                            ? [(status.errs ? "<font color='" + win.red + "'>✕ " + status.errs + "</font>" : "<font color='" + pal.faint + "'>✕ 0</font>") + "  " +
                               (status.warns ? "<font color='" + win.yellow + "'>⚠ " + status.warns + "</font>" : "<font color='" + pal.faint + "'>⚠ 0</font>"), () => win.nextProblem()] : null
                    ].filter(x => x) : [["<font color='" + pal.faint + "'>нет открытых файлов</font>", null]]
                    Text {
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: win.mono; font.pixelSize: cfg.uiSize - 1; color: pal.dim; textFormat: Text.StyledText
                        text: modelData[0]
                        MouseArea { anchors.fill: parent; enabled: !!parent.modelData[1]; cursorShape: Qt.PointingHandCursor; onClicked: parent.modelData[1]() }
                    }
                }
                Text {   // сообщение компилятора для текущей строки
                    visible: !!status.here
                    anchors.verticalCenter: parent.verticalCenter; width: Math.max(0, status.width - x - rightInfo.width - 40); elide: Text.ElideRight
                    font.family: win.mono; font.pixelSize: cfg.uiSize - 1
                    color: status.here && status.here.sev === "error" ? win.red : win.yellow
                    text: status.here ? "› " + status.here.msg : ""
                }
            }
            Row {
                id: rightInfo
                anchors.right: parent.right; anchors.rightMargin: 14; height: parent.height; spacing: 16
                Text { id: savedTxt; anchors.verticalCenter: parent.verticalCenter; font.family: win.mono; font.pixelSize: cfg.uiSize - 1; color: pal.light; text: "✓ сохранено"; opacity: 0 }
                Text { anchors.verticalCenter: parent.verticalCenter; font.family: win.mono; font.pixelSize: cfg.uiSize - 1; color: pal.faint
                       text: (status.e && win.canComplete(status.e.lang) ? (status.e.lang === "cpp" ? "clangd" : "jedi") + " ● · " : "") + "пробелы: " + cfg.tabWidth + " · UTF-8 · " + cfg.std }
            }
            SequentialAnimation {
                id: savedFx
                NumberAnimation { target: savedTxt; property: "opacity"; to: 1; duration: 120 }
                PauseAnimation { duration: 900 }
                NumberAnimation { target: savedTxt; property: "opacity"; to: 0; duration: 500 }
            }
        }

        Canvas {   // строки развёртки, как во всех D3R-окнах (рисуются один раз)
            anchors.fill: parent; z: 30; visible: cfg.scanlines
            onPaint: { const g = getContext("2d"); g.reset(); g.fillStyle = Qt.rgba(0, 0, 0, 0.09); for (let y = 0; y < height; y += 3) g.fillRect(0, y, width, 1); }
            onHeightChanged: requestPaint()
        }

        // ══════ всплывающие панели ══════
        MouseArea {   // клик мимо панели — закрыть
            anchors.fill: parent; z: 45
            enabled: setMenu.open || themeMenu.open || quick.open || gotoBox.open || help.open || newProj.open || menu.open || searchBox.open || ioBox.open
            onClicked: win.closePopups()
        }

        Pop {   // тема
            id: themeMenu
            x: Math.min(parent.width - width - 10, winBtns.x + themeBtn.x - 120); y: bar.height + 4
            width: 260; height: 64 + T.list.length * 34
            Column {
                width: parent.width; spacing: 4
                Text { font.family: win.mono; font.pixelSize: cfg.uiSize - 1; color: pal.dim; text: "› тема редактора"; bottomPadding: 4 }
                Repeater {
                    model: T.list
                    Rectangle {
                        required property var modelData
                        readonly property bool on: cfg.theme === modelData.id
                        width: parent.width; height: 30; radius: 6
                        color: on ? Qt.alpha(pal.sel, 0.45) : thm.containsMouse ? Qt.alpha(pal.head, 0.9) : "transparent"
                        Rectangle { x: 8; anchors.verticalCenter: parent.verticalCenter; width: 16; height: 16; radius: 8; color: parent.modelData.bg
                                    border.width: 3; border.color: parent.modelData.acc }
                        Text { x: 34; anchors.verticalCenter: parent.verticalCenter; font.family: win.mono; font.pixelSize: cfg.uiSize
                               color: parent.on ? pal.light : pal.text; text: parent.modelData.name }
                        MouseArea { id: thm; anchors.fill: parent; hoverEnabled: true; onClicked: cfg.theme = parent.modelData.id }
                    }
                }
            }
        }

        Pop {   // настройки
            id: setMenu
            x: Math.min(parent.width - width - 10, winBtns.x + setBtn.x - 200); y: bar.height + 4
            width: 380; height: setCol.implicitHeight + 28
            Column {
                id: setCol
                width: parent.width
                Text { font.family: win.mono; font.pixelSize: cfg.uiSize - 1; color: pal.dim; text: "› вид"; bottomPadding: 4 }
                Row2 { label: "шрифт кода" }
                Flow {   // установленные шрифты для кода, каждый — своим начертанием
                    width: parent.width; spacing: 4; bottomPadding: 6
                    Repeater {
                        model: win.codeFonts
                        Rectangle {
                            required property var modelData
                            readonly property bool on: cfg.font === modelData[0]
                            width: fl.implicitWidth + 14; height: 24; radius: 4
                            color: on ? Qt.alpha(pal.sel, 0.6) : fm.containsMouse ? Qt.alpha(pal.btn, 0.9) : Qt.alpha(pal.head, 0.9)
                            border.width: 1; border.color: Qt.alpha(pal.acc, on ? 0.7 : 0.25)
                            Text { id: fl; anchors.centerIn: parent; font.family: parent.modelData[0]; font.pixelSize: cfg.uiSize - 1; color: parent.on ? pal.light : pal.text; text: parent.modelData[1] }
                            MouseArea { id: fm; anchors.fill: parent; hoverEnabled: true; onClicked: cfg.font = parent.modelData[0] }
                        }
                    }
                }
                Row2 { label: "размер кода"; Stepper { value: cfg.fontSize; from: 9; to: 32; suffix: "px"; onMoved: v => cfg.fontSize = v } }
                Row2 { label: "размер интерфейса"; Stepper { value: cfg.uiSize; from: 10; to: 18; suffix: "px"; onMoved: v => cfg.uiSize = v } }
                Row2 { label: "непрозрачность"; Stepper { value: Math.round(cfg.opacity * 100); from: 60; to: 100; suffix: "%"; onMoved: v => cfg.opacity = v / 100 } }
                Row2 { label: "номера строк"; Toggle { checked: cfg.lineNumbers; onToggled: v => cfg.lineNumbers = v } }
                Row2 { label: "подсветка строки"; Toggle { checked: cfg.curLine; onToggled: v => cfg.curLine = v } }
                Row2 { label: "перенос длинных строк"; Toggle { checked: cfg.wrap; onToggled: v => cfg.wrap = v } }
                Row2 { label: "анимации"; Toggle { checked: cfg.anim; onToggled: v => cfg.anim = v } }
                Row2 { label: "строки развёртки"; Toggle { checked: cfg.scanlines; onToggled: v => cfg.scanlines = v } }
                Text { font.family: win.mono; font.pixelSize: cfg.uiSize - 1; color: pal.dim; text: "› код"; topPadding: 8; bottomPadding: 4 }
                Row2 { label: "отступ"; Chips { value: cfg.tabWidth; options: [[2, "2"], [4, "4"], [8, "8"]]; onPicked: v => cfg.tabWidth = v } }
                Row2 { label: "стандарт C++"; Chips { value: cfg.std; options: [["c++17", "17"], ["c++20", "20"], ["c++23", "23"]]; onPicked: v => { cfg.std = v; win.check(win.curEd); } } }
                Row2 { label: "закрывать скобки и кавычки"; Toggle { checked: cfg.autoClose; onToggled: v => cfg.autoClose = v } }
                Row2 { label: "автосохранение"; Toggle { checked: cfg.autoSave; onToggled: v => cfg.autoSave = v } }
                Row2 { label: "автодополнение (clangd / jedi)"; Toggle { checked: cfg.complete; onToggled: v => cfg.complete = v } }
                Row2 { label: "ошибки на лету"; Toggle { checked: cfg.liveCheck; onToggled: v => { cfg.liveCheck = v; win.check(win.curEd); } } }
                Row2 { label: "скрытые файлы в проекте"; Toggle { checked: cfg.hidden; onToggled: v => cfg.hidden = v } }
                Item { width: 1; height: 6 }
                Item {
                    width: parent.width; height: 24
                    Text { anchors.verticalCenter: parent.verticalCenter; font.family: win.mono; font.pixelSize: cfg.uiSize - 1; color: pal.dim; text: "› инструменты" }
                    Btn { anchors.right: parent.right; height: 24; label: "обновить"; onClicked: win.refreshTools() }
                }
                Repeater {
                    model: [["g++", win.tools.gpp], ["clangd", win.tools.clangd], ["clang-format", win.tools.clangFormat], ["cmake", win.tools.cmake], ["python", win.tools.python]]
                    Text {
                        required property var modelData
                        width: parent.width; elide: Text.ElideMiddle; font.family: win.mono; font.pixelSize: cfg.uiSize - 2
                        color: modelData[1] ? pal.text : win.red
                        text: (modelData[1] ? "✓ " : "✕ ") + modelData[0].padEnd(13) + (modelData[1] || "не найден")
                    }
                }
                Text {
                    visible: !win.tools.gpp || !win.tools.clangd
                    width: parent.width; wrapMode: Text.WrapAnywhere; font.family: win.mono; font.pixelSize: cfg.uiSize - 2; color: pal.dim
                    text: "компилятор и clangd одной командой:\n" + win.installHint
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: win.copyText(win.installHint) }
                }
            }
        }

        Pop {   // быстрый переход к файлу
            id: quick
            anchors.horizontalCenter: parent.horizontalCenter; y: bar.height + 30
            width: Math.min(640, parent.width - 80); height: 420
            Field { id: quickField; width: parent.width; hint: "файл в проекте…"
                    onAccepted: { const r = quickList.model[quickList.currentIndex]; if (r) { win.openFile(cfg.project + "/" + r); quick.open = false; } }
                    onDownPressed: quickList.incrementCurrentIndex()
                    onUpPressed: quickList.decrementCurrentIndex() }
            ListView {
                id: quickList
                y: 40; width: parent.width; height: parent.height - 40; clip: true
                highlightMoveDuration: 80
                model: { const q = quickField.input.text; if (!q) return win.allFiles.slice(0, 200);
                         return win.allFiles.map(f => [win.fuzzy(q, f), f]).filter(x => x[0] >= 0).sort((a, b) => a[0] - b[0]).slice(0, 200).map(x => x[1]); }
                onModelChanged: currentIndex = 0
                highlight: Rectangle { radius: 6; color: Qt.alpha(pal.sel, 0.4); Rectangle { width: 2; height: parent.height; color: pal.acc } }
                delegate: Item {
                    required property string modelData
                    required property int index
                    width: quickList.width; height: 28
                    Text { x: 10; anchors.verticalCenter: parent.verticalCenter; font.family: win.mono; font.pixelSize: cfg.uiSize; textFormat: Text.StyledText
                           color: pal.text
                           text: "<font color='" + win.iconColor(win.baseName(parent.modelData)) + "'>" + win.iconFor(win.baseName(parent.modelData)) + "</font>  " +
                                 win.baseName(parent.modelData) + "  <font color='" + pal.faint + "'>" + parent.modelData + "</font>" }
                    MouseArea { anchors.fill: parent; onClicked: { win.openFile(cfg.project + "/" + parent.modelData); quick.open = false; } }
                }
            }
        }

        Pop {   // к строке
            id: gotoBox
            anchors.horizontalCenter: parent.horizontalCenter; y: bar.height + 30
            width: 320; height: 64
            Field { id: gotoField; width: parent.width; hint: win.curEd ? "строка 1–" + win.curEd.lineCount + " (или строка:столбец)" : ""
                    onAccepted: { const m = input.text.match(/(\d+)(?::(\d+))?/); if (m && win.curEd) win.curEd.gotoLine(+m[1], +(m[2] || 1)); gotoBox.open = false; } }
        }

        Pop {   // новый проект
            id: newProj
            property string kind: "cpp"
            function show(k) { kind = k || kind; open = true; projName.input.text = ""; projWhere.input.text = "~/Projects"; projName.input.forceActiveFocus(); }
            anchors.centerIn: parent
            width: 440; height: 250
            Column {
                width: parent.width; spacing: 10
                Text { font.family: win.mono; font.pixelSize: cfg.uiSize + 1; font.bold: true; color: pal.light; text: "новый проект" }
                Row2 { label: "язык"; Chips { value: newProj.kind; options: [["cpp", "\u{E61D} C++ (CMake)"], ["python", "\u{F0320} Python"]]; onPicked: v => newProj.kind = v } }
                Field { id: projName; width: parent.width; hint: "имя, например hello"; onAccepted: win.createProject(input.text, newProj.kind, projWhere.input.text) }
                Field { id: projWhere; width: parent.width; hint: "где создать" }
                Row {
                    anchors.right: parent.right; spacing: 8
                    Btn { label: "отмена"; onClicked: newProj.open = false }
                    Btn { label: "создать"; accent: true; onClicked: win.createProject(projName.input.text, newProj.kind, projWhere.input.text) }
                }
            }
        }

        Pop {   // клавиши
            id: help
            anchors.centerIn: parent
            width: Math.min(parent.width - 60, 1000); height: Math.min(parent.height - 60, 640)
            Text { font.family: win.mono; font.pixelSize: cfg.uiSize + 1; font.bold: true; color: pal.light; text: "клавиши" }
            Flow {
                y: 34; width: parent.width; height: parent.height - 34; flow: Flow.TopToBottom; spacing: 2
                Repeater {
                    model: [
                        ["Ctrl+N", "новый файл"], ["Ctrl+O", "открыть файл"], ["Ctrl+Shift+O", "открыть папку"], ["Ctrl+Shift+N", "новый проект"],
                        ["Ctrl+S", "сохранить"], ["Ctrl+Shift+S", "сохранить как"], ["Ctrl+W", "закрыть вкладку"], ["Ctrl+Tab", "следующая вкладка"],
                        ["Alt+1..9", "вкладка по номеру"], ["Ctrl+P", "найти файл в проекте"], ["Ctrl+G", "перейти к строке"], ["Ctrl+F / Ctrl+H", "поиск / замена"],
                        ["F3 / Shift+F3", "следующее / предыдущее"], ["F5", "запустить"], ["Ctrl+Shift+B", "собрать"], ["Shift+F5", "остановить"],
                        ["F8", "следующая ошибка"], ["Ctrl+J", "консоль"], ["Ctrl+B", "панель проекта"],
                        ["Ctrl+Shift+F", "поиск по проекту"], ["Ctrl+Shift+R", "ввод и аргументы запуска"], ["Ctrl+Shift+E", "структура файла"],
                        ["F12 / Ctrl+клик", "к определению"], ["F2", "переименовать везде"], ["Shift+Alt+F", "форматировать"],
                        ["F9 / Ctrl+F9", "свернуть блок / всё"], ["Shift+F9", "развернуть всё"], ["Ctrl+D", "ещё курсор: то же слово"], ["Alt+клик", "ещё курсор"],
                        ["слово + Tab", "шаблон: for, if, main, cout…"], ["Ctrl+Shift+Space", "подсказка параметров"],
                        ["Ctrl+/", "закомментировать"], ["Ctrl+Shift+D", "дублировать строку"], ["Ctrl+Shift+K", "удалить строку"], ["Alt+↑ / ↓", "двигать строки"],
                        ["Ctrl+L", "выделить строку"], ["Tab / Shift+Tab", "отступ / убрать"], ["Ctrl+] / [", "отступ строк"], ["Ctrl+Enter", "новая строка ниже"],
                        ["Ctrl+Z / Ctrl+Y", "отменить / вернуть"], ["Ctrl+Space", "автодополнение"], ["Home", "к началу кода"], ["Ctrl+= / − / 0", "размер шрифта"], ["Ctrl+колесо", "размер шрифта"],
                        ["Ctrl+,", "настройки"], ["F11", "полный экран"], ["Esc", "закрыть панель"]
                    ]
                    Item {
                        required property var modelData
                        width: (help.width - 40) / 2; height: 24
                        Text { width: 170; anchors.verticalCenter: parent.verticalCenter; font.family: win.mono; font.pixelSize: cfg.uiSize - 1; color: pal.acc; text: parent.modelData[0] }
                        Text { x: 176; anchors.verticalCenter: parent.verticalCenter; font.family: win.mono; font.pixelSize: cfg.uiSize - 1; color: pal.text; text: parent.modelData[1] }
                    }
                }
            }
        }

        Pop {   // поиск по проекту
            id: searchBox
            function show() { open = true; searchField.input.forceActiveFocus(); searchField.input.selectAll();
                              const e = win.curEd; if (e && e.selLen > 0 && e.area.selectedText.indexOf("\n") < 0) searchField.input.text = e.area.selectedText; }
            anchors.horizontalCenter: parent.horizontalCenter; y: bar.height + 30
            width: Math.min(820, parent.width - 80); height: Math.min(520, parent.height - 90)
            Field { id: searchField; width: parent.width; hint: "текст во всех файлах " + win.short(win.searchRoot) + "…"
                    onChanged: searchTimer.restart()
                    onAccepted: { const h = win.hits[hitList.currentIndex]; if (h) win.openHit(h); }
                    onDownPressed: hitList.incrementCurrentIndex()
                    onUpPressed: hitList.decrementCurrentIndex() }
            Text { y: 36; font.family: win.mono; font.pixelSize: cfg.uiSize - 2; color: pal.faint
                   text: !win.hitsFor ? "" : win.hits.length ? "найдено: " + win.hits.length + (win.hits.length >= 400 ? "+" : "") + " · Enter — открыть" : "ничего не нашлось" }
            ListView {
                id: hitList
                y: 56; width: parent.width; height: parent.height - 56; clip: true
                highlightMoveDuration: 80
                model: win.hits
                onModelChanged: currentIndex = 0
                highlight: Rectangle { radius: 6; color: Qt.alpha(pal.sel, 0.4); Rectangle { width: 2; height: parent.height; color: pal.acc } }
                section.property: "file"
                section.delegate: Text { required property string section; topPadding: 6; leftPadding: 6; font.family: win.mono; font.pixelSize: cfg.uiSize - 1
                                         textFormat: Text.StyledText; color: pal.light
                                         text: "<font color='" + win.iconColor(win.baseName(section)) + "'>" + win.iconFor(win.baseName(section)) + "</font>  " + section }
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: hitList.width; height: 24
                    Text { x: 22; width: 50; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight
                           font.family: win.mono; font.pixelSize: cfg.uiSize - 2; color: pal.faint; text: parent.modelData.line }
                    Text {
                        x: 82; width: parent.width - 90; anchors.verticalCenter: parent.verticalCenter; elide: Text.ElideRight
                        font.family: win.mono; font.pixelSize: cfg.uiSize - 1; textFormat: Text.StyledText; color: pal.text
                        function esc(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
                        text: { const t = parent.modelData.text, q = win.hitsFor, i = t.toLowerCase().indexOf(q.toLowerCase());
                                return i < 0 ? esc(t) : esc(t.slice(0, i)) + "<b><font color='" + pal.light + "'>" + esc(t.slice(i, i + q.length)) + "</font></b>" + esc(t.slice(i + q.length)); }
                    }
                    MouseArea { anchors.fill: parent; onClicked: win.openHit(parent.modelData) }
                }
            }
        }

        Pop {   // ввод и аргументы запуска
            id: ioBox
            property string key: ""
            function show() {
                const e = win.curEd;
                if (!e || !e.path) { win.toast("сначала открой и сохрани файл с программой", "warn"); return; }
                key = win.runKey(e);
                const io = win.ioFor(key);
                ioInput.text = io.input; ioArgs.input.text = io.args; ioOn.checked = io.on;
                open = true; ioInput.forceActiveFocus();
            }
            function store() { win.setIO(key, { input: ioInput.text, args: ioArgs.input.text.trim(), on: ioOn.checked }); }
            anchors.centerIn: parent
            width: Math.min(560, parent.width - 60); height: Math.min(470, parent.height - 60)
            Text { font.family: win.mono; font.pixelSize: cfg.uiSize + 1; font.bold: true; color: pal.light
                   text: "ввод и аргументы · " + (ioBox.key === cfg.project ? win.baseName(cfg.project) + " (cmake)" : win.baseName(ioBox.key)) }
            Text { y: 24; width: parent.width; wrapMode: Text.Wrap; font.family: win.mono; font.pixelSize: cfg.uiSize - 2; color: pal.faint
                   text: "Этот текст подаётся программе вместо набора с клавиатуры (std::cin, input()) при каждом запуске F5." }
            Row2 { y: 62; label: "подавать ввод при запуске"; Toggle { id: ioOn; onToggled: v => { checked = v; ioBox.store(); } } }
            Rectangle {
                y: 98; width: parent.width; height: parent.height - y - 120; radius: 6
                color: Qt.alpha(pal.head, 0.9); border.width: 1; border.color: Qt.alpha(pal.acc, ioInput.activeFocus ? 0.75 : 0.25)
                Flickable {
                    id: ioFlick
                    anchors.fill: parent; anchors.margins: 8; clip: true
                    contentHeight: ioInput.implicitHeight; boundsBehavior: Flickable.StopAtBounds
                    TextEdit {
                        id: ioInput
                        width: ioFlick.width; font.family: cfg.font; font.pixelSize: cfg.fontSize - 1; color: pal.text
                        selectionColor: pal.sel; selectedTextColor: pal.text; selectByMouse: true
                        onTextChanged: if (ioBox.open) ioBox.store()
                        onCursorRectangleChanged: { if (cursorRectangle.y < ioFlick.contentY) ioFlick.contentY = cursorRectangle.y;
                                                    else if (cursorRectangle.y + cursorRectangle.height > ioFlick.contentY + ioFlick.height) ioFlick.contentY = cursorRectangle.y + cursorRectangle.height - ioFlick.height; }
                        Keys.onEscapePressed: win.closePopups()
                        Text { visible: !ioInput.text; font: ioInput.font; color: pal.faint; text: "5\n1 2 3 4 5" }
                    }
                }
            }
            Text { y: parent.height - 112; font.family: win.mono; font.pixelSize: cfg.uiSize - 1; color: pal.dim; text: "› аргументы командной строки (argv)" }
            Field { id: ioArgs; y: parent.height - 88; width: parent.width; hint: "например: data.txt --fast"; onChanged: if (ioBox.open) ioBox.store() }
            Row {
                anchors.right: parent.right; anchors.bottom: parent.bottom; spacing: 8
                Btn { label: "очистить"; onClicked: { ioInput.text = ""; ioArgs.input.text = ""; } }
                Btn { label: "запустить · F5"; accent: true; onClicked: { win.closePopups(); win.run(false); } }
            }
        }

        Pop {   // контекстное меню
            id: menu
            property var items: []
            function show(pos, l) { items = l; x = Math.min(body.width - width - 8, pos.x); y = Math.min(body.height - height - 8, pos.y); open = true; }
            width: 230; height: items.length * 30 + 28
            Column {
                width: parent.width
                Repeater {
                    model: menu.items
                    Rectangle {
                        required property var modelData
                        width: parent.width; height: 30; radius: 5
                        color: mim.containsMouse ? Qt.alpha(pal.sel, 0.45) : "transparent"
                        Text { x: 8; anchors.verticalCenter: parent.verticalCenter; font.family: win.mono; font.pixelSize: cfg.uiSize; color: pal.text; text: parent.modelData[0] }
                        MouseArea { id: mim; anchors.fill: parent; hoverEnabled: true; onClicked: { menu.open = false; parent.modelData[1](); } }
                    }
                }
            }
        }

        Pop {   // вопрос: сохранить? удалить?
            open: !!win.askData
            anchors.centerIn: parent; z: 60
            width: 420; height: 150
            Column {
                width: parent.width; spacing: 8
                Text { width: parent.width; wrapMode: Text.Wrap; font.family: win.mono; font.pixelSize: cfg.uiSize + 1; font.bold: true; color: pal.light; text: win.askData ? win.askData.title : "" }
                Text { width: parent.width; wrapMode: Text.Wrap; font.family: win.mono; font.pixelSize: cfg.uiSize - 1; color: pal.dim; text: win.askData ? win.askData.text : "" }
            }
            Row {
                anchors.right: parent.right; anchors.bottom: parent.bottom; spacing: 8
                Repeater {
                    model: win.askData ? win.askData.buttons : []
                    Btn { required property var modelData; label: modelData[0]; accent: !!modelData[2]
                          onClicked: { const f = modelData[1]; win.askData = null; f(); } }
                }
            }
        }

        Pop {   // ввод имени
            open: !!win.promptData
            anchors.centerIn: parent; z: 60
            width: 420; height: 120
            Text { font.family: win.mono; font.pixelSize: cfg.uiSize; color: pal.dim; text: win.promptData ? win.promptData.title : "" }
            Field {
                id: promptField
                y: 28; width: parent.width
                onAccepted: { const d = win.promptData, v = input.text.trim(); win.promptData = null; if (v && d) d.cb(v); win.focusEd(); }
            }
        }

        Rectangle {   // всплывающее сообщение снизу
            id: toastBox
            property string msg
            property string kind: "info"
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height; z: 70
            width: tmsg.implicitWidth + 30; height: 34; radius: 8
            color: Qt.alpha(pal.bg, 0.98)
            border.width: 1; border.color: kind === "error" ? win.red : kind === "warn" ? win.yellow : Qt.alpha(pal.acc, 0.6)
            Text { id: tmsg; anchors.centerIn: parent; font.family: win.mono; font.pixelSize: cfg.uiSize; color: toastBox.kind === "error" ? win.red : pal.text; text: toastBox.msg }
            SequentialAnimation {
                id: toastFx
                NumberAnimation { target: toastBox; property: "y"; to: body.height - status.height - 50; duration: cfg.anim ? 220 : 0; easing.type: Easing.OutBack }
                PauseAnimation { duration: 2600 }
                NumberAnimation { target: toastBox; property: "y"; to: body.height; duration: cfg.anim ? 200 : 0; easing.type: Easing.InCubic }
            }
        }
    }

    // края окна — тянуть размер
    Repeater {
        model: [
            { e: Qt.LeftEdge, x: 0, y: 8, w: 6, h: -16, c: Qt.SizeHorCursor }, { e: Qt.RightEdge, x: -6, y: 8, w: 6, h: -16, c: Qt.SizeHorCursor },
            { e: Qt.BottomEdge, x: 8, y: -6, w: -16, h: 6, c: Qt.SizeVerCursor }, { e: Qt.TopEdge, x: 8, y: 0, w: -16, h: 4, c: Qt.SizeVerCursor },
            { e: Qt.LeftEdge | Qt.BottomEdge, x: 0, y: -10, w: 10, h: 10, c: Qt.SizeBDiagCursor }, { e: Qt.RightEdge | Qt.BottomEdge, x: -10, y: -10, w: 10, h: 10, c: Qt.SizeFDiagCursor },
            { e: Qt.LeftEdge | Qt.TopEdge, x: 0, y: 0, w: 10, h: 10, c: Qt.SizeFDiagCursor }, { e: Qt.RightEdge | Qt.TopEdge, x: -10, y: 0, w: 10, h: 10, c: Qt.SizeBDiagCursor }
        ]
        MouseArea {
            required property var modelData
            enabled: !win.maxed
            x: modelData.x < 0 ? win.width + modelData.x : modelData.x; y: modelData.y < 0 ? win.height + modelData.y : modelData.y
            width: modelData.w < 0 ? win.width + modelData.w : modelData.w; height: modelData.h < 0 ? win.height + modelData.h : modelData.h
            cursorShape: modelData.c
            onPressed: win.startSystemResize(modelData.e)
        }
    }
}
