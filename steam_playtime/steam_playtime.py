#!/usr/bin/env python3

import json
import os
import sys
import urllib.parse
import urllib.request
import urllib.error

INSURGENCY_APP_ID = 222880
TIMEOUT = 10


def get_api_key():
    key = os.environ.get("STEAM_API_KEY", "").strip()

    if not key:
        raise RuntimeError("STEAM_API_KEY is not set")

    return key


def get_insurgency_playtime(steamid64):
    params = {
        "key": get_api_key(),
        "steamid": steamid64,
        "include_appinfo": "0",
        "include_played_free_games": "1",
        "appids_filter[0]": str(INSURGENCY_APP_ID),
        "format": "json",
    }

    url = (
        "https://api.steampowered.com/"
        "IPlayerService/GetOwnedGames/v0001/?"
        + urllib.parse.urlencode(params)
    )

    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Losers-Online-Insurgency/1.0"
        },
    )

    try:
        with urllib.request.urlopen(
            request,
            timeout=TIMEOUT
        ) as response:
            data = json.load(response)

    except Exception as exc:
        return {
            "status": "na",
            "hours": None,
            "error": str(exc),
        }

    response_data = data.get("response", {})

    games = response_data.get("games")

    if games is None:
        return {
            "status": "private",
            "hours": None,
        }

    for game in games:
        if game.get("appid") == INSURGENCY_APP_ID:
            minutes = int(
                game.get("playtime_forever", 0)
            )

            return {
                "status": "public",
                "hours": round(minutes / 60.0, 1),
            }

    return {
        "status": "public",
        "hours": 0,
    }


def main():
    if len(sys.argv) != 2:
        print(
            "Usage: steam_playtime.py <SteamID64>",
            file=sys.stderr,
        )
        sys.exit(1)

    steamid64 = sys.argv[1].strip()

    if not steamid64.isdigit():
        print(
            json.dumps({
                "status": "na",
                "hours": None,
                "error": "Invalid SteamID64",
            })
        )
        sys.exit(1)

    result = get_insurgency_playtime(steamid64)

    print(json.dumps(result))


if __name__ == "__main__":
    main()
