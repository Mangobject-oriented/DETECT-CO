#!/usr/bin/env python3

import struct
import sys

FILE = sys.argv[1]

TARGETS = [
    (14.15, 121.05),
    (14.15, 121.15),
    (14.25, 121.05),
    (14.25, 121.15),
]

with open(FILE, "rb") as f:
    data = f.read()

values = struct.unpack("<%df" % (len(data) // 4), data)

for lat, lon in TARGETS:
    row = round((60.0 - lat) / 0.1)
    col = round(lon / 0.1)

    index = row * 3600 + col
    value = values[index]

    print(f"{lat:.2f},{lon:.2f},{value:.4f}")
