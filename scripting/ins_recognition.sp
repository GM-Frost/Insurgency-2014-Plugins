#include <sourcemod>
#include <sdktools>
#include <dbi>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "0.6.0"
#define LOL_PREFIX "[LOL] "

Database g_LocalDB = null;
Database g_HLDB = null;

bool g_HLConnecting = false;

enum RecognitionRank
{
    Rank_None = 0,
    Rank_Newcomer,
    Rank_Regular,
    Rank_Experienced,
    Rank_Veteran,
    Rank_Elite,
    Rank_Legend,
    Rank_Master
};

RecognitionRank g_Rank[MAXPLAYERS + 1];
RecognitionRank g_ManualRank[MAXPLAYERS + 1];
bool g_IsLOLMember[MAXPLAYERS + 1];
char g_BaseName[MAXPLAYERS + 1][MAX_NAME_LENGTH];


/*
 * ============================================================
 * PLUGIN
 * ============================================================
 */

public Plugin myinfo =
{
    name = "Insurgency Recognition",
    author = "Losers Online",
    description = "LOL membership, recognition and player profile system",
    version = PLUGIN_VERSION,
    url = ""
};


public void OnPluginStart()
{
    RegConsoleCmd(
        "sm_profile",
        Command_Profile,
        "Show your -=LOL=- player profile"
    );

    RegAdminCmd(
        "sm_recognition_set",
        Command_SetRecognition,
        ADMFLAG_GENERIC,
        "sm_recognition_set <player|#userid> <newcomer|regular|experienced|veteran|elite|legend|master>"
    );

    RegAdminCmd(
        "sm_recognition_clear",
        Command_ClearRecognition,
        ADMFLAG_GENERIC,
        "sm_recognition_clear <player|#userid>"
    );

    RegAdminCmd(
        "sm_recognition_info",
        Command_RecognitionInfo,
        ADMFLAG_GENERIC,
        "sm_recognition_info <player|#userid>"
    );

    RegAdminCmd(
        "sm_lolmember",
        Command_SetLOLMember,
        ADMFLAG_GENERIC,
        "sm_lolmember <player|#userid> <0|1>"
    );

    RegAdminCmd(
        "sm_recognition_setid",
        Command_SetRecognitionById,
        ADMFLAG_GENERIC,
        "sm_recognition_setid <steamid64> <newcomer|regular|experienced|veteran|elite|legend|master>"
    );

    RegAdminCmd(
        "sm_recognition_clearid",
        Command_ClearRecognitionById,
        ADMFLAG_GENERIC,
        "sm_recognition_clearid <steamid64>"
    );

    RegAdminCmd(
        "sm_recognition_infoid",
        Command_RecognitionInfoById,
        ADMFLAG_GENERIC,
        "sm_recognition_infoid <steamid64>"
    );

    RegAdminCmd(
        "sm_lolmemberid",
        Command_SetLOLMemberById,
        ADMFLAG_GENERIC,
        "sm_lolmemberid <steamid64> <0|1>"
    );

    /*
     * Explicit chat support.
     * This makes !profile and /profile work even if normal
     * SourceMod chat triggers behave oddly in Insurgency.
     */
    AddCommandListener(ChatListener, "say");
    AddCommandListener(ChatListener, "say_team");

    Database.Connect(LocalDB_OnConnect, "storage-local");
    ConnectHLstats();
}


/*
 * ============================================================
 * DATABASE CONNECTIONS
 * ============================================================
 */

public void LocalDB_OnConnect(
    Database db,
    const char[] error,
    any data
)
{
    if (db == null)
    {
        SetFailState(
            "Recognition database failed: %s",
            error
        );

        return;
    }

    g_LocalDB = db;

    char query[1024];

    Format(
        query,
        sizeof(query),
        "CREATE TABLE IF NOT EXISTS ins_recognition ("
        ... "steamid64 TEXT PRIMARY KEY,"
        ... "last_name TEXT NOT NULL DEFAULT '',"
        ... "manual_rank INTEGER NOT NULL DEFAULT 0,"
        ... "lol_member INTEGER NOT NULL DEFAULT 0,"
        ... "first_seen INTEGER NOT NULL DEFAULT 0,"
        ... "last_seen INTEGER NOT NULL DEFAULT 0"
        ... ");"
    );

    g_LocalDB.Query(
        SQL_GenericCallback,
        query
    );

    PrintToServer(
        "[Recognition] Local database connected. Version %s",
        PLUGIN_VERSION
    );

    /*
     * Reload connected players if plugin was reloaded live.
     */
    for (int client = 1; client <= MaxClients; client++)
    {
        if (
            IsClientConnected(client)
            && !IsFakeClient(client)
        )
        {
            RegisterPlayer(client);
            LoadClientRecognition(client);
        }
    }
}


void ConnectHLstats()
{
    if (
        g_HLDB != null
        || g_HLConnecting
    )
    {
        return;
    }

    g_HLConnecting = true;

    Database.Connect(
        HLDB_OnConnect,
        "hlstats"
    );
}


public void HLDB_OnConnect(
    Database db,
    const char[] error,
    any data
)
{
    g_HLConnecting = false;

    if (db == null)
    {
        LogError(
            "[Recognition] Could not connect to HLstats: %s",
            error
        );

        return;
    }

    g_HLDB = db;
    g_HLDB.SetCharset("utf8mb4");

    LogMessage(
        "[Recognition] Connected to HLstats successfully."
    );
}


public void SQL_GenericCallback(
    Database db,
    DBResultSet results,
    const char[] error,
    any data
)
{
    if (
        results == null
        && error[0] != '\0'
    )
    {
        LogError(
            "[Recognition] SQL error: %s",
            error
        );
    }
}


/*
 * ============================================================
 * CLIENT STATE
 * ============================================================
 */

public void OnClientConnected(int client)
{
    g_Rank[client] = Rank_None;
    g_ManualRank[client] = Rank_None;
    g_IsLOLMember[client] = false;
    g_BaseName[client][0] = '\0';
}


public void OnClientAuthorized(
    int client,
    const char[] auth
)
{
    if (
        client <= 0
        || IsFakeClient(client)
    )
    {
        return;
    }

    CreateTimer(
        1.0,
        Timer_RegisterPlayer,
        GetClientUserId(client),
        TIMER_FLAG_NO_MAPCHANGE
    );
}


public void OnClientDisconnect(int client)
{
  g_Rank[client] = Rank_None;
  g_ManualRank[client] = Rank_None;
  g_IsLOLMember[client] = false;
  g_BaseName[client][0] = '\0';
}


public Action Timer_RegisterPlayer(
    Handle timer,
    any userid
)
{
    int client = GetClientOfUserId(userid);

    /*
     * Player disconnected completely.
     */
    if (
        client <= 0
        || !IsClientConnected(client)
        || IsFakeClient(client)
    )
    {
        return Plugin_Stop;
    }

    /*
     * Insurgency may authenticate the player before they are
     * completely in-game. Retry instead of giving up.
     */
    if (!IsClientInGame(client))
    {
        CreateTimer(
            1.0,
            Timer_RegisterPlayer,
            userid,
            TIMER_FLAG_NO_MAPCHANGE
        );

        return Plugin_Stop;
    }

    RegisterPlayer(client);
    LoadClientRecognition(client);

    return Plugin_Stop;
}


/*
 * ============================================================
 * PLAYER REGISTRATION
 * ============================================================
 */

void RegisterPlayer(int client)
{
    if (
        g_LocalDB == null
        || !IsValidHuman(client)
    )
    {
        return;
    }

    char steamid64[32];

    if (!GetClientAuthId(
        client,
        AuthId_SteamID64,
        steamid64,
        sizeof(steamid64),
        true
    ))
    {
        return;
    }

    char currentName[MAX_NAME_LENGTH];
    GetClientName(
        client,
        currentName,
        sizeof(currentName)
    );

    char cleanName[MAX_NAME_LENGTH];

    StripLOLPrefix(
        currentName,
        cleanName,
        sizeof(cleanName)
    );

    strcopy(
        g_BaseName[client],
        sizeof(g_BaseName[]),
        cleanName
    );

    char escapedName[(MAX_NAME_LENGTH * 2) + 1];

    g_LocalDB.Escape(
        cleanName,
        escapedName,
        sizeof(escapedName)
    );

    int now = GetTime();

    char query[1024];

    Format(
        query,
        sizeof(query),
        "INSERT OR IGNORE INTO ins_recognition "
        ... "(steamid64,last_name,manual_rank,lol_member,first_seen,last_seen) "
        ... "VALUES ('%s','%s',0,0,%d,%d);",
        steamid64,
        escapedName,
        now,
        now
    );

    g_LocalDB.Query(
        SQL_GenericCallback,
        query
    );

    Format(
        query,
        sizeof(query),
        "UPDATE ins_recognition "
        ... "SET last_name='%s',last_seen=%d "
        ... "WHERE steamid64='%s';",
        escapedName,
        now,
        steamid64
    );

    g_LocalDB.Query(
        SQL_GenericCallback,
        query
    );
}


/*
 * ============================================================
 * LOAD RECOGNITION
 * ============================================================
 */

void LoadClientRecognition(int client)
{
    if (
        g_LocalDB == null
        || !IsValidHuman(client)
    )
    {
        return;
    }

    char steamid64[32];

    if (!GetClientAuthId(
        client,
        AuthId_SteamID64,
        steamid64,
        sizeof(steamid64),
        true
    ))
    {
        return;
    }

    DataPack pack = new DataPack();

    pack.WriteCell(
        GetClientUserId(client)
    );

    char query[512];

    Format(
        query,
        sizeof(query),
        "SELECT manual_rank,lol_member "
        ... "FROM ins_recognition "
        ... "WHERE steamid64='%s' LIMIT 1;",
        steamid64
    );

    g_LocalDB.Query(
        SQL_LoadRecognition,
        query,
        pack
    );
}


public void SQL_LoadRecognition(
    Database db,
    DBResultSet results,
    const char[] error,
    any data
)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int userid = pack.ReadCell();

    delete pack;

    int client = GetClientOfUserId(userid);

    if (!IsValidHuman(client))
    {
        return;
    }

    if (results == null)
    {
        LogError(
            "[Recognition] Failed loading player recognition: %s",
            error
        );

        return;
    }

    if (!results.FetchRow())
    {
        return;
    }

    RecognitionRank databaseRank =
    view_as<RecognitionRank>(
        results.FetchInt(0)
    );

    RecognitionRank configRank =
        GetRecognitionFromConfig(client);

    if (configRank != Rank_None)
    {
        g_ManualRank[client] = configRank;
    }
    else
    {
        g_ManualRank[client] = databaseRank;
    }

    g_Rank[client] =
        g_ManualRank[client];

    bool databaseMember =
    results.FetchInt(1) == 1;

    g_IsLOLMember[client] =
        databaseMember
        || IsClientSourceModAdmin(client)
        || IsLOLMemberFromConfig(client);

    ApplyLOLDisplayName(client);
}


/*
 * ============================================================
 * NAME / LOL TAG
 * ============================================================
 */

public void OnClientSettingsChanged(int client)
{
    if (!IsValidHuman(client))
    {
        return;
    }

    char currentName[MAX_NAME_LENGTH];

    GetClientName(
        client,
        currentName,
        sizeof(currentName)
    );

    char cleanName[MAX_NAME_LENGTH];

    StripLOLPrefix(
        currentName,
        cleanName,
        sizeof(cleanName)
    );

    if (
        cleanName[0] != '\0'
        && !StrEqual(
            cleanName,
            g_BaseName[client],
            true
        )
    )
    {
        strcopy(
            g_BaseName[client],
            sizeof(g_BaseName[]),
            cleanName
        );

        UpdateStoredPlayerName(client);
    }

    ApplyLOLDisplayName(client);
}


void UpdateStoredPlayerName(int client)
{
    if (
        g_LocalDB == null
        || !IsValidHuman(client)
    )
    {
        return;
    }

    char steamid64[32];

    if (!GetClientAuthId(
        client,
        AuthId_SteamID64,
        steamid64,
        sizeof(steamid64),
        true
    ))
    {
        return;
    }

    char escapedName[(MAX_NAME_LENGTH * 2) + 1];

    g_LocalDB.Escape(
        g_BaseName[client],
        escapedName,
        sizeof(escapedName)
    );

    char query[512];

    Format(
        query,
        sizeof(query),
        "UPDATE ins_recognition "
        ... "SET last_name='%s',last_seen=%d "
        ... "WHERE steamid64='%s';",
        escapedName,
        GetTime(),
        steamid64
    );

    g_LocalDB.Query(
        SQL_GenericCallback,
        query
    );
}


void ApplyLOLDisplayName(int client)
{
    if (!IsValidHuman(client))
    {
        return;
    }

    char currentName[MAX_NAME_LENGTH];

    GetClientName(
        client,
        currentName,
        sizeof(currentName)
    );

    if (g_BaseName[client][0] == '\0')
    {
        StripLOLPrefix(
            currentName,
            g_BaseName[client],
            sizeof(g_BaseName[])
        );
    }

    char desiredName[MAX_NAME_LENGTH];

    if (g_IsLOLMember[client])
    {
        Format(
            desiredName,
            sizeof(desiredName),
            "%s%s",
            LOL_PREFIX,
            g_BaseName[client]
        );
    }
    else
    {
        strcopy(
            desiredName,
            sizeof(desiredName),
            g_BaseName[client]
        );
    }

    if (!StrEqual(
        currentName,
        desiredName,
        true
    ))
    {
        SetClientName(
            client,
            desiredName
        );
    }
}


void StripLOLPrefix(
    const char[] input,
    char[] output,
    int maxlen
)
{
    strcopy(
        output,
        maxlen,
        input
    );

    if (
        StrContains(
            output,
            LOL_PREFIX,
            false
        ) == 0
    )
    {
        ReplaceString(
            output,
            maxlen,
            LOL_PREFIX,
            "",
            false
        );
    }
}


/*
 * ============================================================
 * CHAT !PROFILE
 * ============================================================
 */

public Action ChatListener(
    int client,
    const char[] command,
    int argc
)
{
    if (!IsValidHuman(client))
    {
        return Plugin_Continue;
    }

    char message[192];

    GetCmdArgString(
        message,
        sizeof(message)
    );

    StripQuotes(message);
    TrimString(message);

    if (
        StrEqual(message, "!profile", false)
        || StrEqual(message, "/profile", false)
    )
    {
        ShowProfile(client, client);
        return Plugin_Handled;
    }

    return Plugin_Continue;
}


/*
 * ============================================================
 * PROFILE COMMAND
 * ============================================================
 */

public Action Command_Profile(
    int client,
    int args
)
{
    if (!IsValidHuman(client))
    {
        return Plugin_Handled;
    }

    /*
     * !profile
     */
    if (args == 0)
    {
        ShowProfile(client, client);
        return Plugin_Handled;
    }

    /*
     * Admin/console style:
     * sm_profile PlayerName
     */
    char targetArg[64];

    GetCmdArg(
        1,
        targetArg,
        sizeof(targetArg)
    );

    int target =
        ResolveOnlineTarget(targetArg);

    if (target <= 0)
    {
        PrintToChat(
            client,
            "\x01[\x04-=LOL=-\x01] Player not found."
        );

        return Plugin_Handled;
    }

    ShowProfile(client, target);

    return Plugin_Handled;
}


/*
 * ============================================================
 * PROFILE -> HLSTATS
 * ============================================================
 */

void ShowProfile(
    int caller,
    int target
)
{
    if (
        !IsValidHuman(caller)
        || !IsValidHuman(target)
    )
    {
        return;
    }

    if (g_HLDB == null)
    {
        ConnectHLstats();

        ShowProfilePanel(
            caller,
            target,
            false,
            0,
            0,
            0
        );

        return;
    }

    char steamId[64];

    if (!GetClientAuthId(
        target,
        AuthId_Steam2,
        steamId,
        sizeof(steamId),
        true
    ))
    {
        ShowProfilePanel(
            caller,
            target,
            false,
            0,
            0,
            0
        );

        return;
    }

    char uniqueId[64];

    if (!ConvertSteam2ToHLstatsId(
        steamId,
        uniqueId,
        sizeof(uniqueId)
    ))
    {
        ShowProfilePanel(
            caller,
            target,
            false,
            0,
            0,
            0
        );

        return;
    }

    DataPack pack = new DataPack();

    pack.WriteCell(
        GetClientUserId(caller)
    );

    pack.WriteCell(
        GetClientUserId(target)
    );

    char query[2048];

    g_HLDB.Format(
        query,
        sizeof(query),
        "SELECT "
        ... "p.connection_time,"
        ... "p.skill,"
        ... "1 + ("
            ... "SELECT COUNT(*) "
            ... "FROM hlstats_Players p2 "
            ... "WHERE p2.game='insmod' "
            ... "AND p2.hideranking=0 "
            ... "AND p2.skill > p.skill"
        ... ") AS player_rank "
        ... "FROM hlstats_PlayerUniqueIds uid "
        ... "INNER JOIN hlstats_Players p "
        ... "ON p.playerId=uid.playerId "
        ... "AND p.game=uid.game "
        ... "WHERE uid.uniqueId='%s' "
        ... "AND uid.game='insmod' "
        ... "AND p.hideranking=0 "
        ... "LIMIT 1",
        uniqueId
    );

    g_HLDB.Query(
        SQL_ProfileLoaded,
        query,
        pack
    );
}


public void SQL_ProfileLoaded(
    Database db,
    DBResultSet results,
    const char[] error,
    any data
)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();

    int callerUserid = pack.ReadCell();
    int targetUserid = pack.ReadCell();

    delete pack;

    int caller =
        GetClientOfUserId(callerUserid);

    int target =
        GetClientOfUserId(targetUserid);

    if (
        !IsValidHuman(caller)
        || !IsValidHuman(target)
    )
    {
        return;
    }

    if (results == null)
    {
        LogError(
            "[Recognition] HLstats profile query failed: %s",
            error
        );

        ShowProfilePanel(
            caller,
            target,
            false,
            0,
            0,
            0
        );

        return;
    }

    if (!results.FetchRow())
    {
        ShowProfilePanel(
            caller,
            target,
            false,
            0,
            0,
            0
        );

        return;
    }

    int connectionTime =
        results.FetchInt(0);

    int skill =
        results.FetchInt(1);

    int playerRank =
        results.FetchInt(2);

    g_Rank[target] =
      ResolveRecognitionRank(
          target,
          connectionTime
      );

    ShowProfilePanel(
        caller,
        target,
        true,
        connectionTime,
        playerRank,
        skill
    );
}


/*
 * ============================================================
 * PROFILE PANEL
 * ============================================================
 */

void ShowProfilePanel(
    int client,
    int target,
    bool hasHLstats,
    int connectionTime,
    int playerRank,
    int skill
)
{
    Panel panel = new Panel();

    panel.SetTitle(
        "-=LOL=- PLAYER PROFILE"
    );

    char line[192];
    char playerName[MAX_NAME_LENGTH];
    char rankName[32];

    if (g_BaseName[target][0] != '\0')
    {
        strcopy(
            playerName,
            sizeof(playerName),
            g_BaseName[target]
        );
    }
    else
    {
        GetClientName(
            target,
            playerName,
            sizeof(playerName)
        );

        StripLOLPrefix(
            playerName,
            playerName,
            sizeof(playerName)
        );
    }

    GetRankName(
        g_Rank[target],
        rankName,
        sizeof(rankName)
    );

    Format(
        line,
        sizeof(line),
        "Player: %s",
        playerName
    );
    panel.DrawText(line);

    panel.DrawText(" ");

    Format(
        line,
        sizeof(line),
        "LOL Member: %s",
        g_IsLOLMember[target]
            ? "YES"
            : "NO"
    );
    panel.DrawText(line);

    Format(
        line,
        sizeof(line),
        "Recognition: %s",
        rankName
    );
    panel.DrawText(line);

    panel.DrawText(" ");

    if (hasHLstats)
    {
        char playtime[64];

        FormatPlaytime(
            connectionTime,
            playtime,
            sizeof(playtime)
        );

        Format(
            line,
            sizeof(line),
            "LOL Server Playtime: %s",
            playtime
        );
        panel.DrawText(line);

        /*
         * Steam lifetime Insurgency hours are intentionally
         * shown as unavailable until the Steam API/cache
         * component is installed.
         */
        char steamExperience[64];

        GetSteamExperienceText(
            target,
            steamExperience,
            sizeof(steamExperience)
        );

        Format(
            line,
            sizeof(line),
            "Insurgency Experience: %s",
            steamExperience
        );

        panel.DrawText(line);

        Format(
            line,
            sizeof(line),
            "Server Rank: #%d",
            playerRank
        );
        panel.DrawText(line);

        Format(
            line,
            sizeof(line),
            "Skill: %d",
            skill
        );
        panel.DrawText(line);
    }
    else
    {
        panel.DrawText(
            "LOL Server Playtime: N/A"
        );

        panel.DrawText(
            "Insurgency Experience: N/A"
        );

        panel.DrawText(
            "Server Rank: N/A"
        );

        panel.DrawText(
            "Skill: N/A"
        );
    }

    panel.DrawText(" ");

    panel.DrawItem("Back");

    panel.Send(
        client,
        Handler_ProfilePanel,
        30
    );

    delete panel;
}


public int Handler_ProfilePanel(
    Menu menu,
    MenuAction action,
    int client,
    int item
)
{
    if (
        action == MenuAction_Select
        && IsValidHuman(client)
    )
    {
        /*
         * Return to !menu if server menu plugin exists.
         */
        if (CommandExists("sm_menu"))
        {
            FakeClientCommand(
                client,
                "sm_menu"
            );
        }
    }

    return 0;
}


/*
 * ============================================================
 * PLAYTIME FORMAT
 * ============================================================
 */

void FormatPlaytime(
    int seconds,
    char[] buffer,
    int maxlen
)
{
    int hours =
        seconds / 3600;

    int minutes =
        (seconds % 3600) / 60;

    if (hours > 0)
    {
        Format(
            buffer,
            maxlen,
            "%dh %dm",
            hours,
            minutes
        );
    }
    else
    {
        Format(
            buffer,
            maxlen,
            "%dm",
            minutes
        );
    }
}


/*
 * ============================================================
 * STEAM -> HLSTATS ID
 * ============================================================
 */

bool ConvertSteam2ToHLstatsId(
    const char[] steamId,
    char[] output,
    int maxlen
)
{
    char pieces[3][32];

    int count = ExplodeString(
        steamId,
        ":",
        pieces,
        sizeof(pieces),
        sizeof(pieces[])
    );

    if (count != 3)
    {
        return false;
    }

    if (
        StrContains(
            pieces[0],
            "STEAM_",
            false
        ) != 0
    )
    {
        return false;
    }

    Format(
        output,
        maxlen,
        "%s:%s",
        pieces[1],
        pieces[2]
    );

    return true;
}


/*
 * ============================================================
 * RANK
 * ============================================================
 */

RecognitionRank ParseRank(
    const char[] input
)
{
    if (StrEqual(input, "newcomer", false))
    {
        return Rank_Newcomer;
    }

    if (StrEqual(input, "regular", false))
    {
        return Rank_Regular;
    }

    if (StrEqual(input, "experienced", false))
    {
        return Rank_Experienced;
    }

    if (StrEqual(input, "veteran", false))
    {
        return Rank_Veteran;
    }

    if (StrEqual(input, "elite", false))
    {
        return Rank_Elite;
    }

    if (StrEqual(input, "legend", false))
    {
        return Rank_Legend;
    }

    if (StrEqual(input, "master", false))
    {
        return Rank_Master;
    }

    return Rank_None;
}

void GetRankName(
    RecognitionRank rank,
    char[] buffer,
    int maxlen
)
{
    switch (rank)
    {
        case Rank_Newcomer:
        {
            strcopy(buffer, maxlen, "NEWCOMER");
        }

        case Rank_Regular:
        {
            strcopy(buffer, maxlen, "REGULAR");
        }

        case Rank_Experienced:
        {
            strcopy(buffer, maxlen, "EXPERIENCED");
        }

        case Rank_Veteran:
        {
            strcopy(buffer, maxlen, "VETERAN");
        }

        case Rank_Elite:
        {
            strcopy(buffer, maxlen, "ELITE");
        }

        case Rank_Legend:
        {
            strcopy(buffer, maxlen, "LEGEND");
        }

        case Rank_Master:
        {
            strcopy(buffer, maxlen, "MASTER");
        }

        default:
        {
            strcopy(buffer, maxlen, "NONE");
        }
    }
}

RecognitionRank GetAutomaticRankFromHours(float hours)
{
    if (hours < 50.0)
    {
        return Rank_Newcomer;
    }

    if (hours < 200.0)
    {
        return Rank_Regular;
    }

    if (hours < 1000.0)
    {
        return Rank_Experienced;
    }

    if (hours < 2000.0)
    {
        return Rank_Veteran;
    }

    if (hours < 3000.0)
    {
        return Rank_Elite;
    }

    if (hours < 4000.0)
    {
        return Rank_Legend;
    }

    return Rank_Master;
}

RecognitionRank GetAutomaticRankFromServerHours(float hours)
{
    if (hours < 10.0)
    {
        return Rank_Newcomer;
    }

    if (hours < 50.0)
    {
        return Rank_Regular;
    }

    if (hours < 150.0)
    {
        return Rank_Experienced;
    }

    if (hours < 300.0)
    {
        return Rank_Veteran;
    }

    if (hours < 600.0)
    {
        return Rank_Elite;
    }

    return Rank_Legend;
}

RecognitionRank ResolveRecognitionRank(
    int client,
    int connectionTime
)
{
    if (g_ManualRank[client] != Rank_None)
    {
        return g_ManualRank[client];
    }

    float steamHours;
    bool isPrivate;

    if (GetSteamExperienceHours(
        client,
        steamHours,
        isPrivate
    ))
    {
        return GetAutomaticRankFromHours(
            steamHours
        );
    }

    float serverHours =
        float(connectionTime) / 3600.0;

    return GetAutomaticRankFromServerHours(
        serverHours
    );
}

/*
 * ============================================================
 * ONLINE ADMIN: RECOGNITION
 * ============================================================
 */

public Action Command_SetRecognition(
    int client,
    int args
)
{
    if (args < 2)
    {
        AdminReply(
            client,
            "[Recognition] Usage: sm_recognition_set <player|#userid> <newcomer|regular|experienced|veteran|elite|legend|master>"
        );

        return Plugin_Handled;
    }

    if (g_LocalDB == null)
    {
        AdminReply(
            client,
            "[Recognition] Database unavailable."
        );

        return Plugin_Handled;
    }

    char targetArg[64];
    char rankArg[32];

    GetCmdArg(
        1,
        targetArg,
        sizeof(targetArg)
    );

    GetCmdArg(
        2,
        rankArg,
        sizeof(rankArg)
    );

    int target =
        ResolveOnlineTarget(targetArg);

    if (target <= 0)
    {
        AdminReply(
            client,
            "[Recognition] Player not found or target is ambiguous."
        );

        return Plugin_Handled;
    }

    RecognitionRank rank =
        ParseRank(rankArg);

    if (rank == Rank_None)
    {
        AdminReply(
            client,
            "[Recognition] Use newcomer, regular, experienced, veteran, elite, legend, or master."
        );

        return Plugin_Handled;
    }

    char steamid64[32];

    if (!GetClientAuthId(
        target,
        AuthId_SteamID64,
        steamid64,
        sizeof(steamid64),
        true
    ))
    {
        AdminReply(
            client,
            "[Recognition] SteamID64 unavailable."
        );

        return Plugin_Handled;
    }

    RegisterPlayer(target);

    char query[512];

    Format(
        query,
        sizeof(query),
        "UPDATE ins_recognition "
        ... "SET manual_rank=%d "
        ... "WHERE steamid64='%s';",
        view_as<int>(rank),
        steamid64
    );

    g_LocalDB.Query(
        SQL_GenericCallback,
        query
    );

    g_ManualRank[target] = rank;
    g_Rank[target] = rank;

    char rankName[32];

    GetRankName(
        rank,
        rankName,
        sizeof(rankName)
    );

    AdminReplyFormat(
        client,
        "[Recognition] %s assigned %s.",
        g_BaseName[target],
        rankName
    );

    return Plugin_Handled;
}


public Action Command_ClearRecognition(
    int client,
    int args
)
{
    if (args < 1)
    {
        AdminReply(
            client,
            "[Recognition] Usage: sm_recognition_clear <player|#userid>"
        );

        return Plugin_Handled;
    }

    char targetArg[64];

    GetCmdArg(
        1,
        targetArg,
        sizeof(targetArg)
    );

    int target =
        ResolveOnlineTarget(targetArg);

    if (target <= 0)
    {
        AdminReply(
            client,
            "[Recognition] Player not found."
        );

        return Plugin_Handled;
    }

    char steamid64[32];

    if (!GetClientAuthId(
        target,
        AuthId_SteamID64,
        steamid64,
        sizeof(steamid64),
        true
    ))
    {
        return Plugin_Handled;
    }

    char query[512];

    Format(
        query,
        sizeof(query),
        "UPDATE ins_recognition "
        ... "SET manual_rank=0 "
        ... "WHERE steamid64='%s';",
        steamid64
    );

    g_LocalDB.Query(
        SQL_GenericCallback,
        query
    );

    g_ManualRank[target] = Rank_None;
    g_Rank[target] = Rank_None;

    AdminReplyFormat(
        client,
        "[Recognition] Recognition cleared for %s.",
        g_BaseName[target]
    );

    return Plugin_Handled;
}


/*
 * ============================================================
 * ONLINE ADMIN: LOL MEMBER
 * ============================================================
 */

public Action Command_SetLOLMember(
    int client,
    int args
)
{
    if (args < 2)
    {
        AdminReply(
            client,
            "[Recognition] Usage: sm_lolmember <player|#userid> <0|1>"
        );

        return Plugin_Handled;
    }

    char targetArg[64];
    char valueArg[8];

    GetCmdArg(
        1,
        targetArg,
        sizeof(targetArg)
    );

    GetCmdArg(
        2,
        valueArg,
        sizeof(valueArg)
    );

    int target =
        ResolveOnlineTarget(targetArg);

    if (target <= 0)
    {
        AdminReply(
            client,
            "[Recognition] Player not found."
        );

        return Plugin_Handled;
    }

    int value =
        StringToInt(valueArg);

    if (
        value != 0
        && value != 1
    )
    {
        AdminReply(
            client,
            "[Recognition] Value must be 0 or 1."
        );

        return Plugin_Handled;
    }

    char steamid64[32];

    if (!GetClientAuthId(
        target,
        AuthId_SteamID64,
        steamid64,
        sizeof(steamid64),
        true
    ))
    {
        return Plugin_Handled;
    }

    RegisterPlayer(target);

    char query[512];

    Format(
        query,
        sizeof(query),
        "UPDATE ins_recognition "
        ... "SET lol_member=%d "
        ... "WHERE steamid64='%s';",
        value,
        steamid64
    );

    g_LocalDB.Query(
        SQL_GenericCallback,
        query
    );

    g_IsLOLMember[target] =
        value == 1;

    ApplyLOLDisplayName(target);

    AdminReplyFormat(
        client,
        "[Recognition] %s LOL membership: %s.",
        g_BaseName[target],
        value == 1 ? "YES" : "NO"
    );

    return Plugin_Handled;
}


/*
 * ============================================================
 * ONLINE INFO
 * ============================================================
 */

public Action Command_RecognitionInfo(
    int client,
    int args
)
{
    if (args < 1)
    {
        AdminReply(
            client,
            "[Recognition] Usage: sm_recognition_info <player|#userid>"
        );

        return Plugin_Handled;
    }

    char targetArg[64];

    GetCmdArg(
        1,
        targetArg,
        sizeof(targetArg)
    );

    int target =
        ResolveOnlineTarget(targetArg);

    if (target <= 0)
    {
        AdminReply(
            client,
            "[Recognition] Player not found."
        );

        return Plugin_Handled;
    }

    char rankName[32];
    char steamid64[32];

    GetRankName(
        g_Rank[target],
        rankName,
        sizeof(rankName)
    );

    GetClientAuthId(
        target,
        AuthId_SteamID64,
        steamid64,
        sizeof(steamid64),
        true
    );

    AdminReplyFormat(
        client,
        "[Recognition] Player=%s SteamID64=%s LOL=%s Rank=%s",
        g_BaseName[target],
        steamid64,
        g_IsLOLMember[target] ? "YES" : "NO",
        rankName
    );

    return Plugin_Handled;
}


/*
 * ============================================================
 * OFFLINE STEAMID64 ADMIN COMMANDS
 * ============================================================
 */

public Action Command_SetRecognitionById(
    int client,
    int args
)
{
    if (args < 2)
    {
        AdminReply(
            client,
            "[Recognition] Usage: sm_recognition_setid <steamid64> <newcomer|regular|experienced|veteran|elite|legend|master>"
        );

        return Plugin_Handled;
    }

    char steamid64[32];
    char rankArg[32];

    GetCmdArg(
        1,
        steamid64,
        sizeof(steamid64)
    );

    GetCmdArg(
        2,
        rankArg,
        sizeof(rankArg)
    );

    RecognitionRank rank =
        ParseRank(rankArg);

    if (
        rank == Rank_None
        || !IsValidSteamID64(steamid64)
    )
    {
        AdminReply(
            client,
            "[Recognition] Invalid SteamID64 or rank."
        );

        return Plugin_Handled;
    }

    int now = GetTime();

    char query[1024];

    Format(
        query,
        sizeof(query),
        "INSERT OR IGNORE INTO ins_recognition "
        ... "(steamid64,last_name,manual_rank,lol_member,first_seen,last_seen) "
        ... "VALUES ('%s','',%d,0,%d,%d);",
        steamid64,
        view_as<int>(rank),
        now,
        now
    );

    g_LocalDB.Query(
        SQL_GenericCallback,
        query
    );

    Format(
        query,
        sizeof(query),
        "UPDATE ins_recognition "
        ... "SET manual_rank=%d "
        ... "WHERE steamid64='%s';",
        view_as<int>(rank),
        steamid64
    );

    g_LocalDB.Query(
        SQL_GenericCallback,
        query
    );

    char rankName[32];

    GetRankName(
        rank,
        rankName,
        sizeof(rankName)
    );

    AdminReplyFormat(
        client,
        "[Recognition] %s assigned %s.",
        steamid64,
        rankName
    );

    return Plugin_Handled;
}


public Action Command_ClearRecognitionById(
    int client,
    int args
)
{
    if (args < 1)
    {
        AdminReply(
            client,
            "[Recognition] Usage: sm_recognition_clearid <steamid64>"
        );

        return Plugin_Handled;
    }

    char steamid64[32];

    GetCmdArg(
        1,
        steamid64,
        sizeof(steamid64)
    );

    char query[512];

    Format(
        query,
        sizeof(query),
        "UPDATE ins_recognition "
        ... "SET manual_rank=0 "
        ... "WHERE steamid64='%s';",
        steamid64
    );

    g_LocalDB.Query(
        SQL_GenericCallback,
        query
    );

    AdminReplyFormat(
        client,
        "[Recognition] Recognition cleared for %s.",
        steamid64
    );

    return Plugin_Handled;
}


public Action Command_SetLOLMemberById(
    int client,
    int args
)
{
    if (args < 2)
    {
        AdminReply(
            client,
            "[Recognition] Usage: sm_lolmemberid <steamid64> <0|1>"
        );

        return Plugin_Handled;
    }

    char steamid64[32];
    char valueArg[8];

    GetCmdArg(
        1,
        steamid64,
        sizeof(steamid64)
    );

    GetCmdArg(
        2,
        valueArg,
        sizeof(valueArg)
    );

    int value =
        StringToInt(valueArg);

    if (
        !IsValidSteamID64(steamid64)
        || (
            value != 0
            && value != 1
        )
    )
    {
        AdminReply(
            client,
            "[Recognition] Invalid SteamID64 or membership value."
        );

        return Plugin_Handled;
    }

    int now =
        GetTime();

    char query[1024];

    Format(
        query,
        sizeof(query),
        "INSERT OR IGNORE INTO ins_recognition "
        ... "(steamid64,last_name,manual_rank,lol_member,first_seen,last_seen) "
        ... "VALUES ('%s','',0,%d,%d,%d);",
        steamid64,
        value,
        now,
        now
    );

    g_LocalDB.Query(
        SQL_GenericCallback,
        query
    );

    Format(
        query,
        sizeof(query),
        "UPDATE ins_recognition "
        ... "SET lol_member=%d "
        ... "WHERE steamid64='%s';",
        value,
        steamid64
    );

    g_LocalDB.Query(
        SQL_GenericCallback,
        query
    );

    AdminReplyFormat(
        client,
        "[Recognition] %s LOL membership: %s.",
        steamid64,
        value == 1 ? "YES" : "NO"
    );

    return Plugin_Handled;
}


public Action Command_RecognitionInfoById(
    int client,
    int args
)
{
    if (args < 1)
    {
        AdminReply(
            client,
            "[Recognition] Usage: sm_recognition_infoid <steamid64>"
        );

        return Plugin_Handled;
    }

    char steamid64[32];

    GetCmdArg(
        1,
        steamid64,
        sizeof(steamid64)
    );

    if (!IsValidSteamID64(steamid64))
    {
        AdminReply(
            client,
            "[Recognition] Invalid SteamID64."
        );

        return Plugin_Handled;
    }

    DataPack pack = new DataPack();

    if (client == 0)
    {
        pack.WriteCell(0);
    }
    else
    {
        pack.WriteCell(
            GetClientUserId(client)
        );
    }

    pack.WriteString(steamid64);

    char query[512];

    Format(
        query,
        sizeof(query),
        "SELECT last_name,manual_rank,lol_member "
        ... "FROM ins_recognition "
        ... "WHERE steamid64='%s' LIMIT 1;",
        steamid64
    );

    g_LocalDB.Query(
        SQL_OfflineInfo,
        query,
        pack
    );

    return Plugin_Handled;
}


public void SQL_OfflineInfo(
    Database db,
    DBResultSet results,
    const char[] error,
    any data
)
{
    DataPack pack =
        view_as<DataPack>(data);

    pack.Reset();

    int callerUserid =
        pack.ReadCell();

    char steamid64[32];

    pack.ReadString(
        steamid64,
        sizeof(steamid64)
    );

    delete pack;

    int caller = 0;

    if (callerUserid != 0)
    {
        caller =
            GetClientOfUserId(
                callerUserid
            );

        if (caller <= 0)
        {
            return;
        }
    }

    if (
        results == null
        || !results.FetchRow()
    )
    {
        AdminReply(
            caller,
            "[Recognition] No record found."
        );

        return;
    }

    char name[MAX_NAME_LENGTH];

    results.FetchString(
        0,
        name,
        sizeof(name)
    );

    RecognitionRank rank =
        view_as<RecognitionRank>(
            results.FetchInt(1)
        );

    bool lol =
        results.FetchInt(2) == 1;

    char rankName[32];

    GetRankName(
        rank,
        rankName,
        sizeof(rankName)
    );

    AdminReplyFormat(
        caller,
        "[Recognition] Name=%s SteamID64=%s LOL=%s Rank=%s",
        name[0] != '\0' ? name : "UNKNOWN",
        steamid64,
        lol ? "YES" : "NO",
        rankName
    );
}


/*
 * ============================================================
 * TARGET
 * ============================================================
 */

int ResolveOnlineTarget(
    const char[] argument
)
{
    if (argument[0] == '#')
    {
        int userid =
            StringToInt(argument[1]);

        int target =
            GetClientOfUserId(userid);

        if (IsValidHuman(target))
        {
            return target;
        }

        return 0;
    }

    /*
     * Exact match.
     */
    for (
        int client = 1;
        client <= MaxClients;
        client++
    )
    {
        if (!IsValidHuman(client))
        {
            continue;
        }

        char name[MAX_NAME_LENGTH];

        GetClientName(
            client,
            name,
            sizeof(name)
        );

        if (
            StrEqual(
                name,
                argument,
                false
            )
            ||
            StrEqual(
                g_BaseName[client],
                argument,
                false
            )
        )
        {
            return client;
        }
    }

    /*
     * Unique partial match.
     */
    int found = 0;
    int count = 0;

    for (
        int client = 1;
        client <= MaxClients;
        client++
    )
    {
        if (!IsValidHuman(client))
        {
            continue;
        }

        char name[MAX_NAME_LENGTH];

        GetClientName(
            client,
            name,
            sizeof(name)
        );

        if (
            StrContains(
                name,
                argument,
                false
            ) != -1
            ||
            StrContains(
                g_BaseName[client],
                argument,
                false
            ) != -1
        )
        {
            found = client;
            count++;
        }
    }

    if (count == 1)
    {
        return found;
    }

    return 0;
}



RecognitionRank GetRecognitionFromConfig(int client)
{
    char steamId[64];

    if (!GetClientAuthId(
        client,
        AuthId_Steam2,
        steamId,
        sizeof(steamId),
        true
    ))
    {
        return Rank_None;
    }

    char path[PLATFORM_MAX_PATH];

    BuildPath(
        Path_SM,
        path,
        sizeof(path),
        "configs/lol_recognition.txt"
    );

    File file = OpenFile(path, "r");

    if (file == null)
    {
        return Rank_None;
    }

    char line[256];

    while (!file.EndOfFile())
    {
        if (!file.ReadLine(line, sizeof(line)))
        {
            break;
        }

        TrimString(line);

        if (
            line[0] == '\0'
            || (line[0] == '/' && line[1] == '/')
        )
        {
            continue;
        }

        int commentPos =
            StrContains(line, "//", false);

        if (commentPos != -1)
        {
            line[commentPos] = '\0';
            TrimString(line);
        }

        char parts[2][64];

        int count =
            ExplodeString(
                line,
                " ",
                parts,
                sizeof(parts),
                sizeof(parts[])
            );

        if (count < 2)
        {
            continue;
        }

        TrimString(parts[0]);
        TrimString(parts[1]);

        if (!StrEqual(parts[0], steamId, false))
        {
            continue;
        }

        RecognitionRank rank =
            ParseRank(parts[1]);

        delete file;
        return rank;
    }

    delete file;
    return Rank_None;
}
/*
 * ============================================================
 * HELPERS
 * ============================================================
 */

bool IsValidHuman(int client)
{
    return (
        client > 0
        && client <= MaxClients
        && IsClientConnected(client)
        && IsClientInGame(client)
        && !IsFakeClient(client)
    );
}


bool IsValidSteamID64(
    const char[] steamid
)
{
    int length =
        strlen(steamid);

    if (
        length < 16
        || length > 20
    )
    {
        return false;
    }

    for (
        int i = 0;
        i < length;
        i++
    )
    {
        if (
            steamid[i] < '0'
            || steamid[i] > '9'
        )
        {
            return false;
        }
    }

    return true;
}


void AdminReply(
    int client,
    const char[] message
)
{
    if (client == 0)
    {
        PrintToServer(
            "%s",
            message
        );
    }
    else if (
        client > 0
        && IsClientConnected(client)
    )
    {
        ReplyToCommand(
            client,
            "%s",
            message
        );
    }
}


void AdminReplyFormat(
    int client,
    const char[] format,
    any ...
)
{
    char buffer[512];

    VFormat(
        buffer,
        sizeof(buffer),
        format,
        3
    );

    AdminReply(
        client,
        buffer
    );
}

bool GetSteamExperienceHours(
    int client,
    float &hours,
    bool &isPrivate
)
{
    hours = -1.0;
    isPrivate = false;

    char steamid64[32];

    if (!GetClientAuthId(
        client,
        AuthId_SteamID64,
        steamid64,
        sizeof(steamid64),
        true
    ))
    {
        return false;
    }

    char cachePath[PLATFORM_MAX_PATH];

    BuildPath(
        Path_SM,
        cachePath,
        sizeof(cachePath),
        "data/steam_playtime_cache.cfg"
    );

    KeyValues kv =
        new KeyValues("SteamPlaytime");

    if (!kv.ImportFromFile(cachePath))
    {
        delete kv;
        return false;
    }

    if (!kv.JumpToKey(steamid64))
    {
        delete kv;
        return false;
    }

    char status[32];

    kv.GetString(
        "status",
        status,
        sizeof(status),
        "na"
    );

    if (StrEqual(status, "private", false))
    {
        isPrivate = true;
        delete kv;
        return false;
    }

    if (!StrEqual(status, "public", false))
    {
        delete kv;
        return false;
    }

    hours =
        kv.GetFloat(
            "hours",
            -1.0
        );

    delete kv;

    return hours >= 0.0;
}

void GetSteamExperienceText(
    int client,
    char[] buffer,
    int maxlen
)
{
    char steamid64[32];

    if (!GetClientAuthId(
        client,
        AuthId_SteamID64,
        steamid64,
        sizeof(steamid64),
        true
    ))
    {
        strcopy(buffer, maxlen, "N/A");
        return;
    }

    char cachePath[PLATFORM_MAX_PATH];

    BuildPath(
        Path_SM,
        cachePath,
        sizeof(cachePath),
        "data/steam_playtime_cache.cfg"
    );

    KeyValues kv =
        new KeyValues("SteamPlaytime");

    if (!kv.ImportFromFile(cachePath))
    {
        delete kv;

        strcopy(
            buffer,
            maxlen,
            "N/A"
        );

        return;
    }

    if (!kv.JumpToKey(steamid64))
    {
        delete kv;

        strcopy(
            buffer,
            maxlen,
            "N/A"
        );

        return;
    }

    char status[32];

    kv.GetString(
        "status",
        status,
        sizeof(status),
        "na"
    );

    if (StrEqual(status, "private", false))
    {
        strcopy(
            buffer,
            maxlen,
            "PRIVATE"
        );
    }
    else if (StrEqual(status, "public", false))
    {
        float hours =
            kv.GetFloat(
                "hours",
                -1.0
            );

        if (hours >= 0.0)
        {
            Format(
                buffer,
                maxlen,
                "%.1fh",
                hours
            );
        }
        else
        {
            strcopy(
                buffer,
                maxlen,
                "N/A"
            );
        }
    }
    else
    {
        strcopy(
            buffer,
            maxlen,
            "N/A"
        );
    }

    delete kv;
}

bool IsClientSourceModAdmin(int client)
{
    return GetUserAdmin(client) != INVALID_ADMIN_ID;
}


bool IsLOLMemberFromConfig(int client)
{
    char steamId[64];

    if (!GetClientAuthId(
        client,
        AuthId_Steam2,
        steamId,
        sizeof(steamId),
        true
    ))
    {
        return false;
    }

    char path[PLATFORM_MAX_PATH];

    BuildPath(
        Path_SM,
        path,
        sizeof(path),
        "configs/lol_members.txt"
    );

    File file = OpenFile(path, "r");

    if (file == null)
    {
        return false;
    }

    char line[256];

    while (!file.EndOfFile())
    {
        if (!file.ReadLine(
            line,
            sizeof(line)
        ))
        {
            break;
        }

        TrimString(line);

        if (
            line[0] == '\0'
            || (
                line[0] == '/'
                && line[1] == '/'
            )
        )
        {
            continue;
        }

        int commentPos =
            StrContains(
                line,
                "//",
                false
            );

        if (commentPos != -1)
        {
            line[commentPos] = '\0';
            TrimString(line);
        }

        if (StrEqual(
            line,
            steamId,
            false
        ))
        {
            delete file;
            return true;
        }
    }

    delete file;
    return false;
}
