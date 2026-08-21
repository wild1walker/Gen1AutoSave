import math

def build(N=16):
    c = (N - 1) / 2.0
    R = N / 2.0 - 0.35
    grid = [[0]*N for _ in range(N)]
    band_hi, band_lo = c - 1.05, c + 1.05      # the dark centre band
    for y in range(N):
        for x in range(N):
            d = math.hypot(x - c, y - c)
            if d > R:
                continue
            if d > R - 1.05:
                grid[y][x] = 1                 # outline
            elif band_hi <= y <= band_lo:
                grid[y][x] = 1                 # band reads as outline colour
            elif y < c:
                grid[y][x] = 2                 # red dome
            else:
                grid[y][x] = 3                 # white base
    # the button: white core, dark ring, sitting on the band
    for y in range(N):
        for x in range(N):
            dc = math.hypot(x - c, y - c)
            if dc <= 1.35:
                grid[y][x] = 3
            elif dc <= 2.45 and grid[y][x] != 0:
                grid[y][x] = 1
    return grid

if __name__ == "__main__":
    g = build(16)
    art = {0: "  ", 1: "██", 2: "RR", 3: "░░"}
    for row in g:
        print("".join(art[v] for v in row))
