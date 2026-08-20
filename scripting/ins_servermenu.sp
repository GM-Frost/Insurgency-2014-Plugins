#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <dbi>

#define PLUGIN_VERSION "1.3.0"

#define STATS_URL   "https://199.119.136.77/stats/"
#define DISCORD_URL "https://discord.gg/C3cj4Wf7st"
#define STEAM_URL   "https://steamcommunity.com/groups/losers-online"
#define DONATE_URL  "https://ko-fi.com/losersonline"

Database g_DB = null;
bool g_bDatabaseConnecting = false;

public Plugin myinfo =
{
    name = "INS Server Menu",
    author = "Nayan",
    description = "Main -=LOL=- server menu with HLstats integration for Insurgency 2014",
    version = PLUGIN_VERSION,
    url = ""
};

public void OnPluginStart()
{
    RegConsoleCmd(
        "sm_menu",
        Command_ServerMenu,
        "Open the -=LOL=- server menu."
    );

    RegConsoleCmd(
        "sm_servermenu",
        Command_ServerMenu,
        "Open the -=LOL=- server menu."
    );

    RegConsoleCmd(
        "sm_stats",
        Command_Stats,
        "Show your -=LOL=- player statistics."
    );

    RegConsoleCmd(
        "sm_discord",
        Command_Discord,
        "Show the -=LOL=- Discord invite."
    );

    RegConsoleCmd(
        "sm_steam",
        Command_Steam,
        "Show the -=LOL=- Steam community."
    );

    RegConsoleCmd(
        "sm_rules",
        Command_Rules,
        "Show the -=LOL=- server rules."
    );

    RegConsoleCmd(
        "sm_community",
        Command_Community,
        "Show the -=LOL=- community menu."
    );

    RegConsoleCmd(
        "sm_donate",
        Command_Donate,
        "Support the -=LOL=- community server."
    );

    CreateConVar(
        "sm_ins_servermenu_version",
        PLUGIN_VERSION,
        "INS Server Menu version.",
        FCVAR_NOTIFY | FCVAR_DONTRECORD
    );

    AddCommandListener(ChatListener_Menu, "say");
    AddCommandListener(ChatListener_Menu, "say_team");
    ConnectToHLstats();
}

public Action ChatListener_Menu(
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

    if (ChatCommandMatches(message, "menu")
        || ChatCommandMatches(message, "servermenu"))
    {
        ShowServerMenu(client);
        return Plugin_Handled;
    }

    if (ChatCommandMatches(message, "stats"))
    {
        ShowStats(client);
        return Plugin_Handled;
    }

    if (ChatCommandMatches(message, "ranks"))
    {
        FakeClientCommand(client, "sm_ranks");
        return Plugin_Handled;
    }

    if (ChatCommandMatches(message, "discord"))
    {
        ShowDiscord(client);
        return Plugin_Handled;
    }

    if (ChatCommandMatches(message, "steam"))
    {
        ShowSteam(client);
        return Plugin_Handled;
    }

    if (ChatCommandMatches(message, "rules"))
    {
        ShowRules(client);
        return Plugin_Handled;
    }

    if (ChatCommandMatches(message, "donate"))
    {
        ShowDonate(client);
        return Plugin_Handled;
    }

    if (ChatCommandMatches(message, "community"))
    {
        ShowCommunityMenu(client);
        return Plugin_Handled;
    }

    return Plugin_Continue;
}

public void OnPluginEnd()
{
    if (g_DB != null)
    {
        delete g_DB;
        g_DB = null;
    }
}

/*
 * ============================================================
 * HLSTATS DATABASE CONNECTION
 * ============================================================
 */

void ConnectToHLstats()
{
    if (g_DB != null || g_bDatabaseConnecting)
    {
        return;
    }

    g_bDatabaseConnecting = true;

    Database.Connect(
        SQL_OnDatabaseConnected,
        "hlstats"
    );
}

public void SQL_OnDatabaseConnected(
    Database db,
    const char[] error,
    any data
)
{
    g_bDatabaseConnecting = false;

    if (db == null)
    {
        LogError(
            "[INS Server Menu] Could not connect to HLstats database: %s",
            error
        );

        return;
    }

    g_DB = db;

    /*
     * HLstats uses normal text values. utf8mb4 is safe for
     * player names and weapon names if supported by the driver.
     */
    g_DB.SetCharset("utf8mb4");

    LogMessage(
        "[INS Server Menu] Connected to HLstats database successfully."
    );
}

/*
 * ============================================================
 * MAIN COMMAND
 * ============================================================
 */

public Action Command_ServerMenu(
    int client,
    int args
)
{
    if (!IsValidHuman(client))
    {
        return Plugin_Handled;
    }

    ShowServerMenu(client);

    return Plugin_Handled;
}

public Action Command_Donate(
    int client,
    int args
)
{
    if (!IsValidHuman(client))
    {
        return Plugin_Handled;
    }

    ShowDonate(client);

    return Plugin_Handled;
}

public Action Command_Stats(int client, int args)
{
    if (IsValidHuman(client))
    {
        ShowStats(client);
    }

    return Plugin_Handled;
}

public Action Command_Discord(int client, int args)
{
    if (IsValidHuman(client))
    {
        ShowDiscord(client);
    }

    return Plugin_Handled;
}

public Action Command_Steam(int client, int args)
{
    if (IsValidHuman(client))
    {
        ShowSteam(client);
    }

    return Plugin_Handled;
}

public Action Command_Rules(int client, int args)
{
    if (IsValidHuman(client))
    {
        ShowRules(client);
    }

    return Plugin_Handled;
}

public Action Command_Community(int client, int args)
{
    if (IsValidHuman(client))
    {
        ShowCommunityMenu(client);
    }

    return Plugin_Handled;
}

/*
 * ============================================================
 * MAIN MENU
 * ============================================================
 */

void ShowServerMenu(int client)
{
    Menu menu = new Menu(
        Handler_ServerMenu
    );

    menu.Pagination = MENU_NO_PAGINATION;
    menu.ExitButton = true;

    menu.SetTitle(
        "-=LOL=- LOSERS ONLINE\nSERVER MENU\nSelect an option:"
    );

    menu.AddItem(
        "stats",
        "My Stats"
    );

    menu.AddItem(
    "profile",
    "Player Profile"
    );

    menu.AddItem(
    "ranks",
    "Online Player Ranks"
    );

    menu.AddItem(
        "special",
        "Special Round Vote"
    );

    menu.AddItem(
        "rules",
        "Server Rules"
    );

    menu.AddItem(
      "donate",
      "Support / Donate"
    );

    menu.AddItem(
      "community",
      "Community / Server Info"
    );

    menu.AddItem(
        "map",
        "Current / Next Map"
    );

    menu.ExitButton = true;

    menu.Display(
        client,
        30
    );
}

public int Handler_ServerMenu(
    Menu menu,
    MenuAction action,
    int client,
    int item
)
{
    if (action == MenuAction_Select)
    {
        if (!IsValidHuman(client))
        {
            return 0;
        }

        char info[32];

        menu.GetItem(
            item,
            info,
            sizeof(info)
        );

        if (StrEqual(info, "stats", false))
        {
            ShowStats(client);
        }
        else if (StrEqual(info, "profile", false))
        {
            FakeClientCommand(client, "sm_profile");
        }
        else if (StrEqual(info, "ranks", false))
        {
            FakeClientCommand(
                client,
                "sm_ranks"
            );
        }
        else if (StrEqual(info, "special", false))
        {
            OpenSpecialRoundVote(client);
        }
        else if (StrEqual(info, "rules", false))
        {
            ShowRules(client);
        }
        else if (StrEqual(info, "donate", false))
        {
            ShowSupportMenu(client);
        }
        else if (StrEqual(info, "community", false))
        {
            ShowCommunityMenu(client);
        }
        else if (StrEqual(info, "map", false))
        {
            ShowMapInfo(client);
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

/*
 * ============================================================
 * MY STATS
 * ============================================================
 */

void ShowStats(int client)
{
    if (g_DB == null)
    {
        ConnectToHLstats();

        PrintToChat(
            client,
            "\x01[\x04-=LOL=-\x01] Player statistics are currently connecting. Try again in a few seconds."
        );

        return;
    }

    char steamId[64];

    if (!GetClientAuthId(
        client,
        AuthId_Steam2,
        steamId,
        sizeof(steamId),
        true
    ))
    {
        PrintToChat(
            client,
            "\x01[\x04-=LOL=-\x01] Unable to retrieve your Steam ID."
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
        PrintToChat(
            client,
            "\x01[\x04-=LOL=-\x01] Unable to identify your HLstats account."
        );

        LogError(
            "[INS Server Menu] Could not convert Steam ID '%s' to HLstats format.",
            steamId
        );

        return;
    }

    char query[4096];

    g_DB.Format(
        query,
        sizeof(query),
        "SELECT p.playerId, p.lastName, p.skill, p.kills, p.deaths, 1 + (SELECT COUNT(*) FROM hlstats_Players p2 WHERE p2.game = 'insmod' AND p2.hideranking = 0 AND p2.skill > p.skill) AS player_rank, (SELECT COUNT(*) FROM hlstats_Players p3 WHERE p3.game = 'insmod' AND p3.hideranking = 0) AS total_players, COALESCE((SELECT COALESCE(NULLIF(w.name, ''), e.weapon) FROM hlstats_Events_Frags e LEFT JOIN hlstats_Weapons w ON w.game = 'insmod' AND w.code = e.weapon WHERE e.killerId = p.playerId GROUP BY e.weapon, w.name ORDER BY COUNT(*) DESC, e.weapon ASC LIMIT 1), 'None') AS top_weapon, COALESCE((SELECT COUNT(*) FROM hlstats_Events_Frags e2 WHERE e2.killerId = p.playerId GROUP BY e2.weapon ORDER BY COUNT(*) DESC, e2.weapon ASC LIMIT 1), 0) AS top_weapon_kills FROM hlstats_PlayerUniqueIds uid INNER JOIN hlstats_Players p ON p.playerId = uid.playerId AND p.game = uid.game WHERE uid.uniqueId = '%s' AND uid.game = 'insmod' AND p.hideranking = 0 LIMIT 1",
        uniqueId
    );

    PrintToChat(
        client,
        "\x01[\x04-=LOL=-\x01] Loading your player statistics..."
    );

    g_DB.Query(
        SQL_OnPlayerStatsLoaded,
        query,
        GetClientUserId(client)
    );
}

public void SQL_OnPlayerStatsLoaded(
    Database db,
    DBResultSet results,
    const char[] error,
    any userid
)
{
    int client = GetClientOfUserId(userid);

    if (!IsValidHuman(client))
    {
        return;
    }

    if (results == null)
    {
        LogError(
            "[INS Server Menu] HLstats query failed: %s",
            error
        );

        PrintToChat(
            client,
            "\x01[\x04-=LOL=-\x01] Unable to load your statistics right now."
        );

        return;
    }

    if (!results.FetchRow())
    {
        ShowUnrankedStats(client);
        return;
    }

    int playerId = results.FetchInt(0);

    char playerName[128];
    results.FetchString(
        1,
        playerName,
        sizeof(playerName)
    );

    int skill = results.FetchInt(2);
    int kills = results.FetchInt(3);
    int deaths = results.FetchInt(4);
    int playerRank = results.FetchInt(5);
    int totalPlayers = results.FetchInt(6);

    char topWeapon[128];
    results.FetchString(
        7,
        topWeapon,
        sizeof(topWeapon)
    );

    int topWeaponKills = results.FetchInt(8);

    char kdText[64];

    if (deaths > 0)
    {
        float kd = float(kills) / float(deaths);

        Format(
            kdText,
            sizeof(kdText),
            "%.2f",
            kd
        );
    }
    else
    {
        strcopy(
            kdText,
            sizeof(kdText),
            "N/A (0 deaths)"
        );
    }

    LogMessage(
    "[INS Server Menu] Stats loaded for %N: rank=%d/%d skill=%d kills=%d deaths=%d weapon=%s weaponkills=%d",
    client,
    playerRank,
    totalPlayers,
    skill,
    kills,
    deaths,
    topWeapon,
    topWeaponKills
    );

    ShowPlayerStatsMenu(
        client,
        playerId,
        playerName,
        playerRank,
        totalPlayers,
        skill,
        kills,
        deaths,
        kdText,
        topWeapon,
        topWeaponKills
    );
}

/*
 * ============================================================
 * PLAYER STATS DISPLAY
 * ============================================================
 */

void ShowPlayerStatsMenu(
    int client,
    int playerId,
    const char[] playerName,
    int playerRank,
    int totalPlayers,
    int skill,
    int kills,
    int deaths,
    const char[] kdText,
    const char[] topWeapon,
    int topWeaponKills
)
{
    Panel panel = new Panel();

    panel.SetTitle("-= MY STATS =-");

    char line[192];

    Format(line, sizeof(line), "Player: %s", playerName);
    panel.DrawText(line);

    panel.DrawText(" ");

    Format(line, sizeof(line), "Rank: #%d / %d", playerRank, totalPlayers);
    panel.DrawText(line);

    Format(line, sizeof(line), "Skill: %d", skill);
    panel.DrawText(line);

    Format(line, sizeof(line), "K/D: %s", kdText);
    panel.DrawText(line);

    Format(line, sizeof(line), "Kills: %d", kills);
    panel.DrawText(line);

    Format(line, sizeof(line), "Deaths: %d", deaths);
    panel.DrawText(line);

    if (topWeaponKills > 0)
    {
        Format(
            line,
            sizeof(line),
            "Top Weapon: %s (%d kills)",
            topWeapon,
            topWeaponKills
        );
    }
    else
    {
        strcopy(
            line,
            sizeof(line),
            "Top Weapon: No weapon data yet"
        );
    }

    panel.DrawText(line);

    panel.DrawText(" ");
    panel.DrawText("-=LOL=- Full Stats at:");
    panel.DrawText(STATS_URL);

    panel.DrawText(" ");

    panel.DrawItem("Back");

    panel.Send(
        client,
        Handler_PlayerStatsPanel,
        30
    );

    delete panel;

    PrintToConsole(client, "");
    PrintToConsole(client, "-=LOL=- Full Stats:");
    PrintToConsole(client, "%s", STATS_URL);
    PrintToConsole(client, "");
}

public int Handler_PlayerStatsPanel(
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
        ShowServerMenu(client);
    }

    return 0;
}

void ShowUnrankedStats(int client)
{
    Menu menu = new Menu(
        Handler_UnrankedStatsMenu
    );

    menu.SetTitle(
        "-=LOL=- MY STATS\n\nNo ranked HLstats record was found for your Steam account."
    );

    menu.AddItem(
        "website",
        "Open Full Stats Website"
    );

    menu.ExitBackButton = true;
    menu.ExitButton = true;

    menu.Display(
        client,
        20
    );
}

public int Handler_UnrankedStatsMenu(
    Menu menu,
    MenuAction action,
    int client,
    int item
)
{
    if (action == MenuAction_Select)
    {
        if (!IsValidHuman(client))
        {
            return 0;
        }

        char info[32];

        menu.GetItem(
            item,
            info,
            sizeof(info)
        );

        if (StrEqual(info, "website", false))
        {
            PrintToChat(
                client,
                "\x01[\x04-=LOL=-\x01] %s",
                STATS_URL
            );
        }
    }
    else if (action == MenuAction_Cancel)
    {
        if (
            item == MenuCancel_ExitBack
            && IsValidHuman(client)
        )
        {
            ShowServerMenu(client);
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

/*
 * ============================================================
 * STEAM ID -> HLSTATS UNIQUE ID
 * ============================================================
 */

bool ConvertSteam2ToHLstatsId(
    const char[] steamId,
    char[] output,
    int maxlen
)
{
    /*
     * SourceMod example:
     *
     * STEAM_0:0:102453596
     *
     * HLstats stores:
     *
     * 0:102453596
     */

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

    if (StrContains(
        pieces[0],
        "STEAM_",
        false
    ) != 0)
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
 * SPECIAL ROUND VOTE
 * ============================================================
 */

void OpenSpecialRoundVote(int client)
{
    if (!CommandExists("sm_vote"))
    {
        PrintToChat(
            client,
            "\x01[\x04-=LOL=-\x01] Special Round voting is currently unavailable."
        );

        return;
    }

    FakeClientCommand(
        client,
        "sm_vote"
    );
}

/*
 * ============================================================
 * SERVER RULES
 * ============================================================
 */

void ShowRules(int client)
{
    Menu menu = new Menu(
        Handler_RulesMenu
    );

    menu.SetTitle(
        "-=LOL=- SERVER RULES\n\nFight hard. Play fair."
    );

    menu.AddItem(
        "rule1",
        "No cheating or external assistance",
        ITEMDRAW_DISABLED
    );

    menu.AddItem(
        "rule2",
        "No exploiting or map glitching",
        ITEMDRAW_DISABLED
    );

    menu.AddItem(
        "rule3",
        "No intentional team disruption",
        ITEMDRAW_DISABLED
    );

    menu.AddItem(
        "rule4",
        "Respect players and admins",
        ITEMDRAW_DISABLED
    );

    menu.AddItem(
        "rule5",
        "Follow admin instructions",
        ITEMDRAW_DISABLED
    );

    menu.ExitBackButton = true;
    menu.ExitButton = true;

    menu.Display(
        client,
        30
    );
}

public int Handler_RulesMenu(
    Menu menu,
    MenuAction action,
    int client,
    int item
)
{
    if (action == MenuAction_Cancel)
    {
        if (
            item == MenuCancel_ExitBack
            && IsValidHuman(client)
        )
        {
            ShowServerMenu(client);
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

/*
 * ============================================================
 * DISCORD
 * ============================================================
 */

void ShowDiscord(int client)
{
    PrintToChat(
        client,
        "\x01[\x04-=LOL=-\x01] DISCORD"
    );

    PrintToChat(
        client,
        "\x01Join our community:"
    );

    PrintToChat(
        client,
        "\x04%s",
        DISCORD_URL
    );
}

/*
 * ============================================================
 * STEAM COMMUNITY
 * ============================================================
 */

void ShowSteam(int client)
{
    PrintToChat(
        client,
        "\x01[\x04-=LOL=-\x01] STEAM COMMUNITY"
    );

    PrintToChat(
        client,
        "\x01Join the Losers Online Steam group:"
    );

    PrintToChat(
        client,
        "\x04%s",
        STEAM_URL
    );
}

void ShowCommunityMenu(int client)
{
    Menu menu = new Menu(
        Handler_CommunityMenu
    );

    menu.SetTitle(
        "-=LOL=- COMMUNITY / SERVER INFO\n\nChoose an option:"
    );

    menu.AddItem(
        "discord",
        "Discord"
    );

    menu.AddItem(
        "steam",
        "Steam Community"
    );

    menu.ExitBackButton = true;
    menu.ExitButton = true;

    menu.Display(
        client,
        30
    );
}

public int Handler_CommunityMenu(
    Menu menu,
    MenuAction action,
    int client,
    int item
)
{
    if (action == MenuAction_Select)
    {
        if (!IsValidHuman(client))
        {
            return 0;
        }

        char info[32];

        menu.GetItem(
            item,
            info,
            sizeof(info)
        );

        if (StrEqual(info, "discord", false))
        {
            ShowDiscord(client);
        }
        else if (StrEqual(info, "steam", false))
        {
            ShowSteam(client);
        }
    }
    else if (action == MenuAction_Cancel)
    {
        if (
            item == MenuCancel_ExitBack
            && IsValidHuman(client)
        )
        {
            ShowServerMenu(client);
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}
/*
 * ============================================================
 * SUPPORT -=LOL=-
 * ============================================================
 */

void ShowDonate(int client)
{
    PrintToChat(
        client,
        "\x01[\x04-=LOL=-\x01] SUPPORT -=LOL=-"
    );

    PrintToChat(
        client,
        "\x01Enjoy the server and our mods? Help keep -=LOL=- online!"
    );

    PrintToChat(
        client,
        "\x04%s",
        DONATE_URL
    );

    PrintToConsole(client, "");
    PrintToConsole(client, "-=LOL=- Support:");
    PrintToConsole(client, "%s", DONATE_URL);
    PrintToConsole(client, "");
}

void ShowSupportMenu(int client)
{
    Menu menu = new Menu(
        Handler_SupportMenu
    );

    menu.SetTitle(
        "-=LOL=- SUPPORT THE SERVER\n\nChoose an option:"
    );

    menu.AddItem(
        "supporters",
        "Supporters This Month"
    );

    menu.AddItem(
        "donate",
        "Support / Donate"
    );

    menu.ExitBackButton = true;
    menu.ExitButton = true;

    menu.Display(
        client,
        30
    );
}

public int Handler_SupportMenu(
    Menu menu,
    MenuAction action,
    int client,
    int item
)
{
    if (action == MenuAction_Select)
    {
        if (!IsValidHuman(client))
        {
            return 0;
        }

        char info[32];

        menu.GetItem(
            item,
            info,
            sizeof(info)
        );

        if (StrEqual(info, "supporters", false))
        {
            ShowSupportersThisMonth(client);
        }
        else if (StrEqual(info, "donate", false))
        {
            ShowDonate(client);
        }
    }
    else if (action == MenuAction_Cancel)
    {
        if (
            item == MenuCancel_ExitBack
            && IsValidHuman(client)
        )
        {
            ShowServerMenu(client);
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}

void ShowSupportersThisMonth(int client)
{
    Menu menu = new Menu(
        Handler_SupportersMenu
    );

    menu.SetTitle(
        "-=LOL=- SUPPORTERS THIS MONTH"
    );

    char path[PLATFORM_MAX_PATH];

    BuildPath(
        Path_SM,
        path,
        sizeof(path),
        "configs/lol_donors.txt"
    );

    File file = OpenFile(path, "r");

    if (file == null)
    {
        menu.AddItem(
            "",
            "No supporter data available.",
            ITEMDRAW_DISABLED
        );
    }
    else
    {
        char line[256];
        bool found = false;

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

            int commentPos = StrContains(line, "//", false);

            char supporterName[128];
            supporterName[0] = '\0';

            if (commentPos != -1)
            {
                strcopy(
                    supporterName,
                    sizeof(supporterName),
                    line[commentPos + 2]
                );

                TrimString(supporterName);

                line[commentPos] = '\0';
                TrimString(line);
            }

            char parts[4][64];

            int count = ExplodeString(
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

            bool active = false;

            if (StrEqual(parts[1], "forever", false))
            {
                active = true;
            }
            else if (count >= 3)
            {
                char dateParts[3][8];

                if (ExplodeString(
                    parts[1],
                    "-",
                    dateParts,
                    sizeof(dateParts),
                    sizeof(dateParts[])
                ) == 3)
                {
                    int year = StringToInt(dateParts[0]);
                    int month = StringToInt(dateParts[1]);
                    int day = StringToInt(dateParts[2]);
                    int durationDays = StringToInt(parts[2]);

                    int startTime = TimeToUnix_Menu(
                        year,
                        month,
                        day
                    );

                    if (
                        startTime > 0
                        && durationDays > 0
                    )
                    {
                        int endTime =
                            startTime
                            + (durationDays * 86400);

                        int now = GetTime();

                        active =
                            now >= startTime
                            && now < endTime;
                    }
                }
            }

            if (!active)
            {
                continue;
            }

            found = true;

            if (supporterName[0] != '\0')
            {
                menu.AddItem(
                    "",
                    supporterName,
                    ITEMDRAW_DISABLED
                );
            }
            else
            {
                menu.AddItem(
                    "",
                    parts[0],
                    ITEMDRAW_DISABLED
                );
            }
        }

        delete file;

        if (!found)
        {
            menu.AddItem(
                "",
                "No active supporters this month.",
                ITEMDRAW_DISABLED
            );
        }
    }

    menu.ExitBackButton = true;
    menu.ExitButton = true;

    menu.Display(
        client,
        30
    );
}
public int Handler_SupportersMenu(
    Menu menu,
    MenuAction action,
    int client,
    int item
)
{
    if (
        action == MenuAction_Cancel
        && item == MenuCancel_ExitBack
        && IsValidHuman(client)
    )
    {
        ShowSupportMenu(client);
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }

    return 0;
}
/*
 * ============================================================
 * CURRENT / NEXT MAP
 * ============================================================
 */

void ShowMapInfo(int client)
{
    char currentMap[PLATFORM_MAX_PATH];
    char nextMap[PLATFORM_MAX_PATH];

    GetCurrentMap(
        currentMap,
        sizeof(currentMap)
    );

    PrintToChat(
        client,
        "\x01[\x04-=LOL=-\x01] MAP INFORMATION"
    );

    PrintToChat(
        client,
        "\x01Current Map: \x04%s",
        currentMap
    );

    ConVar cvNextMap = FindConVar(
        "sm_nextmap"
    );

    if (cvNextMap != null)
    {
        cvNextMap.GetString(
            nextMap,
            sizeof(nextMap)
        );

        if (nextMap[0] != '\0')
        {
            PrintToChat(
                client,
                "\x01Next Map: \x04%s",
                nextMap
            );

            return;
        }
    }

    PrintToChat(
        client,
        "\x01Next Map: \x04Not currently selected"
    );
}

/*
 * ============================================================
 * CLIENT VALIDATION
 * ============================================================
 */

bool IsLeapYear_Menu(int year)
{
    return (
        (year % 400 == 0)
        || (
            year % 4 == 0
            && year % 100 != 0
        )
    );
}

int TimeToUnix_Menu(
    int year,
    int month,
    int day
)
{
    if (
        year < 1970
        || month < 1
        || month > 12
        || day < 1
    )
    {
        return 0;
    }

    int daysInMonth[12] =
    {
        31, 28, 31, 30, 31, 30,
        31, 31, 30, 31, 30, 31
    };

    if (IsLeapYear_Menu(year))
    {
        daysInMonth[1] = 29;
    }

    if (day > daysInMonth[month - 1])
    {
        return 0;
    }

    int totalDays = 0;

    for (int y = 1970; y < year; y++)
    {
        totalDays += IsLeapYear_Menu(y)
            ? 366
            : 365;
    }

    for (int m = 1; m < month; m++)
    {
        totalDays += daysInMonth[m - 1];
    }

    totalDays += day - 1;

    return totalDays * 86400;
}

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

bool ChatCommandMatches(
    const char[] message,
    const char[] commandName
)
{
    if (message[0] != '!' && message[0] != '/')
    {
        return false;
    }

    return StrEqual(message[1], commandName, false);
}
