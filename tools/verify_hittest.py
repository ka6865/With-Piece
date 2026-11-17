"""설계 문서 4.3 투영과 4.4 hit-test를 실제 데이터로 검증한다.

229개 조각 각각에 대해 내부 점을 하나 찾아 탭했을 때 그 조각이
선택되는지 확인한다. Dart 구현이 통과해야 할 기준을 미리 확인하는 용도다.
"""
import json, math, sys, collections, re

MERGE = {"수원시","성남시","안양시","안산시","고양시","용인시","청주시","천안시","전주시","포항시","창원시"}
ULLEUNG = "37430"

def merged_city(name):
    m = re.match(r"^(.+시)(.+구)$", name)
    return m.group(1) if m and m.group(1) in MERGE else None

def build_id_map(entries):
    city_codes = collections.defaultdict(list)
    for c, n in entries:
        city = merged_city(n)
        if city: city_codes[city].append(c)
    city_ids = {city: cs[0][:2] + "-" + min(cs) for city, cs in city_codes.items()}
    out = {}
    for c, n in entries:
        city = merged_city(n)
        out[c] = city_ids[city] if city else c
    return out

def polys(geom):
    return [geom["coordinates"]] if geom["type"] == "Polygon" else geom["coordinates"]

def project(lon, lat, bbox, w, h):
    west, south, east, north = bbox
    cos = math.cos(math.radians((south + north) / 2))
    spanx = (east - west) * cos
    spany = north - south
    k = min(w / spanx, h / spany)
    dx = (w - spanx * k) / 2
    dy = (h - spany * k) / 2
    return dx + (lon - west) * cos * k, dy + (north - lat) * k

def in_ring(pt, ring):
    """짝수-홀수 규칙."""
    x, y = pt
    inside = False
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        if (y1 > y) != (y2 > y):
            xi = (x2 - x1) * (y - y1) / (y2 - y1) + x1
            if x < xi:
                inside = not inside
    return inside

def main(path):
    feats = json.load(open(path, encoding="utf-8"))["features"]
    entries = [(f["properties"]["code"], f["properties"]["name"]) for f in feats]
    id_map = build_id_map(entries)

    # 본토 bbox (울릉군 제외)
    lons, lats = [], []
    for f in feats:
        if f["properties"]["code"] == ULLEUNG: continue
        for poly in polys(f["geometry"]):
            for ring in poly:
                for p in ring:
                    lons.append(p[0]); lats.append(p[1])
    bbox = (min(lons), min(lats), max(lons), max(lats))
    W, H = 390.0, 600.0

    # 조각별 화면좌표 폴리곤
    shapes = collections.defaultdict(list)
    for f in feats:
        code = f["properties"]["code"]
        if code == ULLEUNG: continue
        pid = id_map[code]
        for poly in polys(f["geometry"]):
            rings = [[project(p[0], p[1], bbox, W, H) for p in ring] for ring in poly]
            shapes[pid].append(rings)

    def area(rings):
        r = rings[0]; s = 0.0
        for i in range(len(r)):
            x1,y1 = r[i]; x2,y2 = r[(i+1)%len(r)]
            s += x1*y2 - x2*y1
        return abs(s)/2

    def hit(pt):
        cands = []
        for pid, plist in shapes.items():
            for rings in plist:
                xs = [p[0] for p in rings[0]]; ys = [p[1] for p in rings[0]]
                if not (min(xs) <= pt[0] <= max(xs) and min(ys) <= pt[1] <= max(ys)):
                    continue
                if not in_ring(pt, rings[0]):
                    continue
                if any(in_ring(pt, hole) for hole in rings[1:]):
                    continue
                cands.append((area(rings), pid))
        if not cands: return None
        return min(cands)[1]

    # 각 조각의 대표 내부 점을 찾는다: 최대 면적 폴리곤의 무게중심 주변 탐색
    fails = []
    tested = 0
    for pid, plist in shapes.items():
        best = max(plist, key=area)
        r = best[0]
        cx = sum(p[0] for p in r)/len(r); cy = sum(p[1] for p in r)/len(r)
        pt = None
        if in_ring((cx,cy), r) and not any(in_ring((cx,cy),h) for h in best[1:]):
            pt = (cx,cy)
        else:
            xs=[p[0] for p in r]; ys=[p[1] for p in r]
            for i in range(1,60):
                t=i/60.0
                cand=(min(xs)+(max(xs)-min(xs))*t, cy)
                if in_ring(cand,r) and not any(in_ring(cand,h) for h in best[1:]):
                    pt=cand; break
        if pt is None:
            fails.append((pid,"내부점 못찾음")); continue
        tested += 1
        got = hit(pt)
        if got != pid:
            fails.append((pid, "탭 결과 %s" % got))

    print("본토 bbox:", tuple(round(v,5) for v in bbox))
    print("조각 수(본토): %d" % len(shapes))
    print("내부점 확보: %d" % tested)
    print("실패: %d" % len(fails))
    for f in fails[:20]: print("  ", f)

main(sys.argv[1])
