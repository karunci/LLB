import struct
import sys

def convert(ppm_path, bmp_path):
    with open(ppm_path, "rb") as f:
        header = b""
        while True:
            line = f.readline()
            if line.startswith(b"#"):
                continue
            header += line
            parts = header.split()
            if len(parts) >= 4:
                break
        w = int(parts[1])
        h = int(parts[2])
        raw = f.read()

    row_stride = (w * 3 + 3) & ~3
    data_size = row_stride * h
    file_size = 54 + data_size

    bmp_header = struct.pack("<2sIHHI", b"BM", file_size, 0, 0, 54)
    dib_header = struct.pack("<IiiHHIIiiII", 40, w, h, 1, 24, 0, data_size, 2835, 2835, 0, 0)

    bmp_rows = []
    for y in range(h - 1, -1, -1):
        row = raw[y * w * 3 : (y + 1) * w * 3]
        bgr = bytearray(row_stride)
        for x in range(w):
            bgr[x * 3] = row[x * 3 + 2]
            bgr[x * 3 + 1] = row[x * 3 + 1]
            bgr[x * 3 + 2] = row[x * 3]
        bmp_rows.append(bytes(bgr))

    with open(bmp_path, "wb") as f:
        f.write(bmp_header + dib_header + b"".join(bmp_rows))
    print(f"Successfully converted {w}x{h} PPM to {bmp_path}!")

if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else "desktop.ppm"
    dst = sys.argv[2] if len(sys.argv) > 2 else "desktop.bmp"
    convert(src, dst)
