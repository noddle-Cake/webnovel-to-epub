"""Regenerate the code-drawn book icon without imaging dependencies."""
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1] / 'flutter_app'


def inside_polygon(x, y, points):
    inside = False
    previous = points[-1]
    for current in points:
        px, py = previous
        cx, cy = current
        if (cy > y) != (py > y) and x < (px - cx) * (y - cy) / (py - cy) + cx:
            inside = not inside
        previous = current
    return inside


def color(x, y):
    ink = (25, 62, 54)
    cream = (245, 239, 224)
    left = [(0.23, .29), (.44, .29), (.49, .33), (.49, .72), (.43, .68), (.23, .68)]
    right = [(0.51, .33), (.56, .29), (.77, .29), (.77, .68), (.57, .68), (.51, .72)]
    if inside_polygon(x, y, left) or inside_polygon(x, y, right):
        for line in [.40, .48, .56]:
            if abs(y - line) < .009 and (.28 < x < .43 or .57 < x < .72):
                return ink
        return cream
    return ink


def make_png(size):
    data = bytearray()
    for y in range(size):
        data.append(0)
        for x in range(size):
            samples = [color((x + dx) / size, (y + dy) / size)
                       for dx, dy in [(.25, .25), (.75, .25), (.25, .75), (.75, .75)]]
            data.extend(sum(c[i] for c in samples) // 4 for i in range(3))
    def chunk(kind, payload):
        return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress(bytes(data))) + chunk(b'IEND', b''))


if __name__ == '__main__':
    paths = list((ROOT / 'web/icons').glob('*.png'))
    paths += [ROOT / 'web/favicon.png']
    paths += list((ROOT / 'android/app/src/main/res').glob('mipmap-*/ic_launcher.png'))
    paths += list((ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset').glob('*.png'))
    cache = {}
    for path in paths:
        size = struct.unpack('>I', path.read_bytes()[16:20])[0]
        if size not in cache:
            cache[size] = make_png(size)
        path.write_bytes(cache[size])
    print(f'Generated {len(paths)} platform icons.')
