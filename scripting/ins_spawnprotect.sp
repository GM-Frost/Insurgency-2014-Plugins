#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PLUGIN_VERSION "1.0.0"

ConVar g_cvEnabled;
ConVar g_cvProtectionTime;
ConVar g_cvCancelOnAttack;
ConVar g_cvAnnounce;

bool g_bProtected[MAXPLAYERS + 1];
Handle g_hProtectionTimer[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name = "INS Spawn Protection",
    author = "Nayan",
    description = "Spawn protection for Insurgency 2014",
    version = PLUGIN_VERSION,
    url = ""
};

public void OnPluginStart()
{
    g_cvEnabled = CreateConVar(
        "sm_ins_spawnprotect_enable",
        "1",
        "Enable or disable spawn protection.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    g_cvProtectionTime = CreateConVar(
        "sm_ins_spawnprotect_time",
        "15.0",
        "Number of seconds a player is protected after spawning.",
        FCVAR_NOTIFY,
        true,
        0.1,
        true,
        30.0
    );

    g_cvCancelOnAttack = CreateConVar(
        "sm_ins_spawnprotect_cancel_attack",
        "1",
        "Remove spawn protection when the player attacks.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    g_cvAnnounce = CreateConVar(
        "sm_ins_spawnprotect_announce",
        "1",
        "Show spawn protection messages to players.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    CreateConVar(
        "sm_ins_spawnprotect_version",
        PLUGIN_VERSION,
        "INS Spawn Protection version.",
        FCVAR_NOTIFY | FCVAR_DONTRECORD
    );

    HookEvent(
        "player_spawn",
        Event_PlayerSpawn,
        EventHookMode_Post
    );

    HookEvent(
        "player_death",
        Event_PlayerDeath,
        EventHookMode_Post
    );

    AutoExecConfig(
        true,
        "ins_spawnprotect"
    );

    /*
     * Hook players that may already be connected
     * when the plugin is loaded manually.
     */
    for (int client = 1; client <= MaxClients; client++)
    {
        if (IsClientInGame(client))
        {
            SDKHook(
                client,
                SDKHook_OnTakeDamage,
                OnTakeDamage
            );
        }
    }
}

public void OnClientPutInServer(int client)
{
    ResetProtection(client);

    SDKHook(
        client,
        SDKHook_OnTakeDamage,
        OnTakeDamage
    );
}

public void OnClientDisconnect(int client)
{
    ResetProtection(client);
}

public void OnMapEnd()
{
    for (int client = 1; client <= MaxClients; client++)
    {
        ResetProtection(client);
    }
}

public void Event_PlayerSpawn(
    Event event,
    const char[] name,
    bool dontBroadcast
)
{
    if (!g_cvEnabled.BoolValue)
    {
        return;
    }

    int client = GetClientOfUserId(
        event.GetInt("userid")
    );

    if (!IsValidHuman(client))
    {
        return;
    }

    if (!IsPlayerAlive(client))
    {
        return;
    }

    StartProtection(client);
}

public void Event_PlayerDeath(
    Event event,
    const char[] name,
    bool dontBroadcast
)
{
    int client = GetClientOfUserId(
        event.GetInt("userid")
    );

    if (client > 0 && client <= MaxClients)
    {
        ResetProtection(client);
    }
}

void StartProtection(int client)
{
    ResetProtection(client);

    float duration = g_cvProtectionTime.FloatValue;

    g_bProtected[client] = true;

    g_hProtectionTimer[client] = CreateTimer(
        duration,
        Timer_EndProtection,
        GetClientUserId(client),
        TIMER_FLAG_NO_MAPCHANGE
    );

    if (g_cvAnnounce.BoolValue)
    {
        PrintToChat(
            client,
            "\x01[\x04Spawn Protection\x01] Protected for %.0f seconds.",
            duration
        );
    }
}

public Action Timer_EndProtection(
    Handle timer,
    any userid
)
{
    int client = GetClientOfUserId(userid);

    if (client <= 0 || client > MaxClients)
    {
        return Plugin_Stop;
    }

    /*
     * SourceMod is already destroying this timer.
     * Clear our stored handle first.
     */
    g_hProtectionTimer[client] = null;

    EndProtection(
        client,
        true
    );

    return Plugin_Stop;
}

void EndProtection(
    int client,
    bool announce
)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    if (!g_bProtected[client])
    {
        return;
    }

    g_bProtected[client] = false;

    if (g_hProtectionTimer[client] != null)
    {
        delete g_hProtectionTimer[client];
        g_hProtectionTimer[client] = null;
    }

    if (
        announce
        && g_cvAnnounce.BoolValue
        && IsValidHuman(client)
    )
    {
        PrintToChat(
            client,
            "\x01[\x04Spawn Protection\x01] Protection disabled."
        );
    }
}

void ResetProtection(int client)
{
    if (client <= 0 || client > MaxClients)
    {
        return;
    }

    g_bProtected[client] = false;

    if (g_hProtectionTimer[client] != null)
    {
        delete g_hProtectionTimer[client];
        g_hProtectionTimer[client] = null;
    }
}

public Action OnTakeDamage(
    int victim,
    int &attacker,
    int &inflictor,
    float &damage,
    int &damagetype
)
{
    if (
        victim <= 0
        || victim > MaxClients
        || !g_bProtected[victim]
    )
    {
        return Plugin_Continue;
    }

    /*
     * Protected players receive zero damage.
     *
     * This covers bullets, explosions, RPG damage,
     * and other damage routed through OnTakeDamage.
     */
    damage = 0.0;

    return Plugin_Changed;
}

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
    if (!g_cvCancelOnAttack.BoolValue)
    {
        return Plugin_Continue;
    }

    if (!IsValidHuman(client))
    {
        return Plugin_Continue;
    }

    if (!IsPlayerAlive(client))
    {
        return Plugin_Continue;
    }

    if (!g_bProtected[client])
    {
        return Plugin_Continue;
    }

    /*
     * IMPORTANT:
     *
     * Only PRIMARY ATTACK removes protection.
     *
     * We intentionally do NOT check IN_ATTACK2
     * because secondary attack may be used for
     * aiming / ADS in Insurgency.
     *
     * Player may:
     *
     * - move
     * - sprint
     * - crouch
     * - jump
     * - aim / ADS
     * - switch weapons
     *
     * without losing spawn protection.
     *
     * Pressing primary attack immediately removes it.
     */
    if (buttons & IN_ATTACK)
    {
        EndProtection(
            client,
            true
        );
    }

    return Plugin_Continue;
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
