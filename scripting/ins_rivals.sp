// ============================================================================
// [INS] LOL Rivals
//
// Human-only nemesis and revenge system for Insurgency (2014).
// Rivalries persist between rounds and reset on map change or disconnect.
// ============================================================================

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define PLUGIN_VERSION "2.0.1"
#define MAX_PANEL_RIVALS 3

enum RivalMessagePool
{
    Pool_Nemesis = 0,
    Pool_Five,
    Pool_Seven,
    Pool_Ten,
    Pool_Revenge,
    Pool_Count
};

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
int g_LastMessage[Pool_Count];


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
        "Unanswered kills required to become a nemesis. Fixed at 3 for these callouts.",
        FCVAR_NOTIFY,
        true,
        3.0,
        true,
        3.0
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

    // Team changes invalidate an enemy-only rivalry. HookEventEx keeps the
    // plugin load-safe if a particular game build does not expose this event.
    HookEventEx(
        "player_team",
        Event_PlayerTeam,
        EventHookMode_Post
    );

    AutoExecConfig(true, "ins_rivals");
    ResetAllRivalries();
    ResetMessageHistory();
}


public void OnMapStart()
{
    ResetAllRivalries();
    ResetMessageHistory();
}


public void OnClientPutInServer(int client)
{
    ResetClientRivalries(client);
}


public void OnClientDisconnect(int client)
{
    ResetClientRivalries(client);
}


public void Event_PlayerTeam(
    Event event,
    const char[] name,
    bool dontBroadcast
)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (client >= 1 && client <= MaxClients && IsClientInGame(client))
    {
        // Delay until all automatic side-swap events have settled. Rivalries
        // remain intact when both players swap and are still opponents.
        CreateTimer(
            0.50,
            Timer_RevalidateRivalries,
            GetClientUserId(client),
            TIMER_FLAG_NO_MAPCHANGE
        );
    }
}


public Action Timer_RevalidateRivalries(Handle timer, any userId)
{
    int client = GetClientOfUserId(userId);

    if (!IsValidHuman(client))
    {
        return Plugin_Stop;
    }

    int clientTeam = GetClientTeam(client);

    for (int rival = 1; rival <= MaxClients; rival++)
    {
        if (
            rival == client
            || !IsValidHuman(rival)
            || GetClientTeam(rival) != clientTeam
        )
        {
            continue;
        }

        g_Unanswered[client][rival] = 0;
        g_Unanswered[rival][client] = 0;
    }

    return Plugin_Stop;
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
        // The revenge kill is also the first unanswered kill of a new streak.
        g_Unanswered[attacker][victim] = 1;
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
            streak
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


int PickDifferentMessage(RivalMessagePool pool)
{
    int poolIndex = view_as<int>(pool);
    int selected = GetRandomInt(0, 7);

    if (g_LastMessage[poolIndex] == selected)
    {
        selected = (selected + GetRandomInt(1, 7)) % 8;
    }

    g_LastMessage[poolIndex] = selected;
    return selected;
}


void BuildNemesisMessage(
    int attacker,
    int victim,
    char[] output,
    int maxLength
)
{
    switch (PickDifferentMessage(Pool_Nemesis))
    {
        case 0: Format(output, maxLength, "\x07D5D7DC%N\x01, this is getting embarrassing.", victim);
        case 1: Format(output, maxLength, "\x07D5D7DC%N\x01 has lost the same gunfight three different ways.", victim);
        case 2: Format(output, maxLength, "\x07D5D7DC%N\x01, blink twice if you need backup.", victim);
        case 3: Format(output, maxLength, "\x07D5D7DC%N\x01, whatever the plan is, it isn't working.", victim);
        case 4: Format(output, maxLength, "\x07D5D7DC%N\x01 is 0-3 and still approaching with confidence.", victim);
        case 5: Format(output, maxLength, "\x07D5D7DC%N\x01, maybe stop peeking the same fucking guy.", victim);
        case 6: Format(output, maxLength, "\x07D5D7DC%N\x01 is starting to look nervous around \x07C58CFF%N\x01.", victim, attacker);
        case 7: Format(output, maxLength, "\x07D5D7DC%N\x01 is running out of ways to call this bad luck.", victim);
    }
}


void BuildFiveMessage(
    int attacker,
    int victim,
    char[] output,
    int maxLength
)
{
    switch (PickDifferentMessage(Pool_Five))
    {
        case 0: Format(output, maxLength, "\x07D5D7DC%N\x01 sees \x07C58CFF%N\x01 and forgets how to aim.", victim, attacker);
        case 1: Format(output, maxLength, "\x07D5D7DC%N\x01 keeps showing up like the result might change.", victim);
        case 2: Format(output, maxLength, "\x07D5D7DC%N\x01 has died to \x07C58CFF%N\x01 in every available position.", victim, attacker);
        case 3: Format(output, maxLength, "\x07D5D7DC%N's\x01 strategy remains spawn, search, die.", victim);
        case 4: Format(output, maxLength, "\x07D5D7DC%N\x01, try something besides dying first.", victim);
        case 5: Format(output, maxLength, "\x07D5D7DC%N\x01 keeps dying before the fight becomes interesting.", victim);
        case 6: Format(output, maxLength, "\x07D5D7DC%N\x01, changing weapons won't fix whatever this is.", victim);
        case 7: Format(output, maxLength, "Five straight. \x07D5D7DC%N\x01 is officially out of excuses.", victim);
    }
}


void BuildSevenMessage(
    int attacker,
    int victim,
    char[] output,
    int maxLength
)
{
    switch (PickDifferentMessage(Pool_Seven))
    {
        case 0: strcopy(output, maxLength, "This is bullying. Keep going.");
        case 1: Format(output, maxLength, "\x07D5D7DC%N\x01 sees \x07C58CFF%N\x01 and dies automatically.", victim, attacker);
        case 2: Format(output, maxLength, "Somebody tell \x07D5D7DC%N\x01 that he can shoot back.", victim);
        case 3: strcopy(output, maxLength, "Seven straight. Even the kill feed is getting bored.");
        case 4: Format(output, maxLength, "\x07D5D7DC%N\x01 has tried everything except staying alive.", victim);
        case 5: Format(output, maxLength, "\x07D5D7DC%N\x01 has died seven times and still looks surprised.", victim);
        case 6: Format(output, maxLength, "\x07D5D7DC%N\x01 is helping \x07C58CFF%N\x01 more than his own team.", victim, attacker);
        case 7: Format(output, maxLength, "\x07D5D7DC%N\x01 is seven deaths deep and still taking the same route.", victim);
    }
}


void BuildTenMessage(
    int victim,
    char[] output,
    int maxLength
)
{
    switch (PickDifferentMessage(Pool_Ten))
    {
        case 0: strcopy(output, maxLength, "Double digits. This needs adult supervision.");
        case 1: strcopy(output, maxLength, "Ten deaths. Not one useful adjustment.");
        case 2: Format(output, maxLength, "Even probability has stopped defending \x07D5D7DC%N\x01.", victim);
        case 3: strcopy(output, maxLength, "The kill feed has stopped pretending this is news.");
        case 4: Format(output, maxLength, "\x07D5D7DC%N\x01 has died more times than some players have fired.", victim);
        case 5: Format(output, maxLength, "\x07D5D7DC%N\x01 has spent ten lives reaching the same conclusion.", victim);
        case 6: Format(output, maxLength, "\x07D5D7DC%N\x01 has been wrong ten times in a row with a rifle.", victim);
        case 7: strcopy(output, maxLength, "Ten straight. At this point, surviving would be suspicious.");
    }
}


void BuildRevengeMessage(
    int attacker,
    int formerNemesis,
    int endedStreak,
    char[] output,
    int maxLength
)
{
    switch (PickDifferentMessage(Pool_Revenge))
    {
        case 0: Format(output, maxLength, "\x07C58CFF%N\x01 got one! Nobody fucking move.", attacker);
        case 1: Format(output, maxLength, "\x07C58CFF%N\x01 remembered which button shoots.", attacker);
        case 2: Format(output, maxLength, "\x07C58CFF%N\x01 finally killed \x07D5D7DC%N\x01. Screenshot it.", attacker, formerNemesis);
        case 3: Format(output, maxLength, "\x07C58CFF%N\x01 killed \x07D5D7DC%N\x01. The server has witnessed a miracle.", attacker, formerNemesis);
        case 4: Format(output, maxLength, "\x07C58CFF%N\x01 finally answered. The kill feed had to double-check.", attacker);
        case 5: Format(output, maxLength, "\x07C58CFF%N\x01 got revenge. Please remain calm.", attacker);
        case 6: Format(output, maxLength, "\x07C58CFF%N\x01 killed \x07D5D7DC%N\x01. Witnesses are being interviewed.", attacker, formerNemesis);
        case 7: Format(output, maxLength, "\x07C58CFF%N\x01 broke the streak. Only took %d attempts.", attacker, endedStreak + 1);
    }
}


void AnnounceDominanceMilestone(
    int attacker,
    int victim,
    int streak
)
{
    char detail[256];

    switch (streak)
    {
        case 5: BuildFiveMessage(attacker, victim, detail, sizeof(detail));
        case 7: BuildSevenMessage(attacker, victim, detail, sizeof(detail));
        case 10: BuildTenMessage(victim, detail, sizeof(detail));
        default: return;
    }

    PrintRivalryCallout(streak, detail);

    SendPersonalStreakStatus(
        attacker,
        victim,
        streak
    );
}


void PrintRivalryCallout(
    int streak,
    const char[] detail
)
{
    PrintToChatAll(
        "\x01[\x079CFF57-=LOL=-\x01] \x07FF7138%d-0\x01 | %s",
        streak,
        detail
    );
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
        "\x01[\x079CFF57-=LOL=-\x01] \x07FF7138STREAK\x01 | You have \x07D5D7DC%N\x01 \x07FF7138%d-0\x01.",
        victim,
        streak
    );

    PrintToChat(
        victim,
        "\x01[\x079CFF57-=LOL=-\x01] \x0758F2C2REVENGE\x01 | \x07C58CFF%N\x01 has you \x07FF71380-%d\x01. Kill him.",
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
        "\x01[\x079CFF57-=LOL=-\x01] \x07FF7138RIVAL\x01 | One more kill makes you \x07D5D7DC%N's\x01 nemesis.",
        victim
    );

    PrintToChat(
        victim,
        "\x01[\x079CFF57-=LOL=-\x01] \x07FF7138WARNING\x01 | \x07C58CFF%N\x01 has you \x07FF71380-%d\x01. Kill him.",
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
    char detail[256];
    BuildNemesisMessage(attacker, victim, detail, sizeof(detail));
    PrintRivalryCallout(streak, detail);

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

    char detail[256];
    BuildRevengeMessage(
        attacker,
        formerNemesis,
        endedStreak,
        detail,
        sizeof(detail)
    );

    PrintToChatAll(
        "\x01[\x079CFF57-=LOL=-\x01] \x0758F2C2REVENGE\x01 | %s",
        detail
    );

    if (g_CvarPrivateStatus.BoolValue)
    {
        PrintToChat(
            attacker,
            "\x01[\x079CFF57-=LOL=-\x01] \x0758F2C2REVENGE\x01 | You ended \x07D5D7DC%N's\x01 \x07FF7138%d-kill streak\x01.",
            formerNemesis,
            endedStreak
        );

        PrintToChat(
            formerNemesis,
            "\x01[\x079CFF57-=LOL=-\x01] \x07FF7138STREAK ENDED\x01 | \x07C58CFF%N\x01 got revenge after \x07FF7138%d deaths\x01.",
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
    bool used[MAXPLAYERS + 1];

    for (int rival = 1; rival <= MaxClients; rival++)
    {
        used[rival] = false;
    }

    panel.DrawText(" ");
    panel.DrawText("YOUR NEMESIS:");

    while (shown < MAX_PANEL_RIVALS)
    {
        int bestRival = 0;
        int bestStreak = 0;

        for (int rival = 1; rival <= MaxClients; rival++)
        {
            int streak = g_Unanswered[rival][client];

            if (
                used[rival]
                || !IsValidHuman(rival)
                || streak < nemesisKills
                || streak <= bestStreak
            )
            {
                continue;
            }

            bestRival = rival;
            bestStreak = streak;
        }

        if (bestRival == 0)
        {
            break;
        }

        used[bestRival] = true;
        Format(
            line,
            sizeof(line),
            "%N - %d unanswered deaths",
            bestRival,
            bestStreak
        );

        panel.DrawText(line);
        shown++;
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
        used[rival] = false;
    }

    while (shown < MAX_PANEL_RIVALS)
    {
        int bestRival = 0;
        int bestStreak = 0;

        for (int rival = 1; rival <= MaxClients; rival++)
        {
            int streak = g_Unanswered[client][rival];

            if (
                used[rival]
                || !IsValidHuman(rival)
                || streak <= bestStreak
            )
            {
                continue;
            }

            bestRival = rival;
            bestStreak = streak;
        }

        if (bestRival == 0)
        {
            break;
        }

        used[bestRival] = true;
        Format(
            line,
            sizeof(line),
            "%N - %d unanswered kills",
            bestRival,
            bestStreak
        );

        panel.DrawText(line);
        shown++;
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


void ResetMessageHistory()
{
    for (int pool = 0; pool < view_as<int>(Pool_Count); pool++)
    {
        g_LastMessage[pool] = -1;
    }
}
