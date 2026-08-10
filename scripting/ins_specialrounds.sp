#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.0.0"

#define VOTE_DURATION 15
#define STRIP_DELAY 0.25

enum SpecialRoundType
{
    Round_Normal = 0,
    Round_Knife,
    Round_Pistol
};

ConVar g_cvEnabled;
ConVar g_cvVotePercent;
ConVar g_cvVoteCooldown;
ConVar g_cvMinPlayers;

SpecialRoundType g_NextRound = Round_Normal;
SpecialRoundType g_ActiveRound = Round_Normal;

bool g_bVoteRunning = false;
SpecialRoundType g_VoteType = Round_Normal;

float g_fNextVoteAllowed = 0.0;

public Plugin myinfo =
{
    name = "INS Special Rounds",
    author = "Nayan",
    description = "Player-voted and admin-controlled special rounds for Insurgency 2014",
    version = PLUGIN_VERSION,
    url = ""
};

public void OnPluginStart()
{
    g_cvEnabled = CreateConVar(
        "sm_ins_specialrounds_enable",
        "1",
        "Enable the special-round system.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    g_cvVotePercent = CreateConVar(
        "sm_ins_specialrounds_vote_percent",
        "60",
        "Percentage of YES votes required.",
        FCVAR_NOTIFY,
        true,
        1.0,
        true,
        100.0
    );

    g_cvVoteCooldown = CreateConVar(
        "sm_ins_specialrounds_vote_cooldown",
        "60.0",
        "Seconds before another special-round vote may be started.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1800.0
    );

    g_cvMinPlayers = CreateConVar(
        "sm_ins_specialrounds_min_players",
        "2",
        "Minimum number of active human players required to vote.",
        FCVAR_NOTIFY,
        true,
        1.0,
        true,
        32.0
    );

    CreateConVar(
        "sm_ins_specialrounds_version",
        PLUGIN_VERSION,
        "INS Special Rounds version.",
        FCVAR_NOTIFY | FCVAR_DONTRECORD
    );

    /*
     * PLAYER MENU
     *
     * !vote
     * /vote
     */
    RegConsoleCmd(
        "sm_vote",
        Command_VoteMenu,
        "Open the -=LOL=- special-round vote menu."
    );

    /*
     * ADMIN COMMANDS
     */
    RegAdminCmd(
        "sm_knifenext",
        Command_KnifeNext,
        ADMFLAG_GENERIC,
        "Schedule a Knife / Melee Round for next round."
    );

    RegAdminCmd(
        "sm_pistolnext",
        Command_PistolNext,
        ADMFLAG_GENERIC,
        "Schedule a Pistol + Melee Round for next round."
    );

    RegAdminCmd(
        "sm_specialcancel",
        Command_SpecialCancel,
        ADMFLAG_GENERIC,
        "Cancel a scheduled special round."
    );

    /*
     * Keep old knife command for convenience.
     */
    RegAdminCmd(
        "sm_knifecancel",
        Command_SpecialCancel,
        ADMFLAG_GENERIC,
        "Cancel a scheduled special round."
    );

    RegAdminCmd(
        "sm_specialstatus",
        Command_SpecialStatus,
        ADMFLAG_GENERIC,
        "Show current special-round status."
    );

    /*
     * Keep old status command too.
     */
    RegAdminCmd(
        "sm_knifestatus",
        Command_SpecialStatus,
        ADMFLAG_GENERIC,
        "Show current special-round status."
    );

    HookEventEx(
        "round_start",
        Event_RoundStart,
        EventHookMode_Post
    );

    HookEventEx(
        "round_end",
        Event_RoundEnd,
        EventHookMode_Post
    );

    HookEventEx(
        "player_spawn",
        Event_PlayerSpawn,
        EventHookMode_Post
    );

    AutoExecConfig(
        true,
        "ins_specialrounds"
    );

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client))
        {
            HookClient(client);
        }
    }
}

public void OnClientPutInServer(int client)
{
    HookClient(client);
}

public void OnMapEnd()
{
    /*
     * Do not carry special rounds into another map.
     */
    g_NextRound = Round_Normal;
    g_ActiveRound = Round_Normal;
    g_bVoteRunning = false;
    g_VoteType = Round_Normal;
    g_fNextVoteAllowed = 0.0;
}

void HookClient(int client)
{
    SDKHook(
        client,
        SDKHook_WeaponCanUse,
        OnWeaponCanUse
    );
}

/*
 * ============================================================
 * !vote MENU
 * ============================================================
 */

public Action Command_VoteMenu(
    int client,
    int args
)
{
    if (!g_cvEnabled.BoolValue)
    {
        PrintToChat(
            client,
            "\x01[\x04-=LOL=-\x01] Special-round voting is currently disabled."
        );

        return Plugin_Handled;
    }

    if (!IsValidHuman(client))
    {
        return Plugin_Handled;
    }

    Menu menu = new Menu(
        Handler_SpecialRoundMenu
    );

    menu.SetTitle(
        "-=LOL=- SPECIAL ROUNDS\nChoose a vote:"
    );

    menu.AddItem(
        "knife",
        "Knife / Melee Round - NEXT ROUND"
    );

    menu.AddItem(
        "pistol",
        "Pistol + Melee Round - NEXT ROUND"
    );

    menu.ExitButton = true;

    menu.Display(
        client,
        20
    );

    return Plugin_Handled;
}

public int Handler_SpecialRoundMenu(
    Menu menu,
    MenuAction action,
    int client,
    int item
)
{
    if (action == MenuAction_Select)
    {
        char info[32];

        menu.GetItem(
            item,
            info,
            sizeof(info)
        );

        if (StrEqual(info, "knife", false))
        {
            TryStartSpecialVote(
                client,
                Round_Knife
            );
        }
        else if (StrEqual(info, "pistol", false))
        {
            TryStartSpecialVote(
                client,
                Round_Pistol
            );
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
 * VOTE START
 * ============================================================
 */

void TryStartSpecialVote(
    int client,
    SpecialRoundType type
)
{
    if (!IsValidHuman(client))
    {
        return;
    }

    if (g_ActiveRound != Round_Normal)
    {
        PrintToChat(
            client,
            "\x01[\x04-=LOL=-\x01] A special round is already active."
        );

        return;
    }

    if (g_NextRound != Round_Normal)
    {
        PrintToChat(
            client,
            "\x01[\x04-=LOL=-\x01] A special round is already scheduled for next round."
        );

        return;
    }

    if (g_bVoteRunning || IsVoteInProgress())
    {
        PrintToChat(
            client,
            "\x01[\x04-=LOL=-\x01] Another vote is already running."
        );

        return;
    }

    int humans = CountHumanPlayers();

    if (humans < g_cvMinPlayers.IntValue)
    {
        PrintToChat(
            client,
            "\x01[\x04-=LOL=-\x01] At least %d active players are required.",
            g_cvMinPlayers.IntValue
        );

        return;
    }

    float now = GetGameTime();

    if (now < g_fNextVoteAllowed)
    {
        int remaining = RoundToCeil(
            g_fNextVoteAllowed - now
        );

        PrintToChat(
            client,
            "\x01[\x04-=LOL=-\x01] Another special-round vote can be started in %d seconds.",
            remaining
        );

        return;
    }

    StartSpecialVote(
        client,
        type
    );
}

void StartSpecialVote(
    int caller,
    SpecialRoundType type
)
{
    Menu vote = new Menu(
        Handler_SpecialVote
    );

    if (type == Round_Knife)
    {
        vote.SetTitle(
            "-=LOL=- KNIFE ROUND\n\nKnife / Melee ONLY next round?"
        );
    }
    else if (type == Round_Pistol)
    {
        vote.SetTitle(
            "-=LOL=- PISTOL ROUND\n\nPistols + Melee ONLY next round?"
        );
    }
    else
    {
        delete vote;
        return;
    }

    vote.AddItem(
        "yes",
        "YES - Let's do it!"
    );

    vote.AddItem(
        "no",
        "NO - Normal weapons"
    );

    vote.ExitButton = false;

    int clients[MAXPLAYERS];
    int count = 0;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidHuman(client))
        {
            continue;
        }

        clients[count] = client;
        count++;
    }

    if (count <= 0)
    {
        delete vote;
        return;
    }

    g_bVoteRunning = true;
    g_VoteType = type;

    g_fNextVoteAllowed =
        GetGameTime()
        + g_cvVoteCooldown.FloatValue;

    if (type == Round_Knife)
    {
        PrintToChatAll(
            "\x01[\x04-=LOL=-\x01] %N called a vote: \x04KNIFE ROUND NEXT ROUND\x01.",
            caller
        );
    }
    else
    {
        PrintToChatAll(
            "\x01[\x04-=LOL=-\x01] %N called a vote: \x04PISTOL ROUND NEXT ROUND\x01.",
            caller
        );
    }

    vote.DisplayVote(
        clients,
        count,
        VOTE_DURATION
    );
}

public int Handler_SpecialVote(
    Menu menu,
    MenuAction action,
    int param1,
    int param2
)
{
    if (action == MenuAction_VoteEnd)
    {
        int winningVotes;
        int totalVotes;

        GetMenuVoteInfo(
            param2,
            winningVotes,
            totalVotes
        );

        char winner[16];

        menu.GetItem(
            param1,
            winner,
            sizeof(winner)
        );

        bool yesWon = StrEqual(
            winner,
            "yes",
            false
        );

        float yesPercent = 0.0;

        if (totalVotes > 0)
        {
            yesPercent =
                (float(winningVotes)
                / float(totalVotes))
                * 100.0;
        }

        if (
            yesWon
            && yesPercent >= g_cvVotePercent.FloatValue
        )
        {
            g_NextRound = g_VoteType;

            if (g_VoteType == Round_Knife)
            {
                PrintToChatAll(
                    "\x01[\x04-=LOL=-\x01] Vote \x04PASSED\x01 - Next round is KNIFE / MELEE ONLY! (%.0f%% YES)",
                    yesPercent
                );
            }
            else if (g_VoteType == Round_Pistol)
            {
                PrintToChatAll(
                    "\x01[\x04-=LOL=-\x01] Vote \x04PASSED\x01 - Next round is PISTOLS + MELEE ONLY! (%.0f%% YES)",
                    yesPercent
                );
            }
        }
        else
        {
            PrintToChatAll(
                "\x01[\x04-=LOL=-\x01] Special-round vote failed. %.0f%% YES required.",
                g_cvVotePercent.FloatValue
            );
        }
    }
    else if (action == MenuAction_End)
    {
        g_bVoteRunning = false;
        g_VoteType = Round_Normal;

        delete menu;
    }

    return 0;
}

/*
 * ============================================================
 * ROUND STATE
 * ============================================================
 */

public void Event_RoundStart(
    Event event,
    const char[] name,
    bool dontBroadcast
)
{
    if (!g_cvEnabled.BoolValue)
    {
        g_NextRound = Round_Normal;
        g_ActiveRound = Round_Normal;
        return;
    }

    /*
     * No special round scheduled.
     */
    if (g_NextRound == Round_Normal)
    {
        g_ActiveRound = Round_Normal;
        return;
    }

    /*
     * Activate the scheduled special round.
     */
    g_ActiveRound = g_NextRound;
    g_NextRound = Round_Normal;

    if (g_ActiveRound == Round_Knife)
    {
        PrintToChatAll(
            "\x01[\x04-=LOL=-\x01] \x04KNIFE ROUND ACTIVE\x01 - Knives, Katana, Knuckles and Riot Shield ONLY!"
        );
    }
    else if (g_ActiveRound == Round_Pistol)
    {
        PrintToChatAll(
            "\x01[\x04-=LOL=-\x01] \x04PISTOL ROUND ACTIVE\x01 - Pistols + Melee ONLY!"
        );
    }

    /*
     * Strip anyone already alive.
     */
    for (int client = 1; client <= MaxClients; client++)
    {
        if (
            IsValidHuman(client)
            && IsPlayerAlive(client)
        )
        {
            CreateTimer(
                STRIP_DELAY,
                Timer_StripWeapons,
                GetClientUserId(client),
                TIMER_FLAG_NO_MAPCHANGE
            );
        }
    }
}

public void Event_RoundEnd(
    Event event,
    const char[] name,
    bool dontBroadcast
)
{
    if (g_ActiveRound == Round_Normal)
    {
        return;
    }

    if (g_ActiveRound == Round_Knife)
    {
        PrintToChatAll(
            "\x01[\x04-=LOL=-\x01] Knife Round finished - normal weapons return next round."
        );
    }
    else if (g_ActiveRound == Round_Pistol)
    {
        PrintToChatAll(
            "\x01[\x04-=LOL=-\x01] Pistol Round finished - normal weapons return next round."
        );
    }

    g_ActiveRound = Round_Normal;
}

/*
 * ============================================================
 * SPAWN DURING SPECIAL ROUND
 * ============================================================
 */

public void Event_PlayerSpawn(
    Event event,
    const char[] name,
    bool dontBroadcast
)
{
    if (g_ActiveRound == Round_Normal)
    {
        return;
    }

    int client = GetClientOfUserId(
        event.GetInt("userid")
    );

    if (
        !IsValidHuman(client)
        || !IsPlayerAlive(client)
    )
    {
        return;
    }

    /*
     * Give Insurgency a moment to finish generating
     * the player's selected loadout.
     */
    CreateTimer(
        STRIP_DELAY,
        Timer_StripWeapons,
        GetClientUserId(client),
        TIMER_FLAG_NO_MAPCHANGE
    );
}

/*
 * ============================================================
 * WEAPON RESTRICTION
 * ============================================================
 */

public Action OnWeaponCanUse(
    int client,
    int weapon
)
{
    if (g_ActiveRound == Round_Normal)
    {
        return Plugin_Continue;
    }

    if (
        !IsValidHuman(client)
        || weapon <= MaxClients
        || !IsValidEntity(weapon)
    )
    {
        return Plugin_Continue;
    }

    char classname[64];

    GetEntityClassname(
        weapon,
        classname,
        sizeof(classname)
    );

    if (IsAllowedForActiveRound(classname))
    {
        return Plugin_Continue;
    }

    /*
     * Prevent picking up or using disallowed weapons.
     */
    return Plugin_Handled;
}

public Action Timer_StripWeapons(
    Handle timer,
    any userid
)
{
    int client = GetClientOfUserId(userid);

    if (
        g_ActiveRound == Round_Normal
        || !IsValidHuman(client)
        || !IsPlayerAlive(client)
    )
    {
        return Plugin_Stop;
    }

    StripDisallowedWeapons(client);

    return Plugin_Stop;
}

void StripDisallowedWeapons(int client)
{
    int maxEntities = GetMaxEntities();

    for (
        int entity = MaxClients + 1;
        entity < maxEntities;
        entity++
    )
    {
        if (!IsValidEntity(entity))
        {
            continue;
        }

        if (!HasEntProp(
            entity,
            Prop_Send,
            "m_hOwnerEntity"
        ))
        {
            continue;
        }

        int owner = GetEntPropEnt(
            entity,
            Prop_Send,
            "m_hOwnerEntity"
        );

        if (owner != client)
        {
            continue;
        }

        char classname[64];

        GetEntityClassname(
            entity,
            classname,
            sizeof(classname)
        );

        /*
         * Ignore entities that are not weapon_* entities.
         */
        if (
            StrContains(
                classname,
                "weapon_",
                false
            ) != 0
        )
        {
            continue;
        }

        /*
         * Keep whitelisted weapons.
         */
        if (IsAllowedForActiveRound(classname))
        {
            continue;
        }

        /*
         * Remove everything else.
         */
        if (RemovePlayerItem(client, entity))
        {
            AcceptEntityInput(
                entity,
                "Kill"
            );
        }
    }
}

/*
 * ============================================================
 * ROUND-SPECIFIC WHITELISTS
 * ============================================================
 */

bool IsAllowedForActiveRound(
    const char[] classname
)
{
    if (g_ActiveRound == Round_Knife)
    {
        return IsAllowedMelee(classname);
    }

    if (g_ActiveRound == Round_Pistol)
    {
        /*
         * Pistol Round = Pistol + Melee.
         */
        return (
            IsAllowedMelee(classname)
            || IsAllowedPistol(classname)
        );
    }

    return true;
}

/*
 * ============================================================
 * CONFIRMED MELEE WHITELIST
 * ============================================================
 */

bool IsAllowedMelee(
    const char[] classname
)
{
    return (
        StrEqual(
            classname,
            "weapon_kabar",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_gurkha",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_katana",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_doi2ins_brassknuckles",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_riotshield",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_brassknuckles",
            false
        )
    );
}

/*
 * ============================================================
 * CONFIRMED PISTOL / HANDGUN WHITELIST
 * ============================================================
 */

bool IsAllowedPistol(
    const char[] classname
)
{
    return (
        StrEqual(
            classname,
            "weapon_m9",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_9mmsidearm",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_m1911seriespistol",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_m45seriespistol",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_glock33",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_glock17",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_glock18",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_taurusjudge",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_sigp226",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_makarov",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_deagle",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_combatcommander",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_fiveseven",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_hkusp",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_model10",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_mp443",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_sigp220",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_beretta93r",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_cobra",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_ots33",
            false
        )
        ||
        StrEqual(
            classname,
            "weapon_p2a1s",
            false
        )
    );
}

/*
 * ============================================================
 * ADMIN COMMANDS
 * ============================================================
 */

public Action Command_KnifeNext(
    int client,
    int args
)
{
    return ScheduleAdminRound(
        client,
        Round_Knife
    );
}

public Action Command_PistolNext(
    int client,
    int args
)
{
    return ScheduleAdminRound(
        client,
        Round_Pistol
    );
}

Action ScheduleAdminRound(
    int client,
    SpecialRoundType type
)
{
    if (!g_cvEnabled.BoolValue)
    {
        ReplyToCommand(
            client,
            "[Special Rounds] Plugin is disabled."
        );

        return Plugin_Handled;
    }

    if (g_ActiveRound != Round_Normal)
    {
        ReplyToCommand(
            client,
            "[Special Rounds] A special round is already active."
        );

        return Plugin_Handled;
    }

    if (g_NextRound != Round_Normal)
    {
        ReplyToCommand(
            client,
            "[Special Rounds] A special round is already scheduled."
        );

        return Plugin_Handled;
    }

    g_NextRound = type;

    if (type == Round_Knife)
    {
        PrintToChatAll(
            "\x01[\x04-=LOL=-\x01] ADMIN scheduled a \x04KNIFE ROUND\x01 for next round."
        );
    }
    else if (type == Round_Pistol)
    {
        PrintToChatAll(
            "\x01[\x04-=LOL=-\x01] ADMIN scheduled a \x04PISTOL ROUND\x01 for next round."
        );
    }

    return Plugin_Handled;
}

public Action Command_SpecialCancel(
    int client,
    int args
)
{
    if (g_NextRound == Round_Normal)
    {
        ReplyToCommand(
            client,
            "[Special Rounds] No special round is currently scheduled."
        );

        return Plugin_Handled;
    }

    g_NextRound = Round_Normal;

    PrintToChatAll(
        "\x01[\x04-=LOL=-\x01] Scheduled special round has been cancelled."
    );

    return Plugin_Handled;
}

public Action Command_SpecialStatus(
    int client,
    int args
)
{
    char activeName[64];
    char nextName[64];

    GetRoundName(
        g_ActiveRound,
        activeName,
        sizeof(activeName)
    );

    GetRoundName(
        g_NextRound,
        nextName,
        sizeof(nextName)
    );

    ReplyToCommand(
        client,
        "[Special Rounds] Active: %s | Next: %s",
        activeName,
        nextName
    );

    return Plugin_Handled;
}

/*
 * ============================================================
 * HELPERS
 * ============================================================
 */

void GetRoundName(
    SpecialRoundType type,
    char[] buffer,
    int maxlen
)
{
    switch (type)
    {
        case Round_Knife:
        {
            strcopy(
                buffer,
                maxlen,
                "KNIFE / MELEE"
            );
        }

        case Round_Pistol:
        {
            strcopy(
                buffer,
                maxlen,
                "PISTOL + MELEE"
            );
        }

        default:
        {
            strcopy(
                buffer,
                maxlen,
                "NORMAL"
            );
        }
    }
}

int CountHumanPlayers()
{
    int count = 0;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsValidHuman(client))
        {
            count++;
        }
    }

    return count;
}

bool IsValidHuman(int client)
{
    return (
        client > 0
        && client <= MaxClients
        && IsClientConnected(client)
        && IsClientInGame(client)
        && !IsFakeClient(client)
        && GetClientTeam(client) > 1
    );
}
