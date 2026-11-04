"""Помощник D3R Code для Python: автодополнение и подсказки (jedi), форматирование (black / autopep8),
проверка синтаксиса. Редактор запускает его один раз и говорит строками JSON через stdin/stdout:
  → {"id": 1, "op": "complete", "body": {lang, path, text, line, col, ...}}   ← {"id": 1, "res": {...}}
Первой строкой помощник сообщает {"ready": true, "jedi": true|false}. Формы ответов — как в lsp.py (D3R Code для Linux)."""
import json, sys

try: import jedi
except ImportError: jedi = None
# вид варианта jedi → вид LSP (как у clangd), чтобы редактор рисовал одинаково
JEDI_KIND = {"function": 3, "class": 7, "module": 9, "instance": 6, "statement": 6, "param": 6, "keyword": 14,
             "property": 10, "path": 17}


def py_complete(path, text, line, col):
    out = []
    for c in jedi.Script(code=text, path=path or None).complete(line + 1, col)[:80]:
        call = c.type in ("function", "class")
        label = c.name + ("()" if call else "")
        if call:   # есть ли параметры — от этого зависит, встанет ли курсор внутрь скобок
            try:
                sig = c.get_signatures()
                if sig and sig[0].params and not (c.type == "class" and [p.name for p in sig[0].params] == ["self"]):
                    label = c.name + "(" + ", ".join(p.name for p in sig[0].params) + ")"
            except Exception: pass
        try: doc = c.docstring(raw=True)[:400]
        except Exception: doc = ""
        out.append({"label": label, "insert": c.name, "kind": JEDI_KIND.get(c.type, 0), "detail": c.type if c.type != "statement" else "",
                    "doc": doc, "start": -1})
    return out


def py_signature(path, text, line, col):
    sigs = jedi.Script(code=text, path=path or None).get_signatures(line + 1, col)
    if not sigs: return {}
    s, params, label = sigs[0], [], sigs[0].name + "("
    for i, p in enumerate(s.params):
        if i: label += ", "
        params.append([len(label), len(label) + len(p.to_string())]); label += p.to_string()
    return {"label": label + ")", "params": params, "active": s.index or 0}


def py_hover(path, text, line, col):
    names = jedi.Script(code=text, path=path or None).help(line + 1, col)
    if not names: return {"text": ""}
    n = names[0]
    doc = n.docstring() or ""
    return {"text": (doc if doc.startswith(n.name) else (n.description + "\n\n" + doc)).strip()[:1500]}


def py_definition(path, text, line, col):
    for d in jedi.Script(code=text, path=path or None).goto(line + 1, col, follow_imports=True):
        if d.module_path and d.line: return {"path": str(d.module_path), "line": d.line, "col": d.column + 1}
    return {}


def py_highlight(path, text, line, col):
    refs = jedi.Script(code=text, path=path or None).get_references(line + 1, col, scope="file")
    return {"items": [[r.line - 1, r.column, len(r.name)] for r in refs if r.line]}


def py_rename(path, text, line, col, name):
    ch = jedi.Script(code=text, path=path or None).rename(line + 1, col, new_name=name).get_changed_files()
    return {"files": {str(p): f.get_new_code() for p, f in ch.items()}}


def py_symbols(path, text):
    out = []
    for n in jedi.Script(code=text, path=path or None).get_names(all_scopes=True, definitions=True):
        if n.type not in ("function", "class"): continue
        depth, p = 0, n.parent()
        while p and p.type != "module": depth += 1; p = p.parent()
        out.append({"name": n.name, "kind": 5 if n.type == "class" else 6 if depth else 12, "line": n.line, "depth": depth})
    return {"items": out}

def check(path, text):   # синтаксис: ошибки в том же виде, что у g++ в редакторе
    try:
        compile(text, path or "<file>", "exec")
        return {"items": []}
    except SyntaxError as e:
        return {"items": [{"line": e.lineno or 1, "col": e.offset or 1, "sev": "error", "msg": e.msg}]}


def fmt(text):
    try:
        import black
        return {"text": black.format_str(text, mode=black.Mode())}
    except ImportError:
        pass
    except Exception as e:
        return {"error": str(e).splitlines()[0][:200]}
    try:
        import autopep8
        return {"text": autopep8.fix_code(text)}
    except ImportError:
        return {"error": "нет форматтера Python: py -m pip install black"}


def handle(op, b):
    path, text = b.get("path") or None, b.get("text", "")
    pos = (int(b.get("line", 0)), int(b.get("col", 0)))
    if op == "check": return check(path, text)
    if op == "format": return fmt(text)
    if not jedi: return {}
    if op == "complete": return {"items": py_complete(path, text, *pos)}
    if op == "symbols": return py_symbols(path, text)
    if op == "rename": return py_rename(path, text, *pos, b["name"])
    return {"signature": py_signature, "hover": py_hover, "definition": py_definition, "highlight": py_highlight}[op](path, text, *pos)


def main():
    out = sys.stdout
    out.write(json.dumps({"ready": True, "jedi": bool(jedi)}) + "\n"); out.flush()
    for line in sys.stdin:
        try: msg = json.loads(line)
        except ValueError: continue
        try: res = handle(msg.get("op"), msg.get("body") or {})
        except Exception as e: res = {"items": [], "error": str(e)}
        out.write(json.dumps({"id": msg.get("id"), "res": res}, ensure_ascii=False) + "\n"); out.flush()


if __name__ == "__main__":
    if sys.argv[1:] == ["--test"]:
        assert check("t.py", "def f(:\n")["items"][0]["line"] == 1
        assert check("t.py", "x = 1\n")["items"] == []
        if jedi: assert any(i["insert"] == "print" for i in py_complete("t.py", "pri", 0, 3))
        print("pyhelper OK, jedi:", bool(jedi))
    else: main()
