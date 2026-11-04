// Один открытый файл в D3R Code: текст с подсветкой (Highlighter из C++, цвета Visual Studio), номера строк, текущая строка,
// парные скобки, поиск, ошибки компилятора на полях. Правки кода (отступы, комментарии, перенос строк) — функции ниже,
// их зовут хоткеи из Code.qml; набор (Tab, Enter, скобки, Backspace) обрабатывается здесь же в Keys.
// Ещё здесь: сворачивание блоков, несколько курсоров, шаблоны (сниппеты), подсказка параметров и описание под мышью.
import QtQuick
import D3R

Item {
    id: ed
    required property var app                 // окно Code.qml: палитра pal, настройки cfg, тема th
    property string path: ""                  // "" — новый файл без имени
    property string title: "untitled"
    readonly property string name: path ? path.split("/").pop() : title
    readonly property string lang: /\.(c|cc|cpp|cxx|c\+\+|h|hh|hpp|hxx|ipp|tpp|ino)$/i.test(name) ? "cpp"
                                 : /\.(py|pyw)$/i.test(name) ? "python" : "text"
    readonly property string comment: lang === "python" || /\.(sh|cmake|txt|toml|ya?ml|conf)$/i.test(name) || name === "CMakeLists.txt" ? "#" : "//"
    readonly property alias area: area
    // настоящий текст файла: свёрнутые блоки в area заменены метками (см. «сворачивание»)
    readonly property string text: area.text.indexOf("\uFDDF") >= 0 ? expand(area.text) : area.text
    property string saved: ""
    property bool loaded: path === ""
    readonly property bool dirty: loaded && text !== saved
    property var starts: [0]                  // позиции начала строк (в area, то есть со свёрнутыми блоками)
    readonly property int lineCount: realLines
    property int curLine: 1
    property int curCol: 1
    readonly property int selLen: area.selectionEnd - area.selectionStart
    property var diags: []                    // [{line, col, sev: error|warning, msg}]
    readonly property var diagAt: { const m = {}; for (const d of diags) if (!m[d.line] || d.sev === "error") m[d.line] = d; return m; }
    readonly property string unit: " ".repeat(app.cfg.tabWidth)
    readonly property real charW: fm.advanceWidth("m")
    readonly property real lineH: fm.height
    signal edited()
    property var tip: null
    property int checkSeq: 0                  // номер последней проверки компилятором (старые ответы отбрасываются)
    property string uid: ""                    // подсказка к метке ошибки: {msg, y}

    FontMetrics { id: fm; font: area.font }

    // ── файл ──
    property bool crlf: false                 // файл с концами строк Windows — так и сохраняется
    function load() {
        area.text = Sys.read(path); crlf = Sys.crlf(path); saved = area.text; loaded = true;
        area.cursorPosition = 0; recount();
    }
    function save(done) {   // запись атомарная (QSaveFile): при ошибке старый файл цел
        const t = text, ok = Sys.write(path, t, crlf);
        if (ok) saved = t;
        if (done) done(ok);
    }
    Component.onCompleted: if (path) load()

    // ── строки ──
    function recount() {
        const t = area.text, s = [0];
        let i = -1;
        while ((i = t.indexOf("\n", i + 1)) !== -1) s.push(i + 1);
        starts = s;
        const marks = [];
        if (t.indexOf("\uFDDF") >= 0) { const re = /\uFDDF[\uE000-\uF8FF]/g; let m; while ((m = re.exec(t))) marks.push(m.index); }
        foldMarks = marks;
        if (marks.length) {   // номер настоящей строки для каждой видимой
            const add = marks.map(p => (expand(t.substr(p, 2)).match(/\n/g) || []).length), map = [];
            let extra = 0, k = 0;
            for (let j = 0; j < s.length; j++) { while (k < marks.length && marks[k] < s[j]) extra += add[k++]; map.push(j + extra); }
            while (k < marks.length) extra += add[k++];
            lineMap = map; realLines = s.length + extra;
        } else { lineMap = []; realLines = s.length; }
        updCursor();
    }
    function realLine(i) { return lineMap.length ? (lineMap[i] === undefined ? i : lineMap[i]) : i; }
    function dispLine(r) {   // видимая строка для настоящей (строка внутри свёрнутого блока → строка с меткой)
        if (!lineMap.length) return Math.max(0, Math.min(starts.length - 1, r));
        let lo = 0, hi = lineMap.length - 1;
        while (lo < hi) { const m = (lo + hi + 1) >> 1; if (lineMap[m] <= r) lo = m; else hi = m - 1; }
        return lo;
    }
    function lspPos(p) {   // позиция в area → [строка, столбец] настоящего текста (для clangd/jedi)
        const l = lineOf(p);
        if (!foldMarks.length) return [l, p - starts[l]];
        let r = p;
        for (const m of foldMarks) if (m < p) r += expand(area.text.substr(m, 2)).length - 2;
        const t = text, ls = t.lastIndexOf("\n", r - 1) + 1;
        return [(t.slice(0, r).match(/\n/g) || []).length, r - ls];
    }
    function setText(t) {   // заменить весь текст (формат, переименование): меняется только отличающаяся середина
        unfoldAll();
        const o = area.text;
        if (o === t) return;
        let a = 0; while (a < o.length && a < t.length && o[a] === t[a]) a++;
        let b = 0; while (b < o.length - a && b < t.length - a && o[o.length - 1 - b] === t[t.length - 1 - b]) b++;
        const c = area.cursorPosition, y = flick.contentY;
        area.remove(a, o.length - b); area.insert(a, t.slice(a, t.length - b));
        area.cursorPosition = c <= a ? c : c >= o.length - b ? c + t.length - o.length : Math.min(c, t.length - b);
        flick.contentY = y;
    }
    function wordAt(p) {   // [начало, конец] слова вокруг позиции
        const t = area.text;
        let a = p, b = p;
        while (a > 0 && /\w/.test(t[a - 1])) a--;
        while (b < t.length && /\w/.test(t[b])) b++;
        return [a, b];
    }
    function lineOf(pos) {   // номер строки (с 0) по позиции, двоичный поиск
        let lo = 0, hi = starts.length - 1;
        while (lo < hi) { const m = (lo + hi + 1) >> 1; if (starts[m] <= pos) lo = m; else hi = m - 1; }
        return lo;
    }
    function lineEnd(i) { return i + 1 < starts.length ? starts[i + 1] - 1 : area.text.length; }
    function updCursor() { const l = lineOf(area.cursorPosition); curLine = realLine(l) + 1; curCol = area.cursorPosition - starts[l] + 1; }
    function gotoLine(n, col) {   // n — настоящая строка; свёрнутое разворачивается
        unfoldAll();
        const l = Math.max(0, Math.min(starts.length - 1, n - 1));
        area.cursorPosition = Math.min(lineEnd(l), starts[l] + Math.max(0, (col || 1) - 1));
        area.forceActiveFocus(); center();
    }
    function center() { const r = area.cursorRectangle; flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, r.y + area.y - flick.height / 3)); }
    function ensureVisible() {
        const r = area.cursorRectangle, y = r.y + area.y, x = r.x + area.x;
        if (y < flick.contentY) flick.contentY = Math.max(0, y - 4);
        else if (y + r.height > flick.contentY + flick.height) flick.contentY = y + r.height - flick.height + 4;
        if (x < flick.contentX + 20) flick.contentX = Math.max(0, x - 60);
        else if (x > flick.contentX + flick.width - 30) flick.contentX = x - flick.width + 60;
    }

    // ── правки по строкам: строки a..b (с 0) заменяются на fn(массив строк); выделение — на изменённый блок ──
    function selLines() {
        const s = area.selectionStart, e = area.selectionEnd;
        const a = lineOf(s);
        let b = lineOf(e);
        if (e > s && b > a && e === starts[b]) b--;   // выделение до начала строки эту строку не захватывает
        return [a, b];
    }
    function replaceLines(a, b, fn, keepSel) {
        const s0 = starts[a], e0 = lineEnd(b), old = area.text.slice(s0, e0);
        const nw = fn(old.split("\n")).join("\n");
        if (nw === old) return;
        const cur = area.cursorPosition - s0;
        area.remove(s0, e0); area.insert(s0, nw);
        if (keepSel) area.select(s0, s0 + nw.length);
        else area.cursorPosition = s0 + Math.max(0, Math.min(nw.length, cur + (nw.length - old.length)));
    }
    function indent(dir) {
        const [a, b] = selLines(), multi = a !== b || selLen > 0;
        replaceLines(a, b, L => L.map(l => dir > 0 ? (l.length ? unit + l : l)
                                                     : l.replace(new RegExp("^ {1," + app.cfg.tabWidth + "}|^\\t"), "")), multi);
    }
    function toggleComment() {
        const [a, b] = selLines(), c = comment, multi = a !== b || selLen > 0;
        replaceLines(a, b, L => {
            const used = L.filter(l => l.trim());
            const all = used.length && used.every(l => l.replace(/^\s+/, "").startsWith(c));
            const ind = Math.min(...used.map(l => l.length - l.replace(/^\s+/, "").length));
            return L.map(l => !l.trim() ? l : all ? l.replace(new RegExp("^(\\s*)" + c.replace(/\//g, "\\/") + " ?"), "$1")
                                               : l.slice(0, ind) + c + " " + l.slice(ind));
        }, multi);
    }
    function duplicate() {
        if (selLen > 0) { const t = area.selectedText, e = area.selectionEnd; area.insert(e, t); area.select(e, e + t.length); return; }
        const l = lineOf(area.cursorPosition), col = area.cursorPosition - starts[l], t = area.text.slice(starts[l], lineEnd(l));
        area.insert(lineEnd(l), "\n" + t);
        area.cursorPosition = lineEnd(l) + 1 + col;
    }
    function deleteLine() {
        const [a, b] = selLines(), s = starts[a];
        const e = b + 1 < starts.length ? starts[b + 1] : area.text.length;
        area.remove(a > 0 && e === area.text.length ? s - 1 : s, e);
        area.cursorPosition = Math.min(area.text.length, starts[Math.min(a, starts.length - 1)] || 0);
    }
    function moveLines(dir) {
        const [a, b] = selLines();
        if (dir < 0 && a === 0 || dir > 0 && b >= starts.length - 1) return;
        const col = area.cursorPosition - starts[lineOf(area.cursorPosition)], had = selLen > 0 || a !== b;
        if (dir < 0) replaceLines(a - 1, b, L => [...L.slice(1), L[0]]);
        else replaceLines(a, b + 1, L => [L[L.length - 1], ...L.slice(0, -1)]);
        const na = a + dir, nb = b + dir;
        if (had) area.select(starts[na], lineEnd(nb));
        else area.cursorPosition = Math.min(lineEnd(na), starts[na] + col);
    }
    function selectLine() { const [a, b] = selLines(); area.select(starts[a], b + 1 < starts.length ? starts[b + 1] : area.text.length); }
    function openLine(above) {
        const l = lineOf(area.cursorPosition), t = area.text.slice(starts[l], lineEnd(l)), ind = t.match(/^\s*/)[0];
        if (above) { area.insert(starts[l], ind + "\n"); area.cursorPosition = starts[l] + ind.length; }
        else { const e = lineEnd(l); area.insert(e, "\n" + ind); area.cursorPosition = e + 1 + ind.length; }
    }

    // ── сворачивание: блок заменяется в area меткой «\uFDDF + ключ», сам текст хранится в foldMap[ключ].
    // Настоящий текст (ed.text) собирается обратно функцией expand, поэтому сохранение, проверка и clangd видят весь файл.
    // Ключи не удаляются из foldMap — Ctrl+Z может вернуть старую метку, и её текст должен найтись.
    property var foldMap: ({})
    property int foldN: 0
    property var foldMarks: []                // позиции меток в area
    property var lineMap: []                  // видимая строка → настоящая (пусто — ничего не свёрнуто)
    property int realLines: 1
    function expand(t) {
        for (let i = 0; i < 30 && t.indexOf("\uFDDF") >= 0; i++) t = t.replace(/\uFDDF([\uE000-\uF8FF])/g, (m, c) => foldMap[c] || "");
        return t.replace(/\uFDDF/g, "");   // одинокая метка (её половину стёрли) — просто убрать
    }
    function foldable(l) {
        const line = area.text.slice(starts[l], lineEnd(l));
        return lang === "python" ? /:\s*(#.*)?$/.test(line) : /\{\s*(\/\/.*)?$/.test(line);
    }
    function foldRange(l) {   // что прятать для строки l: [от, до] в area или null
        const t = area.text, ls = starts[l], le = lineEnd(l), line = t.slice(ls, le);
        if (lang === "python") {   // блок — строки ниже с большим отступом
            if (!/:\s*(#.*)?$/.test(line)) return null;
            const ind = line.match(/^\s*/)[0].length;
            let b = l;
            for (let k = l + 1; k < starts.length; k++) {
                const s = t.slice(starts[k], lineEnd(k));
                if (!s.trim()) continue;
                if (s.match(/^\s*/)[0].length <= ind) break;
                b = k;
            }
            return b > l ? [le, lineEnd(b)] : null;
        }
        const o = line.lastIndexOf("{");
        if (o < 0) return null;
        for (let i = ls + o, depth = 0; i < t.length; i++) {
            if (t[i] === "{") depth++;
            else if (t[i] === "}" && --depth === 0) return lineOf(i) > l ? [ls + o + 1, i] : null;
        }
        return null;
    }
    function fold(l) {
        const r = foldRange(l);
        if (!r) return false;
        // shortcut: ключей 6400 — после стольких сворачиваний одного файла за сеанс они пойдут по кругу
        const k = String.fromCharCode(0xE000 + foldN++ % 6400), c = area.cursorPosition;
        foldMap[k] = area.text.slice(r[0], r[1]);
        area.remove(r[0], r[1]); area.insert(r[0], "\uFDDF" + k);
        area.cursorPosition = c > r[0] && c <= r[1] ? r[0] + 2 : c > r[1] ? c - (r[1] - r[0]) + 2 : c;
        return true;
    }
    function unfold(p) {
        const h = foldMap[area.text[p + 1]] || "", c = area.cursorPosition;
        area.remove(p, p + 2); area.insert(p, h);
        area.cursorPosition = c >= p + 2 ? c + h.length - 2 : c;
    }
    function unfoldAll() { for (let n = 0; n < 30 && foldMarks.length; n++) for (const m of foldMarks.slice().reverse()) unfold(m); }
    function toggleFold() {   // Ctrl+Shift+[ : свернуть блок, в котором курсор (или развернуть свёрнутый на этой строке)
        const p = area.cursorPosition, l = lineOf(p);
        const m = foldMarks.find(x => x >= starts[l] && x <= lineEnd(l));
        if (m !== undefined) { unfold(m); return; }
        for (let k = l; k >= 0 && k > l - 3000; k--) { const r = foldRange(k); if (r && r[1] >= p) { fold(k); return; } }
    }
    function foldAll() { for (let k = starts.length - 1; k >= 0; k--) if (foldable(k) && /^\S/.test(area.text.slice(starts[k], lineEnd(k)))) fold(k); }

    // ── шаблоны: слово + Tab в начале строки. ${1:текст} — поле (Tab — к следующему), $0 — где курсор окажется в конце ──
    readonly property var snippets: lang === "python" ? {
        main: "def main():\n\t${1:pass}\n\n\nif __name__ == \"__main__\":\n\tmain()",
        def: "def ${1:name}(${2}):\n\t${0:pass}",
        class: "class ${1:Name}:\n\tdef __init__(self${2}):\n\t\t${0:pass}",
        for: "for ${1:i} in range(${2:n}):\n\t${0:pass}",
        forin: "for ${1:x} in ${2:items}:\n\t${0:pass}",
        if: "if ${1:cond}:\n\t${0:pass}",
        ife: "if ${1:cond}:\n\t${2:pass}\nelse:\n\t${0:pass}",
        while: "while ${1:cond}:\n\t${0:pass}",
        try: "try:\n\t${1:pass}\nexcept ${2:Exception} as e:\n\t${0:print(e)}",
        pr: "print(${0})",
        inp: "${1:x} = int(input())$0"
    } : lang === "cpp" ? {
        main: "int main() {\n\t$0\n\treturn 0;\n}",
        inc: "#include <${1:iostream}>$0",
        for: "for (int i = 0; i < ${1:n}; i++) {\n\t$0\n}",
        forr: "for (auto& ${1:x} : ${2:v}) {\n\t$0\n}",
        while: "while (${1:cond}) {\n\t$0\n}",
        if: "if (${1:cond}) {\n\t$0\n}",
        ife: "if (${1:cond}) {\n\t$2\n} else {\n\t$0\n}",
        fn: "${1:void} ${2:name}(${3}) {\n\t$0\n}",
        class: "class ${1:Name} {\npublic:\n\t$0\n};",
        struct: "struct ${1:Name} {\n\t$0\n};",
        cout: "std::cout << ${1} << std::endl;$0",
        cin: "std::cin >> ${1:x};$0",
        vec: "std::vector<${1:int}> ${2:v};$0"
    } : ({})
    property var snip: []                     // оставшиеся поля шаблона: {fromEnd, len} — отсчёт от конца текста не сдвигается, пока правишь поле выше
    function snippetWord() {   // слово перед курсором, если перед ним на строке только пробелы, и для него есть шаблон
        const p = area.cursorPosition, before = area.text.slice(starts[lineOf(p)], p), m = before.match(/^\s*(\w+)$/);
        return m && snippets[m[1]] ? m[1] : "";
    }
    function expandSnippet(word) {
        const p = area.cursorPosition, s0 = p - word.length, ind = area.text.slice(starts[lineOf(p)], p).match(/^\s*/)[0];
        const src = snippets[word].replace(/\t/g, unit).replace(/\n/g, "\n" + ind), re = /\$\{(\d+)(?::([^}]*))?\}|\$(\d+)/g, stops = [];
        let out = "", last = 0, m;
        while ((m = re.exec(src))) {
            out += src.slice(last, m.index);
            stops.push({ n: +(m[1] || m[3]), at: out.length, len: (m[2] || "").length });
            out += m[2] || ""; last = re.lastIndex;
        }
        out += src.slice(last);
        closeComp();
        area.remove(s0, p); area.insert(s0, out);
        if (!stops.some(x => x.n === 0)) stops.push({ n: 0, at: out.length, len: 0 });
        stops.sort((a, b) => (a.n || 1e9) - (b.n || 1e9));   // $0 — последним
        const end = area.text.length;
        snip = stops.map(x => ({ fromEnd: end - s0 - x.at, len: x.len }));
        nextStop();
    }
    function nextStop() {
        const st = snip[0];
        snip = snip.slice(1);
        const a = area.text.length - st.fromEnd;
        area.select(a, a + st.len);
    }

    // ── несколько курсоров: Ctrl+D — следующее такое же слово, Alt+клик — ещё курсор. Главный курсор — сам TextEdit ──
    property var extras: []                   // дополнительные: [{s, e}] (выделение от s до e)
    property bool multiBusy: false            // правим сами — не сбрасывать курсоры
    function addNextMatch() {
        if (selLen === 0) { const w = wordAt(area.cursorPosition); if (w[1] > w[0]) area.select(w[0], w[1]); return; }
        const w = area.selectedText, t = area.text;
        let i = t.indexOf(w, area.selectionEnd);
        if (i < 0) i = t.indexOf(w);
        const all = extras.concat([{ s: area.selectionStart, e: area.selectionEnd }]);
        if (i < 0 || all.some(r => r.s === i)) return;
        multiBusy = true; extras = all; area.select(i, i + w.length); multiBusy = false;
        Qt.callLater(ensureVisible);
    }
    function addCaret(p) {
        if (p === area.cursorPosition || extras.some(r => r.s === p)) return;
        multiBusy = true; extras = extras.concat([{ s: area.selectionStart, e: area.selectionEnd }]); area.cursorPosition = p; multiBusy = false;
    }
    function multiKey(e) {   // клавиша для всех курсоров сразу; false — не наша, курсоры сбрасываются
        const k = e.key, ch = e.text, plain = !(e.modifiers & (Qt.ControlModifier | Qt.AltModifier));
        const L = area.text.length, all = extras.concat([{ s: area.selectionStart, e: area.selectionEnd, main: true }]);
        if (k === Qt.Key_Escape) { extras = []; return true; }
        if ((k === Qt.Key_Left || k === Qt.Key_Right) && plain && !(e.modifiers & Qt.ShiftModifier)) {
            const mv = r => k === Qt.Key_Left ? (r.s < r.e ? r.s : Math.max(0, r.s - 1)) : (r.s < r.e ? r.e : Math.min(L, r.e + 1));
            multiBusy = true;
            extras = extras.map(r => ({ s: mv(r), e: mv(r) }));
            area.cursorPosition = mv(all[all.length - 1]);
            multiBusy = false; return true;
        }
        let op = null;
        if (k === Qt.Key_Backspace) op = r => r.s < r.e ? [r.s, r.e, ""] : [Math.max(0, r.s - 1), r.s, ""];
        else if (k === Qt.Key_Delete) op = r => r.s < r.e ? [r.s, r.e, ""] : [r.s, Math.min(L, r.s + 1), ""];
        else if ((k === Qt.Key_Return || k === Qt.Key_Enter) && plain) op = r => [r.s, r.e, "\n"];
        else if (ch.length === 1 && plain && ch >= " ") op = r => [r.s, r.e, ch];
        if (!op) { if (k !== Qt.Key_Shift && k !== Qt.Key_Control && k !== Qt.Key_Alt) extras = []; return false; }
        const eds = all.map(r => { const o = op(r); return { a: o[0], b: o[1], ins: o[2], main: !!r.main }; }).sort((x, y) => x.a - y.a)
                       .filter((d, i, arr) => i === 0 || d.a >= arr[i - 1].b);   // курсоры слиплись — правка одна
        closeComp();
        multiBusy = true;
        for (let i = eds.length - 1; i >= 0; i--) { area.remove(eds[i].a, eds[i].b); if (eds[i].ins) area.insert(eds[i].a, eds[i].ins); }
        let shift = 0, main = -1;
        const nx = [];
        for (const d of eds) {
            const pos = d.a + shift + d.ins.length;
            shift += d.ins.length - (d.b - d.a);
            if (d.main) main = pos; else nx.push({ s: pos, e: pos });
        }
        if (main < 0) main = nx.pop().s;
        area.cursorPosition = main; extras = nx;
        multiBusy = false;
        return true;
    }

    // ── подсказка параметров: после «(» и «,» — подпись функции, текущий параметр выделен ──
    property var sig: null                    // {label, params: [[от, до]…], active}
    property int sigSeq: 0
    property int sigLine: -1
    function requestSig() {
        if (!path || !app.canComplete(lang)) return;
        const p = area.cursorPosition, seq = ++sigSeq, lc = lspPos(p);
        app.lsp("signature", { lang: lang, path: path, text: text, line: lc[0], col: lc[1] }, r => {
            if (seq !== sigSeq) return;
            sig = r && r.label ? r : null; sigLine = lineOf(area.cursorPosition);
        });
    }

    // ── та же переменная по всему файлу: под мышью, а если мышь не над словом — под курсором (clangd/jedi понимают код,
    // поэтому однофамильцы из других функций, строк и комментариев не подсвечиваются) ──
    property var occ: []                      // [[позиция в area, длина]]
    property int occSeq: 0
    property int occAt: -1                    // начало слова, для которого уже подсвечено
    function requestOcc(p) {
        const w = wordAt(p);
        if (!path || !app.canComplete(lang) || w[1] <= w[0] || !/[A-Za-z_]/.test(area.text[w[0]])) { occ = []; occAt = -1; return; }
        if (w[0] === occAt) return;
        const seq = ++occSeq, lc = lspPos(w[0]);
        app.lsp("highlight", { lang: lang, path: path, text: text, line: lc[0], col: lc[1] }, r => {
            if (seq !== occSeq) return;
            const out = [];
            for (const h of r.items || []) {   // настоящие строки → видимые; внутри свёрнутого не рисуем
                const d = dispLine(h[0]);
                if (realLine(d) === h[0]) out.push([starts[d] + h[1], h[2]]);
            }
            occ = out.length > 1 ? out : [];   // одно вхождение подсвечивать незачем
            occAt = w[0];
        });
    }
    Timer { id: occTimer; property int pos: -1; interval: 120; onTriggered: ed.requestOcc(pos) }
    function occFrom(p) { occTimer.pos = p; occTimer.restart(); }

    // ── описание под мышью ──
    property var hover: null                  // {text, x, y, a, b}: что показать и над каким словом
    property int hoverSeq: 0
    function requestHover(p, x, y) {
        const w = wordAt(p);
        if (!path || !app.canComplete(lang) || w[1] <= w[0] || !/[A-Za-z_]/.test(area.text[w[0]])) { hover = null; return; }
        if (hover && hover.a === w[0]) return;
        const seq = ++hoverSeq, lc = lspPos(w[0] + 1 <= w[1] ? w[0] + 1 : w[0]);
        app.lsp("hover", { lang: lang, path: path, text: text, line: lc[0], col: lc[1] }, r => {
            if (seq !== hoverSeq || !hov.hovered) return;
            const t = r && r.text ? r.text.split("\n").slice(0, 16).join("\n") : "";
            hover = t ? { text: t, x: x, y: y, a: w[0], b: w[1] } : null;
        });
    }

    // ── поиск ──
    property string query: ""
    property bool matchCase: false
    property var matches: []
    function findAll() {
        const q = query, m = [];
        if (q) {
            const t = matchCase ? area.text : area.text.toLowerCase(), qq = matchCase ? q : q.toLowerCase();
            let i = -1;
            while ((i = t.indexOf(qq, i + 1)) !== -1 && m.length < 2000) m.push(i);
        }
        matches = m;
    }
    onQueryChanged: findAll()
    onMatchCaseChanged: findAll()
    readonly property int matchIndex: { const p = area.selectionStart; return matches.indexOf(p); }
    function findNext(back) {
        if (!matches.length) return;
        const p = back ? area.selectionStart : area.selectionEnd;
        let k = back ? -1 : matches.findIndex(m => m >= p);
        if (back) for (let j = matches.length - 1; j >= 0; j--) if (matches[j] < p) { k = j; break; }
        if (k < 0) k = back ? matches.length - 1 : 0;   // по кругу
        area.select(matches[k], matches[k] + query.length);
        center();
    }
    function replaceOne(r) {
        if (selLen > 0 && (matchCase ? area.selectedText === query : area.selectedText.toLowerCase() === query.toLowerCase())) {
            const s = area.selectionStart; area.remove(s, area.selectionEnd); area.insert(s, r); area.cursorPosition = s + r.length;
        }
        findAll(); findNext(false);
    }
    function replaceAll(r) {
        if (!matches.length) return 0;
        const ms = matches.slice(), n = ms.length, len = query.length;   // копия: после каждой правки matches пересчитывается
        for (let k = n - 1; k >= 0; k--) { area.remove(ms[k], ms[k] + len); area.insert(ms[k], r); }
        findAll();
        return n;
    }

    // ── парная скобка рядом с курсором ──
    property var brackets: []
    function matchBracket() {
        const t = area.text, p = area.cursorPosition, pairs = { "(": ")", "[": "]", "{": "}" }, back = { ")": "(", "]": "[", "}": "{" };
        let at = -1;
        if (pairs[t[p]] || back[t[p]]) at = p; else if (pairs[t[p - 1]] || back[t[p - 1]]) at = p - 1;
        if (at < 0) { brackets = []; return; }
        const c = t[at], fwd = !!pairs[c], o = fwd ? pairs[c] : back[c];
        let depth = 0;
        for (let i = at, n = 0; i >= 0 && i < t.length && n < 20000; i += fwd ? 1 : -1, n++) {
            if (t[i] === c) depth++;
            else if (t[i] === o && --depth === 0) { brackets = [at, i]; return; }
        }
        brackets = [at];   // пары нет — подсветим одну, красным
    }

    // ── автодополнение (clangd через app.lspComplete) ──
    property var comps: []                    // варианты от clangd
    property int compStart: -1                // позиция начала дополняемого слова; -1 — список закрыт
    property int compSel: 0
    property int compSeq: 0
    readonly property string compWord: compStart >= 0 && area.cursorPosition >= compStart ? area.text.slice(compStart, area.cursorPosition) : ""
    readonly property var compShown: {   // пока clangd отвечает, сужаем уже полученный список сами
        if (compStart < 0) return [];
        const w = compWord.toLowerCase();
        if (!w) return comps.slice(0, 60);
        const a = [], b = [];
        // шаблоны — первыми, если слово стоит в начале строки
        if (/^\s*\w*$/.test(area.text.slice(starts[lineOf(compStart)], area.cursorPosition)))
            for (const k in snippets) if (k.startsWith(w)) a.push({ label: k, insert: k, kind: 15, detail: "шаблон · Tab", snippet: true,
                                                                   doc: snippets[k].replace(/\$\{\d+:?([^}]*)\}|\$\d/g, "$1").replace(/\t/g, "  ") });
        for (const c of comps) { const t = c.insert.toLowerCase(); if (t.startsWith(w)) a.push(c); else if (t.indexOf(w) > 0) b.push(c); }
        return a.concat(b).slice(0, 60);
    }
    readonly property bool compOpen: compShown.length > 0 && area.activeFocus
    function closeComp() { compStart = -1; comps = []; compSel = 0; compSeq++; }
    function maybeComplete(force) {
        if (!path || !app.canComplete(lang)) return;
        const p = area.cursorPosition, l = lineOf(p), before = area.text.slice(starts[l], p);
        const m = before.match(/[A-Za-z_]\w*$/), word = m ? m[0] : "", lead = before.slice(0, before.length - word.length);
        const member = lang === "python" ? /\.$/.test(lead) : /(\.|->|::)$/.test(lead);
        if (!force && !(word.length >= 2 || member) || /^\s*#\s*include/.test(before) && !force) { closeComp(); return; }
        if (!force && /^[0-9]/.test(word)) { closeComp(); return; }
        compTimer.restart();
    }
    Timer {
        id: compTimer; interval: 70
        onTriggered: {
            const p = area.cursorPosition, l = ed.lineOf(p), seq = ++ed.compSeq, lc = ed.lspPos(p);
            const before = area.text.slice(ed.starts[l], p), m = before.match(/[A-Za-z_]\w*$/);
            ed.app.lsp("complete", { lang: ed.lang, path: ed.path, text: ed.text, line: lc[0], col: lc[1] }, r => {
                const items = r.items || [];
                if (seq !== ed.compSeq || area.cursorPosition !== p) return;   // пока ждали ответ, курсор ушёл
                const st = items.length && items[0].start >= 0 ? p - (lc[1] - items[0].start) : p - (m ? m[0].length : 0);
                ed.comps = items; ed.compSel = 0; ed.compStart = items.length ? st : -1;
            });
        }
    }
    function acceptComp() {
        const c = compShown[compSel];
        if (!c) { closeComp(); return; }
        if (c.snippet) { area.remove(compStart, area.cursorPosition); area.insert(compStart, c.insert); expandSnippet(c.insert); return; }
        const s0 = compStart, p = area.cursorPosition;
        let ins = c.insert;
        const fn = c.kind === 2 || c.kind === 3 || c.kind === 4;
        const call = fn && area.text[p] !== "(" && c.label.indexOf("(") >= 0;
        area.remove(s0, p);
        area.insert(s0, call ? ins + "()" : ins);
        // у функции с параметрами курсор — внутрь скобок
        area.cursorPosition = s0 + ins.length + (call ? (/\(\s*\)/.test(c.label) ? 2 : 1) : 0);
        closeComp();
        if (call && !/\(\s*\)/.test(c.label)) Qt.callLater(requestSig);
    }
    function compKind(k) {   // буква и цвет вида варианта
        return ({ 2: ["m", app.pal.light], 3: ["f", app.pal.light], 4: ["c", app.pal.light], 5: ["·", app.pal.text], 6: ["v", app.pal.text],
                  7: ["C", app.pal.acc], 8: ["I", app.pal.acc], 9: ["N", app.pal.dim], 10: ["p", app.pal.text], 13: ["E", app.pal.acc],
                  14: ["k", app.pal.acc], 17: ["i", app.pal.dim], 20: ["e", app.pal.text], 21: ["#", app.pal.light], 22: ["S", app.pal.acc],
                  15: ["s", app.pal.light], 25: ["T", app.pal.acc] })[k] || ["·", app.pal.dim];
    }

    // ── набор: отступы, Enter, скобки и кавычки ──
    function key(e) {
        const ctrl = e.modifiers & Qt.ControlModifier, alt = e.modifiers & Qt.AltModifier;
        hover = null;
        if (extras.length && multiKey(e)) { e.accepted = true; return; }
        if (e.key === Qt.Key_Tab && !ctrl && selLen === 0) {   // шаблон: слово + Tab
            const w = snippetWord();
            if (w) { expandSnippet(w); e.accepted = true; return; }
        }
        if ((e.matches(StandardKey.Copy) || e.matches(StandardKey.Cut)) && area.selectedText.indexOf("\uFDDF") >= 0) {
            clip.text = expand(area.selectedText); clip.selectAll(); clip.copy();   // в буфер — со свёрнутым внутри
            if (e.matches(StandardKey.Cut)) area.remove(area.selectionStart, area.selectionEnd);
            e.accepted = true; return;
        }
        if (compOpen) {   // открыт список подсказок: стрелки, Enter/Tab — выбрать, Esc — закрыть
            if (e.key === Qt.Key_Down) { compSel = (compSel + 1) % compShown.length; e.accepted = true; return; }
            if (e.key === Qt.Key_Up) { compSel = (compSel - 1 + compShown.length) % compShown.length; e.accepted = true; return; }
            if (e.key === Qt.Key_PageDown) { compSel = Math.min(compShown.length - 1, compSel + 8); e.accepted = true; return; }
            if (e.key === Qt.Key_PageUp) { compSel = Math.max(0, compSel - 8); e.accepted = true; return; }
            if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Tab) && !ctrl) { acceptComp(); e.accepted = true; return; }
            if (e.key === Qt.Key_Escape) { closeComp(); e.accepted = true; return; }
            if (e.key === Qt.Key_Left || e.key === Qt.Key_Right || e.key === Qt.Key_Home || e.key === Qt.Key_End) closeComp();
        }
        if (e.key === Qt.Key_Escape && (sig || snip.length)) { sig = null; snip = []; e.accepted = true; return; }
        if (e.key === Qt.Key_Tab && !ctrl && snip.length) { nextStop(); e.accepted = true; return; }
        if (e.key === Qt.Key_Backspace && compStart >= 0) Qt.callLater(maybeComplete);
        if (e.key === Qt.Key_Backspace && sig) Qt.callLater(requestSig);
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) sig = null;
        if (e.text.length === 1 && !ctrl && !alt) Qt.callLater(() => {
            if (/[\w.:>]/.test(e.text)) maybeComplete(); else closeComp();
            if (e.text === "(" || e.text === "," || e.text === ")" && sig) requestSig();
        });
        const t = area.text, p = area.cursorPosition, hasSel = selLen > 0;
        if (!hasSel && !ctrl && (e.key === Qt.Key_Backspace && t[p - 2] === "\uFDDF" || e.key === Qt.Key_Delete && t[p] === "\uFDDF")) {
            unfold(e.key === Qt.Key_Backspace ? p - 2 : p); e.accepted = true; return;   // стирать свёрнутое — сначала развернуть
        }
        const closers = { ")": 1, "]": 1, "}": 1, "\"": 1, "'": 1 }, pairs = { "(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'" };
        if (e.key === Qt.Key_Tab && !ctrl) {
            if (hasSel && area.selectedText.indexOf("\n") >= 0) indent(1);
            else { if (hasSel) area.remove(area.selectionStart, area.selectionEnd);
                   const col = area.cursorPosition - starts[lineOf(area.cursorPosition)];
                   area.insert(area.cursorPosition, " ".repeat(app.cfg.tabWidth - col % app.cfg.tabWidth)); }
            e.accepted = true; return;
        }
        if (e.key === Qt.Key_Backtab) { indent(-1); e.accepted = true; return; }
        if ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && !ctrl && !alt) {
            if (hasSel) area.remove(area.selectionStart, area.selectionEnd);
            const q = area.cursorPosition, ls = starts[lineOf(q)], before = area.text.slice(ls, q);
            const ind = before.match(/^\s*/)[0], last = before.replace(/\s+$/, "").slice(-1), next = area.text[q];
            const extra = last === "{" || last === "(" || last === "[" || (lang === "python" && last === ":") ? unit : "";
            if (extra && pairs[last] && next === pairs[last]) {
                area.insert(q, "\n" + ind + extra + "\n" + ind);
                area.cursorPosition = q + 1 + ind.length + extra.length;
            } else {
                // Python: после return/pass/break/continue/raise следующая строка на уровень левее
                const out = lang === "python" && /^\s*(return\b|pass\b|break\b|continue\b|raise\b)/.test(before) ? ind.slice(app.cfg.tabWidth) : null;
                const s = "\n" + (out !== null ? out : ind + extra);
                area.insert(q, s); area.cursorPosition = q + s.length;
            }
            e.accepted = true; return;
        }
        if (e.key === Qt.Key_Backspace && !hasSel && !ctrl && p > 0) {
            if (pairs[t[p - 1]] && pairs[t[p - 1]] === t[p]) { area.remove(p - 1, p + 1); e.accepted = true; return; }
            const ls = starts[lineOf(p)], before = t.slice(ls, p);
            if (before.length && !before.trim() && before.length % app.cfg.tabWidth === 0) { area.remove(p - app.cfg.tabWidth, p); e.accepted = true; return; }
            return;
        }
        if (e.key === Qt.Key_Home && !ctrl) {   // умный Home: к началу кода, второй раз — к началу строки
            const ls = starts[lineOf(p)], first = ls + t.slice(ls, lineEnd(lineOf(p))).match(/^\s*/)[0].length;
            const to = p === first ? ls : first;
            if (e.modifiers & Qt.ShiftModifier) { const anchor = p === area.selectionEnd ? area.selectionStart : area.selectionEnd; area.select(anchor, to); area.cursorPosition = to; area.select(anchor, to); }
            else area.cursorPosition = to;
            e.accepted = true; return;
        }
        const ch = e.text;
        if (ch.length !== 1 || ctrl || alt) return;
        if (closers[ch] && !hasSel && t[p] === ch && (ch !== "\"" && ch !== "'" || t[p - 1] !== "\\")) {   // перешагнуть закрывающую
            area.cursorPosition = p + 1; e.accepted = true; return;
        }
        if (pairs[ch] && app.cfg.autoClose) {
            if (hasSel) {   // обернуть выделение
                const s = area.selectionStart, en = area.selectionEnd, inner = area.selectedText;
                area.remove(s, en); area.insert(s, ch + inner + pairs[ch]); area.select(s + 1, s + 1 + inner.length);
                e.accepted = true; return;
            }
            const quote = ch === "\"" || ch === "'";
            const nextOk = p >= t.length || /[\s)\]};,]/.test(t[p]);
            const prevOk = !quote || p === 0 || !/[\w"'\\]/.test(t[p - 1]);
            if (nextOk && prevOk) { area.insert(p, ch + pairs[ch]); area.cursorPosition = p + 1; e.accepted = true; return; }
        }
        if (ch === "}" && !hasSel) {   // закрывающая на пустой строке — на уровень левее
            const ls = starts[lineOf(p)], before = t.slice(ls, p);
            if (before.length >= app.cfg.tabWidth && !before.trim()) { area.remove(p - app.cfg.tabWidth, p); area.insert(p - app.cfg.tabWidth, "}"); e.accepted = true; }
        }
    }

    // ══════ вид ══════
    // поля: номера строк и метки ошибок
    Item {
        id: gutter
        width: app.cfg.lineNumbers ? Math.max(3, String(ed.lineCount).length) * ed.charW + 30 : 14
        height: parent.height; clip: true
        Behavior on width { NumberAnimation { duration: app.cfg.anim ? 160 : 0 } }
        readonly property int first: { void (flick.contentY); void (area.contentHeight); return ed.lineOf(area.positionAt(0, flick.contentY - area.y)); }
        HoverHandler { id: gutterHov }
        Repeater {
            model: Math.ceil(flick.height / Math.max(1, ed.lineH)) + 2
            Item {
                id: ln
                required property int index
                readonly property int line: gutter.first + index
                readonly property int real: { void (ed.lineMap); return ed.realLine(line); }
                readonly property var d: ed.diagAt[real + 1]
                readonly property int mark: { void (ed.foldMarks); return visible ? ed.foldMarks.findIndex(m => m >= ed.starts[line] && m <= ed.lineEnd(line)) : -1; }
                visible: line < ed.starts.length
                width: gutter.width; height: ed.lineH
                y: { void (flick.contentY); void (area.contentHeight); void (app.cfg.fontSize); void (area.width);
                     return visible ? area.positionToRectangle(ed.starts[line]).y + area.y - flick.contentY : -100; }
                Text {
                    visible: app.cfg.lineNumbers
                    anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter
                    font.family: area.font.family; font.pixelSize: Math.max(9, area.font.pixelSize - 2)
                    color: ln.real + 1 === ed.curLine ? app.pal.light : ln.d ? (ln.d.sev === "error" ? "#e8607e" : "#e8b85e") : app.pal.faint
                    font.bold: ln.real + 1 === ed.curLine
                    text: ln.real + 1
                }
                Text {   // свернуть / развернуть блок: стрелка видна, когда мышь над полями (у свёрнутого — всегда)
                    anchors.right: parent.right; anchors.rightMargin: 1; anchors.verticalCenter: parent.verticalCenter
                    font.family: app.mono; font.pixelSize: 9; color: ln.mark >= 0 ? app.pal.light : app.pal.dim
                    visible: { void (area.text); return ln.visible && (ln.mark >= 0 || gutterHov.hovered && ed.foldable(ln.line)); }
                    text: ln.mark >= 0 ? "▶" : "▼"
                    MouseArea { anchors.fill: parent; anchors.margins: -4
                                onClicked: ln.mark >= 0 ? ed.unfold(ed.foldMarks[ln.mark]) : ed.fold(ln.line) }
                }
                Rectangle {   // метка ошибки/предупреждения; наведение — текст сообщения
                    visible: !!ln.d
                    x: 4; anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3
                    color: ln.d && ln.d.sev === "error" ? "#e8607e" : "#e8b85e"
                    MouseArea { anchors.fill: parent; anchors.margins: -6; hoverEnabled: true
                                onContainsMouseChanged: ed.tip = containsMouse && ln.d ? { msg: ln.d.msg, y: ln.y } : null }
                }
            }
        }
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Qt.alpha(app.pal.acc, 0.12) }
    }

    // ── список подсказок у курсора ──
    Rectangle {
        id: comp
        readonly property rect r: { void (flick.contentY); void (flick.contentX); return area.positionToRectangle(Math.max(0, ed.compStart)); }
        readonly property bool below: r.y + area.y - flick.contentY + ed.lineH + height < ed.height - 8
        visible: opacity > 0.01
        opacity: ed.compOpen ? 1 : 0
        scale: ed.compOpen ? 1 : 0.97
        transformOrigin: below ? Item.TopLeft : Item.BottomLeft
        Behavior on opacity { NumberAnimation { duration: ed.app.cfg.anim ? 90 : 0 } }
        Behavior on scale { NumberAnimation { duration: ed.app.cfg.anim ? 110 : 0; easing.type: Easing.OutCubic } }
        z: 90
        x: Math.min(ed.width - width - 6, gutter.width + r.x + area.x - flick.contentX - 28)
        y: below ? r.y + area.y - flick.contentY + ed.lineH + 2 : r.y + area.y - flick.contentY - height - 2
        width: 460; height: Math.min(9, ed.compShown.length) * 26 + 8 + (docText.text ? docText.implicitHeight + 14 : 0)
        radius: 7
        color: Qt.alpha(ed.app.pal.bg, 0.98)
        border.width: 1; border.color: Qt.alpha(ed.app.pal.acc, 0.55)
        ListView {
            id: compList
            x: 4; y: 4; width: parent.width - 8; height: Math.min(9, ed.compShown.length) * 26
            clip: true; interactive: false
            model: ed.compShown
            currentIndex: ed.compSel
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
            highlightMoveDuration: ed.app.cfg.anim ? 60 : 0
            highlight: Rectangle { radius: 5; color: Qt.alpha(ed.app.pal.sel, 0.5); Rectangle { width: 2; height: parent.height; color: ed.app.pal.acc } }
            WheelHandler { onWheel: w => ed.compSel = Math.max(0, Math.min(ed.compShown.length - 1, ed.compSel + (w.angleDelta.y < 0 ? 1 : -1))) }
            delegate: Item {
                required property var modelData
                required property int index
                width: compList.width; height: 26
                readonly property var k: ed.compKind(modelData.kind)
                Rectangle {   // буква вида: m — метод, f — функция, v — переменная, C — класс, k — ключевое слово…
                    x: 6; anchors.verticalCenter: parent.verticalCenter; width: 18; height: 18; radius: 4
                    color: Qt.alpha(parent.k[1], 0.15); border.width: 1; border.color: Qt.alpha(parent.k[1], 0.5)
                    Text { anchors.centerIn: parent; font.family: ed.app.mono; font.pixelSize: 11; font.bold: true; color: parent.parent.k[1]; text: parent.parent.k[0] }
                }
                Text {
                    x: 32; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 40 - det.width; elide: Text.ElideRight
                    font.family: ed.app.cfg.font; font.pixelSize: Math.max(11, ed.app.cfg.fontSize - 2); textFormat: Text.StyledText
                    color: ed.app.pal.text
                    readonly property int n: ed.compWord.length && parent.modelData.label.toLowerCase().startsWith(ed.compWord.toLowerCase()) ? ed.compWord.length : 0
                    function esc(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
                    text: "<b><font color='" + ed.app.pal.light + "'>" + esc(parent.modelData.label.slice(0, n)) + "</font></b>" + esc(parent.modelData.label.slice(n))
                }
                Text {
                    id: det
                    anchors.right: parent.right; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 150); elide: Text.ElideLeft
                    font.family: ed.app.cfg.font; font.pixelSize: Math.max(10, ed.app.cfg.fontSize - 4); color: ed.app.pal.faint
                    text: parent.modelData.detail || ""
                }
                MouseArea { anchors.fill: parent; onClicked: { ed.compSel = parent.index; ed.acceptComp(); area.forceActiveFocus(); } }
            }
        }
        Rectangle { visible: !!docText.text; x: 8; y: compList.y + compList.height + 6; width: parent.width - 16; height: 1; color: Qt.alpha(ed.app.pal.acc, 0.25) }
        Text {   // описание выбранного варианта (из комментариев в заголовках)
            id: docText
            x: 10; y: compList.y + compList.height + 11; width: parent.width - 20
            wrapMode: Text.Wrap; maximumLineCount: 4; elide: Text.ElideRight
            font.family: ed.app.cfg.font; font.pixelSize: 11; color: ed.app.pal.dim
            text: { const c = ed.compShown[ed.compSel]; return c && c.doc ? c.doc.replace(/\n+/g, " ").replace(/@brief\s*/g, "") : ""; }
        }
    }

    ToolTipBox { app: ed.app; show: !!ed.tip; msg: ed.tip ? ed.tip.msg : ""; x: gutter.width + 6; y: ed.tip ? ed.tip.y - 4 : 0 }
    ToolTipBox {   // описание под мышью
        app: ed.app; show: !!ed.hover && !ed.compOpen; msg: ed.hover ? ed.hover.text : ""
        x: ed.hover ? Math.max(4, Math.min(ed.width - width - 8, ed.hover.x - 20)) : 0
        y: ed.hover ? (ed.hover.y + ed.lineH + height + 6 < ed.height ? ed.hover.y + ed.lineH + 4 : Math.max(4, ed.hover.y - height - 4)) : 0
    }
    Rectangle {   // подсказка параметров над курсором
        id: sigBox
        readonly property rect r: { void (flick.contentY); void (flick.contentX); return area.cursorRectangle; }
        readonly property real cy: r.y + area.y - flick.contentY
        visible: !!ed.sig && area.activeFocus
        z: 95
        x: Math.max(4, Math.min(ed.width - width - 8, gutter.width + r.x + area.x - flick.contentX - 20))
        y: cy - height - 4 >= 0 ? cy - height - 4 : cy + ed.lineH + 4
        width: Math.min(ed.width - 20, sigText.implicitWidth + 20); height: sigText.implicitHeight + 10; radius: 6
        color: Qt.alpha(ed.app.pal.head, 0.97); border.width: 1; border.color: Qt.alpha(ed.app.pal.acc, 0.5)
        Text {
            id: sigText
            x: 10; y: 5; width: Math.min(implicitWidth, ed.width - 40); elide: Text.ElideRight
            font.family: ed.app.cfg.font; font.pixelSize: Math.max(11, ed.app.cfg.fontSize - 2); textFormat: Text.StyledText; color: ed.app.pal.dim
            function esc(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
            text: {
                const s = ed.sig;
                if (!s) return "";
                const p = s.params[s.active];
                if (!p || p[1] <= p[0]) return esc(s.label);
                return esc(s.label.slice(0, p[0])) + "<b><font color='" + ed.app.pal.light + "'>" + esc(s.label.slice(p[0], p[1])) + "</font></b>" + esc(s.label.slice(p[1]));
            }
        }
    }
    TextEdit { id: clip; visible: false }

    Flickable {
        id: flick
        anchors.fill: parent; anchors.leftMargin: gutter.width
        contentWidth: Math.max(width, area.width)
        contentHeight: Math.max(height, area.height + height * 0.4)   // можно прокрутить за конец файла
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: false              // колесо и полосы — сами; тащить текст мышью = выделять
        WheelHandler {
            onWheel: e => {
                if (e.modifiers & Qt.ControlModifier) { ed.app.zoom(e.angleDelta.y > 0 ? 1 : -1); return; }
                const dy = e.pixelDelta.y || e.angleDelta.y / 120 * ed.lineH * 3, dx = e.pixelDelta.x || e.angleDelta.x / 120 * ed.charW * 6;
                if (e.modifiers & Qt.ShiftModifier) flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX - dy));
                else flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY - dy));
                if (dx) flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX - dx));
            }
        }

        // текущая строка
        Rectangle {
            visible: app.cfg.curLine && area.activeFocus
            x: 0; width: flick.contentWidth; height: area.cursorRectangle.height
            y: area.cursorRectangle.y + area.y
            color: Qt.alpha(app.pal.panel, 0.9)
            Behavior on y { enabled: app.cfg.anim; NumberAnimation { duration: 70; easing.type: Easing.OutCubic } }
            Rectangle { width: 2; height: parent.height; color: Qt.alpha(app.pal.acc, 0.7) }
        }
        // строки с ошибками
        Repeater {
            model: ed.diags
            Rectangle {
                required property var modelData
                readonly property int l: { void (ed.lineMap); return ed.dispLine(modelData.line - 1); }
                x: 0; width: flick.contentWidth; height: ed.lineH
                y: { void (area.contentHeight); void (app.cfg.fontSize); return area.positionToRectangle(ed.starts[l] || 0).y + area.y; }
                color: Qt.alpha(modelData.sev === "error" ? "#e8607e" : "#e8b85e", 0.09)
                Rectangle { y: parent.height - 1; width: parent.width; height: 1; color: Qt.alpha(modelData.sev === "error" ? "#e8607e" : "#e8b85e", 0.35) }
            }
        }
        // совпадения поиска
        Repeater {
            model: ed.query ? ed.matches.slice(0, 500) : []
            Rectangle {
                required property int modelData
                readonly property rect r: { void (area.contentHeight); void (app.cfg.fontSize); return area.positionToRectangle(modelData); }
                x: r.x + area.x - 1; y: r.y + area.y; height: r.height; radius: 2
                width: { void (area.contentHeight); return area.positionToRectangle(modelData + ed.query.length).x - r.x + 2; }
                color: modelData === area.selectionStart ? Qt.alpha(app.pal.light, 0.35) : Qt.alpha(app.pal.acc, 0.2)
                border.width: 1; border.color: Qt.alpha(app.pal.acc, 0.5)
            }
        }
        // та же переменная в других местах файла
        Repeater {
            model: ed.occ
            Rectangle {
                required property var modelData
                readonly property rect r: { void (area.contentHeight); void (app.cfg.fontSize); return area.positionToRectangle(modelData[0]); }
                x: r.x + area.x - 1; y: r.y + area.y; height: r.height; radius: 3
                width: { void (area.contentHeight); return area.positionToRectangle(modelData[0] + modelData[1]).x - r.x + 2; }
                color: Qt.alpha(app.pal.light, 0.13)
                border.width: 1; border.color: Qt.alpha(app.pal.light, 0.4)
            }
        }
        // парные скобки
        Repeater {
            model: ed.brackets
            Rectangle {
                required property int modelData
                readonly property rect r: { void (area.contentHeight); void (app.cfg.fontSize); return area.positionToRectangle(modelData); }
                x: r.x + area.x; y: r.y + area.y; width: ed.charW; height: r.height; radius: 2
                color: ed.brackets.length === 1 ? Qt.alpha("#e8607e", 0.35) : Qt.alpha(app.pal.sel, 0.55)
                border.width: 1; border.color: ed.brackets.length === 1 ? "#e8607e" : Qt.alpha(app.pal.light, 0.6)
            }
        }

        // свёрнутые блоки: плашка «⋯» поверх метки, клик — развернуть
        Repeater {
            model: ed.foldMarks
            Rectangle {
                required property int modelData
                readonly property rect r: { void (area.contentHeight); void (app.cfg.fontSize); return area.positionToRectangle(modelData); }
                x: r.x + area.x; y: r.y + area.y + 2; height: r.height - 4; radius: 4; z: 2
                width: { void (area.contentHeight); return Math.max(ed.charW * 2, area.positionToRectangle(modelData + 2).x - r.x); }
                color: fpm.containsMouse ? app.pal.sel : app.pal.head; border.width: 1; border.color: Qt.alpha(app.pal.acc, 0.6)
                Text { anchors.centerIn: parent; font.family: app.mono; font.pixelSize: Math.max(9, app.cfg.fontSize - 3); color: app.pal.light; text: "⋯" }
                MouseArea { id: fpm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ed.unfold(parent.modelData) }
            }
        }
        // дополнительные курсоры
        Repeater {
            model: ed.extras
            Item {
                required property var modelData
                readonly property rect rs: { void (area.contentHeight); void (app.cfg.fontSize); return area.positionToRectangle(modelData.s); }
                readonly property rect re: { void (area.contentHeight); void (app.cfg.fontSize); return area.positionToRectangle(modelData.e); }
                z: 2
                Rectangle { visible: parent.modelData.e > parent.modelData.s && parent.re.y === parent.rs.y
                            x: parent.rs.x + area.x; y: parent.rs.y + area.y; width: parent.re.x - parent.rs.x; height: parent.rs.height
                            color: Qt.alpha(app.pal.sel, 0.75) }
                Rectangle { x: parent.re.x + area.x; y: parent.re.y + area.y; width: 2; height: parent.re.height; color: app.pal.light
                            opacity: caretBlink.on ? 1 : 0.35 }
            }
        }

        TextEdit {
            id: area
            x: 0; y: 0
            width: app.cfg.wrap ? flick.width - 8 : Math.max(flick.width - 8, implicitWidth + 40)
            leftPadding: 10; topPadding: 6; rightPadding: 10
            font.family: app.cfg.font; font.pixelSize: app.cfg.fontSize
            color: app.pal.text
            selectionColor: Qt.alpha(app.pal.sel, 0.75); selectedTextColor: app.pal.text
            selectByMouse: true; persistentSelection: true
            textFormat: TextEdit.PlainText
            wrapMode: app.cfg.wrap ? TextEdit.WrapAtWordBoundaryOrAnywhere : TextEdit.NoWrap
            tabStopDistance: ed.charW * app.cfg.tabWidth
            focus: true
            Keys.onPressed: e => ed.key(e)
            onTextChanged: { ed.recount(); ed.findAll(); ed.edited(); if (!ed.multiBusy && ed.extras.length) ed.extras = [];
                             ed.occ = []; ed.occAt = -1; ed.occFrom(cursorPosition); }
            onCursorPositionChanged: { if (ed.compStart >= 0 && (cursorPosition < ed.compStart || /\W/.test(text.slice(ed.compStart, cursorPosition)))) ed.closeComp();
                                       if (!ed.multiBusy && ed.extras.length) ed.extras = [];
                                       if (!hov.hovered || !hov.onWord) ed.occFrom(cursorPosition);
                                       if (ed.sig && ed.lineOf(cursorPosition) !== ed.sigLine) ed.sig = null;
                                       if (text[cursorPosition - 1] === "\uFDDF" && ed.selLen === 0) cursorPosition++;   // не внутри метки свёрнутого
                                       ed.updCursor(); Qt.callLater(ed.ensureVisible); Qt.callLater(ed.matchBracket); blink.restart(); caretBlink.on = true; }
            cursorDelegate: Item {}   // свой курсор ниже: мигает таймером, а не анимацией каждый кадр
            Timer { id: blink; interval: 530; repeat: true; running: area.activeFocus; onTriggered: caretBlink.on = !caretBlink.on }
            HoverHandler {   // описание под мышью: задержались на слове — спросить clangd/jedi
                id: hov
                property bool onWord: false
                onPointChanged: {
                    const p = point.position, pos = area.positionAt(p.x, p.y), w = ed.wordAt(pos);
                    onWord = w[1] > w[0];
                    ed.occFrom(onWord ? pos : area.cursorPosition);
                    if (ed.hover && (pos < ed.hover.a || pos > ed.hover.b)) ed.hover = null;
                    hoverTimer.pos = pos; hoverTimer.at = area.mapToItem(ed, p.x, area.positionToRectangle(pos).y); hoverTimer.restart();
                }
                onHoveredChanged: if (!hovered) { ed.hover = null; hoverTimer.stop(); onWord = false; ed.occFrom(area.cursorPosition); }
            }
            Timer { id: hoverTimer; property int pos; property point at; interval: 550; onTriggered: ed.requestHover(pos, at.x, at.y) }
        }
        MouseArea {   // Ctrl+клик — к определению, Alt+клик — ещё курсор; обычные клики проходят к тексту
            anchors.fill: area; z: 3
            cursorShape: Qt.IBeamCursor
            onPressed: m => {
                const pos = area.positionAt(m.x, m.y);
                if (m.modifiers & Qt.ControlModifier) ed.app.gotoDef(ed, pos);
                else if (m.modifiers & Qt.AltModifier) ed.addCaret(pos);
                else { m.accepted = false; return; }
                area.forceActiveFocus();
            }
        }
        Rectangle {
            id: caretBlink
            property bool on: true
            x: area.cursorRectangle.x + area.x; y: area.cursorRectangle.y + area.y
            width: 2; height: area.cursorRectangle.height
            color: app.pal.light
            visible: on && area.activeFocus && ed.selLen === 0
        }
    }

    Highlighter { document: area.textDocument; lang: ed.lang }

    // тонкие полосы прокрутки
    Rectangle {
        anchors.right: parent.right; anchors.rightMargin: 2
        visible: flick.contentHeight > flick.height
        y: flick.contentY / flick.contentHeight * flick.height; width: 5; radius: 2.5
        height: Math.max(24, flick.height * flick.height / flick.contentHeight)
        color: Qt.alpha(app.pal.acc, vs.containsMouse || vs.pressed ? 0.6 : 0.25)
        MouseArea { id: vs; anchors.fill: parent; anchors.margins: -4; hoverEnabled: true
            property real y0; property real c0
            onPressed: m => { y0 = mapToItem(ed, 0, m.y).y; c0 = flick.contentY; }
            onPositionChanged: m => { if (pressed) flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, c0 + (mapToItem(ed, 0, m.y).y - y0) * flick.contentHeight / flick.height)); } }
    }
    Repeater {   // метки ошибок на полосе прокрутки: видно, где они в файле
        model: ed.diags
        Rectangle {
            required property var modelData
            anchors.right: parent.right; width: 4; height: 3
            y: (modelData.line - 1) / Math.max(1, ed.lineCount) * flick.height
            color: modelData.sev === "error" ? "#e8607e" : "#e8b85e"
        }
    }
    Rectangle {
        y: parent.height - 7
        visible: flick.contentWidth > flick.width
        x: gutter.width + flick.contentX / flick.contentWidth * flick.width; height: 5; radius: 2.5
        width: Math.max(24, flick.width * flick.width / flick.contentWidth)
        color: Qt.alpha(app.pal.acc, 0.25)
    }
}
