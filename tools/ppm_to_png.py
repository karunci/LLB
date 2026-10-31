import zlib
import struct
import sys

def ppm_to_png(ppm_path, png_path):
    with open(ppm_path, "rb") as f:
        magic = f.readline().strip()
        line = f.readline()
        while line.startswith(b"#"):
            line = f.readline()
        w, h = map(int, line.split())
        maxval = int(f.readline().strip())
        raw = f.read()

    raw_lines = [b"\x00" + raw[r * w * 3 : (r + 1) * w * 3] for r in range(h)]
    compressed = zlib.compress(b"".join(raw_lines))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", compressed)
    png += chunk(b"IEND", b"")

    with open(png_path, "wb") as f:
        f.write(png)
    print(f"Saved {png_path}: {len(png)} bytes")

if __name__ == '__main__':
    ppm = sys.argv[1] if len(sys.argv) > 1 else "test_cmd.ppm"
    png = sys.argv[2] if len(sys.argv) > 2 else "test_cmd.png"
    ppm_to_png(ppm, png)

