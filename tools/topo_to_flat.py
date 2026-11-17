import json, sys

def decode_arcs(topo):
    sx, sy = topo["transform"]["scale"]
    tx, ty = topo["transform"]["translate"]
    out = []
    for arc in topo["arcs"]:
        x = y = 0
        pts = []
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
    return pts

def main(src, dst):
    topo = json.load(open(src, encoding="utf-8"))
    arcs = decode_arcs(topo)
    key = list(topo["objects"].keys())[0]
    feats = []
    for g in topo["objects"][key]["geometries"]:
        p = g["properties"]
        if g["type"] == "Polygon":
            polys = [g["arcs"]]
        else:
            polys = g["arcs"]
        feats.append({
            "code": p["code"],
            "name": p["name"],
            "polygons": [[ring(arcs, r) for r in poly] for poly in polys],
        })
    json.dump({"features": feats}, open(dst, "w", encoding="utf-8"), ensure_ascii=False)
    print("피처 %d" % len(feats))

main(sys.argv[1], sys.argv[2])
