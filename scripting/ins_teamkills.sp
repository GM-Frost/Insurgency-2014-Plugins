// ============================================================================
// [INS] ReflectTK
//
// Reflects friendly-fire damage back to the attacker.
//
// Victim:
//   - Takes no friendly-fire damage.
//
// Attacker:
//   - Takes the same amount of damage.
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

#define PLUGIN_VERSION "3.2"

ConVar g_CvarEnabled;
ConVar g_CvarFriendlyFire;

bool g_LateLoad = false;


// ============================================================================
// Plugin Information
// ============================================================================

public Plugin myinfo =
{
    name = "[INS] ReflectTK",
    author = "Nayan",
    description = "Reflects friendly-fire damage back to the attacker.",
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

    g_CvarFriendlyFire = FindConVar("mp_friendlyfire");

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
    SDKHook(
        client,
        SDKHook_OnTakeDamage,
        Hook_OnTakeDamage
    );
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
    float reflectedDamage = damage;

    if (reflectedDamage < 0.0)
    {
        reflectedDamage *= -1.0;
    }

    int reflectedAmount = RoundFloat(reflectedDamage);

    // Ignore zero / invalid damage callbacks.
    if (reflectedAmount <= 0)
    {
        return Plugin_Continue;
    }

    // Completely protect the teammate.
    damage = 0.0;

    // Reflect damage only if attacker is alive.
    if (IsPlayerAlive(attacker))
    {
        int currentHealth = GetClientHealth(attacker);
        int newHealth = currentHealth - reflectedAmount;

        if (newHealth <= 0)
        {
            ShowReflectPanel(attacker, 0);

            ForcePlayerSuicide(attacker);
        }
        else
        {
            SetEntityHealth(attacker, newHealth);

            ShowReflectPanel(attacker, newHealth);
        }
    }

    // Tell SDKHooks that victim damage was changed.
    return Plugin_Changed;
}
