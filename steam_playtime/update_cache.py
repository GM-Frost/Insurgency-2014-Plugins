#!/usr/bin/env python3

import json
import os
import sqlite3
import subprocess
import tempfile
from pathlib import Path

RECOGNITION_DB = Path(
    "/home/insserver/serverfiles/insurgency/addons/sourcemod/data/sqlite/sourcemod-local.sq3"
)

CACHE_FILE = Path(
    "/home/insserver/serverfiles/insurgency/addons/sourcemod/data/steam_playtime_cache.cfg"
)

LOOKUP_SCRIPT = "/opt/losers-online/steam/steam_playtime.py"


def lookup(steamid64):
    result = subprocess.run(
        [LOOKUP_SCRIPT, steamid64],
        capture_output=True,
        text=True,
        timeout=15,
    )

    if result.returncode != 0:
        return {"status": "na", "hours": None}

    try:
        return json.loads(result.stdout)
    except Exception:
        return {"status": "na", "hours": None}


def main():
    db = sqlite3.connect(RECOGNITION_DB)

    rows = db.execute(
        "SELECT steamid64 FROM ins_recognition"
    ).fetchall()

    db.close()

    lines = [
        '"SteamPlaytime"',
        "{",
    ]

    for (steamid64,) in rows:
        result = lookup(steamid64)

        status = result.get("status", "na")
        hours = result.get("hours")

        if hours is None:
            hours_text = "-1"
        else:
            hours_text = str(hours)

        lines.extend([
            f'    "{steamid64}"',
            "    {",
            f'        "status" "{status}"',
            f'        "hours" "{hours_text}"',
            "    }",
        ])

        print(
            f"{steamid64}: {status} "
            f"{hours if hours is not None else ''}"
        )

    lines.append("}")

    CACHE_FILE.parent.mkdir(
        parents=True,
        exist_ok=True
    )

    with tempfile.NamedTemporaryFile(
        mode="w",
        delete=False,
        dir=CACHE_FILE.parent,
    ) as tmp:
        tmp.write("\n".join(lines) + "\n")
        temp_name = tmp.name

    os.replace(temp_name, CACHE_FILE)


if __name__ == "__main__":
    main()
