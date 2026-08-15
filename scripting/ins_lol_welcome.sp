#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define PLUGIN_VERSION "3.0"

ConVar g_CvarEnabled;
ConVar g_CvarDelay;
ConVar g_CvarDisplayTime;

bool g_WelcomeShown[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name = "[INS] LOL Welcome",
    author = "Nayan",
    description = "Official Losers Online welcome and server information panel.",
    version = PLUGIN_VERSION,
    url = ""
};


// ============================================================================
// Plugin Start
// ============================================================================

public void OnPluginStart()
{
    g_CvarEnabled = CreateConVar(
        "sm_lolwelcome_enabled",
        "1",
        "Enable or disable the LOL welcome panel."
    );

    g_CvarDelay = CreateConVar(
        "sm_lolwelcome_delay",
        "3.0",
        "Delay after first spawn before showing the welcome panel."
    );

    RegConsoleCmd(
        "sm_welcome",
        Command_Welcome,
        "Display the Losers Online welcome panel."
    );

    RegConsoleCmd(
        "sm_official",
        Command_Official,
        "Display official Losers Online server information."
    );

    RegConsoleCmd(
        "sm_donate",
        Command_Donate,
        "Display server donation information."
    );

    g_CvarDisplayTime = CreateConVar(
    "sm_lolwelcome_displaytime",
    "50",
    "How long the welcome panel stays open in seconds."
    );

    HookEvent("player_spawn", Event_PlayerSpawn);

    AutoExecConfig(true, "plugin.lolwelcome");
}


// ============================================================================
// Client State
// ============================================================================

public void OnClientConnected(int client)
{
    g_WelcomeShown[client] = false;
}

public void OnClientDisconnect(int client)
{
    g_WelcomeShown[client] = false;
}


// ============================================================================
// First Spawn
// ============================================================================

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    if (!g_CvarEnabled.BoolValue)
    {
        return;
    }

    int client = GetClientOfUserId(event.GetInt("userid"));

    if (client <= 0 ||
        client > MaxClients ||
        !IsClientInGame(client) ||
        IsFakeClient(client))
    {
        return;
    }

    if (g_WelcomeShown[client])
    {
        return;
    }

    // Mark now so multiple spawn events cannot create multiple timers.
    g_WelcomeShown[client] = true;

    CreateTimer(
        g_CvarDelay.FloatValue,
        Timer_ShowWelcome,
        GetClientUserId(client),
        TIMER_FLAG_NO_MAPCHANGE
    );
}


// ============================================================================
// Welcome Timer
// ============================================================================

public Action Timer_ShowWelcome(Handle timer, int userid)
{
    int client = GetClientOfUserId(userid);

    if (client <= 0 ||
        !IsClientInGame(client) ||
        IsFakeClient(client))
    {
        return Plugin_Stop;
    }

    ShowWelcomePanel(client);

    return Plugin_Stop;
}


// ============================================================================
// Commands
// ============================================================================

public Action Command_Welcome(int client, int args)
{
    if (!IsValidHumanClient(client))
    {
        return Plugin_Handled;
    }

    ShowWelcomePanel(client);

    return Plugin_Handled;
}


public Action Command_Official(int client, int args)
{
    if (!IsValidHumanClient(client))
    {
        return Plugin_Handled;
    }

    PrintToChat(
        client,
        "\x04[LOL]\x01 OFFICIAL SERVER: \x03199.119.136.77:27015"
    );

    PrintToChat(
        client,
        "\x04[LOL]\x01 Beware of fake servers using the -=LOL=- / Losers Online name."
    );

    return Plugin_Handled;
}


public Action Command_Donate(int client, int args)
{
    if (!IsValidHumanClient(client))
    {
        return Plugin_Handled;
    }

    PrintToChat(
        client,
        "\x04[LOL]\x01 Want to support the server? Visit our official donation page."
    );

    PrintToChat(
        client,
        "\x04[LOL]\x01 Donation information is available through our official community."
    );

    return Plugin_Handled;
}


// ============================================================================
// Welcome Panel
// ============================================================================

void ShowWelcomePanel(int client)
{
    char playerName[MAX_NAME_LENGTH];
    GetClientName(client, playerName, sizeof(playerName));

    char line[192];

    Panel panel = new Panel();

    // =========================================================================
    // Header
    // =========================================================================

    panel.SetTitle("-=LOL=- LOSERS ONLINE");

    panel.DrawText(" ");
    panel.DrawText("  OFFICIAL SINGAPORE SERVER");
    panel.DrawText(" ");

    // =========================================================================
    // Player / Server
    // =========================================================================

    Format(
        line,
        sizeof(line),
        "Welcome, %s!",
        playerName
    );
    panel.DrawText(line);

    panel.DrawText(" ");
    panel.DrawText("PvP | New Guns & Skins");

    // =========================================================================
    // Official Server
    // =========================================================================

    panel.DrawText(" ");
    panel.DrawText("----------------------");
    panel.DrawText("OFFICIAL SERVER");
    panel.DrawText("----------------------");

    panel.DrawText("199.119.136.77:27015");

    panel.DrawText(" ");
    panel.DrawText("Beware of fake LOL servers.");
    panel.DrawText("Use !official to verify.");

    // =========================================================================
    // Commands
    // =========================================================================

    panel.DrawText(" ");
    panel.DrawText("----------------------");
    panel.DrawText("QUICK COMMANDS");
    panel.DrawText("----------------------");

    panel.DrawText("!menu      Server Menu");
    panel.DrawText("!profile   My Profile");
    panel.DrawText("!ranks     Online Ranks");
    panel.DrawText("!donate    Support LOL");
    panel.DrawText("!official  Verify Server");

    // =========================================================================
    // Footer
    // =========================================================================

    panel.DrawText(" ");
    panel.DrawText("----------------------");
    panel.DrawText("Respect | Objective | Have Fun");
    panel.DrawText("----------------------");

    panel.DrawText(" ");

    panel.DrawItem("OK - Continue");

    // Stay open for configured duration (50 seconds by default)
    panel.Send(
        client,
        WelcomePanelHandler,
        g_CvarDisplayTime.IntValue
    );

    delete panel;
}


// ============================================================================
// Panel Handler
// ============================================================================

public int WelcomePanelHandler(
    Menu menu,
    MenuAction action,
    int param1,
    int param2
)
{
    return 0;
}


// ============================================================================
// Helpers
// ============================================================================

bool IsValidHumanClient(int client)
{
    return (
        client > 0 &&
        client <= MaxClients &&
        IsClientInGame(client) &&
        !IsFakeClient(client)
    );
}
