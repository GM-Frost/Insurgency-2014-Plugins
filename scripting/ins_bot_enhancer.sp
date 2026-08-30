// ============================================================================
// [INS] LOL Bot Enhancer
//
// Aggressive tuning layer for Insurgency 2014 native PvP NextBots.
// The seed manager owns bot population; this plugin owns bot behaviour only.
// ============================================================================

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define PLUGIN_VERSION "1.0.1"
#define VALUE_SIZE 32

static const char g_NativeNames[][] =
{
    // Difficulty and damage.
    "ins_bot_difficulty",
    "ins_bot_change_difficulty",
    "bot_damage",

    // Fast first contact without instant robotic snapshots.
    "bot_attackdelay_base",
    "bot_attackdelay_frac_hipfirerange",
    "bot_attackdelay_frac_desiredrange",
    "bot_attackdelay_frac_maxrange",
    "bot_attackdelay_frac_outofrange",
    "bot_attackdelay_frac_outsidefov",

    // Commit to a threat and fire meaningful bursts.
    "bot_attack_retarget_mintime",
    "bot_attack_retarget_maxtime",
    "bot_attack_burst_mintime",
    "bot_attack_burst_maxtime",
    "ins_bot_attack_reload_ratio",
    "ins_bot_attack_pistol_fire_rate",

    // Strong but imperfect weapon control.
    "bot_recoil_multiplier",
    "bot_targeting_noise_x_base",
    "bot_targeting_noise_y_base",
    "bot_targeting_noise_z_base",
    "bot_targeting_noise_x_frac_hipfirerange",
    "bot_targeting_noise_y_frac_hipfirerange",
    "bot_targeting_noise_z_frac_hipfirerange",
    "bot_targeting_noise_x_frac_desiredrange",
    "bot_targeting_noise_y_frac_desiredrange",
    "bot_targeting_noise_z_frac_desiredrange",
    "bot_targeting_noise_x_frac_maxrange",
    "bot_targeting_noise_y_frac_maxrange",
    "bot_targeting_noise_z_frac_maxrange",

    // Do not encourage bots to back away to an inflated preferred range.
    "bot_range_frac_hipfirerange",
    "bot_range_frac_desiredrange",
    "bot_range_frac_maxrange",

    // Combat momentum.
    "ins_bot_arousal_combat_max",
    "ins_bot_arousal_firing_max",
    "ins_bot_arousal_suppression_max",
    "ins_bot_arousal_frac_attackdelay_min",
    "ins_bot_arousal_frac_attackdelay_med",
    "ins_bot_arousal_frac_attackdelay_max",
    "ins_bot_arousal_frac_recognizetime_min",
    "ins_bot_arousal_frac_recognizetime_med",
    "ins_bot_arousal_frac_recognizetime_max",
    "ins_bot_arousal_frac_angularvelocity_min",
    "ins_bot_arousal_frac_angularvelocity_med",
    "ins_bot_arousal_frac_angularvelocity_max",

    // Grenades and RPGs remain dangerous without point-blank nonsense.
    "ins_bot_max_grenade_range",
    "ins_bot_rpg_grace_time",
    "ins_bot_rpg_minimum_firing_distance",
    "ins_bot_rpg_minimum_player_cluster",
    "ins_bot_rpg_player_cluster_radius",

    // Native NextBot locomotion/pathing controls. Several are FCVAR_CHEAT, so
    // the plugin temporarily removes that flag only while applying the value.
    "bot_loco_path_max_retreat_length",
    "bot_loco_path_minlookahead",
    "bot_loco_hurry_sprinthold_min",
    "bot_loco_hurry_sprinthold_max",
    "bot_loco_pronehold_min",
    "bot_loco_pronehold_max",
    "bot_loco_slowdown_walkhold_max",
    "ins_bot_path_compute_throttle_combat",
    "ins_bot_path_compute_throttle_ooc",
    "ins_bot_path_distance_max",
    "ins_bot_path_simplify_range",
    "ins_bot_pathfollower_aimahead",
    "ins_bot_ignore_human_triggers",
    "ins_bot_suppress_visible_requirement",
    "ins_bot_suppressing_fire_duration"
};

static const char g_BrutalValues[][] =
{
    "3", "1", "1.10",
    "0.50", "0.30", "0.50", "0.75", "0.95", "1.05",
    "0.35", "0.85", "0.35", "1.20", "0.15", "4.0",
    "0.48", "38", "38", "48",
    "0.80", "0.80", "0.80",
    "1.00", "1.00", "1.00",
    "1.25", "1.25", "1.25",
    "1.00", "0.95", "1.10",
    "9", "9", "7",
    "0.85", "0.70", "0.55",
    "0.90", "0.75", "0.60",
    "0.90", "1.05", "1.20",
    "1100", "8", "512", "2", "460",
    "160", "180", "0.60", "1.50", "0.50", "2.00", "0.25",
    "0.15", "0.75", "20000", "700", "300", "0", "0.35", "1.20"
};

ConVar g_CvarEnabled;
ConVar g_CvarEnforceInterval;
ConVar g_CvarVerbose;

ConVar g_NativeCvars[sizeof(g_NativeNames)];
char g_OriginalValues[sizeof(g_NativeNames)][VALUE_SIZE];
int g_OriginalFlags[sizeof(g_NativeNames)];

bool g_ConfigsReady = false;
bool g_OriginalsCaptured = false;
bool g_MissingReported[sizeof(g_NativeNames)];
Handle g_EnforceTimer = null;

public Plugin myinfo =
{
    name = "[INS] LOL Bot Enhancer",
    author = "Nayan",
    description = "Makes native Insurgency PvP bots aggressive, mobile and responsive.",
    version = PLUGIN_VERSION,
    url = ""
};

public void OnPluginStart()
{
    CreateConVar(
        "sm_ins_bot_enhancer_version",
        PLUGIN_VERSION,
        "LOL Bot Enhancer version.",
        FCVAR_NOTIFY | FCVAR_DONTRECORD
    );

    g_CvarEnabled = CreateConVar(
        "sm_ins_bot_enhancer_enabled",
        "1",
        "Enable the aggressive native-bot behaviour profile.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    g_CvarEnforceInterval = CreateConVar(
        "sm_ins_bot_enhancer_enforce_interval",
        "15.0",
        "Seconds between checks that keep native bot CVARs on profile; 0 disables checks.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        120.0
    );

    g_CvarVerbose = CreateConVar(
        "sm_ins_bot_enhancer_verbose",
        "0",
        "Log every native bot CVAR corrected by the enhancer.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    g_CvarEnabled.AddChangeHook(OnControlCvarChanged);
    g_CvarEnforceInterval.AddChangeHook(OnControlCvarChanged);

    RegAdminCmd(
        "sm_botenhancer_status",
        Command_Status,
        ADMFLAG_CONFIG,
        "Shows and reapplies the LOL Bot Enhancer profile."
    );

    AutoExecConfig(true, "ins_bot_enhancer");
}

public void OnConfigsExecuted()
{
    g_ConfigsReady = true;
    CaptureOriginalSettings();

    if (g_CvarEnabled.BoolValue)
    {
        ApplyBrutalProfile(false);
    }

    RestartEnforcementTimer();
}

public void OnMapStart()
{
    if (!g_ConfigsReady)
    {
        return;
    }

    CreateTimer(2.0, Timer_DeferredApply, _, TIMER_FLAG_NO_MAPCHANGE);
    RestartEnforcementTimer();
}

public void OnMapEnd()
{
    g_EnforceTimer = null;
}

public void OnPluginEnd()
{
    if (g_OriginalsCaptured)
    {
        RestoreOriginalSettings();
    }
}

public void OnControlCvarChanged(
    ConVar convar,
    const char[] oldValue,
    const char[] newValue
)
{
    if (!g_ConfigsReady)
    {
        return;
    }

    if (convar == g_CvarEnabled)
    {
        if (g_CvarEnabled.BoolValue)
        {
            CaptureOriginalSettings();
            ApplyBrutalProfile(false);
        }
        else
        {
            RestoreOriginalSettings();
        }
    }

    RestartEnforcementTimer();
}

public Action Timer_DeferredApply(Handle timer)
{
    if (g_CvarEnabled.BoolValue)
    {
        ApplyBrutalProfile(false);
    }

    return Plugin_Stop;
}

public Action Timer_EnforceProfile(Handle timer)
{
    if (!g_CvarEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    ApplyBrutalProfile(true);
    return Plugin_Continue;
}

void RestartEnforcementTimer()
{
    if (g_EnforceTimer != null)
    {
        delete g_EnforceTimer;
        g_EnforceTimer = null;
    }

    float interval = g_CvarEnforceInterval.FloatValue;

    if (!g_CvarEnabled.BoolValue || interval <= 0.0)
    {
        return;
    }

    g_EnforceTimer = CreateTimer(
        interval,
        Timer_EnforceProfile,
        _,
        TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE
    );
}

void CaptureOriginalSettings()
{
    if (g_OriginalsCaptured)
    {
        return;
    }

    for (int i = 0; i < sizeof(g_NativeNames); i++)
    {
        g_NativeCvars[i] = FindConVar(g_NativeNames[i]);

        if (g_NativeCvars[i] == null)
        {
            ReportMissingCvar(i);
            continue;
        }

        g_NativeCvars[i].GetString(g_OriginalValues[i], VALUE_SIZE);
        g_OriginalFlags[i] = g_NativeCvars[i].Flags;
    }

    g_OriginalsCaptured = true;
}

void ApplyBrutalProfile(bool enforcementPass)
{
    int changed = 0;

    for (int i = 0; i < sizeof(g_NativeNames); i++)
    {
        ConVar cvar = g_NativeCvars[i];

        if (cvar == null)
        {
            cvar = FindConVar(g_NativeNames[i]);
            g_NativeCvars[i] = cvar;
        }

        if (cvar == null)
        {
            ReportMissingCvar(i);
            continue;
        }

        char current[VALUE_SIZE];
        cvar.GetString(current, sizeof(current));

        if (StrEqual(current, g_BrutalValues[i]))
        {
            continue;
        }

        SetNativeValue(cvar, g_BrutalValues[i]);
        changed++;

        if (g_CvarVerbose.BoolValue)
        {
            LogMessage(
                "[LOL Bot Enhancer] %s: %s -> %s",
                g_NativeNames[i],
                current,
                g_BrutalValues[i]
            );
        }
    }

    if (!enforcementPass || changed > 0)
    {
        LogMessage(
            "[LOL Bot Enhancer] Brutal profile active; corrected %d native bot setting(s).",
            changed
        );
    }
}

void RestoreOriginalSettings()
{
    if (!g_OriginalsCaptured)
    {
        return;
    }

    for (int i = 0; i < sizeof(g_NativeNames); i++)
    {
        ConVar cvar = g_NativeCvars[i];

        if (cvar == null)
        {
            continue;
        }

        SetNativeValue(cvar, g_OriginalValues[i]);
        cvar.Flags = g_OriginalFlags[i];
    }

    LogMessage("[LOL Bot Enhancer] Original native bot settings restored.");
}

void SetNativeValue(ConVar cvar, const char[] value)
{
    int flags = cvar.Flags;
    bool wasCheatProtected = (flags & FCVAR_CHEAT) != 0;

    if (wasCheatProtected)
    {
        cvar.Flags = flags & ~FCVAR_CHEAT;
    }

    cvar.SetString(value, true, false);

    if (wasCheatProtected)
    {
        cvar.Flags = flags;
    }
}

void ReportMissingCvar(int index)
{
    if (g_MissingReported[index])
    {
        return;
    }

    g_MissingReported[index] = true;
    LogError(
        "[LOL Bot Enhancer] Native CVAR '%s' was not found on this game build.",
        g_NativeNames[index]
    );
}

public Action Command_Status(int client, int args)
{
    if (g_CvarEnabled.BoolValue)
    {
        ApplyBrutalProfile(false);
    }

    int available = 0;

    for (int i = 0; i < sizeof(g_NativeNames); i++)
    {
        if (g_NativeCvars[i] != null)
        {
            available++;
        }
    }

    ReplyToCommand(
        client,
        "[LOL Bot Enhancer] enabled=%d native_settings=%d/%d enforce=%.1fs",
        g_CvarEnabled.BoolValue,
        available,
        sizeof(g_NativeNames),
        g_CvarEnforceInterval.FloatValue
    );

    return Plugin_Handled;
}
