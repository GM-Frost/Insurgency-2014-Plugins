#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define PLUGIN_VERSION "2.0.0"
#define CONFIG_FILE "configs/ins_advertisements.txt"

#define MAX_ADS 32
#define MAX_TEXT 512
#define MAX_COMMAND 64
#define MAX_RESPONSE 512

ConVar g_cvEnabled;
ConVar g_cvInterval;
ConVar g_cvFirstDelay;

char g_AdText[MAX_ADS][MAX_TEXT];
char g_AdCommand[MAX_ADS][MAX_COMMAND];
char g_AdResponse[MAX_ADS][MAX_RESPONSE];

int g_AdCount = 0;
int g_CurrentAd = -1;

Handle g_hFirstAdTimer = null;
Handle g_hAdTimer = null;

public Plugin myinfo =
{
    name = "INS Server Advertisements",
    author = "Nayan",
    description = "Professional rotating colored advertisements for Insurgency 2014",
    version = PLUGIN_VERSION,
    url = ""
};

public void OnPluginStart()
{
    g_cvEnabled = CreateConVar(
        "sm_ins_ads_enable",
        "1",
        "Enable or disable server advertisements.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    g_cvInterval = CreateConVar(
        "sm_ins_ads_interval",
        "40.0",
        "Seconds between advertisements.",
        FCVAR_NOTIFY,
        true,
        15.0,
        true,
        300.0
    );

    g_cvFirstDelay = CreateConVar(
        "sm_ins_ads_first_delay",
        "10.0",
        "Seconds before the first advertisement appears.",
        FCVAR_NOTIFY,
        true,
        1.0,
        true,
        60.0
    );

    CreateConVar(
        "sm_ins_ads_version",
        PLUGIN_VERSION,
        "INS Server Advertisements version.",
        FCVAR_NOTIFY | FCVAR_DONTRECORD
    );

    RegConsoleCmd("sm_stats", Command_CommunityItem, "Show server statistics link.");
    RegConsoleCmd("sm_discord", Command_CommunityItem, "Show Discord invite.");
    RegConsoleCmd("sm_steam", Command_CommunityItem, "Show Steam community link.");
    RegConsoleCmd("sm_rules", Command_CommunityItem, "Show server rules.");
    RegConsoleCmd("sm_community", Command_CommunityMenu, "Show community commands.");
    RegConsoleCmd("sm_help", Command_CommunityMenu, "Show community commands.");
    RegConsoleCmd("sm_ads", Command_CommunityMenu, "Show community commands.");

    RegAdminCmd(
        "sm_ads_reload",
        Command_ReloadAds,
        ADMFLAG_CONFIG,
        "Reload advertisement configuration."
    );

    RegAdminCmd(
        "sm_ads_next",
        Command_NextAd,
        ADMFLAG_CONFIG,
        "Display the next advertisement immediately."
    );

    g_cvEnabled.AddChangeHook(OnSettingsChanged);
    g_cvInterval.AddChangeHook(OnSettingsChanged);
    g_cvFirstDelay.AddChangeHook(OnSettingsChanged);

    AutoExecConfig(true, "ins_advertisements");

    LoadAdvertisements();
    StartAdvertisementSystem();
}

public void OnConfigsExecuted()
{
    LoadAdvertisements();
    StartAdvertisementSystem();
}

public void OnMapStart()
{
    g_CurrentAd = -1;
    LoadAdvertisements();
}

public void OnMapEnd()
{
    StopAdvertisementSystem();
}

public void OnPluginEnd()
{
    StopAdvertisementSystem();
}

public void OnSettingsChanged(
    ConVar convar,
    const char[] oldValue,
    const char[] newValue
)
{
    StartAdvertisementSystem();
}

void StartAdvertisementSystem()
{
    StopAdvertisementSystem();

    if (!g_cvEnabled.BoolValue || g_AdCount <= 0)
    {
        return;
    }

    g_hFirstAdTimer = CreateTimer(
        g_cvFirstDelay.FloatValue,
        Timer_FirstAdvertisement,
        _,
        TIMER_FLAG_NO_MAPCHANGE
    );
}

void StopAdvertisementSystem()
{
    if (g_hFirstAdTimer != null)
    {
        delete g_hFirstAdTimer;
        g_hFirstAdTimer = null;
    }

    if (g_hAdTimer != null)
    {
        delete g_hAdTimer;
        g_hAdTimer = null;
    }
}

public Action Timer_FirstAdvertisement(Handle timer, any data)
{
    g_hFirstAdTimer = null;

    if (!g_cvEnabled.BoolValue || g_AdCount <= 0)
    {
        return Plugin_Stop;
    }

    ShowNextAdvertisement();

    g_hAdTimer = CreateTimer(
        g_cvInterval.FloatValue,
        Timer_Advertisement,
        _,
        TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE
    );

    return Plugin_Stop;
}

public Action Timer_Advertisement(Handle timer, any data)
{
    if (!g_cvEnabled.BoolValue || g_AdCount <= 0)
    {
        return Plugin_Continue;
    }

    ShowNextAdvertisement();
    return Plugin_Continue;
}

void ShowNextAdvertisement()
{
    g_CurrentAd++;

    if (g_CurrentAd >= g_AdCount)
    {
        g_CurrentAd = 0;
    }

    ShowAdvertisementToAll(g_CurrentAd);
}

void ShowAdvertisementToAll(int ad)
{
    if (ad < 0 || ad >= g_AdCount)
    {
        return;
    }

    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidHuman(client))
        {
            continue;
        }

        PrintProfessionalAd(client, g_AdText[ad]);
    }
}

void PrintProfessionalAd(int client, const char[] source)
{
    char message[MAX_TEXT];
    strcopy(message, sizeof(message), source);

    ApplyColorTags(message, sizeof(message));
    PrintToChat(client, "\x01%s", message);
}

void ApplyColorTags(char[] message, int maxlen)
{
       // Basic
    ReplaceString(message, maxlen, "{default}", "\x01", false);
    ReplaceString(message, maxlen, "{white}",   "\x07F2F2F2", false);

    // Greens
    ReplaceString(message, maxlen, "{green}",   "\x0797D65C", false);
    ReplaceString(message, maxlen, "{lime}",    "\x07B6F26C", false);

    // Blues / Cyans
    ReplaceString(message, maxlen, "{cyan}",    "\x075ED6E8", false);
    ReplaceString(message, maxlen, "{teal}",    "\x0758C9B9", false);
    ReplaceString(message, maxlen, "{blue}",    "\x076FA8FF", false);
    ReplaceString(message, maxlen, "{navy}",    "\x075C7CCF", false);

    // Purple family
    ReplaceString(message, maxlen, "{purple}",  "\x079887E8", false);
    ReplaceString(message, maxlen, "{violet}",  "\x07B47BE8", false);
    ReplaceString(message, maxlen, "{pink}",    "\x07F27FB2", false);
    ReplaceString(message, maxlen, "{magenta}", "\x07E66FD1", false);

    // Yellow / Orange
    ReplaceString(message, maxlen, "{yellow}",  "\x07E8C75A", false);
    ReplaceString(message, maxlen, "{gold}",    "\x07F2B84B", false);
    ReplaceString(message, maxlen, "{orange}",  "\x07E99A45", false);

    // Reds
    ReplaceString(message, maxlen, "{red}",     "\x07E05A5A", false);
    ReplaceString(message, maxlen, "{coral}",   "\x07F07868", false);

    // Neutral
    ReplaceString(message, maxlen, "{gray}",    "\x07B0B0B0", false);
    ReplaceString(message, maxlen, "{silver}",  "\x07CCCCCC", false);

    ReplaceString(message, maxlen, "{brightgreen}", "\x07B7FF6A", false);
    ReplaceString(message, maxlen, "{brightcyan}",  "\x076FF7FF", false);
    ReplaceString(message, maxlen, "{brightblue}",  "\x0786BFFF", false);
    ReplaceString(message, maxlen, "{brightpurple}","\x07C39BFF", false);
    ReplaceString(message, maxlen, "{brightpink}",  "\x07FF86C8", false);
    ReplaceString(message, maxlen, "{brightyellow}","\x07FFE66A", false);
    ReplaceString(message, maxlen, "{brightorange}","\x07FFAE5D", false);
    ReplaceString(message, maxlen, "{brightred}",   "\x07FF6B6B", false);
}

public Action Command_CommunityItem(int client, int args)
{
    if (!IsValidHuman(client))
    {
        return Plugin_Handled;
    }

    char fullCommand[MAX_COMMAND];
    GetCmdArg(0, fullCommand, sizeof(fullCommand));

    if (strncmp(fullCommand, "sm_", 3, false) == 0)
    {
        char normalized[MAX_COMMAND];
        strcopy(normalized, sizeof(normalized), fullCommand[3]);
        strcopy(fullCommand, sizeof(fullCommand), normalized);
    }

    int ad = FindAdvertisementByCommand(fullCommand);

    if (ad == -1)
    {
        PrintToChat(
            client,
            "\x01[\x0797D65C-=LOL=-\x01] Information is currently unavailable."
        );

        return Plugin_Handled;
    }

    if (g_AdResponse[ad][0] != '\0')
    {
        char response[MAX_RESPONSE];
        strcopy(response, sizeof(response), g_AdResponse[ad]);
        ApplyColorTags(response, sizeof(response));

        PrintToChat(
            client,
            "\x01[\x0797D65C-=LOL=-\x01] %s",
            response
        );
    }

    return Plugin_Handled;
}

public Action Command_CommunityMenu(int client, int args)
{
    if (!IsValidHuman(client))
    {
        return Plugin_Handled;
    }

    PrintToChat(
        client,
        "\x01[\x0797D65C-=LOL=-\x01] \x07E8C75A!stats\x01  \x076FA8FF!discord\x01  \x075ED6E8!steam\x01  \x07E99A45!rules\x01"
    );

    PrintToChat(
        client,
        "\x01[\x0797D65C-=LOL=-\x01] Type \x07E8C75A!community\x01 or \x07E8C75A!help\x01 anytime."
    );

    return Plugin_Handled;
}

public Action Command_ReloadAds(int client, int args)
{
    if (!LoadAdvertisements())
    {
        ReplyToCommand(
            client,
            "[INS Ads] Failed to load advertisements."
        );

        return Plugin_Handled;
    }

    StartAdvertisementSystem();

    ReplyToCommand(
        client,
        "[INS Ads] Reloaded %d advertisements.",
        g_AdCount
    );

    return Plugin_Handled;
}

public Action Command_NextAd(int client, int args)
{
    if (g_AdCount <= 0)
    {
        ReplyToCommand(
            client,
            "[INS Ads] No advertisements loaded."
        );

        return Plugin_Handled;
    }

    ShowNextAdvertisement();

    ReplyToCommand(
        client,
        "[INS Ads] Displayed advertisement %d/%d.",
        g_CurrentAd + 1,
        g_AdCount
    );

    return Plugin_Handled;
}

bool LoadAdvertisements()
{
    g_AdCount = 0;
    g_CurrentAd = -1;

    char path[PLATFORM_MAX_PATH];

    BuildPath(
        Path_SM,
        path,
        sizeof(path),
        CONFIG_FILE
    );

    KeyValues kv = new KeyValues("Advertisements");
    kv.SetEscapeSequences(true);

    if (!kv.ImportFromFile(path))
    {
        LogError(
            "Could not load advertisement file: %s",
            path
        );

        delete kv;
        return false;
    }

    if (!kv.GotoFirstSubKey())
    {
        LogError(
            "No advertisements found in: %s",
            path
        );

        delete kv;
        return false;
    }

    do
    {
        if (g_AdCount >= MAX_ADS)
        {
            LogError(
                "Maximum advertisement count (%d) reached.",
                MAX_ADS
            );

            break;
        }

        kv.GetString(
            "text",
            g_AdText[g_AdCount],
            sizeof(g_AdText[])
        );

        kv.GetString(
            "command",
            g_AdCommand[g_AdCount],
            sizeof(g_AdCommand[])
        );

        kv.GetString(
            "response",
            g_AdResponse[g_AdCount],
            sizeof(g_AdResponse[])
        );

        TrimString(g_AdText[g_AdCount]);
        TrimString(g_AdCommand[g_AdCount]);
        TrimString(g_AdResponse[g_AdCount]);

        RemoveCommandPrefix(g_AdCommand[g_AdCount]);

        if (g_AdText[g_AdCount][0] == '\0')
        {
            LogError(
                "Advertisement %d has no text and was skipped.",
                g_AdCount + 1
            );

            continue;
        }

        g_AdCount++;
    }
    while (kv.GotoNextKey());

    delete kv;

    LogMessage(
        "Loaded %d INS advertisements.",
        g_AdCount
    );

    return (g_AdCount > 0);
}

int FindAdvertisementByCommand(const char[] requested)
{
    for (int i = 0; i < g_AdCount; i++)
    {
        if (g_AdCommand[i][0] == '\0')
        {
            continue;
        }

        if (StrEqual(requested, g_AdCommand[i], false))
        {
            return i;
        }
    }

    return -1;
}

void RemoveCommandPrefix(char[] command)
{
    TrimString(command);

    if (command[0] == '!' || command[0] == '/')
    {
        char temp[MAX_COMMAND];
        strcopy(temp, sizeof(temp), command[1]);
        strcopy(command, MAX_COMMAND, temp);
    }
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
