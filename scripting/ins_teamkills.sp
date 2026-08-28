// ============================================================================
// [INS] ReflectTK
//
// Protects teammates and applies scaled, progressive reflected damage.
//
// Victim:
//   - Takes no friendly-fire damage.
//
// Attacker:
//   - Takes reduced reflected damage.
//   - Cannot be killed by an isolated accident.
//   - Can be killed after repeated friendly-fire incidents in one round.
//   - Sees remaining HP in a dark panel:
//
//       HP: 63
//       Friendly fire reflected
//
// Designed for Insurgency (2014).
// ============================================================================

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>

#define PLUGIN_VERSION "4.0"

ConVar g_CvarEnabled;
ConVar g_CvarFriendlyFire;
ConVar g_CvarDirectScale;
ConVar g_CvarExplosiveScale;
ConVar g_CvarIncidentWindow;
ConVar g_CvarIncidentCap;
ConVar g_CvarSafetyHealth;
ConVar g_CvarLethalThreshold;

float g_IncidentStarted[MAXPLAYERS + 1];
int g_IncidentReflected[MAXPLAYERS + 1];
int g_RoundReflected[MAXPLAYERS + 1];

bool g_LateLoad = false;


// ============================================================================
// Plugin Information
// ============================================================================

public Plugin myinfo =
{
    name = "[INS] ReflectTK",
    author = "Nayan",
    description = "Protects teammates with forgiving progressive damage reflection.",
    version = PLUGIN_VERSION,
    url = ""
};


// ============================================================================
// Late Load Support
// ============================================================================

public APLRes AskPluginLoad2(
    Handle myself,
    bool late,
    char[] error,
    int err_max
)
{
    g_LateLoad = late;
    return APLRes_Success;
}


// ============================================================================
// Plugin Start
// ============================================================================

public void OnPluginStart()
{
    CreateConVar(
        "sm_reflecttk_version",
        PLUGIN_VERSION,
        "ReflectTK plugin version.",
        FCVAR_NOTIFY | FCVAR_DONTRECORD
    );

    g_CvarEnabled = CreateConVar(
        "sm_reflecttk_enabled",
        "1",
        "Enable or disable ReflectTK. 1 = Enabled, 0 = Disabled.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    g_CvarDirectScale = CreateConVar(
        "sm_reflecttk_direct_scale",
        "0.50",
        "Fraction of bullet and melee friendly-fire damage reflected.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    g_CvarExplosiveScale = CreateConVar(
        "sm_reflecttk_explosive_scale",
        "0.20",
        "Fraction of explosive and fire friendly-fire damage reflected.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    g_CvarIncidentWindow = CreateConVar(
        "sm_reflecttk_incident_window",
        "1.25",
        "Seconds grouped into one friendly-fire incident.",
        FCVAR_NOTIFY,
        true,
        0.1,
        true,
        5.0
    );

    g_CvarIncidentCap = CreateConVar(
        "sm_reflecttk_incident_cap",
        "35",
        "Maximum reflected damage per incident. 0 disables the cap.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        500.0
    );

    g_CvarSafetyHealth = CreateConVar(
        "sm_reflecttk_safety_health",
        "10",
        "Minimum attacker HP before the repeat-offender threshold is reached.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        100.0
    );

    g_CvarLethalThreshold = CreateConVar(
        "sm_reflecttk_lethal_threshold",
        "100",
        "Round reflected damage before reflection may kill. 0 keeps the safety floor permanently.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1000.0
    );

    g_CvarFriendlyFire = FindConVar("mp_friendlyfire");

    HookEvent(
        "round_start",
        Event_RoundStart,
        EventHookMode_PostNoCopy
    );

    AutoExecConfig(true, "ins_teamkill");

    // If the plugin was loaded while players are already connected,
    // hook those players immediately.
    if (g_LateLoad)
    {
        for (int client = 1; client <= MaxClients; client++)
        {
            if (IsClientInGame(client))
            {
                SDKHook(
                    client,
                    SDKHook_OnTakeDamage,
                    Hook_OnTakeDamage
                );
            }
        }
    }
}


// ============================================================================
// Client Join
// ============================================================================

public void OnClientPutInServer(int client)
{
    ResetClientReflection(client);

    SDKHook(
        client,
        SDKHook_OnTakeDamage,
        Hook_OnTakeDamage
    );
}


public void OnClientDisconnect(int client)
{
    ResetClientReflection(client);
}


public void Event_RoundStart(
    Event event,
    const char[] name,
    bool dontBroadcast
)
{
    for (int client = 1; client <= MaxClients; client++)
    {
        ResetClientReflection(client);
    }
}


void ResetClientReflection(int client)
{
    g_IncidentStarted[client] = 0.0;
    g_IncidentReflected[client] = 0;
    g_RoundReflected[client] = 0;
}


// ============================================================================
// Reflect Notification Panel
// ============================================================================

void ShowReflectPanel(int client, int health)
{
    if (client < 1 ||
        client > MaxClients ||
        !IsClientInGame(client))
    {
        return;
    }

    Panel panel = new Panel();

    char message[128];

    Format(
        message,
        sizeof(message),
        "HP: %d\nFriendly fire reflected",
        health
    );

    panel.DrawText(message);

    panel.Send(
        client,
        NullMenuHandler,
        2
    );

    delete panel;
}


// ============================================================================
// Panel Handler
// ============================================================================

public int NullMenuHandler(
    Menu menu,
    MenuAction action,
    int param1,
    int param2
)
{
    return 0;
}


// ============================================================================
// Damage Handler
// ============================================================================

public Action Hook_OnTakeDamage(
    int victim,
    int &attacker,
    int &inflictor,
    float &damage,
    int &damagetype
)
{
    // Plugin disabled.
    if (!g_CvarEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    // Friendly fire must exist and be enabled.
    if (g_CvarFriendlyFire == null ||
        !g_CvarFriendlyFire.BoolValue)
    {
        return Plugin_Continue;
    }

    // Victim must be a valid player.
    if (victim < 1 || victim > MaxClients)
    {
        return Plugin_Continue;
    }

    // Attacker must be a valid player.
    if (attacker < 1 || attacker > MaxClients)
    {
        return Plugin_Continue;
    }

    // Both must be in game.
    if (!IsClientInGame(victim) ||
        !IsClientInGame(attacker))
    {
        return Plugin_Continue;
    }

    // Ignore self damage.
    if (attacker == victim)
    {
        return Plugin_Continue;
    }

    // Only handle damage between teammates.
    if (GetClientTeam(attacker) != GetClientTeam(victim))
    {
        return Plugin_Continue;
    }

    // Save original friendly-fire damage.
    float friendlyDamage = damage;

    if (friendlyDamage < 0.0)
    {
        friendlyDamage *= -1.0;
    }

    // Ignore zero / invalid damage callbacks.
    if (friendlyDamage <= 0.0)
    {
        return Plugin_Continue;
    }

    // Completely protect the teammate.
    damage = 0.0;

    if (!IsPlayerAlive(attacker))
    {
        return Plugin_Changed;
    }

    bool explosive =
        (damagetype & DMG_BLAST) != 0
        || (damagetype & DMG_BURN) != 0
        || (damagetype & DMG_SLOWBURN) != 0;

    float scale = explosive
        ? g_CvarExplosiveScale.FloatValue
        : g_CvarDirectScale.FloatValue;

    int reflectedAmount = RoundToCeil(
        friendlyDamage * scale
    );

    if (reflectedAmount <= 0)
    {
        return Plugin_Changed;
    }

    float now = GetGameTime();

    if (
        g_IncidentStarted[attacker] <= 0.0
        || now - g_IncidentStarted[attacker]
            >= g_CvarIncidentWindow.FloatValue
    )
    {
        g_IncidentStarted[attacker] = now;
        g_IncidentReflected[attacker] = 0;
    }

    int incidentCap = g_CvarIncidentCap.IntValue;

    if (incidentCap > 0)
    {
        int remaining =
            incidentCap - g_IncidentReflected[attacker];

        if (remaining <= 0)
        {
            return Plugin_Changed;
        }

        if (reflectedAmount > remaining)
        {
            reflectedAmount = remaining;
        }
    }

    int lethalThreshold =
        g_CvarLethalThreshold.IntValue;

    bool repeatOffender =
        lethalThreshold > 0
        && g_RoundReflected[attacker] >= lethalThreshold;

    g_IncidentReflected[attacker] += reflectedAmount;
    g_RoundReflected[attacker] += reflectedAmount;

    int currentHealth = GetClientHealth(attacker);
    int newHealth = currentHealth - reflectedAmount;

    if (!repeatOffender)
    {
        int safetyHealth = g_CvarSafetyHealth.IntValue;

        if (newHealth < safetyHealth)
        {
            newHealth = safetyHealth;
        }
    }

    if (newHealth <= 0)
    {
        ShowReflectPanel(attacker, 0);
        ForcePlayerSuicide(attacker);
    }
    else if (newHealth < currentHealth)
    {
        SetEntityHealth(attacker, newHealth);
        ShowReflectPanel(attacker, newHealth);
    }

    // Tell SDKHooks that victim damage was changed.
    return Plugin_Changed;
}
