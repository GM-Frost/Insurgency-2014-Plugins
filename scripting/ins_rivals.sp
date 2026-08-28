// ============================================================================
// [INS] LOL Rivals
//
// Human-only nemesis and revenge system for Insurgency (2014).
// Rivalries persist between rounds and reset on map change or disconnect.
// ============================================================================

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define PLUGIN_VERSION "1.5.0"
#define MAX_PANEL_RIVALS 3

ConVar g_CvarEnabled;
ConVar g_CvarNemesisKills;
ConVar g_CvarPrivateWarnings;
ConVar g_CvarFunCallouts;
ConVar g_CvarPrivateStatus;
ConVar g_CvarVictimHint;
ConVar g_CvarVictimHintDelay;
ConVar g_CvarCenterMessages;
ConVar g_CvarPanelTime;

// Directed unanswered kill count: killer -> victim.
int g_Unanswered[MAXPLAYERS + 1][MAXPLAYERS + 1];


public Plugin myinfo =
{
    name = "[INS] LOL Rivals",
    author = "Nayan",
    description = "Colored human-only nemesis and revenge announcements.",
    version = PLUGIN_VERSION,
    url = ""
};


public void OnPluginStart()
{
    CreateConVar(
        "sm_lol_rivals_version",
        PLUGIN_VERSION,
        "LOL Rivals plugin version.",
        FCVAR_NOTIFY | FCVAR_DONTRECORD
    );

    g_CvarEnabled = CreateConVar(
        "sm_lol_rivals_enabled",
        "1",
        "Enable the LOL nemesis and revenge system.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    g_CvarNemesisKills = CreateConVar(
        "sm_lol_rivals_nemesis_kills",
        "3",
        "Unanswered kills required to become a nemesis.",
        FCVAR_NOTIFY,
        true,
        2.0,
        true,
        10.0
    );

    g_CvarPrivateWarnings = CreateConVar(
        "sm_lol_rivals_private_warnings",
        "1",
        "Show private warnings one kill before nemesis status.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    g_CvarFunCallouts = CreateConVar(
        "sm_lol_rivals_fun_callouts",
        "1",
        "Announce escalating dominance milestones after nemesis status.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    g_CvarPrivateStatus = CreateConVar(
        "sm_lol_rivals_private_status",
        "1",
        "Show personalized colored streak and revenge status in chat.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    g_CvarVictimHint = CreateConVar(
        "sm_lol_rivals_victim_hint",
        "1",
        "Show an sm_hsay-style hint to the dead victim only.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    g_CvarVictimHintDelay = CreateConVar(
        "sm_lol_rivals_victim_hint_delay",
        "0.40",
        "Delay after death before showing the victim hint.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        2.0
    );

    g_CvarCenterMessages = CreateConVar(
        "sm_lol_rivals_center_messages",
        "0",
        "Show center-screen nemesis and revenge messages to involved players.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    g_CvarPanelTime = CreateConVar(
        "sm_lol_rivals_panel_time",
        "12",
        "Seconds the !rivals panel remains open.",
        FCVAR_NOTIFY,
        true,
        3.0,
        true,
        30.0
    );

    RegConsoleCmd(
        "sm_rivals",
        Command_Rivals,
        "Show your current nemesis and rivalry streaks."
    );

    RegConsoleCmd(
        "sm_nemesis",
        Command_Rivals,
        "Show your current nemesis and rivalry streaks."
    );

    HookEvent(
        "player_death",
        Event_PlayerDeath,
        EventHookMode_Post
    );

    AutoExecConfig(true, "ins_rivals");
    ResetAllRivalries();
}


public void OnMapStart()
{
    ResetAllRivalries();
}


public void OnClientDisconnect(int client)
{
    ResetClientRivalries(client);
}


public void Event_PlayerDeath(
    Event event,
    const char[] name,
    bool dontBroadcast
)
{
    if (!g_CvarEnabled.BoolValue)
    {
        return;
    }

    int victim = GetClientOfUserId(
        event.GetInt("userid")
    );

    int attacker = GetClientOfUserId(
        event.GetInt("attacker")
    );

    if (
        !IsValidHuman(victim)
        || !IsValidHuman(attacker)
        || victim == attacker
    )
    {
        return;
    }

    if (GetClientTeam(victim) == GetClientTeam(attacker))
    {
        return;
    }

    int nemesisKills = g_CvarNemesisKills.IntValue;

    // The victim had an active unanswered streak against this attacker.
    if (g_Unanswered[victim][attacker] >= nemesisKills)
    {
        AnnounceRevenge(attacker, victim);

        g_Unanswered[victim][attacker] = 0;
        g_Unanswered[attacker][victim] = 0;
        return;
    }

    // Any answered kill ends the opponent's smaller developing streak.
    g_Unanswered[victim][attacker] = 0;
    g_Unanswered[attacker][victim]++;

    int streak = g_Unanswered[attacker][victim];

    if (streak == nemesisKills)
    {
        AnnounceNemesis(attacker, victim, streak);
    }
    else if (
        g_CvarFunCallouts.BoolValue
        && streak > nemesisKills
    )
    {
        AnnounceDominanceMilestone(
            attacker,
            victim,
            streak,
            nemesisKills
        );
    }
    else if (
        g_CvarPrivateWarnings.BoolValue
        && streak == nemesisKills - 1
    )
    {
        SendPrivateWarnings(attacker, victim, streak);
    }
}


void AnnounceDominanceMilestone(
    int attacker,
    int victim,
    int streak,
    int nemesisKills
)
{
    int extraKills = streak - nemesisKills;
    char title[64];
    char detail[256];
    char color[16];

    if (extraKills == 1)
    {
        strcopy(color, sizeof(color), "\x07FFAE5D");

        if (GetRandomInt(0, 1) == 0)
        {
            strcopy(title, sizeof(title), "RENT FREE");
            Format(
                detail,
                sizeof(detail),
                "\x07F2B84B%N\x01 moved into \x076FF7FF%N's\x01 head and changed the locks!",
                attacker,
                victim
            );
        }
        else
        {
            strcopy(title, sizeof(title), "FOUND YOU AGAIN");
            Format(
                detail,
                sizeof(detail),
                "\x07F2B84B%N\x01 found \x076FF7FF%N\x01 again. Maybe try a different route?",
                attacker,
                victim
            );
        }
    }
    else if (extraKills == 2)
    {
        strcopy(color, sizeof(color), "\x07FF6B6B");

        if (GetRandomInt(0, 1) == 0)
        {
            strcopy(title, sizeof(title), "FREE KILL SUBSCRIPTION");
            Format(
                detail,
                sizeof(detail),
                "\x076FF7FF%N\x01 forgot to cancel \x07F2B84B%N's\x01 free-kill subscription, and auto-renew is on!",
                victim,
                attacker
            );
        }
        else
        {
            strcopy(title, sizeof(title), "RESPAWN SPONSOR");
            Format(
                detail,
                sizeof(detail),
                "\x076FF7FF%N\x01 is personally sponsoring \x07F2B84B%N's\x01 score!",
                victim,
                attacker
            );
        }
    }
    else if (extraKills == 4)
    {
        strcopy(color, sizeof(color), "\x07C39BFF");

        switch (GetRandomInt(0, 2))
        {
            case 0:
            {
                strcopy(title, sizeof(title), "PERSONAL HIGHLIGHT REEL");
                Format(
                    detail,
                    sizeof(detail),
                    "\x076FF7FF%N\x01 is now starring in \x07F2B84B%N's\x01 personal highlight reel!",
                    victim,
                    attacker
                );
            }

            case 1:
            {
                strcopy(title, sizeof(title), "SKILL ISSUE CONFIRMED");
                Format(
                    detail,
                    sizeof(detail),
                    "The investigation is over: \x076FF7FF%N\x01 has a confirmed skill issue against \x07F2B84B%N\x01!",
                    victim,
                    attacker
                );
            }

            case 2:
            {
                strcopy(title, sizeof(title), "CHECK THEIR PING");
                Format(
                    detail,
                    sizeof(detail),
                    "Someone check \x076FF7FF%N's\x01 ping; \x07F2B84B%N\x01 keeps making them disappear!",
                    victim,
                    attacker
                );
            }
        }
    }
    else if (extraKills == 7)
    {
        strcopy(color, sizeof(color), "\x07FF6B6B");

        switch (GetRandomInt(0, 2))
        {
            case 0:
            {
                strcopy(title, sizeof(title), "THIS IS NO LONGER A RIVALRY");
                Format(
                    detail,
                    sizeof(detail),
                    "\x07F2B84B%N\x01 versus \x076FF7FF%N\x01 is no longer a rivalry. This is scheduled farming.",
                    attacker,
                    victim
                );
            }

            case 1:
            {
                strcopy(title, sizeof(title), "KILL FEED ON REPEAT");
                Format(
                    detail,
                    sizeof(detail),
                    "\x07F2B84B%N\x01 keeps sending \x076FF7FF%N\x01 back; even the kill feed knows the script!",
                    attacker,
                    victim
                );
            }

            case 2:
            {
                strcopy(title, sizeof(title), "CALL FOR BACKUP");
                Format(
                    detail,
                    sizeof(detail),
                    "\x076FF7FF%N\x01 should call for backup. Actually, call everybody before \x07F2B84B%N\x01 returns.",
                    victim,
                    attacker
                );
            }
        }
    }
    else if (extraKills > 7 && streak % 5 == 0)
    {
        strcopy(color, sizeof(color), "\x07B47BE8");

        switch (GetRandomInt(0, 3))
        {
            case 0:
            {
                strcopy(title, sizeof(title), "ABSOLUTELY FARMED");
                Format(
                    detail,
                    sizeof(detail),
                    "\x07F2B84B%N\x01 has farmed \x076FF7FF%N\x01 so much the process is now automated!",
                    attacker,
                    victim
                );
            }

            case 1:
            {
                strcopy(title, sizeof(title), "RESPAWN SCREEN VIP");
                Format(
                    detail,
                    sizeof(detail),
                    "\x076FF7FF%N\x01 earned VIP seating on the respawn screen, courtesy of \x07F2B84B%N\x01!",
                    victim,
                    attacker
                );
            }

            case 2:
            {
                strcopy(title, sizeof(title), "PLEASE CHANGE YOUR ROUTE");
                Format(
                    detail,
                    sizeof(detail),
                    "\x076FF7FF%N\x01 should change route; \x07F2B84B%N\x01 already pre-aimed the next one!",
                    victim,
                    attacker
                );
            }

            case 3:
            {
                strcopy(title, sizeof(title), "FREE DELIVERY");
                Format(
                    detail,
                    sizeof(detail),
                    "\x07F2B84B%N\x01 keeps delivering \x076FF7FF%N\x01 to the same destination: respawn.",
                    attacker,
                    victim
                );
            }
        }
    }
    else
    {
        return;
    }

    PrintRivalryCallout(
        color,
        title,
        streak,
        detail
    );

    SendPersonalStreakStatus(
        attacker,
        victim,
        streak
    );
}


void PrintRivalryCallout(
    const char[] color,
    const char[] title,
    int streak,
    const char[] detail
)
{
    // Two short messages protect the headline and UTF-8 player names from
    // truncation when players use long clan tags or multibyte names.
    PrintToChatAll(
        "\x01[\x0797D65C-=LOL=-\x01] %s%s\x01 | %s%d-0\x01",
        color,
        title,
        color,
        streak
    );

    PrintToChatAll("\x01  >> %s", detail);
}


void SendPersonalStreakStatus(
    int attacker,
    int victim,
    int streak
)
{
    ScheduleVictimHint(
        victim,
        attacker,
        streak,
        false
    );

    if (!g_CvarPrivateStatus.BoolValue)
    {
        return;
    }

    PrintToChat(
        attacker,
        "\x01[\x0797D65C-=LOL=-\x01] \x07B7FF6AYOUR STREAK\x01 | You have \x076FF7FF%N\x01 at \x07B7FF6A%d-0\x01. Keep the pressure on!",
        victim,
        streak
    );

    PrintToChat(
        victim,
        "\x01[\x0797D65C-=LOL=-\x01] \x07FF6B6BREVENGE TARGET\x01 | \x07F2B84B%N\x01 has you at \x07FF6B6B0-%d\x01. End the streak!",
        attacker,
        streak
    );

}


void SendPrivateWarnings(
    int attacker,
    int victim,
    int streak
)
{
    PrintToChat(
        attacker,
        "\x01[\x0797D65C-=LOL=-\x01] \x07FFAE5DRIVAL ALERT\x01 | One more kill on \x076FF7FF%N\x01 makes you their \x07FF6B6BNEMESIS\x01!",
        victim
    );

    PrintToChat(
        victim,
        "\x01[\x0797D65C-=LOL=-\x01] \x07FFAE5DRIVAL ALERT\x01 | \x07F2B84B%N\x01 defeated you \x07FFAE5D%d times\x01. Stop them before they become your \x07FF6B6BNEMESIS\x01!",
        attacker,
        streak
    );
}


void AnnounceNemesis(
    int attacker,
    int victim,
    int streak
)
{
    PrintToChatAll(
        "\x01[\x0797D65C-=LOL=-\x01] \x07FF6B6BNEMESIS DECLARED\x01 | \x07FF6B6B%d-0\x01",
        streak
    );

    PrintToChatAll(
        "\x01  >> \x07F2B84B%N\x01 became \x076FF7FF%N's\x01 nemesis. Revenge is the only way out!",
        attacker,
        victim
    );

    SendPersonalStreakStatus(
        attacker,
        victim,
        streak
    );

    if (g_CvarCenterMessages.BoolValue)
    {
        PrintCenterText(
            attacker,
            "NEMESIS: You dominate %N!",
            victim
        );

        PrintCenterText(
            victim,
            "%N IS YOUR NEMESIS!",
            attacker
        );
    }
}


void AnnounceRevenge(int attacker, int formerNemesis)
{
    int endedStreak =
        g_Unanswered[formerNemesis][attacker];

    char title[64];
    char detail[256];

    switch (GetRandomInt(0, 2))
    {
        case 0:
        {
            strcopy(title, sizeof(title), "SUBSCRIPTION CANCELLED");
            Format(
                detail,
                sizeof(detail),
                "\x076FF7FF%N\x01 finally cancelled \x07FF6B6B%N's\x01 free-kill subscription!",
                attacker,
                formerNemesis
            );
        }

        case 1:
        {
            strcopy(title, sizeof(title), "THE CURSE IS BROKEN");
            Format(
                detail,
                sizeof(detail),
                "\x076FF7FF%N\x01 broke the curse and finally took \x07FF6B6B%N\x01 down!",
                attacker,
                formerNemesis
            );
        }

        case 2:
        {
            strcopy(title, sizeof(title), "FINALLY, THE SCRIPT CHANGED");
            Format(
                detail,
                sizeof(detail),
                "\x076FF7FF%N\x01 finally changed the script and gave the kill feed new content against \x07FF6B6B%N\x01!",
                attacker,
                formerNemesis
            );
        }
    }

    PrintToChatAll(
        "\x01[\x0797D65C-=LOL=-\x01] \x07B7FF6AREVENGE\x01 | \x07B7FF6A%s\x01",
        title
    );

    PrintToChatAll(
        "\x01  >> %s \x07F2B84BRivalry reset.\x01",
        detail
    );

    if (g_CvarPrivateStatus.BoolValue)
    {
        PrintToChat(
            attacker,
            "\x01[\x0797D65C-=LOL=-\x01] \x07B7FF6AREVENGE COMPLETE\x01 | You ended \x07FF6B6B%N's\x01 \x07B7FF6A%d-kill streak\x01!",
            formerNemesis,
            endedStreak
        );

        PrintToChat(
            formerNemesis,
            "\x01[\x0797D65C-=LOL=-\x01] \x07FF6B6BSTREAK ENDED\x01 | \x076FF7FF%N\x01 finally answered your \x07FF6B6B%d-kill streak\x01.",
            attacker,
            endedStreak
        );
    }

    ScheduleVictimHint(
        formerNemesis,
        attacker,
        endedStreak,
        true
    );

    if (g_CvarCenterMessages.BoolValue)
    {
        PrintCenterText(
            attacker,
            "REVENGE on %N!",
            formerNemesis
        );

        PrintCenterText(
            formerNemesis,
            "%N GOT REVENGE!",
            attacker
        );
    }
}


void ScheduleVictimHint(
    int victim,
    int opponent,
    int streak,
    bool revengeEnded
)
{
    if (!g_CvarVictimHint.BoolValue)
    {
        return;
    }

    DataPack pack;

    CreateDataTimer(
        g_CvarVictimHintDelay.FloatValue,
        Timer_ShowVictimHint,
        pack,
        TIMER_FLAG_NO_MAPCHANGE
    );

    pack.WriteCell(GetClientUserId(victim));
    pack.WriteCell(GetClientUserId(opponent));
    pack.WriteCell(streak);
    pack.WriteCell(revengeEnded);
}


public Action Timer_ShowVictimHint(
    Handle timer,
    DataPack pack
)
{
    pack.Reset();

    int victim = GetClientOfUserId(pack.ReadCell());
    int opponent = GetClientOfUserId(pack.ReadCell());
    int streak = pack.ReadCell();
    bool revengeEnded = pack.ReadCell();

    if (
        !IsValidHuman(victim)
        || !IsValidHuman(opponent)
        || IsPlayerAlive(victim)
    )
    {
        return Plugin_Stop;
    }

    if (revengeEnded)
    {
        PrintHintText(
            victim,
            "STREAK ENDED\n%N finally answered your %d-kill streak",
            opponent,
            streak
        );
    }
    else
    {
        PrintHintText(
            victim,
            "REVENGE TARGET\n%N has you 0-%d\nEnd the streak!",
            opponent,
            streak
        );
    }

    return Plugin_Stop;
}


public Action Command_Rivals(int client, int args)
{
    if (!IsValidHuman(client))
    {
        return Plugin_Handled;
    }

    ShowRivalsPanel(client);
    return Plugin_Handled;
}


void ShowRivalsPanel(int client)
{
    Panel panel = new Panel();
    panel.SetTitle("-=LOL=- YOUR RIVALRIES");

    int nemesisKills = g_CvarNemesisKills.IntValue;
    int shown = 0;
    char line[128];

    panel.DrawText(" ");
    panel.DrawText("YOUR NEMESIS:");

    for (int rival = 1; rival <= MaxClients; rival++)
    {
        if (
            !IsValidHuman(rival)
            || g_Unanswered[rival][client] < nemesisKills
        )
        {
            continue;
        }

        Format(
            line,
            sizeof(line),
            "%N - %d unanswered deaths",
            rival,
            g_Unanswered[rival][client]
        );

        panel.DrawText(line);
        shown++;

        if (shown >= MAX_PANEL_RIVALS)
        {
            break;
        }
    }

    if (shown == 0)
    {
        panel.DrawText("None - keep it that way!");
    }

    panel.DrawText(" ");
    panel.DrawText("YOU DOMINATE:");
    shown = 0;

    for (int rival = 1; rival <= MaxClients; rival++)
    {
        if (
            !IsValidHuman(rival)
            || g_Unanswered[client][rival] <= 0
        )
        {
            continue;
        }

        Format(
            line,
            sizeof(line),
            "%N - %d unanswered kills",
            rival,
            g_Unanswered[client][rival]
        );

        panel.DrawText(line);
        shown++;

        if (shown >= MAX_PANEL_RIVALS)
        {
            break;
        }
    }

    if (shown == 0)
    {
        panel.DrawText("No active streaks yet.");
    }

    panel.DrawText(" ");
    panel.DrawText("Rivalries reset on map change.");

    panel.Send(
        client,
        NullPanelHandler,
        g_CvarPanelTime.IntValue
    );

    delete panel;
}


public int NullPanelHandler(
    Menu menu,
    MenuAction action,
    int param1,
    int param2
)
{
    return 0;
}


bool IsValidHuman(int client)
{
    return (
        client > 0
        && client <= MaxClients
        && IsClientConnected(client)
        && IsClientInGame(client)
        && !IsFakeClient(client)
        && !IsClientSourceTV(client)
    );
}


void ResetClientRivalries(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    for (int rival = 1; rival <= MaxClients; rival++)
    {
        g_Unanswered[client][rival] = 0;
        g_Unanswered[rival][client] = 0;
    }
}


void ResetAllRivalries()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        for (int rival = 1; rival <= MaxClients; rival++)
        {
            g_Unanswered[client][rival] = 0;
        }
    }
}
