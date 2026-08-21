// ============================================================================
// [INS] LOL Seed Manager
//
// Insurgency (2014) - Push PvP population seeding.
//
// VERSION 1.7
//
// VERIFIED NATIVE COMMANDS:
//
// Seed mode:
//   - Empty server: no bots.
//   - Starts only after the first human selects a team/class and spawns.
//   - Active while the server has 1-5 playing human players.
//   - Targets exactly 5 active participants per faction.
//   - New humans are assigned to the faction with fewer humans.
//   - Humans replace bots on their own faction.
//   - When the final playing human leaves, every bot is removed.
//
// Live PvP mode:
//   - Enter at 6 playing humans.
//   - Remove all bots.
//   - Return to seed mode when the population falls below 6 humans.
//
// IMPORTANT:
//
//   - Only humans actually on Security/Insurgent teams count.
//   - Spectators/unassigned humans do not count toward thresholds.
//   - Uses native Insurgency NextBots.
//   - Does NOT create fake clients manually.
//   - Does NOT modify A2S/Steam/browser reporting.
//   - Uses ins_bot_quota so the game owns bot lifecycle across round changes.
// ============================================================================

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.7.1"

// Five active participants per faction while seeded.
#define SEED_TARGET_PER_TEAM       5

// More than five playing humans means pure PvP.
#define LIVE_HUMAN_THRESHOLD       6

// Periodic sanity reconciliation while server is awake.
#define RECONCILE_INTERVAL         5.0

// Delay after joins/team initialization.
#define JOIN_DEBOUNCE              2.0

// ============================================================================
// Plugin information
// ============================================================================

public Plugin myinfo =
{
    name = "[INS] LOL Seed Manager",
    author = "Nayan",
    description = "Seeds low-population Push PvP with native Insurgency bots.",
    version = PLUGIN_VERSION,
    url = ""
};


// ============================================================================
// State
// ============================================================================

enum SeedState
{
    SeedState_Unknown = 0,
    SeedState_Empty,
    SeedState_Seeded,
    SeedState_Live
};

SeedState g_State = SeedState_Unknown;


// Team indexes discovered from the game at runtime.
//
// We deliberately do NOT assume:
//   Security  = team X
//   Insurgent = team Y
//
// The game provides team names such as #Team_Security / #Team_Insurgent.
int g_SecurityTeam = -1;
int g_InsurgentTeam = -1;


Handle g_JoinDebounceTimer = null;
bool g_PendingAutoAssign[MAXPLAYERS + 1];
bool g_HumanHasSpawned[MAXPLAYERS + 1];
bool g_HumanDisconnectPending[MAXPLAYERS + 1];
bool g_SeedActivated = false;
int g_DesiredBotQuota = 0;
ConVar g_BotQuota = null;


// ============================================================================
// Plugin start
// ============================================================================

public void OnPluginStart()
{
    g_BotQuota = FindConVar("ins_bot_quota");

    if (g_BotQuota == null)
    {
        LogError(
            "[LOL Seed Manager] ins_bot_quota was not found; native bot management may conflict."
        );
    }
    else
    {
        HookConVarChange(
            g_BotQuota,
            ConVarChanged_BotQuota
        );

        SetNativeBotQuota(0);
    }

    HookEvent(
        "round_start",
        Event_RoundStart,
        EventHookMode_PostNoCopy
    );

    HookEvent(
        "round_end",
        Event_RoundEnd,
        EventHookMode_PostNoCopy
    );

    HookEvent(
        "player_team",
        Event_PlayerTeam,
        EventHookMode_Post
    );

    HookEvent(
        "player_spawn",
        Event_PlayerSpawn,
        EventHookMode_Post
    );

    RegAdminCmd(
        "sm_seedstatus",
        Command_SeedStatus,
        ADMFLAG_GENERIC,
        "Shows LOL Seed Manager state and team populations."
    );

    RegAdminCmd(
        "sm_seedreconcile",
        Command_SeedReconcile,
        ADMFLAG_ROOT,
        "Forces LOL Seed Manager to reconcile population."
    );

    RegAdminCmd(
        "sm_seedon",
        Command_SeedOn,
        ADMFLAG_ROOT,
        "Forces seed mode."
    );

    RegAdminCmd(
        "sm_seedoff",
        Command_SeedOff,
        ADMFLAG_ROOT,
        "Forces pure PvP mode and removes bots."
    );

    RegAdminCmd(
        "sm_seedteams",
        Command_SeedTeams,
        ADMFLAG_ROOT,
        "Shows Source team indexes/names seen by the seed manager."
    );

    CreateTimer(
        RECONCILE_INTERVAL,
        Timer_Reconcile,
        _,
        TIMER_REPEAT
    );

    LogMessage(
        "[LOL Seed Manager] Loaded version %s.",
        PLUGIN_VERSION
    );
}


// ============================================================================
// Config / map lifecycle
// ============================================================================

public void OnMapStart()
{
    CancelJoinDebounceTimer();

    g_State = SeedState_Unknown;
    g_SeedActivated = false;
    g_DesiredBotQuota = 0;

    g_SecurityTeam = -1;
    g_InsurgentTeam = -1;

    for (int client = 1; client <= MaxClients; client++)
    {
        g_PendingAutoAssign[client] = false;
        g_HumanHasSpawned[client] = false;
        g_HumanDisconnectPending[client] = false;
    }
}


public void OnConfigsExecuted()
{
    /*
     * Important:
     *
     * The old implementation waited for a timer.
     *
     * OnConfigsExecuted happens during map/server initialization, so we can
     * remove leftover bots immediately and enter EMPTY mode before hibernation.
     */

    SetNativeBotQuota(0);
    DiscoverTeamIndexes();

    ReconcilePopulation();
}


void SetNativeBotQuota(int quota)
{
    g_DesiredBotQuota = quota;

    if (g_BotQuota == null || g_BotQuota.IntValue == quota)
    {
        return;
    }

    LogMessage(
        "[LOL Seed Manager] Setting ins_bot_quota %d -> %d.",
        g_BotQuota.IntValue,
        quota
    );

    g_BotQuota.IntValue = quota;
}


public void ConVarChanged_BotQuota(
    ConVar convar,
    const char[] oldValue,
    const char[] newValue
)
{
    if (convar.IntValue != g_DesiredBotQuota)
    {
        SetNativeBotQuota(g_DesiredBotQuota);
    }
}


public void OnMapEnd()
{
    CancelJoinDebounceTimer();

    SetNativeBotQuota(0);
    g_State = SeedState_Unknown;
    g_SeedActivated = false;
}


// ============================================================================
// Client lifecycle
// ============================================================================

public void OnClientPutInServer(int client)
{
    /*
     * Bots also trigger this forward.
     *
     * Only schedule a join reconcile for genuine humans.
     */

    if (!IsRealHuman(client))
    {
        return;
    }

    LogMessage(
        "[LOL Seed Manager] Human connected: %N.",
        client
    );

    g_PendingAutoAssign[client] = true;
    g_HumanHasSpawned[client] = false;
    g_HumanDisconnectPending[client] = false;

    ScheduleJoinReconcile();
}


public void OnClientDisconnect(int client)
{
    /*
     * This forward runs while client classification is still available.
     * Ignore native bot removals so they cannot trigger extra reconciliation
     * cycles. The debounce timer executes after a real human has disconnected.
     */

    if (!IsRealHuman(client))
    {
        return;
    }

    g_PendingAutoAssign[client] = false;
    g_HumanHasSpawned[client] = false;
    g_HumanDisconnectPending[client] = true;
}


public void OnClientDisconnect_Post(int client)
{
    if (!g_HumanDisconnectPending[client])
    {
        return;
    }

    g_HumanDisconnectPending[client] = false;

    /*
     * Reconcile after the human is gone so the final departure removes every
     * bot before an empty server can hibernate and pause ordinary timers.
     */
    ReconcilePopulation();
}


// ============================================================================
// Client classification
// ============================================================================

bool IsRealHuman(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return false;
    }

    if (!IsClientConnected(client))
    {
        return false;
    }

    if (!IsClientInGame(client))
    {
        return false;
    }

    if (IsFakeClient(client))
    {
        return false;
    }

    if (IsClientSourceTV(client))
    {
        return false;
    }

    return true;
}


bool IsGameBot(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return false;
    }

    if (!IsClientConnected(client))
    {
        return false;
    }

    if (!IsClientInGame(client))
    {
        return false;
    }

    if (!IsFakeClient(client))
    {
        return false;
    }

    if (IsClientSourceTV(client))
    {
        return false;
    }

    return true;
}


// ============================================================================
// Team discovery
// ============================================================================

bool DiscoverTeamIndexes()
{
    g_SecurityTeam = -1;
    g_InsurgentTeam = -1;

    int teamCount = GetTeamCount();

    char teamName[64];

    for (int team = 0; team < teamCount; team++)
    {
        teamName[0] = '\0';

        GetTeamName(
            team,
            teamName,
            sizeof(teamName)
        );

        /*
         * Some builds/plugins may expose descriptive faction names.
         */
        if (StrContains(teamName, "Security", false) != -1)
        {
            g_SecurityTeam = team;
            continue;
        }

        if (StrContains(teamName, "Insurgent", false) != -1)
        {
            g_InsurgentTeam = team;
            continue;
        }

        /*
         * Insurgency 2014 dedicated server exposes the two playable
         * factions through SourceMod as:
         *
         *   Team 2 = "TEAM ONE" -> Security
         *   Team 3 = "TEAM TWO" -> Insurgents
         *
         * This corresponds with the native commands verified on this server:
         *
         *   ins_bot_add       -> Security
         *   ins_bot_add_t2    -> Insurgents
         *   ins_bot_kick_t1   -> Insurgents
         *   ins_bot_kick_t2   -> Security
         */

        if (StrEqual(teamName, "TEAM ONE", false))
        {
            g_SecurityTeam = team;
            continue;
        }

        if (StrEqual(teamName, "TEAM TWO", false))
        {
            g_InsurgentTeam = team;
            continue;
        }
    }

    if (
        g_SecurityTeam == -1
        || g_InsurgentTeam == -1
    )
    {
        LogError(
            "[LOL Seed Manager] Could not discover faction team indexes. Security=%d Insurgent=%d.",
            g_SecurityTeam,
            g_InsurgentTeam
        );

        return false;
    }

    LogMessage(
        "[LOL Seed Manager] Team mapping: Security=%d Insurgent=%d.",
        g_SecurityTeam,
        g_InsurgentTeam
    );

    return true;
}

bool EnsureTeamIndexes()
{
    if (
        g_SecurityTeam >= 0
        && g_InsurgentTeam >= 0
    )
    {
        return true;
    }

    return DiscoverTeamIndexes();
}


// ============================================================================
// Population counts
// ============================================================================

int CountHumansOnTeam(int team)
{
    int count = 0;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsRealHuman(client))
        {
            continue;
        }

        if (GetClientTeam(client) == team)
        {
            count++;
        }
    }

    return count;
}


int CountBotsOnTeam(int team)
{
    int count = 0;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsGameBot(client))
        {
            continue;
        }

        if (GetClientTeam(client) == team)
        {
            count++;
        }
    }

    return count;
}


int CountPlayingHumans()
{
    if (!EnsureTeamIndexes())
    {
        return 0;
    }

    return
        CountHumansOnTeam(g_SecurityTeam)
        +
        CountHumansOnTeam(g_InsurgentTeam);
}


int CountConnectedHumans()
{
    int count = 0;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsRealHuman(client))
        {
            count++;
        }
    }

    return count;
}


int CountAllBots()
{
    int count = 0;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsGameBot(client))
        {
            count++;
        }
    }

    return count;
}


void TrimExcessBotsOnTeam(int team)
{
    int humans = CountHumansOnTeam(team);
    int bots = CountBotsOnTeam(team);
    int excess = humans + bots - SEED_TARGET_PER_TEAM;

    if (excess <= 0)
    {
        return;
    }

    LogMessage(
        "[LOL Seed Manager] Team %d exceeds seed target: H=%d B=%d. Removing %d replacement bot(s).",
        team,
        humans,
        bots,
        excess
    );

    for (int client = 1; client <= MaxClients && excess > 0; client++)
    {
        if (!IsGameBot(client) || GetClientTeam(client) != team)
        {
            continue;
        }

        KickClient(client, "Human player reclaimed seed slot");
        excess--;
    }
}


void TrimSeedTeamsToTarget()
{
    if (
        !EnsureTeamIndexes()
        || g_DesiredBotQuota != SEED_TARGET_PER_TEAM
        || CountConnectedHumans() >= LIVE_HUMAN_THRESHOLD
    )
    {
        return;
    }

    TrimExcessBotsOnTeam(g_SecurityTeam);
    TrimExcessBotsOnTeam(g_InsurgentTeam);
}


bool HasSpawnedPlayingHuman()
{
    if (!EnsureTeamIndexes())
    {
        return false;
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!g_HumanHasSpawned[client] || !IsRealHuman(client))
        {
            continue;
        }

        int team = GetClientTeam(client);

        if (team == g_SecurityTeam || team == g_InsurgentTeam)
        {
            return true;
        }
    }

    return false;
}


// ============================================================================
// Seeded human team balancing
// ============================================================================

void AutoAssignPendingHumans()
{
    if (!EnsureTeamIndexes())
    {
        return;
    }

    int securityHumans = CountHumansOnTeam(g_SecurityTeam);
    int insurgentHumans = CountHumansOnTeam(g_InsurgentTeam);

    /*
     * Let the first human choose either faction. Once that choice exists,
     * later arrivals go to the faction with fewer human players.
     */
    if (securityHumans + insurgentHumans == 0)
    {
        return;
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!g_PendingAutoAssign[client] || !IsRealHuman(client))
        {
            continue;
        }

        g_PendingAutoAssign[client] = false;

        int currentTeam = GetClientTeam(client);

        if (currentTeam == g_SecurityTeam || currentTeam == g_InsurgentTeam)
        {
            continue;
        }

        int targetTeam;

        if (securityHumans <= insurgentHumans)
        {
            targetTeam = g_SecurityTeam;
            securityHumans++;
        }
        else
        {
            targetTeam = g_InsurgentTeam;
            insurgentHumans++;
        }

        LogMessage(
            "[LOL Seed Manager] Auto-assigning %N to team %d to balance humans.",
            client,
            targetTeam
        );

        ChangeClientTeam(client, targetTeam);
    }
}


void BalanceHumanTeamChoice(int client)
{
    if (!IsRealHuman(client) || !EnsureTeamIndexes())
    {
        return;
    }

    int totalHumans = CountPlayingHumans();

    if (totalHumans >= LIVE_HUMAN_THRESHOLD)
    {
        return;
    }

    int currentTeam = GetClientTeam(client);
    int securityHumans = CountHumansOnTeam(g_SecurityTeam);
    int insurgentHumans = CountHumansOnTeam(g_InsurgentTeam);
    int targetTeam = currentTeam;

    if (
        currentTeam == g_SecurityTeam
        && securityHumans > insurgentHumans + 1
    )
    {
        targetTeam = g_InsurgentTeam;
    }
    else if (
        currentTeam == g_InsurgentTeam
        && insurgentHumans > securityHumans + 1
    )
    {
        targetTeam = g_SecurityTeam;
    }

    if (targetTeam == currentTeam)
    {
        return;
    }

    LogMessage(
        "[LOL Seed Manager] Moving %N from team %d to team %d to balance seeded humans.",
        client,
        currentTeam,
        targetTeam
    );

    ChangeClientTeam(client, targetTeam);
}


public void Frame_BalanceHumanTeam(any userId)
{
    int client = GetClientOfUserId(userId);

    if (client == 0)
    {
        return;
    }

    BalanceHumanTeamChoice(client);

    /*
     * Reconcile immediately after the team event instead of waiting for the
     * join debounce. A delayed bot removal can make Insurgency rebuild squads
     * after the human has already started choosing a class/loadout.
     */
    ReconcilePopulation();
}


// ============================================================================
// Core state machine
// ============================================================================

void ReconcilePopulation()
{
    if (!EnsureTeamIndexes())
    {
        return;
    }

    int connectedHumans = CountConnectedHumans();

    /*
     * Only a truly empty server disables bots. Once seeding has activated, a
     * human who moves to Spectator still keeps the seeded match available.
     */
    if (connectedHumans == 0)
    {
        g_SeedActivated = false;
        EnterEmptyMode();
        return;
    }

    /*
     * Let the first human complete team, squad, class, and loadout selection.
     * The first player_spawn event is the signal that bot seeding may begin.
     */
    if (!g_SeedActivated && !HasSpawnedPlayingHuman())
    {
        EnterEmptyMode();
        return;
    }

    g_SeedActivated = true;

    /*
     * Startup / map-change state.
     */

    if (
        g_State == SeedState_Unknown
        || g_State == SeedState_Empty
    )
    {
        if (connectedHumans >= LIVE_HUMAN_THRESHOLD)
        {
            EnterLiveMode();
        }
        else
        {
            EnterSeedMode();
        }

        return;
    }

    /*
     * Seeded -> Live.
     */

    if (
        g_State == SeedState_Seeded
        && connectedHumans >= LIVE_HUMAN_THRESHOLD
    )
    {
        EnterLiveMode();
        return;
    }

    if (g_State == SeedState_Live)
    {
        if (connectedHumans < LIVE_HUMAN_THRESHOLD)
        {
            EnterSeedMode();
        }

        return;
    }

    /*
     * Already seeded.
     */

    if (g_State == SeedState_Seeded)
    {
        MaintainSeedPopulation();
    }
}


void EnterEmptyMode()
{
    if (!EnsureTeamIndexes())
    {
        return;
    }

    if (g_State != SeedState_Empty || g_DesiredBotQuota != 0)
    {
        LogMessage(
            "[LOL Seed Manager] Entering EMPTY mode."
        );
    }

    g_State = SeedState_Empty;
    SetNativeBotQuota(0);
}


// ============================================================================
// Seed mode
// ============================================================================

void EnterSeedMode()
{
    if (!EnsureTeamIndexes())
    {
        return;
    }

    g_State = SeedState_Seeded;

    int humans = CountPlayingHumans();

    LogMessage(
        "[LOL Seed Manager] Entering SEED mode. PlayingHumans=%d ConnectedHumans=%d.",
        humans,
        CountConnectedHumans()
    );

    MaintainSeedPopulation();
}


void MaintainSeedPopulation()
{
    if (!EnsureTeamIndexes())
    {
        return;
    }

    int totalHumans = CountConnectedHumans();

    if (totalHumans >= LIVE_HUMAN_THRESHOLD)
    {
        EnterLiveMode();
        return;
    }

    SetNativeBotQuota(SEED_TARGET_PER_TEAM);
    TrimSeedTeamsToTarget();
}


// ============================================================================
// Live PvP mode
// ============================================================================

void EnterLiveMode()
{
    if (!EnsureTeamIndexes())
    {
        return;
    }

    g_State = SeedState_Live;

    LogMessage(
        "[LOL Seed Manager] Entering LIVE PvP. ConnectedHumans=%d.",
        CountConnectedHumans()
    );

    SetNativeBotQuota(0);
}


// ============================================================================
// Reconcile debounce
// ============================================================================

void ScheduleJoinReconcile()
{
    CancelJoinDebounceTimer();

    g_JoinDebounceTimer = CreateTimer(
        JOIN_DEBOUNCE,
        Timer_JoinDebounce,
        _,
        TIMER_FLAG_NO_MAPCHANGE
    );
}


void CancelJoinDebounceTimer()
{
    if (g_JoinDebounceTimer != null)
    {
        KillTimer(g_JoinDebounceTimer);

        g_JoinDebounceTimer = null;
    }
}


// ============================================================================
// Timers
// ============================================================================

public Action Timer_Reconcile(
    Handle timer,
    any data
)
{
    ReconcilePopulation();

    return Plugin_Continue;
}


public Action Timer_JoinDebounce(
    Handle timer,
    any data
)
{
    g_JoinDebounceTimer = null;

    AutoAssignPendingHumans();
    ReconcilePopulation();

    return Plugin_Stop;
}


// ============================================================================
// Round events
// ============================================================================

public void Event_PlayerTeam(
    Event event,
    const char[] name,
    bool dontBroadcast
)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (!IsRealHuman(client))
    {
        return;
    }

    g_PendingAutoAssign[client] = false;

    /*
     * Defer the correction until the game has finished processing its own
     * player_team event. A second event caused by ChangeClientTeam is harmless
     * because the human counts will already be balanced.
     */
    RequestFrame(
        Frame_BalanceHumanTeam,
        GetClientUserId(client)
    );
}


public void Event_PlayerSpawn(
    Event event,
    const char[] name,
    bool dontBroadcast
)
{
    int client = GetClientOfUserId(event.GetInt("userid"));

    if (!IsRealHuman(client))
    {
        return;
    }

    int team = GetClientTeam(client);

    if (team != g_SecurityTeam && team != g_InsurgentTeam)
    {
        return;
    }

    bool firstReadyHuman = !HasSpawnedPlayingHuman();

    g_HumanHasSpawned[client] = true;
    g_SeedActivated = true;

    if (firstReadyHuman)
    {
        LogMessage(
            "[LOL Seed Manager] First playing human spawned: %N. Activating seed bots.",
            client
        );
    }

    ScheduleJoinReconcile();
}

public void Event_RoundStart(
    Event event,
    const char[] name,
    bool dontBroadcast
)
{
    /*
     * By round start, faction/team placement should be stable.
     */

    ReconcilePopulation();
}


public void Event_RoundEnd(
    Event event,
    const char[] name,
    bool dontBroadcast
)
{
    ReconcilePopulation();
}


// ============================================================================
// Admin diagnostics
// ============================================================================

public Action Command_SeedStatus(
    int client,
    int args
)
{
    EnsureTeamIndexes();

    char stateName[32];

    switch (g_State)
    {
        case SeedState_Empty:
        {
            strcopy(
                stateName,
                sizeof(stateName),
                "EMPTY"
            );
        }

        case SeedState_Seeded:
        {
            strcopy(
                stateName,
                sizeof(stateName),
                "SEED"
            );
        }

        case SeedState_Live:
        {
            strcopy(
                stateName,
                sizeof(stateName),
                "LIVE"
            );
        }

        default:
        {
            strcopy(
                stateName,
                sizeof(stateName),
                "UNKNOWN"
            );
        }
    }


    int securityHumans = 0;
    int insurgentHumans = 0;
    int securityBots = 0;
    int insurgentBots = 0;

    if (
        g_SecurityTeam >= 0
        && g_InsurgentTeam >= 0
    )
    {
        securityHumans =
            CountHumansOnTeam(g_SecurityTeam);

        insurgentHumans =
            CountHumansOnTeam(g_InsurgentTeam);

        securityBots =
            CountBotsOnTeam(g_SecurityTeam);

        insurgentBots =
            CountBotsOnTeam(g_InsurgentTeam);
    }


    ReplyToCommand(
        client,
        "[LOL Seed] State=%s | SEC H=%d B=%d | INS H=%d B=%d | Playing=%d Connected=%d Bots=%d Quota=%d",
        stateName,
        securityHumans,
        securityBots,
        insurgentHumans,
        insurgentBots,
        securityHumans + insurgentHumans,
        CountConnectedHumans(),
        CountAllBots(),
        g_DesiredBotQuota
    );

    return Plugin_Handled;
}


public Action Command_SeedReconcile(
    int client,
    int args
)
{
    ReconcilePopulation();

    ReplyToCommand(
        client,
        "[LOL Seed] Population reconciled."
    );

    return Plugin_Handled;
}


public Action Command_SeedOn(
    int client,
    int args
)
{
    EnterSeedMode();

    ReplyToCommand(
        client,
        "[LOL Seed] Forced SEED mode."
    );

    return Plugin_Handled;
}


public Action Command_SeedOff(
    int client,
    int args
)
{
    EnterLiveMode();

    ReplyToCommand(
        client,
        "[LOL Seed] Forced LIVE mode."
    );

    return Plugin_Handled;
}


public Action Command_SeedTeams(
    int client,
    int args
)
{
    int teamCount = GetTeamCount();

    ReplyToCommand(
        client,
        "[LOL Seed] Source reports %d teams:",
        teamCount
    );

    char teamName[64];

    for (int team = 0; team < teamCount; team++)
    {
        teamName[0] = '\0';

        GetTeamName(
            team,
            teamName,
            sizeof(teamName)
        );

        ReplyToCommand(
            client,
            "[LOL Seed] Team %d = \"%s\"",
            team,
            teamName
        );
    }

    ReplyToCommand(
        client,
        "[LOL Seed] Detected Security=%d Insurgent=%d",
        g_SecurityTeam,
        g_InsurgentTeam
    );

    return Plugin_Handled;
}
