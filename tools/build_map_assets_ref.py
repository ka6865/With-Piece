"""계획서에 넣을 Dart 전처리의 참조 구현. 산출물 스키마와 값을 확정한다."""
import collections, json, re, sys

MERGE = {"수원시","성남시","안양시","안산시","고양시","용인시","청주시","천안시","전주시","포항시","창원시"}
ULLEUNG = "37430"
INSET_LON_SPLIT = 131.0

def decode_arcs(topo):
    sx, sy = topo["transform"]["scale"]
    tx, ty = topo["transform"]["translate"]
    out = []
    for arc in topo["arcs"]:
        x = y = 0; pts = []
        for dx, dy in arc:
            x += dx; y += dy
            pts.append([x * sx + tx, y * sy + ty])
        out.append(pts)
    return out

def ring(arcs, idx_list):
    pts = []
    for i in idx_list:
        a = arcs[~i][::-1] if i < 0 else arcs[i]
        pts.extend(a if not pts else a[1:])
    if pts and pts[0] != pts[-1]:
        pts.append(pts[0])
    return pts

def merged_city(name):
    m = re.match(r"^(.+시)(.+구)$", name)
    return m.group(1) if m and m.group(1) in MERGE else None

def load(path):
    topo = json.load(open(path, encoding="utf-8"))
    arcs = decode_arcs(topo)
    key = list(topo["objects"].keys())[0]
    raw = []
    for g in topo["objects"][key]["geometries"]:
        p = g["properties"]
        polys = [g["arcs"]] if g["type"] == "Polygon" else g["arcs"]
        raw.append({
            "code": p["code"], "name": p["name"],
            "polygons": [[ring(arcs, r) for r in poly] for poly in polys],
        })
    return raw

def build(raw):
    city_codes = collections.defaultdict(list)
    for f in raw:
        c = merged_city(f["name"])
        if c: city_codes[c].append(f["code"])
    city_ids = {c: cs[0][:2] + "-" + min(cs) for c, cs in city_codes.items()}

    merged = collections.OrderedDict()
    for f in raw:
        city = merged_city(f["name"])
        pid = city_ids[city] if city else f["code"]
        name = city if city else f["name"]
        if pid not in merged:
            merged[pid] = {"id": pid, "parentId": pid[:2], "name": name, "polygons": []}
        merged[pid]["polygons"].extend(f["polygons"])
    return merged

def bbox(polys):
    lons = [p[0] for poly in polys for r in poly for p in r]
    lats = [p[1] for poly in polys for r in poly for p in r]
    return [min(lons), min(lats), max(lons), max(lats)]

def main(src, dst):
    merged = build(load(src))
    assert len(merged) == 229, len(merged)

    mainland = [f["polygons"] for pid, f in merged.items() if pid != ULLEUNG]
    flat = [poly for polys in mainland for poly in polys]
    mb = bbox(flat)

    ull = merged[ULLEUNG]["polygons"]
    ulleung_idx = [i for i, poly in enumerate(ull)
                   if max(p[0] for r in poly for p in r) < INSET_LON_SPLIT]
    dokdo_idx = [i for i, poly in enumerate(ull)
                 if max(p[0] for r in poly for p in r) >= INSET_LON_SPLIT]
    assert ulleung_idx and dokdo_idx

    for f in merged.values():
        f["polygons"] = [[[[round(p[0], 5), round(p[1], 5)] for p in r]
                          for r in poly] for poly in f["polygons"]]

    payload = {
        "version": 1,
        "mainlandBbox": [round(v, 5) for v in mb],
        "insets": [
            {"id": "ulleung", "regionId": ULLEUNG,
             "bbox": [round(v, 5) for v in bbox([ull[i] for i in ulleung_idx])],
             "polygonIndexes": ulleung_idx},
            {"id": "dokdo", "regionId": ULLEUNG,
             "bbox": [round(v, 5) for v in bbox([ull[i] for i in dokdo_idx])],
             "polygonIndexes": dokdo_idx},
        ],
        "features": list(merged.values()),
    }
    json.dump(payload, open(dst, "w", encoding="utf-8"),
              ensure_ascii=False, separators=(",", ":"))

    pts = sum(len(r) for f in merged.values() for poly in f["polygons"] for r in poly)
    print("조각 %d, 점 %d" % (len(merged), pts))
    print("mainlandBbox", [round(v,5) for v in mb])
    for ins in payload["insets"]:
        print(ins["id"], [round(v,5) for v in ins["bbox"]], ins["polygonIndexes"])
    prov = collections.Counter(f["parentId"] for f in merged.values())
    print("시도 수", len(prov))

main(sys.argv[1], sys.argv[2])
