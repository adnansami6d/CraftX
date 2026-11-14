#!/usr/bin/env python3
"""Shrinks characters/valery.glb: drops normal / metal-rough / occlusion maps, resizes the
colour maps, simplifies the meshes (quadric edge collapse with UV error) and packs the vertex data.
usage: python3 shrink_glb.py in.glb out.glb [total_triangles]"""
import sys, json, struct, io, heapq
import numpy as np
from PIL import Image

CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}
BORDER_W = 10.0
UV_W = 1.5          # how strongly texture-coordinate error counts compared to position error (metres per uv unit)


def read_glb(path):
    d = open(path, 'rb').read()
    jl = struct.unpack('<I', d[12:16])[0]
    j = json.loads(d[20:20 + jl])
    binchunk = d[20 + jl + 8:]
    return j, binchunk


def acc(j, b, i):
    a = j['accessors'][i]
    bv = j['bufferViews'][a['bufferView']]
    dt = np.dtype(CT[a['componentType']])
    n = NC[a['type']]
    off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride')
    if stride and stride != dt.itemsize * n:
        raw = np.frombuffer(b, dtype=np.uint8, count=stride * a['count'], offset=off).reshape(a['count'], stride)
        arr = np.frombuffer(raw[:, :dt.itemsize * n].tobytes(), dtype=dt).reshape(a['count'], n)
    else:
        arr = np.frombuffer(b, dtype=dt, count=a['count'] * n, offset=off).reshape(a['count'], n)
    return arr


# ------------------------------------------------------------------ simplification
def simplify(P, UV, T, target, log=print):
    n = len(P)
    X = np.hstack([P.astype(np.float64), UV.astype(np.float64) * UV_W])   # 5D vertices
    m = len(T)
    QA = np.zeros((n, 5, 5)); Qb = np.zeros((n, 5)); Qc = np.zeros(n)
    I5 = np.eye(5)
    edge_faces = {}
    for fi, (a, b_, c) in enumerate(T):
        for u, v in ((a, b_), (b_, c), (c, a)):
            k = (u, v) if u < v else (v, u)
            edge_faces[k] = edge_faces.get(k, 0) + 1
        p, q, r = X[a], X[b_], X[c]
        e1 = q - p
        l1 = np.linalg.norm(e1)
        if l1 < 1e-12:
            continue
        e1 = e1 / l1
        e2 = (r - p) - np.dot(e1, r - p) * e1
        l2 = np.linalg.norm(e2)
        if l2 < 1e-12:
            continue
        e2 = e2 / l2
        area = 0.5 * np.linalg.norm(np.cross(P[b_] - P[a], P[c] - P[a])) + 1e-9
        A = I5 - np.outer(e1, e1) - np.outer(e2, e2)
        bb = np.dot(p, e1) * e1 + np.dot(p, e2) * e2 - p
        cc = np.dot(p, p) - np.dot(p, e1) ** 2 - np.dot(p, e2) ** 2
        for v in (a, b_, c):
            QA[v] += area * A; Qb[v] += area * bb; Qc[v] += area * cc
    # vertices that sit on a border (hair strips, UV seams) and vertices that have a twin at the same place (seams)
    keyp = [tuple(np.round(p, 5)) for p in P]
    cnt_p = {}
    for k in keyp:
        cnt_p[k] = cnt_p.get(k, 0) + 1
    twin = np.array([cnt_p[k] > 1 for k in keyp])
    bnd = np.zeros(n, bool)
    for fi, (a, b_, c) in enumerate(T):
        fn = np.cross(P[b_] - P[a], P[c] - P[a]); fl = np.linalg.norm(fn)
        if fl < 1e-14:
            continue
        fn = fn / fl
        for u, v in ((a, b_), (b_, c), (c, a)):
            k = (u, v) if u < v else (v, u)
            if edge_faces[k] != 1:
                continue
            bnd[u] = True; bnd[v] = True
            ed = P[v] - P[u]; el = np.linalg.norm(ed)
            if el < 1e-12:
                continue
            n3 = np.cross(ed / el, fn); n3 /= max(np.linalg.norm(n3), 1e-12)
            nn = np.concatenate([n3, [0.0, 0.0]])
            d = -float(np.dot(n3, P[u]))
            w = BORDER_W * el * el
            for x in (u, v):
                QA[x] += w * np.outer(nn, nn); Qb[x] += w * d * nn; Qc[x] += w * d * d
    locked = twin.copy()
    log('  vertices %d, triangles %d, border %d, seam-twins (locked) %d' % (n, m, bnd.sum(), twin.sum()))

    faces = [list(map(int, t)) for t in T]
    fal = [True] * m
    vf = [set() for _ in range(n)]
    for fi, t in enumerate(faces):
        for v in t:
            vf[v].add(fi)
    alive_v = [True] * n
    stamp = [0] * n
    ntri = m

    def cost(a, b):
        # collapse a into b: error of putting vertex b's 5D position into the merged quadric
        A = QA[a] + QA[b]; bb = Qb[a] + Qb[b]; c = Qc[a] + Qc[b]
        x = X[b]
        return float(x @ A @ x + 2 * bb @ x + c)

    def nbrs(v):
        s = set()
        for f in vf[v]:
            for w in faces[f]:
                if w != v:
                    s.add(w)
        return s

    heap = []

    def push(a, b):
        if locked[a]:
            return
        heapq.heappush(heap, (cost(a, b), a, b, stamp[a], stamp[b]))

    for v in range(n):
        for w in nbrs(v):
            push(v, w)

    def ok(a, b):
        shared = vf[a] & vf[b]
        if not shared:
            return False
        na = nbrs(a); nb = nbrs(b)
        common = (na & nb)
        if len(common) != len(shared):          # would make a non-manifold / pinched surface
            return False
        if bnd[a] and not (bnd[b] and len(shared) == 1):   # a border vertex may only slide along the border
            return False
        for f in vf[a]:
            if f in shared:
                continue
            t = faces[f]
            old = [P[x] for x in t]
            new = [P[b] if x == a else P[x] for x in t]
            n0 = np.cross(old[1] - old[0], old[2] - old[0])
            n1 = np.cross(new[1] - new[0], new[2] - new[0])
            l0 = np.linalg.norm(n0); l1 = np.linalg.norm(n1)
            if l1 < 1e-10 or l0 < 1e-14:
                return False
            if np.dot(n0, n1) / (l0 * l1) < 0.35:
                return False
            u0 = [UV[x] for x in t]
            u1 = [UV[b] if x == a else UV[x] for x in t]
            s0 = (u0[1][0] - u0[0][0]) * (u0[2][1] - u0[0][1]) - (u0[1][1] - u0[0][1]) * (u0[2][0] - u0[0][0])
            s1 = (u1[1][0] - u1[0][0]) * (u1[2][1] - u1[0][1]) - (u1[1][1] - u1[0][1]) * (u1[2][0] - u1[0][0])
            if s0 * s1 < 0:
                return False
        return True

    while heap and ntri > target:
        c, a, b, sa, sb = heapq.heappop(heap)
        if not (alive_v[a] and alive_v[b]) or stamp[a] != sa or stamp[b] != sb:
            continue
        if not ok(a, b):
            continue
        # collapse a -> b
        for f in list(vf[a]):
            t = faces[f]
            if b in t:
                fal[f] = False
                ntri -= 1
                for v in t:
                    vf[v].discard(f)
            else:
                faces[f] = [b if x == a else x for x in t]
                vf[b].add(f)
        vf[a] = set()
        alive_v[a] = False
        QA[b] += QA[a]; Qb[b] += Qb[a]; Qc[b] += Qc[a]
        stamp[b] += 1
        for w in nbrs(b):
            stamp[w] += 0
            push(b, w)
            push(w, b)
    keep = [f for f in range(m) if fal[f]]
    log('  -> triangles %d' % len(keep))
    return np.array([faces[f] for f in keep], dtype=np.int64)


# ------------------------------------------------------------------ main
def main():
    src, dst = sys.argv[1], sys.argv[2]
    total = int(sys.argv[3]) if len(sys.argv) > 3 else 10000
    j, b = read_glb(src)
    # triangle budget per mesh (the body is mostly hidden under clothes, so it gets the biggest cut)
    share = {0: 0.52, 1: 0.10, 2: 0.20, 3: 0.08, 4: 0.10}
    out = bytearray()
    views = []; accs = []

    def add_view(data, target=None):
        while len(out) % 4:
            out.append(0)
        views.append({'buffer': 0, 'byteOffset': len(out), 'byteLength': len(data), **({'target': target} if target else {})})
        out.extend(data)
        return len(views) - 1

    def add_acc(vi, ctype, count, typ, **kw):
        accs.append({'bufferView': vi, 'componentType': ctype, 'count': count, 'type': typ, **kw})
        return len(accs) - 1

    for mi, mesh in enumerate(j['meshes']):
        p = mesh['primitives'][0]
        at = p['attributes']
        P = acc(j, b, at['POSITION']).astype(np.float64)
        N = acc(j, b, at['NORMAL']).astype(np.float32)
        UV = acc(j, b, at['TEXCOORD_0']).astype(np.float32)
        J = acc(j, b, at['JOINTS_0']).astype(np.int64)
        W = acc(j, b, at['WEIGHTS_0']).astype(np.float32)
        T = acc(j, b, p['indices']).astype(np.int64).reshape(-1, 3)
        tgt = max(300, int(total * share.get(mi, 0.1)))
        print(mesh['name'], 'material', p['material'], 'tris', len(T), '-> target', tgt)
        if len(T) > tgt:
            T = simplify(P, UV.astype(np.float64), T, tgt)
        used = np.unique(T)
        remap = -np.ones(len(P), np.int64); remap[used] = np.arange(len(used))
        T = remap[T]
        P = P[used].astype(np.float32); N = N[used]; UV = UV[used]; J = J[used]; W = W[used]
        N = N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-8)
        # weights (rounded to 1/255 steps, then stored as float)
        W = W / np.maximum(W.sum(axis=1, keepdims=True), 1e-8)
        Wb = np.round(W * 255).astype(np.int64)
        diff = 255 - Wb.sum(axis=1)
        Wb[np.arange(len(Wb)), np.argmax(Wb, axis=1)] += diff
        Wb = np.clip(Wb, 0, 255).astype(np.uint8)
        Jb = J.astype(np.uint8)
        # flip winding is NOT changed
        prim = {'mode': 4, 'material': p['material'], 'attributes': {}}
        vi = add_view(P.astype('<f4').tobytes(), 34962)
        prim['attributes']['POSITION'] = add_acc(vi, 5126, len(P), 'VEC3', min=P.min(0).tolist(), max=P.max(0).tolist())
        vi = add_view(N.astype('<f4').tobytes(), 34962)
        prim['attributes']['NORMAL'] = add_acc(vi, 5126, len(N), 'VEC3')
        vi = add_view(UV.astype('<f4').tobytes(), 34962)
        prim['attributes']['TEXCOORD_0'] = add_acc(vi, 5126, len(UV), 'VEC2')
        vi = add_view(Jb.tobytes(), 34962)
        prim['attributes']['JOINTS_0'] = add_acc(vi, 5121, len(Jb), 'VEC4')
        Wf = (Wb.astype(np.float32) / 255.0)
        Wf = Wf / Wf.sum(axis=1, keepdims=True)        # float weights: every Godot version reads them the same way
        vi = add_view(Wf.astype('<f4').tobytes(), 34962)
        prim['attributes']['WEIGHTS_0'] = add_acc(vi, 5126, len(Wf), 'VEC4')
        vi = add_view(T.astype('<u2').reshape(-1).tobytes(), 34963)
        prim['indices'] = add_acc(vi, 5123, T.size, 'SCALAR')
        mesh['primitives'] = [prim]
        print('   final verts', len(P), 'tris', len(T))

    # inverse bind matrices
    sk = j['skins'][0]
    ibm = acc(j, b, sk['inverseBindMatrices']).astype('<f4')
    vi = add_view(ibm.tobytes())
    sk['inverseBindMatrices'] = add_acc(vi, 5126, len(ibm), 'MAT4')

    # materials: colour map only
    new_tex = []; new_img = []; tex_of = {}
    sizes = {0: 512, 3: 256, 5: 256, 8: 512}       # old texture index -> max size
    for m in j['materials']:
        pbr = m['pbrMetallicRoughness']
        ti = pbr['baseColorTexture']['index']
        if ti not in tex_of:
            im = j['images'][j['textures'][ti]['source']]
            bv = j['bufferViews'][im['bufferView']]
            raw = b[bv['byteOffset']:bv['byteOffset'] + bv['byteLength']]
            img = Image.open(io.BytesIO(raw))
            s = sizes[ti]
            img = img.resize((s, s), Image.LANCZOS)
            buf = io.BytesIO()
            if img.mode in ('LA', 'RGBA'):
                img.save(buf, 'PNG', optimize=True); mt = 'image/png'
            else:
                img.convert('RGB').save(buf, 'JPEG', quality=84, optimize=True, subsampling=1); mt = 'image/jpeg'
            vi = add_view(buf.getvalue())
            new_img.append({'bufferView': vi, 'mimeType': mt})
            new_tex.append({'sampler': j['textures'][ti].get('sampler', 0), 'source': len(new_img) - 1})
            tex_of[ti] = len(new_tex) - 1
            print('texture', ti, s, len(buf.getvalue()), 'bytes')
        pbr['baseColorTexture'] = {'index': tex_of[ti]}
        pbr.pop('metallicRoughnessTexture', None)
        m.pop('normalTexture', None); m.pop('occlusionTexture', None)
        pbr['metallicFactor'] = 0.0
        pbr['roughnessFactor'] = 0.8
    j['textures'] = new_tex
    j['images'] = new_img
    j['samplers'] = [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 33071, 'wrapT': 33071},
                     {'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497},
                     {'magFilter': 9729, 'minFilter': 9987, 'wrapS': 33071, 'wrapT': 33071}]
    j['bufferViews'] = views
    j['accessors'] = accs
    while len(out) % 4:
        out.append(0)
    j['buffers'] = [{'byteLength': len(out)}]
    js = json.dumps(j, separators=(',', ':')).encode()
    while len(js) % 4:
        js += b' '
    glb = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(out)) + struct.pack('<II', len(js), 0x4E4F534A) + js \
        + struct.pack('<II', len(out), 0x004E4942) + bytes(out)
    open(dst, 'wb').write(glb)
    print('WROTE', dst, len(glb), 'bytes')


if __name__ == '__main__':
    main()
