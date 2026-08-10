#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define PLUGIN_VERSION "1.1.0"
#define CONFIG_FILE "configs/ins_advertisements.txt"

#define MAX_ADS 32
#define MAX_TITLE 128
#define MAX_MESSAGE 512
#define MAX_COMMAND 64
#define MAX_RESPONSE 512

ConVar g_cvEnabled;
ConVar g_cvInterval;
ConVar g_cvFirstDelay;
ConVar g_cvDisplayTime;
ConVar g_cvChatReminder;

char g_AdTitle[MAX_ADS][MAX_TITLE];
char g_AdMessage[MAX_ADS][MAX_MESSAGE];
char g_AdCommand[MAX_ADS][MAX_COMMAND];
char g_AdResponse[MAX_ADS][MAX_RESPONSE];

int g_AdColor[MAX_ADS][3];

int g_AdCount = 0;
int g_CurrentAd = -1;

Handle g_hFirstAdTimer = null;
Handle g_hAdTimer = null;


public Plugin myinfo =
{
    name = "INS Server Advertisements",
    author = "Nayan",
    description = "Automatic colored community advertisements for Insurgency 2014",
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
        "8.0",
        "Seconds before the first advertisement appears.",
        FCVAR_NOTIFY,
        true,
        1.0,
        true,
        60.0
    );

    g_cvDisplayTime = CreateConVar(
        "sm_ins_ads_display_time",
        "8",
        "Seconds the left-side advertisement remains visible.",
        FCVAR_NOTIFY,
        true,
        1.0,
        true,
        30.0
    );

    g_cvChatReminder = CreateConVar(
        "sm_ins_ads_chat_reminder",
        "1",
        "Also print a short command reminder in chat when an ad appears.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    CreateConVar(
        "sm_ins_ads_version",
        PLUGIN_VERSION,
        "INS Server Advertisements version.",
        FCVAR_NOTIFY | FCVAR_DONTRECORD
    );


    /*
     * Player commands.
     *
     * SourceMod automatically allows these to be used
     * as chat triggers:
     *
     * !stats
     * !discord
     * !steam
     * !rules
     * !community
     * !help
     * !ads
     */
    RegConsoleCmd(
        "sm_stats",
        Command_CommunityItem,
        "Show server statistics link."
    );

    RegConsoleCmd(
        "sm_discord",
        Command_CommunityItem,
        "Show Discord invite."
    );

    RegConsoleCmd(
        "sm_steam",
        Command_CommunityItem,
        "Show Steam community link."
    );

    RegConsoleCmd(
        "sm_rules",
        Command_CommunityItem,
        "Show server rules."
    );

    RegConsoleCmd(
        "sm_community",
        Command_CommunityMenu,
        "Show community commands."
    );

    RegConsoleCmd(
        "sm_help",
        Command_CommunityMenu,
        "Show community commands."
    );

    RegConsoleCmd(
        "sm_ads",
        Command_CommunityMenu,
        "Show community commands."
    );


    /*
     * Administrator commands.
     */
    RegAdminCmd(
        "sm_ads_reload",
        Command_ReloadAds,
        ADMFLAG_CONFIG,
        "Reload INS advertisement configuration."
    );

    RegAdminCmd(
        "sm_ads_next",
        Command_NextAd,
        ADMFLAG_CONFIG,
        "Display the next advertisement immediately."
    );


    /*
     * Restart advertisement scheduling when timing
     * configuration changes.
     */
    g_cvEnabled.AddChangeHook(OnSettingsChanged);
    g_cvInterval.AddChangeHook(OnSettingsChanged);
    g_cvFirstDelay.AddChangeHook(OnSettingsChanged);


    /*
     * Generates/loads:
     *
     * cfg/sourcemod/ins_advertisements.cfg
     */
    AutoExecConfig(
        true,
        "ins_advertisements"
    );


    /*
     * Load the advertisement text immediately.
     * This also supports loading/reloading the plugin
     * while a map is already running.
     */
    LoadAdvertisements();
    StartAdvertisementSystem();
}


public void OnConfigsExecuted()
{
    /*
     * server.cfg and SourceMod plugin configs have now
     * finished executing.
     *
     * Restart the system using the final configured values.
     */
    LoadAdvertisements();
    StartAdvertisementSystem();
}


public void OnMapStart()
{
    /*
     * Reset the rotation for every new map.
     */
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


/*
 * ============================================================
 * ADVERTISEMENT TIMER SYSTEM
 * ============================================================
 */

void StartAdvertisementSystem()
{
    StopAdvertisementSystem();

    if (!g_cvEnabled.BoolValue)
    {
        return;
    }

    if (g_AdCount <= 0)
    {
        return;
    }

    /*
     * First advertisement appears quickly.
     *
     * Default:
     * 8 seconds after startup/map config execution.
     */
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


public Action Timer_FirstAdvertisement(
    Handle timer,
    any data
)
{
    g_hFirstAdTimer = null;

    if (!g_cvEnabled.BoolValue)
    {
        return Plugin_Stop;
    }

    if (g_AdCount <= 0)
    {
        return Plugin_Stop;
    }

    /*
     * Display first advertisement immediately.
     */
    ShowNextAdvertisement();


    /*
     * Then continue rotating automatically.
     */
    g_hAdTimer = CreateTimer(
        g_cvInterval.FloatValue,
        Timer_Advertisement,
        _,
        TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE
    );

    return Plugin_Stop;
}


public Action Timer_Advertisement(
    Handle timer,
    any data
)
{
    if (!g_cvEnabled.BoolValue)
    {
        return Plugin_Continue;
    }

    if (g_AdCount <= 0)
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


/*
 * ============================================================
 * DISPLAY
 * ============================================================
 */

void ShowAdvertisementToAll(int ad)
{
    if (ad < 0 || ad >= g_AdCount)
    {
        return;
    }

    KeyValues kv = new KeyValues("msg");

    /*
     * Main title.
     */
    kv.SetString(
        "title",
        g_AdTitle[ad]
    );

    /*
     * Main advertisement text.
     */
    kv.SetString(
        "msg",
        g_AdMessage[ad]
    );

    /*
     * Theme RGB color for this advertisement.
     */
    kv.SetColor(
        "color",
        g_AdColor[ad][0],
        g_AdColor[ad][1],
        g_AdColor[ad][2],
        255
    );

    kv.SetNum(
        "level",
        1
    );

    kv.SetNum(
        "time",
        g_cvDisplayTime.IntValue
    );


    for (int client = 1; client <= MaxClients; client++)
    {
        if (!IsValidHuman(client))
        {
            continue;
        }

        /*
         * Left-side Source dialog.
         */
        CreateDialog(
            client,
            kv,
            DialogType_Msg
        );

        /*
         * Optional colored chat reminder.
         */
        if (
            g_cvChatReminder.BoolValue
            && g_AdCommand[ad][0] != '\0'
        )
        {
            PrintAdChatReminder(
                client,
                g_AdCommand[ad]
            );
        }
    }

    delete kv;
}


void PrintAdChatReminder(
    int client,
    const char[] command
)
{
    /*
     * \x01 = default chat color
     * \x04 = green/highlight color on many Source games.
     *
     * We intentionally keep this conservative because arbitrary
     * hex chat colors vary between Source-engine games.
     */
    PrintToChat(
        client,
        "\x01[\x04LOSERS ONLINE\x01] Type \x04!%s\x01 for more information.",
        command
    );
}


/*
 * ============================================================
 * PLAYER COMMANDS
 * ============================================================
 */

public Action Command_CommunityItem(
    int client,
    int args
)
{
    if (!IsValidHuman(client))
    {
        return Plugin_Handled;
    }

    char fullCommand[64];

    GetCmdArg(
        0,
        fullCommand,
        sizeof(fullCommand)
    );

    /*
     * Convert:
     *
     * sm_stats
     *
     * into:
     *
     * stats
     */
    if (strncmp(fullCommand, "sm_", 3, false) == 0)
    {
        strcopy(
            fullCommand,
            sizeof(fullCommand),
            fullCommand[3]
        );
    }

    int ad = FindAdvertisementByCommand(fullCommand);

    if (ad == -1)
    {
        PrintToChat(
            client,
            "\x01[\x04LOSERS ONLINE\x01] Information is currently unavailable."
        );

        return Plugin_Handled;
    }


    /*
     * Print a recognizable heading.
     */
    PrintToChat(
        client,
        "\x04================================"
    );

    PrintToChat(
        client,
        "\x01[\x04LOSERS ONLINE\x01] %s",
        g_AdTitle[ad]
    );


    /*
     * Print the configured response, normally containing
     * the Stats / Discord / Steam URL or rules.
     */
    if (g_AdResponse[ad][0] != '\0')
    {
        PrintToChat(
            client,
            "\x01%s",
            g_AdResponse[ad]
        );
    }


    PrintToChat(
        client,
        "\x04================================"
    );

    return Plugin_Handled;
}


public Action Command_CommunityMenu(
    int client,
    int args
)
{
    if (!IsValidHuman(client))
    {
        return Plugin_Handled;
    }

    PrintToChat(
        client,
        "\x04========================================"
    );

    PrintToChat(
        client,
        "\x01[\x04LOSERS ONLINE COMMUNITY\x01]"
    );

    PrintToChat(
        client,
        "\x04!stats\x01   - Player stats, ranking and K/D"
    );

    PrintToChat(
        client,
        "\x04!discord\x01 - Join our Discord community"
    );

    PrintToChat(
        client,
        "\x04!steam\x01   - Join our Steam group"
    );

    PrintToChat(
        client,
        "\x04!rules\x01   - Read server rules"
    );

    PrintToChat(
        client,
        "\x01Type \x04!community\x01 or \x04!help\x01 anytime."
    );

    PrintToChat(
        client,
        "\x04========================================"
    );

    return Plugin_Handled;
}


/*
 * ============================================================
 * ADMIN COMMANDS
 * ============================================================
 */

public Action Command_ReloadAds(
    int client,
    int args
)
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


public Action Command_NextAd(
    int client,
    int args
)
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


/*
 * ============================================================
 * CONFIG LOADING
 * ============================================================
 */

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


    KeyValues kv = new KeyValues(
        "Advertisements"
    );

    /*
     * Interpret escape sequences such as:
     *
     * \n
     *
     * inside advertisement messages.
     */
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
            "title",
            g_AdTitle[g_AdCount],
            sizeof(g_AdTitle[])
        );


        kv.GetString(
            "message",
            g_AdMessage[g_AdCount],
            sizeof(g_AdMessage[])
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


        char color[64];

        kv.GetString(
            "color",
            color,
            sizeof(color),
            "255 255 255"
        );


        ParseRGB(
            color,
            g_AdColor[g_AdCount]
        );


        /*
         * Normalize command names.
         *
         * If someone accidentally writes:
         *
         * !stats
         *
         * in the config instead of:
         *
         * stats
         *
         * remove the prefix.
         */
        RemoveCommandPrefix(
            g_AdCommand[g_AdCount]
        );


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


int FindAdvertisementByCommand(
    const char[] requested
)
{
    for (int i = 0; i < g_AdCount; i++)
    {
        if (g_AdCommand[i][0] == '\0')
        {
            continue;
        }

        if (
            StrEqual(
                requested,
                g_AdCommand[i],
                false
            )
        )
        {
            return i;
        }
    }

    return -1;
}


void RemoveCommandPrefix(
    char[] command
)
{
    TrimString(command);

    if (
        command[0] == '!'
        || command[0] == '/'
    )
    {
        char temp[MAX_COMMAND];

        strcopy(
            temp,
            sizeof(temp),
            command[1]
        );

        strcopy(
            command,
            MAX_COMMAND,
            temp
        );
    }
}


/*
 * ============================================================
 * RGB
 * ============================================================
 */

void ParseRGB(
    const char[] input,
    int rgb[3]
)
{
    char pieces[3][8];

    int count = ExplodeString(
        input,
        " ",
        pieces,
        sizeof(pieces),
        sizeof(pieces[])
    );


    if (count != 3)
    {
        rgb[0] = 255;
        rgb[1] = 255;
        rgb[2] = 255;

        return;
    }


    for (int i = 0; i < 3; i++)
    {
        rgb[i] = StringToInt(
            pieces[i]
        );


        if (rgb[i] < 0)
        {
            rgb[i] = 0;
        }
        else if (rgb[i] > 255)
        {
            rgb[i] = 255;
        }
    }
}


/*
 * ============================================================
 * CLIENT VALIDATION
 * ============================================================
 */

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
