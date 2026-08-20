// ============================================================================
// [INS] AFK Manager
//
// AFK management for Insurgency (2014).
//
// Normal player:
//   - 2 minutes AFK while on Security / Insurgents -> Spectator
//   - AFK timer resets when moved to Spectator
//   - 4 additional minutes AFK in Spectator -> eligible for FIFO kick
//   - Only kicked while every server slot is occupied
//
// Admin:
//   - 2 minutes AFK while on Security / Insurgents -> Spectator
//   - Never kicked for AFK
//
// Important:
//   - Dead players waiting for reinforcement do NOT accumulate AFK time.
//   - Bots and SourceTV are ignored.
//   - Activity includes keyboard movement, buttons, mouse movement,
//     view-angle movement and chat.
//   - AFK kicks NEVER become bans.
//   - Warnings are shown at 60 seconds and 15 seconds before an action.
//   - Automatic AFK actions are logged.
//
// Designed for Insurgency (2014).
// ============================================================================

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define PLUGIN_VERSION "2.1"

#define TEAM_SPECTATOR 1
#define TEAM_SECURITY  2
#define TEAM_INSURGENT 3

#define AFK_SCAN_INTERVAL 1.0


// ============================================================================
// ConVars
// ============================================================================

ConVar g_CvarEnabled;

ConVar g_CvarSpecTime;
ConVar g_CvarKickTime;

ConVar g_CvarWarningTime;
ConVar g_CvarFinalWarningTime;

ConVar g_CvarAnnounceActions;
ConVar g_CvarLogDays;


// ============================================================================
// Player AFK State
// ============================================================================

float g_LastActivity[MAXPLAYERS + 1];

int g_LastButtons[MAXPLAYERS + 1];

float g_LastAngles[MAXPLAYERS + 1][3];

bool g_WarningShown[MAXPLAYERS + 1];
bool g_FinalWarningShown[MAXPLAYERS + 1];


// ============================================================================
// Logging
// ============================================================================

char g_LogDirectory[PLATFORM_MAX_PATH];
char g_LogFile[PLATFORM_MAX_PATH];
char g_LogDate[16];


// ============================================================================
// Plugin Information
// ============================================================================

public Plugin myinfo =
{
    name = "[INS] AFK Manager",
    author = "Nayan",
    description = "Moves AFK players to Spectator and FIFO-kicks them only when full.",
    version = PLUGIN_VERSION,
    url = ""
};


// ============================================================================
// Plugin Start
// ============================================================================

public void OnPluginStart()
{
    CreateConVar(
        "sm_ins_afk_version",
        PLUGIN_VERSION,
        "INS AFK Manager version.",
        FCVAR_NOTIFY | FCVAR_DONTRECORD
    );

    g_CvarEnabled = CreateConVar(
        "sm_ins_afk_enabled",
        "1",
        "Enable or disable the AFK Manager. 1 = Enabled, 0 = Disabled.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    g_CvarSpecTime = CreateConVar(
        "sm_ins_afk_spec_time",
        "120.0",
        "Seconds of inactivity before a playing player is moved to Spectator. 0 = Disabled.",
        FCVAR_NOTIFY,
        true,
        0.0
    );

    g_CvarKickTime = CreateConVar(
        "sm_ins_afk_kick_time",
        "240.0",
        "Additional seconds of inactivity in Spectator before a normal player is kicked. 0 = Disabled.",
        FCVAR_NOTIFY,
        true,
        0.0
    );

    g_CvarWarningTime = CreateConVar(
        "sm_ins_afk_warning_time",
        "60.0",
        "Seconds before an AFK action when the first warning is shown. 0 = Disabled.",
        FCVAR_NOTIFY,
        true,
        0.0
    );

    g_CvarFinalWarningTime = CreateConVar(
        "sm_ins_afk_final_warning_time",
        "15.0",
        "Seconds before an AFK action when the final warning is shown. 0 = Disabled.",
        FCVAR_NOTIFY,
        true,
        0.0
    );

    g_CvarAnnounceActions = CreateConVar(
        "sm_ins_afk_announce",
        "1",
        "Announce automatic AFK moves and kicks to all players. 1 = Yes, 0 = No.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    g_CvarLogDays = CreateConVar(
        "sm_ins_afk_log_days",
        "2",
        "Number of days AFK logs are retained. 0 = Keep indefinitely.",
        FCVAR_NOTIFY,
        true,
        0.0
    );

    AutoExecConfig(true, "ins_afkmanager");

    HookEvent(
        "player_spawn",
        Event_PlayerSpawn,
        EventHookMode_Post
    );

    HookEvent(
        "player_team",
        Event_PlayerTeam,
        EventHookMode_Post
    );

    BuildLogPath();
    PurgeOldLogs();

    CreateTimer(
        AFK_SCAN_INTERVAL,
        Timer_CheckAFK,
        _,
        TIMER_REPEAT
    );

    // Support loading/reloading the plugin while players are already online.
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsHumanClient(client))
        {
            ResetAFKState(client);
        }
    }
}


// ============================================================================
// Map Handling
// ============================================================================

public void OnMapStart()
{
    BuildLogPath();
    PurgeOldLogs();

    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsHumanClient(client))
        {
            ResetAFKState(client);
        }
    }
}


// ============================================================================
// Client Handling
// ============================================================================

public void OnClientPostAdminCheck(int client)
{
    if (!IsHumanClient(client))
    {
        return;
    }

    ResetAFKState(client);
}


public void OnClientDisconnect(int client)
{
    ClearAFKState(client);
}


// ============================================================================
// Player Events
// ============================================================================

public void Event_PlayerSpawn(
    Event event,
    const char[] name,
    bool dontBroadcast
)
{
    int client = GetClientOfUserId(
        event.GetInt("userid")
    );

    if (!IsHumanClient(client))
    {
        return;
    }

    MarkPlayerActive(client);
}


public void Event_PlayerTeam(
    Event event,
    const char[] name,
    bool dontBroadcast
)
{
    int client = GetClientOfUserId(
        event.GetInt("userid")
    );

    if (!IsHumanClient(client))
    {
        return;
    }

    // Joining/changing a team is intentional player activity.
    MarkPlayerActive(client);
}


// ============================================================================
// Chat Activity
// ============================================================================

public Action OnClientSayCommand(
    int client,
    const char[] command,
    const char[] args
)
{
    if (IsHumanClient(client))
    {
        MarkPlayerActive(client);
    }

    return Plugin_Continue;
}


// ============================================================================
// Player Input Detection
// ============================================================================

public Action OnPlayerRunCmd(
    int client,
    int &buttons,
    int &impulse,
    float vel[3],
    float angles[3],
    int &weapon,
    int &subtype,
    int &cmdnum,
    int &tickcount,
    int &seed,
    int mouse[2]
)
{
    if (!IsHumanClient(client) || cmdnum <= 0)
    {
        return Plugin_Continue;
    }

    bool active = false;


    // ------------------------------------------------------------------------
    // Mouse movement
    // ------------------------------------------------------------------------

    if (mouse[0] != 0 || mouse[1] != 0)
    {
        active = true;
    }


    // ------------------------------------------------------------------------
    // Button state
    //
    // Detects attack, jump, crouch, reload, use, etc.
    // ------------------------------------------------------------------------

    if (buttons != g_LastButtons[client])
    {
        active = true;
    }


    // ------------------------------------------------------------------------
    // Movement input
    //
    // Important:
    // Holding W/A/S/D continuously must count as activity even though
    // the button state itself may no longer change.
    // ------------------------------------------------------------------------

    if (FloatAbs(vel[0]) > 0.01 ||
        FloatAbs(vel[1]) > 0.01 ||
        FloatAbs(vel[2]) > 0.01)
    {
        active = true;
    }


    // ------------------------------------------------------------------------
    // View-angle movement
    // ------------------------------------------------------------------------

    if (AngleDifference(
            angles[0],
            g_LastAngles[client][0]
        ) > 0.01 ||
        AngleDifference(
            angles[1],
            g_LastAngles[client][1]
        ) > 0.01 ||
        AngleDifference(
            angles[2],
            g_LastAngles[client][2]
        ) > 0.01)
    {
        active = true;
    }


    // Store current input state.
    g_LastButtons[client] = buttons;

    g_LastAngles[client][0] = angles[0];
    g_LastAngles[client][1] = angles[1];
    g_LastAngles[client][2] = angles[2];


    if (active)
    {
        MarkPlayerActive(client);
    }

    return Plugin_Continue;
}


// ============================================================================
// AFK Scanner
// ============================================================================

public Action Timer_CheckAFK(
    Handle timer,
    any data
)
{
    if (!g_CvarEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    float now = GetGameTime();

    // Spectator kicks are capacity protection, not routine cleanup.  Select
    // only one candidate per scan: the non-admin spectator who has been AFK
    // the longest.  GetClientCount(false) includes connected players in all
    // teams, including Spectator, which matches actual slot occupancy.
    bool serverFull = (
        GetClientCount(false) >= MaxClients
    );

    int oldestAFKSpectator = 0;
    float oldestActivity = 0.0;

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsHumanClient(client))
        {
            continue;
        }

        int team = GetClientTeam(client);


        // ====================================================================
        // Playing Teams
        // ====================================================================

        if (team == TEAM_SECURITY ||
            team == TEAM_INSURGENT)
        {
            // ----------------------------------------------------------------
            // Dead players are not considered AFK.
            //
            // In Insurgency, a dead player may legitimately be waiting for
            // a reinforcement wave and must not be punished for that.
            // ----------------------------------------------------------------

            if (!IsPlayerAlive(client))
            {
                MarkPlayerActiveAt(
                    client,
                    now
                );

                continue;
            }


            float specTime = g_CvarSpecTime.FloatValue;

            if (specTime <= 0.0)
            {
                continue;
            }

            float idle = now - g_LastActivity[client];
            float remaining = specTime - idle;


            if (remaining <= 0.0)
            {
                MovePlayerToSpectator(
                    client,
                    idle
                );

                continue;
            }


            HandleAFKWarnings(
                client,
                remaining,
                false
            );

            continue;
        }


        // ====================================================================
        // Spectators / Unassigned Players
        // ====================================================================

        // Any SourceMod administrator is completely immune from AFK kicks.
        //
        // Admins can still be moved to Spectator when AFK on a playing team.
        if (IsSourceModAdmin(client))
        {
            continue;
        }


        float kickTime = g_CvarKickTime.FloatValue;

        if (kickTime <= 0.0)
        {
            continue;
        }


        if (!serverFull)
        {
            // No kick is pending while capacity is available.  Reset these so
            // a fresh warning can be issued if the server later becomes full.
            g_WarningShown[client] = false;
            g_FinalWarningShown[client] = false;
            continue;
        }

        if (oldestAFKSpectator == 0
            || g_LastActivity[client] < oldestActivity)
        {
            oldestAFKSpectator = client;
            oldestActivity = g_LastActivity[client];
        }
    }

    // FIFO: when full, only the longest-idle eligible spectator is kicked.
    // Once that player leaves, occupancy drops below MaxClients and no second
    // spectator is removed unless the server fills again.
    if (serverFull && oldestAFKSpectator != 0)
    {
        float idle = now - g_LastActivity[oldestAFKSpectator];
        float remaining = g_CvarKickTime.FloatValue - idle;

        if (remaining <= 0.0)
        {
            KickPlayerForAFK(
                oldestAFKSpectator,
                idle
            );
        }
        else
        {
            HandleAFKWarnings(
                oldestAFKSpectator,
                remaining,
                true
            );
        }
    }

    return Plugin_Continue;
}


// ============================================================================
// Warning Handling
// ============================================================================

void HandleAFKWarnings(
    int client,
    float remaining,
    bool willKick
)
{
    float warningTime =
        g_CvarWarningTime.FloatValue;

    float finalWarningTime =
        g_CvarFinalWarningTime.FloatValue;


    // ------------------------------------------------------------------------
    // Final warning
    // ------------------------------------------------------------------------

    if (finalWarningTime > 0.0 &&
        remaining <= finalWarningTime &&
        !g_FinalWarningShown[client])
    {
        int seconds = RoundToCeil(remaining);

        if (seconds < 1)
        {
            seconds = 1;
        }

        if (willKick)
        {
            PrintToChat(
                client,
                "[AFK] Final warning: move within %d seconds or you will be kicked.",
                seconds
            );
        }
        else
        {
            PrintToChat(
                client,
                "[AFK] Final warning: move within %d seconds or you will be moved to Spectator.",
                seconds
            );
        }

        g_FinalWarningShown[client] = true;

        return;
    }


    // ------------------------------------------------------------------------
    // Initial warning
    // ------------------------------------------------------------------------

    if (warningTime > 0.0 &&
        remaining <= warningTime &&
        !g_WarningShown[client])
    {
        int seconds = RoundToCeil(remaining);

        if (seconds < 1)
        {
            seconds = 1;
        }

        if (willKick)
        {
            PrintToChat(
                client,
                "[AFK] You appear inactive. Move within %d seconds or you will be kicked.",
                seconds
            );
        }
        else
        {
            PrintToChat(
                client,
                "[AFK] You appear inactive. Move within %d seconds or you will be moved to Spectator.",
                seconds
            );
        }

        g_WarningShown[client] = true;
    }
}


// ============================================================================
// Move To Spectator
// ============================================================================

void MovePlayerToSpectator(
    int client,
    float idle
)
{
    if (!IsHumanClient(client))
    {
        return;
    }

    char name[MAX_NAME_LENGTH];

    GetClientName(
        client,
        name,
        sizeof(name)
    );


    char auth[64];

    if (!GetClientAuthId(
        client,
        AuthId_Steam2,
        auth,
        sizeof(auth)
    ))
    {
        strcopy(
            auth,
            sizeof(auth),
            "UNKNOWN"
        );
    }


    ChangeClientTeam(
        client,
        TEAM_SPECTATOR
    );


    // Very important:
    //
    // The kick timer starts fresh when the player reaches Spectator.
    //
    // Default:
    //
    // 120 seconds team AFK
    //       +
    // 240 seconds spectator AFK
    //       =
    // ~6 minutes total inactivity before kick.
    ResetAFKState(client);


    if (g_CvarAnnounceActions.BoolValue)
    {
        PrintToChatAll(
            "[AFK] %s was moved to Spectator after %.0f seconds of inactivity.",
            name,
            idle
        );
    }
    else
    {
        PrintToChat(
            client,
            "[AFK] You were moved to Spectator after %.0f seconds of inactivity.",
            idle
        );
    }


    LogAFK(
        "MOVE: \"%s\" %s idle=%.1fs",
        name,
        auth,
        idle
    );
}


// ============================================================================
// Kick For AFK
// ============================================================================

void KickPlayerForAFK(
    int client,
    float idle
)
{
    if (!IsHumanClient(client))
    {
        return;
    }


    // Safety check:
    //
    // An administrator must NEVER be AFK-kicked.
    if (IsSourceModAdmin(client))
    {
        return;
    }


    char name[MAX_NAME_LENGTH];

    GetClientName(
        client,
        name,
        sizeof(name)
    );


    char auth[64];

    if (!GetClientAuthId(
        client,
        AuthId_Steam2,
        auth,
        sizeof(auth)
    ))
    {
        strcopy(
            auth,
            sizeof(auth),
            "UNKNOWN"
        );
    }


    if (g_CvarAnnounceActions.BoolValue)
    {
        PrintToChatAll(
            "[AFK] %s was kicked for prolonged inactivity because the server was full.",
            name
        );
    }


    LogAFK(
        "KICK: \"%s\" %s spectator_idle=%.1fs",
        name,
        auth,
        idle
    );


    // Kick only.
    //
    // There is intentionally NO ban logic in this plugin.
    KickClient(
        client,
        "[AFK] You were kicked for prolonged inactivity because the server was full."
    );
}


// ============================================================================
// SourceMod Admin Detection
// ============================================================================

bool IsSourceModAdmin(int client)
{
    if (!IsHumanClient(client))
    {
        return false;
    }

    // Any recognized SourceMod administrator receives kick immunity.
    //
    // We intentionally do NOT check specific admin flags.
    return (
        GetUserAdmin(client) != INVALID_ADMIN_ID
    );
}


// ============================================================================
// Human Client Detection
// ============================================================================

bool IsHumanClient(int client)
{
    if (client < 1 ||
        client > MaxClients)
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


// ============================================================================
// Activity Handling
// ============================================================================

void MarkPlayerActive(int client)
{
    MarkPlayerActiveAt(
        client,
        GetGameTime()
    );
}


void MarkPlayerActiveAt(
    int client,
    float now
)
{
    if (client < 1 ||
        client > MaxClients)
    {
        return;
    }

    g_LastActivity[client] = now;

    // Player became active again.
    // Future warnings may be shown if they later go AFK again.
    g_WarningShown[client] = false;
    g_FinalWarningShown[client] = false;
}


// ============================================================================
// Reset Player AFK State
// ============================================================================

void ResetAFKState(int client)
{
    if (client < 1 ||
        client > MaxClients)
    {
        return;
    }

    g_LastActivity[client] =
        GetGameTime();

    g_LastButtons[client] = 0;

    g_LastAngles[client][0] = 0.0;
    g_LastAngles[client][1] = 0.0;
    g_LastAngles[client][2] = 0.0;

    g_WarningShown[client] = false;
    g_FinalWarningShown[client] = false;
}


void ClearAFKState(int client)
{
    if (client < 1 ||
        client > MaxClients)
    {
        return;
    }

    g_LastActivity[client] = 0.0;

    g_LastButtons[client] = 0;

    g_LastAngles[client][0] = 0.0;
    g_LastAngles[client][1] = 0.0;
    g_LastAngles[client][2] = 0.0;

    g_WarningShown[client] = false;
    g_FinalWarningShown[client] = false;
}


// ============================================================================
// Angle Helper
// ============================================================================

float AngleDifference(
    float angle1,
    float angle2
)
{
    float difference =
        FloatAbs(angle1 - angle2);

    // Account for angle wrap-around:
    //
    // 359 degrees -> 0 degrees
    //
    // is a 1-degree movement, not 359 degrees.
    if (difference > 180.0)
    {
        difference =
            360.0 - difference;
    }

    return FloatAbs(difference);
}


// ============================================================================
// Logging
// ============================================================================

void BuildLogPath()
{
    FormatTime(
        g_LogDate,
        sizeof(g_LogDate),
        "%Y-%m-%d",
        GetTime()
    );


    BuildPath(
        Path_SM,
        g_LogDirectory,
        sizeof(g_LogDirectory),
        "logs/ins_afkmanager"
    );


    if (!DirExists(g_LogDirectory))
    {
        // Decimal 493 = Unix 0755.
        CreateDirectory(
            g_LogDirectory,
            493
        );
    }


    BuildPath(
        Path_SM,
        g_LogFile,
        sizeof(g_LogFile),
        "logs/ins_afkmanager/%s.log",
        g_LogDate
    );
}


// ============================================================================
// AFK Logging
// ============================================================================

void LogAFK(
    const char[] format,
    any ...
)
{
    char today[16];

    FormatTime(
        today,
        sizeof(today),
        "%Y-%m-%d",
        GetTime()
    );


    // Date changed while server remained online.
    if (!StrEqual(
        today,
        g_LogDate,
        false
    ))
    {
        BuildLogPath();
        PurgeOldLogs();
    }


    char buffer[512];

    VFormat(
        buffer,
        sizeof(buffer),
        format,
        2
    );


    LogToFileEx(
        g_LogFile,
        "%s",
        buffer
    );
}


// ============================================================================
// Delete Old AFK Logs
// ============================================================================

void PurgeOldLogs()
{
    int days =
        g_CvarLogDays.IntValue;


    // 0 = keep forever.
    if (days <= 0)
    {
        return;
    }


    if (!DirExists(g_LogDirectory))
    {
        return;
    }


    Handle directory =
        OpenDirectory(g_LogDirectory);


    if (directory == null)
    {
        return;
    }


    int cutoff =
        GetTime() - (days * 86400);


    char filename[PLATFORM_MAX_PATH];
    FileType type;


    while (ReadDirEntry(
        directory,
        filename,
        sizeof(filename),
        type
    ))
    {
        if (type != FileType_File)
        {
            continue;
        }


        int length =
            strlen(filename);


        // Must end with ".log".
        if (length < 4 ||
            StrContains(
                filename,
                ".log",
                false
            ) != length - 4)
        {
            continue;
        }


        char fullPath[PLATFORM_MAX_PATH];

        BuildPath(
            Path_SM,
            fullPath,
            sizeof(fullPath),
            "logs/ins_afkmanager/%s",
            filename
        );


        if (GetFileTime(
            fullPath,
            FileTime_LastChange
        ) < cutoff)
        {
            DeleteFile(fullPath);
        }
    }


    CloseHandle(directory);
}
