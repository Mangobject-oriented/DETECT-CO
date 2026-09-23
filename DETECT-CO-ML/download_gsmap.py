
#!/usr/bin/env python3

import os
import subprocess
import gzip
import struct
import csv
import time
from datetime import datetime, timedelta

# ============================================================
# SETTINGS
# ============================================================

START_DATE = datetime(2020, 1, 1, 0)

# 3-hour test: 00:00, 01:00, 02:00
END_DATE = datetime(2020, 1, 1, 2)

FTP_HOST = "hokusai.eorc.jaxa.jp"
FTP_USER = "rainmap"

OUTPUT_DIR = os.path.expanduser(
    "~/DETECT-CO-ML/data/gsmap_calamba"
)

OUTPUT_FILE = os.path.join(
    OUTPUT_DIR,
    "gsmap_calamba_hourly_2020_2026.csv"
)

TEMP_DIR = "/tmp/gsmap_calamba"

TARGETS = [
    (14.15, 121.05),
    (14.15, 121.15),
    (14.25, 121.05),
    (14.25, 121.15),
]

# ============================================================
# PREPARE DIRECTORIES
# ============================================================

os.makedirs(OUTPUT_DIR, exist_ok=True)
os.makedirs(TEMP_DIR, exist_ok=True)

# ============================================================
# CREATE OUTPUT FILE
# ============================================================

if not os.path.exists(OUTPUT_FILE):
    with open(OUTPUT_FILE, "w", newline="") as f:
        writer = csv.writer(f)

        writer.writerow([
            "timestamp",
            "lat",
            "lon",
            "rainfall_mm_h"
        ])

# ============================================================
# RESUME
# ============================================================

current = START_DATE

if os.path.exists(OUTPUT_FILE):

    last_timestamp = None

    with open(OUTPUT_FILE, "r", newline="") as f:
        reader = csv.DictReader(f)

        for row in reader:
            last_timestamp = datetime.strptime(
                row["timestamp"],
                "%Y-%m-%d %H:%M"
            )

    if last_timestamp:
        current = last_timestamp + timedelta(hours=1)

# ============================================================
# EXTRACT FOUR CELLS
# ============================================================

def extract_cells(dat_file, timestamp):

    with open(dat_file, "rb") as f:
        data = f.read()

    values = struct.unpack(
        "<%df" % (len(data) // 4),
        data
    )

    rows = []

    for lat, lon in TARGETS:

        row = round((60.0 - lat) / 0.1)
        col = round(lon / 0.1)

        index = row * 3600 + col

        value = values[index]

        rows.append([
            timestamp.strftime("%Y-%m-%d %H:%M"),
            f"{lat:.2f}",
            f"{lon:.2f}",
            f"{value:.4f}"
        ])

    with open(OUTPUT_FILE, "a", newline="") as f:
        writer = csv.writer(f)
        writer.writerows(rows)

# ============================================================
# START ONE PERSISTENT LFTP SESSION
# ============================================================

print()
print("==============================================")
print(" DETECT-CO GSMaP v8 Calamba Downloader")
print("==============================================")
print()
print("TEST PERIOD:")
print(current)
print("to")
print(END_DATE)
print()
print("Target cells:")

for lat, lon in TARGETS:
    print(f"  {lat:.2f}, {lon:.2f}")

print()
print("Output:")
print(OUTPUT_FILE)
print()
print("JAXA password will be requested once.")
print()
print("Press Ctrl+C to stop.")
print()

lftp = subprocess.Popen(
    [
        "lftp",
        "-u",
        FTP_USER,
        f"ftp://{FTP_HOST}"
    ],
    stdin=subprocess.PIPE,
    stdout=subprocess.DEVNULL,
    stderr=subprocess.STDOUT,
    text=True
)

# ============================================================
# PROCESS FILES
# ============================================================

try:

    while current <= END_DATE:

        date_path = current.strftime("%Y/%m/%d")

        filename = (
            f"gsmap_gauge."
            f"{current.strftime('%Y%m%d')}."
            f"{current.strftime('%H')}00."
            f"v8.0000.1.dat.gz"
        )

        remote_path = (
            f"/standard/v8/hourly_G/"
            f"{date_path}/"
            f"{filename}"
        )

        local_gz = os.path.join(
            TEMP_DIR,
            filename
        )

        local_dat = local_gz[:-3]

        timestamp = current.strftime(
            "%Y-%m-%d %H:%M"
        )

        print(
            f"[{timestamp}] downloading...",
            flush=True
        )

        # Download using the same lftp connection
        command = (
            f'get "{remote_path}" '
            f'-o "{local_gz}"\n'
        )

        lftp.stdin.write(command)
        lftp.stdin.flush()

        # Wait for download
        while not os.path.exists(local_gz):
            time.sleep(0.5)

        # Wait until download size stops changing
        previous_size = -1

        while True:

            size = os.path.getsize(local_gz)

            if size == previous_size:
                break

            previous_size = size
            time.sleep(0.5)

        # Decompress
        with gzip.open(local_gz, "rb") as gz:
            with open(local_dat, "wb") as dat:
                dat.write(gz.read())

        # Extract only four cells
        extract_cells(
            local_dat,
            current
        )

        # Delete temporary files
        os.remove(local_gz)
        os.remove(local_dat)

        print(
            f"[{timestamp}] OK",
            flush=True
        )

        current += timedelta(hours=1)

except KeyboardInterrupt:

    print()
    print("Stopped by user.")

finally:

    try:
        lftp.stdin.write("exit\n")
        lftp.stdin.flush()
        lftp.stdin.close()
    except:
        pass

    lftp.wait()

print()
print("==============================================")
print(" TEST FINISHED")
print("==============================================")
print()
print("CSV:")
print(OUTPUT_FILE)
