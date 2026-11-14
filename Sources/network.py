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
TITLE_STOPWORDS = set("anteckning anteckningar dokument exempel frågor guide information notes overview plan project projekt sammanfattning status study uppdatering version arbete about after before from into the this that these those with utan eller efter från genom med över till under mellan och som för den det".split())


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


def sphere_direction(seed):
    z = 2 * fingerprint(seed + "/latitude") - 1
    angle = 2 * math.pi * fingerprint(seed + "/longitude")
    radius = math.sqrt(1 - z * z)
    return radius * math.cos(angle), radius * math.sin(angle), z


def suggest_visible_edges(items, visible, neighbors):
    """Offer one local bridge for isolated nodes when title or folder provides a signal."""
    visible_set = set(visible)
    covered = {key for key in visible if visible_set.intersection(neighbors[key])}
    folders = {key: posixpath.dirname(items[key]["path"]).casefold() for key in visible}
    titles = {key: {word for word in re.findall(r"[^\W\d_]+", items[key]["title"].casefold())
                    if len(word) >= 4 and word not in TITLE_STOPWORDS} for key in visible}
    result = []
    for key in visible:
        if key in covered:
            continue
        matches = []
        for other in visible:
            if other == key:
                continue
            common = titles[key] & titles[other]
            same_subfolder = "/" in folders[key] and folders[key] == folders[other]
            if common or same_subfolder:
                score = 2 * min(3, len(common)) + int(same_subfolder)
                matches.append((score, other in covered, other))
        if matches:
            _, _, other = max(matches)
            a, b = sorted((key, other))
            result.append({"a": a, "b": b, "kind": "suggested", "weight": 0.18, "count": 0})
            covered.update((key, other))
    return result


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
    # Keep a useful sample of each document type when the focus has few neighbors.
    while len(visible) < limit:
        previous = len(visible)
        for group in groups.values():
            candidate = next((key for key in group if key not in visible), None)
            if candidate and len(visible) < limit:
                visible.append(candidate)
        if len(visible) == previous:
            break
    visible_set = set(visible)
    protected = set(reserve) | set(seeds)
    for key in list(visible):
        if key not in visible_set or not neighbors[key] or visible_set.intersection(neighbors[key]):
            continue
        other = min(neighbors[key], key=lambda candidate: (-neighbors[key][candidate], candidate))
        if len(visible) < limit:
            visible.append(other)
        else:
            replace = next((candidate for candidate in reversed(visible)
                            if candidate != key and candidate not in protected
                            and layer(candidate) == layer(other)
                            and not visible_set.intersection(neighbors[candidate])), None)
            if replace is None:
                continue
            visible[visible.index(replace)] = other
            visible_set.remove(replace)
        visible_set.add(other)
    nodes = []
    for key in visible:
        row = items[key]
        parts = row["path"].split("/", 1)
        folder = parts[0] if len(parts) > 1 else ""
        anchor = sphere_direction("folder/" + folder)
        direction = sphere_direction(key)
        # A cube root samples the sphere's volume evenly. A small folder offset
        # keeps the layout stable and gently groups notes without flattening the cloud.
        radius = 0.87 * fingerprint(key + "/radius") ** (1 / 3)
        x, y, z = (0.13 * center + radius * axis for center, axis in zip(anchor, direction))
        nodes.append({"id": key, "title": row["title"], "path": row["path"], "file": row["file"],
                      "kind": row["kind"], "layer": layer(key), "x": x, "y": y, "z": z,
                      "signal": round(activation.get(key, 0), 4), "degree": len(neighbors[key])})
    links = [{"a": a, "b": b, "kind": "explicit", "weight": 0.82, "count": 1}
             for a, b in sorted(edges) if a in visible_set and b in visible_set]
    links += [{"a": a, "b": b, "kind": "learned", "weight": round(weight, 4), "count": count}
              for a, b, weight, count in live if a in visible_set and b in visible_set]
    links += suggest_visible_edges(items, visible, neighbors)
    return {"nodes": nodes, "edges": links, "total": len(items), "linked": len(edges), "learned": len(live)}
