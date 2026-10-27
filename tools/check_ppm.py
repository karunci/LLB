import sys

filename = sys.argv[1] if len(sys.argv) > 1 else "desktop.ppm"
with open(filename, "rb") as f:
    header = b""
    while len(header.split()) < 4:
        line = f.readline()
        if not line.startswith(b"#"): header += line
    parts = header.split()
    w, h = int(parts[1]), int(parts[2])
    data = f.read()

def get_pixel(x, y):
    off = (y * w + x) * 3
    return data[off:off+3].hex()

print("Resolution:", w, "x", h)
print("Top bar (10, 10):", get_pixel(10, 10))
print("Top bar (100, 10):", get_pixel(100, 10))
print("Center (512, 384):", get_pixel(512, 384))
print("Bottom (900, 750):", get_pixel(900, 750))
print("Boot card (36, 80):", get_pixel(36, 80))
