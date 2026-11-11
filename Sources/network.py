"""Local associative memory. Explicit citations and learned edges stay distinct."""
from collections import defaultdict
from hashlib import blake2s
import math
from pathlib import Path
import posixpath
import re
import time
from urllib.parse import unquote, urlsplit

FENCES = re.compile(r"^[ \t]*(?:```|~~~).*?$.*?^[ \t]*(?:```|~~~)[ \t]*$", re.M | re.S)
WIKI_LINK = re.compile(r"(?<!!)\[\[([^\]\n]+)\]\]")
MD_LINK = re.compile(r'(?<!!)\[[^\]\n]+\]\(\s*(?:<([^>\n]+)>(?:\s+"BigBrain:[a-f0-9]{64}:[0-9]+:[0-9]+")?|([^()\n]+?))\s*\)')
HALF_LIFE = 30 * 86400


def address(text):
    return text.removesuffix(".md").casefold()


def explicit_edges(items):
    paths = {}
    exact_paths = {}
    names = defaultdict(set)
    for key, row in items.items():
        path = row["path"]
        paths[address(path)] = key
        if row["kind"] == "skill":
            paths[address("Codex Skills/" + path)] = key
            exact_paths["Codex Skills/" + path] = key
        else:
            exact_paths[path] = key
        names[address(Path(path).name)].add(key)
        names[address(row["title"])].add(key)

    def resolve(target, parent):
        if target.startswith(("./", "../")) and target.lower().endswith(".md"):
            return exact_paths.get(posixpath.normpath((parent / target).as_posix()))
        for p in (parent / target, Path(target)):
            # Normalize relative Markdown paths against the indexed library, without filesystem traversal.
            key = paths.get(address(posixpath.normpath(p.as_posix())))
            if key:
                return key
        matches = names.get(address(Path(target).name), ())
        return next(iter(matches)) if len(matches) == 1 else None

    links = set()
    for key, row in items.items():
        try:
            body = Path(row["file"]).read_text(encoding="utf-8")[:450000]
        except (OSError, UnicodeError):
            continue
        parent = Path(row["path"]).parent
        if row["kind"] == "skill":
            parent = Path("Codex Skills") / parent
        body = FENCES.sub("", body)
        targets = [value.split("|", 1)[0].split("#", 1)[0].strip() for value in WIKI_LINK.findall(body)]
        for first, second in MD_LINK.findall(body):
            raw = (first or second).strip()
            if re.search(r'\s+["\']', raw):
                raw = re.split(r'\s+["\']', raw, maxsplit=1)[0]
            try:
                url = urlsplit(raw)
            except ValueError:
                continue
            if not url.scheme and not url.netloc and url.path.lower().endswith(".md"):
                targets.append(unquote(url.path))
        for target in targets:
            other = resolve(target, parent) if target else None
            if other and other != key:
                links.add((key, other))
    return links


def effective(weight, updated, now):
    return weight * 0.5 ** (max(0, now - updated) / HALF_LIFE)


def reinforce(conn, library, one, two, now=None):
    if not one or one == two:
        return {"learned": False}
    if conn.execute("SELECT COUNT(*) FROM files WHERE key IN (?, ?)", (one, two)).fetchone()[0] != 2:
        return {"learned": False}
    now = time.time() if now is None else now
    a, b = sorted((one, two))
    conn.execute("BEGIN IMMEDIATE")
    row = conn.execute("SELECT weight, updated FROM associations WHERE library=? AND a=? AND b=?",
                       (library, a, b)).fetchone()
    prior = effective(row[0], row[1], now) if row else 0
    weight = prior + 0.28 * (1 - prior)
    conn.execute("""INSERT INTO associations VALUES (?,?,?,?,?,1)
                 ON CONFLICT(library,a,b) DO UPDATE SET weight=excluded.weight,
                 updated=excluded.updated, count=associations.count+1""", (library, a, b, weight, now))
    return {"learned": True, "weight": weight}


def fingerprint(text):
    return int.from_bytes(blake2s(text.encode("utf-8"), digest_size=8).digest(), "big") / 2**64


def layout(items, edges, learned, seeds, focus, limit, now=None):
    now = time.time() if now is None else now
    neighbors = defaultdict(dict)
    for a, b in edges:
        neighbors[a][b] = neighbors[b][a] = 0.82
    live = []
    for a, b, weight, updated, count in learned:
        if a not in items or b not in items:
            continue
        weight = effective(weight, updated, now)
        if weight < 0.035:
            continue
        live.append((a, b, weight, count))
        merged = max(neighbors[a].get(b, 0), weight)
        neighbors[a][b] = neighbors[b][a] = merged

    activation = {}
    if focus in items:
        seeds = [focus, *(seed for seed in seeds if seed != focus)]
    for rank, key in enumerate(seeds):
        if key in items:
            activation[key] = 1 / (1 + rank * 0.25)
    frontier = dict(activation)
    for _ in range(2):
        next_step = {}
        for key, value in frontier.items():
            for linked, weight in neighbors[key].items():
                signal = value * weight * 0.58
                next_step[linked] = max(next_step.get(linked, 0), signal)
                activation[linked] = max(activation.get(linked, 0), signal)
        frontier = next_step

    def layer(key):
        row = items[key]
        if row["kind"] == "skill":
            return "skill"
        if row["kind"] == "inbox" or "/references/" in row["path"]:
            return "source"
        return "note"

    chosen = sorted(items, key=lambda key: (-activation.get(key, 0), -len(neighbors[key]), key))
    groups = {label: [key for key in chosen if layer(key) == label] for label in ("source", "note", "skill")}
    reserve = [key for group in groups.values() for key in group[:2]]
    visible = list(dict.fromkeys([*reserve, *(key for key in chosen if activation.get(key, 0) > 0)]))[:limit]
    # Reserve a useful sample of each depth plane when the focus has few neighbors.
    while len(visible) < limit:
        previous = len(visible)
        for group in groups.values():
            candidate = next((key for key in group if key not in visible), None)
            if candidate and len(visible) < limit:
                visible.append(candidate)
        if len(visible) == previous:
            break
    visible_set = set(visible)
    nodes = []
    planes = {"source": -0.81, "note": 0.0, "skill": 0.81}
    for key in visible:
        row = items[key]
        top = row["path"].split("/")[0]
        # Folder anchors keep a family together while each node retains a stable position.
        cluster = 2 * math.pi * fingerprint(top)
        angle = 2 * math.pi * fingerprint(key)
        radius = 0.28 + 0.59 * math.sqrt(fingerprint(key + "/radius"))
        x = 0.38 * math.cos(cluster) + radius * math.cos(angle)
        y = 0.30 * math.sin(cluster) + radius * math.sin(angle)
        nodes.append({"id": key, "title": row["title"], "path": row["path"], "file": row["file"],
                      "kind": row["kind"], "layer": layer(key), "x": x, "y": y, "z": planes[layer(key)],
                      "signal": round(activation.get(key, 0), 4), "degree": len(neighbors[key])})
    links = [{"a": a, "b": b, "kind": "explicit", "weight": 0.82, "count": 1}
             for a, b in sorted(edges) if a in visible_set and b in visible_set]
    links += [{"a": a, "b": b, "kind": "learned", "weight": round(weight, 4), "count": count}
              for a, b, weight, count in live if a in visible_set and b in visible_set]
    return {"nodes": nodes, "edges": links, "total": len(items), "linked": len(edges), "learned": len(live)}
