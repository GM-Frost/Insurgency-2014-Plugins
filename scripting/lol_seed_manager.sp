// ============================================================================
// [INS] LOL Seed Manager
//
// Insurgency (2014) - Push PvP population seeding.
//
// VERSION 1.1
//
// VERIFIED NATIVE COMMANDS:
//
//   ins_bot_add       -> Add Security bot
//   ins_bot_add_t2    -> Add Insurgent bot
//
//   ins_bot_kick_t1   -> Remove one Security bot
//   ins_bot_kick_t2   -> Remove one Insurgent bot
//
// Seed mode:
//   - Normally active before server reaches 8 human players.
//   - Targets approximately 5 active participants per faction.
//   - Humans replace bots on their own faction.
//
// Live PvP mode:
//   - Enter at 8 playing humans.
//   - Remove all bots.
//   - Remain pure PvP while 4+ humans remain.
//
// Hysteresis:
//   >= 8 humans -> LIVE PvP
//   4-7 humans  -> remain in current state
//   1-3 humans  -> return to seed mode after delay
//   0 humans    -> return to seed mode immediately
//
// IMPORTANT:
//
//   - Only humans actually on Security/Insurgent teams count.
//   - Spectators/unassigned humans do not count toward thresholds.
//   - Uses native Insurgency NextBots.
//   - Does NOT create fake clients manually.
//   - Does NOT modify A2S/Steam/browser reporting.
//   - Does NOT use ins_bot_quota.
// ============================================================================

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "1.1.1"

// Five active participants per faction while seeded.
#define SEED_TARGET_PER_TEAM       5

// At eight playing humans, remove every bot.
#define LIVE_HUMAN_THRESHOLD       8

// Below four humans, eventually return to seeded mode.
#define SEED_HUMAN_THRESHOLD       3

// Periodic sanity reconciliation while server is awake.
#define RECONCILE_INTERVAL         5.0

// Delay after joins/team initialization.
#define JOIN_DEBOUNCE              2.0

// Prevent transient disconnect/reconnect from immediately restoring bots.
#define LOW_POP_DELAY             60.0


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


Handle g_LowPopulationTimer = null;
Handle g_JoinDebounceTimer = null;


// ============================================================================
// Plugin start
// ============================================================================

public void OnPluginStart()
{
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
    CancelLowPopulationTimer();
    CancelJoinDebounceTimer();

    g_State = SeedState_Unknown;

    g_SecurityTeam = -1;
    g_InsurgentTeam = -1;
}


public void OnConfigsExecuted()
{
    /*
     * Important:
     *
     * The old implementation waited for a timer.
     *
     * An empty Insurgency server can enter hibernation before that timer
     * executes.
     *
     * OnConfigsExecuted happens during map/server initialization, so we seed
     * immediately before relying on recurring timers.
     */

    DiscoverTeamIndexes();

    ReconcilePopulation();
}


public void OnMapEnd()
{
    CancelLowPopulationTimer();
    CancelJoinDebounceTimer();

    g_State = SeedState_Unknown;
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

    ScheduleJoinReconcile();
}


public void OnClientDisconnect_Post(int client)
{
    /*
     * At this point the disconnect has completed, so human counts no longer
     * include the departing player.
     */

    ScheduleJoinReconcile();
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
         *   ins_bot_kick_t1   -> Security
         *   ins_bot_kick_t2   -> Insurgents
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


// ============================================================================
// Core state machine
// ============================================================================

void ReconcilePopulation()
{
    if (!EnsureTeamIndexes())
    {
        return;
    }

    int humans = CountPlayingHumans();

    /*
     * Startup / map-change state.
     */

    if (g_State == SeedState_Unknown)
    {
        if (humans >= LIVE_HUMAN_THRESHOLD)
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
        && humans >= LIVE_HUMAN_THRESHOLD
    )
    {
        EnterLiveMode();
        return;
    }

    /*
     * LIVE state.
     */

    if (g_State == SeedState_Live)
    {
        /*
         * Zero humans:
         *
         * Do not wait 60 seconds.
         *
         * The game may hibernate and timers may stop advancing. There is also
         * nobody present whose match could be disrupted.
         */

        if (humans == 0)
        {
            EnterSeedMode();
            return;
        }

        /*
         * 1-3 humans:
         *
         * Wait before restoring bots in case this was just a reconnect or
         * temporary population fluctuation.
         */

        if (humans <= SEED_HUMAN_THRESHOLD)
        {
            StartLowPopulationTimer();
        }
        else
        {
            CancelLowPopulationTimer();
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


// ============================================================================
// Seed mode
// ============================================================================

void EnterSeedMode()
{
    if (!EnsureTeamIndexes())
    {
        return;
    }

    CancelLowPopulationTimer();

    g_State = SeedState_Seeded;

    int humans = CountPlayingHumans();

    LogMessage(
        "[LOL Seed Manager] Entering SEED mode. Humans=%d.",
        humans
    );

    MaintainSeedPopulation();
}


void MaintainSeedPopulation()
{
    if (!EnsureTeamIndexes())
    {
        return;
    }

    int totalHumans = CountPlayingHumans();

    if (totalHumans >= LIVE_HUMAN_THRESHOLD)
    {
        EnterLiveMode();
        return;
    }

    int securityHumans =
        CountHumansOnTeam(g_SecurityTeam);

    int insurgentHumans =
        CountHumansOnTeam(g_InsurgentTeam);

    int securityBots =
        CountBotsOnTeam(g_SecurityTeam);

    int insurgentBots =
        CountBotsOnTeam(g_InsurgentTeam);


    /*
     * Each faction targets five active participants while seeded.
     *
     * Example:
     *
     *   0 humans:
     *       Security   5 bots
     *       Insurgent  5 bots
     *
     *   1 Security human:
     *       Security   1 human + 4 bots
     *       Insurgent  5 bots
     *
     *   2 vs 3 humans:
     *       Security   2 humans + 3 bots
     *       Insurgent  3 humans + 2 bots
     */

    int desiredSecurityBots =
        SEED_TARGET_PER_TEAM - securityHumans;

    int desiredInsurgentBots =
        SEED_TARGET_PER_TEAM - insurgentHumans;


    if (desiredSecurityBots < 0)
    {
        desiredSecurityBots = 0;
    }

    if (desiredInsurgentBots < 0)
    {
        desiredInsurgentBots = 0;
    }


    LogMessage(
        "[LOL Seed Manager] SEED reconcile: SEC H=%d B=%d->%d | INS H=%d B=%d->%d | TotalHumans=%d.",
        securityHumans,
        securityBots,
        desiredSecurityBots,
        insurgentHumans,
        insurgentBots,
        desiredInsurgentBots,
        totalHumans
    );


    ReconcileSecurityBots(
        securityBots,
        desiredSecurityBots
    );

    ReconcileInsurgentBots(
        insurgentBots,
        desiredInsurgentBots
    );
}


// ============================================================================
// Native bot manipulation
// ============================================================================

void ReconcileSecurityBots(
    int currentBots,
    int desiredBots
)
{
    int difference =
        desiredBots - currentBots;

    if (difference > 0)
    {
        AddSecurityBots(difference);
    }
    else if (difference < 0)
    {
        KickSecurityBots(-difference);
    }
}


void ReconcileInsurgentBots(
    int currentBots,
    int desiredBots
)
{
    int difference =
        desiredBots - currentBots;

    if (difference > 0)
    {
        AddInsurgentBots(difference);
    }
    else if (difference < 0)
    {
        KickInsurgentBots(-difference);
    }
}


void AddSecurityBots(int amount)
{
    if (amount <= 0)
    {
        return;
    }

    LogMessage(
        "[LOL Seed Manager] Adding %d Security bot(s).",
        amount
    );

    for (int i = 0; i < amount; i++)
    {
        ServerCommand("ins_bot_add");
    }

    ServerExecute();
}


void AddInsurgentBots(int amount)
{
    if (amount <= 0)
    {
        return;
    }

    LogMessage(
        "[LOL Seed Manager] Adding %d Insurgent bot(s).",
        amount
    );

    for (int i = 0; i < amount; i++)
    {
        ServerCommand("ins_bot_add_t2");
    }

    ServerExecute();
}


void KickSecurityBots(int amount)
{
    if (amount <= 0)
    {
        return;
    }

    LogMessage(
        "[LOL Seed Manager] Removing %d Security bot(s).",
        amount
    );

    for (int i = 0; i < amount; i++)
    {
        ServerCommand("ins_bot_kick_t1");
    }

    ServerExecute();
}


void KickInsurgentBots(int amount)
{
    if (amount <= 0)
    {
        return;
    }

    LogMessage(
        "[LOL Seed Manager] Removing %d Insurgent bot(s).",
        amount
    );

    for (int i = 0; i < amount; i++)
    {
        ServerCommand("ins_bot_kick_t2");
    }

    ServerExecute();
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

    CancelLowPopulationTimer();

    g_State = SeedState_Live;

    int humans = CountPlayingHumans();

    int securityBots =
        CountBotsOnTeam(g_SecurityTeam);

    int insurgentBots =
        CountBotsOnTeam(g_InsurgentTeam);

    LogMessage(
        "[LOL Seed Manager] Entering LIVE PvP. Humans=%d SecurityBots=%d InsurgentBots=%d.",
        humans,
        securityBots,
        insurgentBots
    );

    /*
     * Remove every native bot.
     *
     * Commands were verified directly on this server:
     *
     *   ins_bot_kick_t1 = Security
     *   ins_bot_kick_t2 = Insurgents
     */

    KickSecurityBots(securityBots);
    KickInsurgentBots(insurgentBots);
}


// ============================================================================
// Low-population hysteresis
// ============================================================================

void StartLowPopulationTimer()
{
    if (g_LowPopulationTimer != null)
    {
        return;
    }

    LogMessage(
        "[LOL Seed Manager] Population <= %d. Starting %.0f second seed-return timer.",
        SEED_HUMAN_THRESHOLD,
        LOW_POP_DELAY
    );

    g_LowPopulationTimer = CreateTimer(
        LOW_POP_DELAY,
        Timer_LowPopulationExpired,
        _,
        TIMER_FLAG_NO_MAPCHANGE
    );
}


void CancelLowPopulationTimer()
{
    if (g_LowPopulationTimer != null)
    {
        KillTimer(g_LowPopulationTimer);

        g_LowPopulationTimer = null;
    }
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

    ReconcilePopulation();

    return Plugin_Stop;
}


public Action Timer_LowPopulationExpired(
    Handle timer,
    any data
)
{
    g_LowPopulationTimer = null;

    int humans = CountPlayingHumans();

    /*
     * Only return to seed mode if population is STILL <= 3.
     */

    if (
        g_State == SeedState_Live
        && humans <= SEED_HUMAN_THRESHOLD
    )
    {
        LogMessage(
            "[LOL Seed Manager] Low population persisted. Humans=%d. Re-entering SEED mode.",
            humans
        );

        EnterSeedMode();
    }

    return Plugin_Stop;
}


// ============================================================================
// Round events
// ============================================================================

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
        "[LOL Seed] State=%s | SEC H=%d B=%d | INS H=%d B=%d | Humans=%d Bots=%d",
        stateName,
        securityHumans,
        securityBots,
        insurgentHumans,
        insurgentBots,
        securityHumans + insurgentHumans,
        CountAllBots()
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
