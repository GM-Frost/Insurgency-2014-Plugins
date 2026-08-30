// ============================================================================
// [INS] Chat Bot
//
// Lightweight, scope-aware reactions to ordinary player conversation.
// Public chat gets a public reply; team chat stays inside the sender's team.
// ============================================================================

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#define PLUGIN_VERSION "2.1.0"
#define CHAT_SIZE 256
#define RESPONSE_SIZE 192

enum ChatTrigger
{
    Trigger_None = -1,
    Trigger_Ping = 0,
    Trigger_Lag,
    Trigger_Aim,
    Trigger_Bot,
    Trigger_Apology,
    Trigger_Carry,
    Trigger_Noob,
    Trigger_Cheat,
    Trigger_SpawnKill,
    Trigger_SpawnCallout,
    Trigger_Camp,
    Trigger_Sex,
    Trigger_Gay,
    Trigger_Profanity,
    Trigger_Stop,
    Trigger_Silence,
    Trigger_Rage,
    Trigger_Knife,
    Trigger_Objective,
    Trigger_Count
};

ConVar g_CvarEnabled;
ConVar g_CvarCooldown;
ConVar g_CvarGlobalCooldown;
ConVar g_CvarDeathContextWindow;
ConVar g_CvarLogReplies;

float g_NextGlobalReplyTime = 0.0;
float g_NextClientReplyTime[MAXPLAYERS + 1];
int g_RecentKillerUserId[MAXPLAYERS + 1];
float g_RecentDeathTime[MAXPLAYERS + 1];
int g_LastResponse[Trigger_Count];


public Plugin myinfo =
{
    name = "[INS] LOL Chat Bot",
    author = "Nayan",
    description = "Randomized, scope-aware reactions to normal player chat.",
    version = PLUGIN_VERSION,
    url = ""
};


public void OnPluginStart()
{
    CreateConVar(
        "sm_ins_chatbot_version",
        PLUGIN_VERSION,
        "INS Chat Bot plugin version.",
        FCVAR_NOTIFY | FCVAR_DONTRECORD
    );

    g_CvarEnabled = CreateConVar(
        "sm_ins_chatbot_enabled",
        "1",
        "Enable normal-conversation chat reactions.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    g_CvarCooldown = CreateConVar(
        "sm_ins_chatbot_cooldown",
        "8.0",
        "Seconds between BOT replies triggered by the same player.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        120.0
    );

    g_CvarGlobalCooldown = CreateConVar(
        "sm_ins_chatbot_global_cooldown",
        "2.5",
        "Server-wide seconds between BOT replies.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        120.0
    );

    g_CvarDeathContextWindow = CreateConVar(
        "sm_ins_chatbot_death_context_window",
        "10.0",
        "Seconds a recent human killer may provide chat-response context.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        60.0
    );

    g_CvarLogReplies = CreateConVar(
        "sm_ins_chatbot_log_replies",
        "1",
        "Write triggers and BOT replies to a separate monthly log.",
        FCVAR_NOTIFY,
        true,
        0.0,
        true,
        1.0
    );

    AddCommandListener(ChatListener, "say");
    AddCommandListener(ChatListener, "say_team");
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);

    AutoExecConfig(true, "ins_chatbot");

    for (int i = 0; i < view_as<int>(Trigger_Count); i++)
    {
        g_LastResponse[i] = -1;
    }

    ResetTransientState();
}


public void OnMapStart()
{
    ResetTransientState();
}


public void OnClientPutInServer(int client)
{
    ResetClientState(client);
}


public void OnClientDisconnect(int client)
{
    ResetClientState(client);
}


public void Event_PlayerDeath(
    Event event,
    const char[] name,
    bool dontBroadcast
)
{
    int victim = GetClientOfUserId(event.GetInt("userid"));

    if (!IsValidHuman(victim))
    {
        return;
    }

    // A new death always replaces any older context for this victim.
    ClearDeathContext(victim);

    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    if (!IsValidHuman(attacker) || attacker == victim)
    {
        return;
    }

    g_RecentKillerUserId[victim] = GetClientUserId(attacker);
    g_RecentDeathTime[victim] = GetGameTime();
}


public Action ChatListener(
    int client,
    const char[] command,
    int argc
)
{
    if (!g_CvarEnabled.BoolValue || !IsValidHuman(client))
    {
        return Plugin_Continue;
    }

    float now = GetGameTime();

    if (now < g_NextGlobalReplyTime
        || now < g_NextClientReplyTime[client])
    {
        return Plugin_Continue;
    }

    char original[CHAT_SIZE];
    GetCmdArgString(original, sizeof(original));
    StripQuotes(original);
    TrimString(original);

    if (original[0] == '\0')
    {
        return Plugin_Continue;
    }

    char normalized[CHAT_SIZE];
    strcopy(normalized, sizeof(normalized), original);
    LowercaseAscii(normalized);

    char squeezed[CHAT_SIZE];
    CollapseRepeatedAscii(normalized, squeezed, sizeof(squeezed));

    ChatTrigger trigger = FindTrigger(normalized, squeezed);

    // Ordinary chat is deliberately ignored when no configured word appears.
    if (trigger == Trigger_None)
    {
        return Plugin_Continue;
    }

    char response[RESPONSE_SIZE];
    BuildRandomResponse(client, trigger, response, sizeof(response));

    bool teamOnly = StrEqual(command, "say_team", false);
    SendBotReply(client, teamOnly, response);

    g_NextGlobalReplyTime = now + g_CvarGlobalCooldown.FloatValue;
    g_NextClientReplyTime[client] = now + g_CvarCooldown.FloatValue;

    if (g_CvarLogReplies.BoolValue)
    {
        LogBotReply(client, teamOnly, original, response);
    }

    // The player's original message must continue normally so HLstats can see it.
    return Plugin_Continue;
}


ChatTrigger FindTrigger(
    const char[] text,
    const char[] squeezed
)
{
    // Specific meanings and multiword phrases get priority. Only one can win.
    if (ContainsWholeWord(text, "apologize")
        || ContainsWholeWord(text, "apologise")
        || ContainsWholeWord(text, "apology")
        || ContainsWholeWord(text, "sorry"))
    {
        return Trigger_Apology;
    }

    if (ContainsWholeWord(text, "carrying")
        || ContainsWholeWord(text, "carried")
        || ContainsWholeWord(text, "carry"))
    {
        return Trigger_Carry;
    }

    if (ContainsWholeWord(text, "hacker")
        || ContainsWholeWord(text, "hacking")
        || ContainsWholeWord(text, "hacks")
        || ContainsWholeWord(text, "hack")
        || ContainsWholeWord(text, "haxxer")
        || ContainsWholeWord(text, "hax")
        || ContainsWholeWord(text, "cheater")
        || ContainsWholeWord(text, "cheating")
        || ContainsWholeWord(text, "cheats")
        || ContainsWholeWord(squeezed, "hacker")
        || ContainsWholeWord(squeezed, "hacking")
        || ContainsWholeWord(squeezed, "hacks")
        || ContainsWholeWord(squeezed, "hack")
        || ContainsWholeWord(squeezed, "haxer")
        || ContainsWholeWord(squeezed, "hax")
        || ContainsWholeWord(squeezed, "cheater")
        || ContainsWholeWord(squeezed, "cheating")
        || ContainsWholeWord(squeezed, "cheats")
        || ContainsWholeWord(squeezed, "chet"))
    {
        return Trigger_Cheat;
    }

    bool mentionsSpawn = MessageMentionsSpawn(text, squeezed);
    bool mentionsCamping = MessageMentionsCamping(text, squeezed);
    bool mentionsKilling = MessageMentionsKilling(text, squeezed);

    // Kill/camp language only becomes spawn killing when spawn is also present.
    // Joined forms are handled separately because "spawn" is not a whole word
    // inside "spawnkill".
    if (MessageMentionsJoinedSpawnKill(text, squeezed)
        || (mentionsSpawn && (mentionsKilling || mentionsCamping)))
    {
        return Trigger_SpawnKill;
    }

    // "spawn" alone is intentionally not a trigger. "in" is deliberately
    // excluded so timing messages such as "spawn in five seconds" stay quiet.
    if (mentionsSpawn && MessageHasSpawnCalloutLanguage(text, squeezed))
    {
        return Trigger_SpawnCallout;
    }

    if (mentionsCamping)
    {
        return Trigger_Camp;
    }

    if (ContainsAlias(text, squeezed, "objective", "objective")
        || ContainsAlias(text, squeezed, "objectives", "objectives")
        || ContainsAlias(text, squeezed, "obj", "obj")
        || ContainsAlias(text, squeezed, "take obj", "take obj")
        || ContainsAlias(text, squeezed, "go obj", "go obj")
        || ContainsAlias(text, squeezed, "push obj", "push obj")
        || ContainsAlias(text, squeezed, "get obj", "get obj")
        || ContainsAlias(text, squeezed, "capture obj", "capture obj")
        || ContainsAlias(text, squeezed, "take objective", "take objective")
        || ContainsAlias(text, squeezed, "go objective", "go objective")
        || ContainsAlias(text, squeezed, "push objective", "push objective")
        || ContainsAlias(text, squeezed, "capture objective", "capture objective")
        || ContainsAlias(text, squeezed, "play objective", "play objective"))
    {
        return Trigger_Objective;
    }

    if (ContainsAlias(text, squeezed, "knife", "knife")
        || ContainsAlias(text, squeezed, "knives", "knives")
        || ContainsAlias(text, squeezed, "knifed", "knifed")
        || ContainsAlias(text, squeezed, "kniffed", "knifed")
        || ContainsAlias(text, squeezed, "knifing", "knifing")
        || ContainsAlias(text, squeezed, "knife him", "knife him")
        || ContainsAlias(text, squeezed, "knife kill", "knife kil")
        || ContainsAlias(text, squeezed, "knifekill", "knifekil"))
    {
        return Trigger_Knife;
    }

    if (ContainsAlias(text, squeezed, "rage", "rage")
        || ContainsAlias(text, squeezed, "raging", "raging")
        || ContainsAlias(text, squeezed, "raged", "raged")
        || ContainsAlias(text, squeezed, "ragequit", "ragequit")
        || ContainsAlias(text, squeezed, "rage quit", "rage quit")
        || ContainsAlias(text, squeezed, "ragequitting", "ragequiting")
        || ContainsAlias(text, squeezed, "rage quitting", "rage quiting"))
    {
        return Trigger_Rage;
    }

    if (ContainsWholeWord(text, "aiming")
        || ContainsWholeWord(text, "accuracy")
        || ContainsWholeWord(text, "aim"))
    {
        return Trigger_Aim;
    }

    if (ContainsWholeWord(text, "lagging")
        || ContainsWholeWord(text, "laggy")
        || ContainsWholeWord(text, "lag")
        || ContainsWholeWord(squeezed, "lag"))
    {
        return Trigger_Lag;
    }

    if (ContainsWholeWord(text, "ping"))
    {
        return Trigger_Ping;
    }

    if (ContainsWholeWord(text, "noobs")
        || ContainsWholeWord(text, "noob"))
    {
        return Trigger_Noob;
    }

    // nub, noob, nooobies and nobbies reduce to one of these forms.
    if (ContainsWholeWord(squeezed, "nub")
        || ContainsWholeWord(squeezed, "nob")
        || ContainsWholeWord(squeezed, "nobies"))
    {
        return Trigger_Noob;
    }

    if (ContainsWholeWord(text, "bots")
        || ContainsWholeWord(text, "bot"))
    {
        return Trigger_Bot;
    }

    if (ContainsAlias(text, squeezed, "sex", "sex")
        || ContainsAlias(text, squeezed, "porn", "porn")
        || ContainsAlias(text, squeezed, "pornhub", "pornhub")
        || ContainsAlias(text, squeezed, "nude", "nude")
        || ContainsAlias(text, squeezed, "nudes", "nudes")
        || ContainsAlias(text, squeezed, "send nude", "send nude")
        || ContainsAlias(text, squeezed, "send nudes", "send nudes")
        || ContainsAlias(text, squeezed, "sendnude", "sendnude")
        || ContainsAlias(text, squeezed, "sendnudes", "sendnudes")
        || ContainsAlias(text, squeezed, "send nud", "send nud")
        || ContainsAlias(text, squeezed, "send nuds", "send nuds")
        || ContainsAlias(text, squeezed, "sendnuds", "sendnuds")
        || ContainsAlias(text, squeezed, "naked", "naked")
        || ContainsAlias(text, squeezed, "boob", "bob")
        || ContainsAlias(text, squeezed, "boobs", "bobs")
        || ContainsAlias(text, squeezed, "boobie", "bobie")
        || ContainsAlias(text, squeezed, "boobies", "bobies")
        || ContainsAlias(text, squeezed, "tits", "tits")
        || ContainsAlias(text, squeezed, "titties", "tities")
        || ContainsAlias(text, squeezed, "booty", "boty")
        // Whole-word matching keeps this short alias out of larger words.
        || ContainsAlias(text, squeezed, "pp", "pp"))
    {
        return Trigger_Sex;
    }

    if (ContainsAlias(text, squeezed, "gay", "gay")
        || ContainsAlias(text, squeezed, "gays", "gays")
        || ContainsAlias(text, squeezed, "gae", "gae")
        || ContainsAlias(text, squeezed, "gai", "gai")
        || ContainsAlias(text, squeezed, "gei", "gei")
        || ContainsAlias(text, squeezed, "ghay", "ghay")
        || ContainsAlias(text, squeezed, "gaylord", "gaylord")
        || ContainsAlias(text, squeezed, "gaylords", "gaylords")
        || ContainsAlias(text, squeezed, "who gay", "who gay")
        || ContainsAlias(text, squeezed, "whogay", "whogay")
        || ContainsAlias(text, squeezed, "ur gay", "ur gay")
        || ContainsAlias(text, squeezed, "you gay", "you gay")
        || ContainsAlias(text, squeezed, "you are gay", "you are gay")
        || ContainsAlias(text, squeezed, "he is gay", "he is gay")
        || ContainsAlias(text, squeezed, "hes gay", "hes gay")
        || ContainsAlias(text, squeezed, "he's gay", "he's gay"))
    {
        return Trigger_Gay;
    }

    if (ContainsWholeWord(text, "stop")
        || ContainsWholeWord(squeezed, "stop"))
    {
        return Trigger_Stop;
    }

    if (ContainsWholeWord(text, "shutup")
        || ContainsWholeWord(text, "shut up")
        || ContainsWholeWord(text, "sattap")
        || ContainsWholeWord(text, "saaddap")
        || ContainsWholeWord(squeezed, "shutup")
        || ContainsWholeWord(squeezed, "shut up")
        || ContainsWholeWord(squeezed, "satap")
        || ContainsWholeWord(squeezed, "sadap"))
    {
        return Trigger_Silence;
    }

    // Keep broad profanity last so it cannot steal a more specific meaning.
    if (ContainsWholeWord(text, "wtf")
        || ContainsWholeWord(text, "fuck")
        || ContainsWholeWord(text, "fuq")
        || ContainsWholeWord(squeezed, "wtf")
        || ContainsWholeWord(squeezed, "fuck")
        || ContainsWholeWord(squeezed, "fuq"))
    {
        return Trigger_Profanity;
    }

    return Trigger_None;
}


void BuildRandomResponse(
    int author,
    ChatTrigger trigger,
    char[] output,
    int maxLength
)
{
    int triggerIndex = view_as<int>(trigger);

    if (triggerIndex < 0 || triggerIndex >= view_as<int>(Trigger_Count))
    {
        output[0] = '\0';
        return;
    }

    int choices = 8;
    int selected = GetRandomInt(0, choices - 1);

    // Avoid repeating the same line twice for a subject.
    if (g_LastResponse[triggerIndex] == selected)
    {
        selected = (selected + GetRandomInt(1, choices - 1)) % choices;
    }

    g_LastResponse[triggerIndex] = selected;

    switch (trigger)
{
    case Trigger_Ping:
    {
        switch (selected)
        {
            case 0: strcopy(output, maxLength, "Your ping is higher than your IQ.");
            case 1: strcopy(output, maxLength, "That packet was delivered by a fucking pigeon.");
            case 2: strcopy(output, maxLength, "Bro is playing from the neighbour's bathroom.");
            case 3: strcopy(output, maxLength, "Your bullets will arrive sometime next Tuesday.");
            case 4: strcopy(output, maxLength, "Stop stealing Wi-Fi from the neighbour's microwave.");
            case 5: strcopy(output, maxLength, "Your ping has its own fucking time zone.");
            case 6: strcopy(output, maxLength, "By the time your packet arrives, the next map will be loading.");
            case 7: strcopy(output, maxLength, "Bro is peeking corners from the past.");
        }
    }

    case Trigger_Lag:
    {
        switch (selected)
        {
            case 0: strcopy(output, maxLength, "That wasn't lag. You just fucking suck.");
            case 1: strcopy(output, maxLength, "Bro is teleporting like a discount superhero.");
            case 2: strcopy(output, maxLength, "Close Pornhub before blaming the server.");
            case 3: strcopy(output, maxLength, "Your character moved, but your brain stayed behind.");
            case 4: strcopy(output, maxLength, "Even your excuses are buffering.");
            case 5: strcopy(output, maxLength, "Your Wi-Fi is performing stop-motion animation.");
            case 6: strcopy(output, maxLength, "Bro didn't dodge. The server simply misplaced him.");
            case 7: strcopy(output, maxLength, "You're not rubber-banding. The game is trying to return you.");
        }
    }

    case Trigger_Aim:
    {
        switch (selected)
        {
            case 0: strcopy(output, maxLength, "Your aim is a hate crime against ammunition.");
            case 1: strcopy(output, maxLength, "Calling that aim would be disrespectful to aiming.");
            case 2: strcopy(output, maxLength, "The enemy is safe as long as you're shooting.");
            case 3: strcopy(output, maxLength, "Bro couldn't hit puberty with an aimbot.");
            case 4: strcopy(output, maxLength, "Your bullets have commitment issues.");
            case 5: strcopy(output, maxLength, "Bro draws perfect outlines around every enemy.");
            case 6: strcopy(output, maxLength, "Your crosshair has a restraining order against targets.");
            case 7: strcopy(output, maxLength, "You miss so consistently that it has to be intentional.");
        }
    }

    case Trigger_Bot:
    {
        switch (selected)
        {
            case 0: strcopy(output, maxLength, "You called, bottom-fragging bitch?");
            case 1: strcopy(output, maxLength, "Yes, human? Have you learned to aim yet?");
            case 2: strcopy(output, maxLength, "I'm a bot and still less artificial than your K/D.");
            case 3: strcopy(output, maxLength, "Keep talking shit. I'm collecting evidence.");
            case 4: strcopy(output, maxLength, "I was programmed to roast noobs. That's why I'm here.");
            case 5: strcopy(output, maxLength, "You rang? I was watching humans reinvent failure.");
            case 6: strcopy(output, maxLength, "I'm lines of code and still have better game sense.");
            case 7: strcopy(output, maxLength, "Careful, meatbag. I have logs and no mercy.");
        }
    }

    case Trigger_Apology:
    {
        switch (selected)
        {
            case 0: strcopy(output, maxLength, "Apology rejected. Send nudes instead.");
            case 1: strcopy(output, maxLength, "Sorry won't unfuck the scoreboard.");
            case 2: strcopy(output, maxLength, "You're forgiven, but you're still a dumbass.");
            case 3: strcopy(output, maxLength, "Apology accepted. Your dignity remains missing.");
            case 4: strcopy(output, maxLength, "That apology had less confidence than your aim.");
            case 5: strcopy(output, maxLength, "Sorry accepted. Skill issue remains unresolved.");
            case 6: strcopy(output, maxLength, "The apology was better aimed than your bullets.");
            case 7: strcopy(output, maxLength, "Forgiveness granted. Respect is still pending.");
        }
    }

    case Trigger_Carry:
    {
        switch (selected)
        {
            case 0: strcopy(output, maxLength, "Someone call a chiropractor. This carry is brutal.");
            case 1: strcopy(output, maxLength, "One player is carrying twenty armed toddlers.");
            case 2: strcopy(output, maxLength, "His backpack is full of useless teammates.");
            case 3: strcopy(output, maxLength, "Stop carrying them. Let natural selection work.");
            case 4: strcopy(output, maxLength, "This isn't a team. It's one player and his liabilities.");
            case 5: strcopy(output, maxLength, "This carry needs a forklift and paid medical leave.");
            case 6: strcopy(output, maxLength, "One player does the work while everyone else provides emotional damage.");
            case 7: strcopy(output, maxLength, "This team is so heavy the backpack has stretch marks.");
        }
    }

    case Trigger_Noob:
    {
        switch (selected)
        {
            case 0: strcopy(output, maxLength, "Calling him a noob is generous.");
            case 1: strcopy(output, maxLength, "The tutorial wants its failure back.");
            case 2: strcopy(output, maxLength, "Noob versus noob: the battle nobody requested.");
            case 3: strcopy(output, maxLength, "Bro installed the game five minutes before joining.");
            case 4: strcopy(output, maxLength, "Even the bots are farming this dumbass.");
            case 5: strcopy(output, maxLength, "Noob detected. Confidence somehow set to maximum.");
            case 6: strcopy(output, maxLength, "Bro is using the kill feed as a tutorial.");
            case 7: strcopy(output, maxLength, "Even the respawn timer is tired of seeing him.");
        }
    }

    case Trigger_Cheat:
    {
        switch (selected)
        {
            case 0: strcopy(output, maxLength, "He's not hacking. You're just fucking blind.");
            case 1: strcopy(output, maxLength, "Breaking news: aiming is now considered cheating.");
            case 2: strcopy(output, maxLength, "Haxxer detected. Gaming chair confiscated.");
            case 3: strcopy(output, maxLength, "Imagine buying hacks and still missing.");
            case 4: strcopy(output, maxLength, "That kill was sponsored by aim.exe.");
            case 5: strcopy(output, maxLength, "Report filed successfully under skill issue.");
            case 6: strcopy(output, maxLength, "Hax accusations: the natural predator of bad aim.");
            case 7: strcopy(output, maxLength, "If he's hacking, ask him why the scoreboard still looks like shit.");
        }
    }

    case Trigger_SpawnKill:
    {
        switch (selected)
        {
            case 0: strcopy(output, maxLength, "Bro found enemies who can't shoot back and called it talent.");
            case 1: strcopy(output, maxLength, "Spawn camping: because fair fights keep hurting his feelings.");
            case 2: strcopy(output, maxLength, "He's guarding spawn like his last Pornhub password is hidden there.");
            case 3: strcopy(output, maxLength, "Imagine spawn-killing and still thinking anyone respects the K/D.");
            case 4: strcopy(output, maxLength, "Spawn killer detected. Skill missing, tiny-dick energy confirmed.");
            case 5: strcopy(output, maxLength, "Bro turned fresh spawns into a personality because skill never loaded.");
            case 6: strcopy(output, maxLength, "Nothing screams confidence like shooting people before their screen finishes loading.");
            case 7: strcopy(output, maxLength, "He's farming spawn because opponents who fight back ruin the fantasy.");
        }
    }

    case Trigger_SpawnCallout:
    {
        switch (selected)
        {
            case 0: strcopy(output, maxLength, "Enemy near spawn. Thanks, budget UAV.");
            case 1: strcopy(output, maxLength, "Spawn callout received. Now put the keyboard down and shoot him.");
            case 2: strcopy(output, maxLength, "Enemy at spawn. Tactical awareness has briefly entered the chat.");
            case 3: strcopy(output, maxLength, "Check spawn, unless dying surprised is still the team strategy.");
            case 4: strcopy(output, maxLength, "Spawn is hot. Unlike this team's reaction speed.");
            case 5: strcopy(output, maxLength, "Enemy near spawn. Try bullets before writing a sequel.");
            case 6: strcopy(output, maxLength, "Callout confirmed. Half the team will ignore it professionally.");
            case 7: strcopy(output, maxLength, "Watch spawn. Common sense has apparently taken the day off.");
        }
    }

    case Trigger_Camp:
    {
        switch (selected)
        {
            case 0: strcopy(output, maxLength, "Bro has been in that corner so long the map started charging rent.");
            case 1: strcopy(output, maxLength, "His W key is still in factory condition.");
            case 2: strcopy(output, maxLength, "He isn't holding the angle. The angle is holding him hostage.");
            case 3: strcopy(output, maxLength, "Someone bring marshmallows. This bitch has been camping all round.");
            case 4: strcopy(output, maxLength, "Bro found one corner and started a fucking family there.");
            case 5: strcopy(output, maxLength, "At this point, the corner deserves half his kills.");
            case 6: strcopy(output, maxLength, "Bro's tent has better map control than his entire team.");
            case 7: strcopy(output, maxLength, "He's not camping. He's emotionally attached to that wall.");
        }
    }

    case Trigger_Rage:
    {
        switch (selected)
        {
            case 0: strcopy(output, maxLength, "Keyboard abuse detected. Skill improvement not detected.");
            case 1: strcopy(output, maxLength, "Bro is one death away from punching the monitor.");
            case 2: strcopy(output, maxLength, "Rage harder. Maybe your aim will become scared and improve.");
            case 3: strcopy(output, maxLength, "Someone check on the gaming chair. It sounds terrified.");
            case 4: strcopy(output, maxLength, "He didn't lose the round. The round lost custody of him.");
            case 5: strcopy(output, maxLength, "Salt levels critical. Somebody hide the breakable furniture.");
            case 6: strcopy(output, maxLength, "Rage quit loading faster than his bullets ever did.");
            case 7: strcopy(output, maxLength, "Take a breath, Gaylord. The scoreboard can't hurt you physically.");
        }
    }

    case Trigger_Knife:
    {
        switch (selected)
        {
            case 0: strcopy(output, maxLength, "Imagine bringing a rifle and losing to cutlery.");
            case 1: strcopy(output, maxLength, "Getting knifed should automatically uninstall the game.");
            case 2: strcopy(output, maxLength, "Bro just got converted into a close-range donation.");
            case 3: strcopy(output, maxLength, "That knife went deeper than the team's strategy.");
            case 4: strcopy(output, maxLength, "Gun: expensive. Knife: free. Humiliation: permanent.");
            case 5: strcopy(output, maxLength, "He brought bullets. The other guy brought pure disrespect.");
            case 6: strcopy(output, maxLength, "Knife kill detected. Dignity dropped with the body.");
            case 7: strcopy(output, maxLength, "Delete the replay before his family sees that shit.");
        }
    }

    case Trigger_Objective:
    {
        switch (selected)
        {
            case 0: strcopy(output, maxLength, "The objective is over there, Christopher Columbus.");
            case 1: strcopy(output, maxLength, "Capture the point, you heavily armed tourists.");
            case 2: strcopy(output, maxLength, "Bro explored the entire map except the objective.");
            case 3: strcopy(output, maxLength, "Kills don't win the round when everyone ignores the fucking objective.");
            case 4: strcopy(output, maxLength, "The objective isn't optional, you tactical dildos.");
            case 5: strcopy(output, maxLength, "Please touch the objective. It has been lonely all round.");
            case 6: strcopy(output, maxLength, "The team treats the objective like terms and conditions.");
            case 7: strcopy(output, maxLength, "Take the objective before it files a missing-person report.");
        }
    }

    case Trigger_Sex:
    {
        switch (selected)
        {
            case 0: strcopy(output, maxLength, "Sex? You can't even penetrate the objective.");
            case 1: strcopy(output, maxLength, "The only thing getting fucked is your K/D.");
            case 2: strcopy(output, maxLength, "Close Pornhub and use both hands.");
            case 3: strcopy(output, maxLength, "Nudes denied. Send proof of good aim first.");
            case 4: strcopy(output, maxLength, "Bro came looking for boobies and found bullets.");
            case 5: strcopy(output, maxLength, "Send nudes? Your scoreboard already exposed enough.");
            case 6: strcopy(output, maxLength, "One hand on the keyboard explains the fucking aim.");
            case 7: strcopy(output, maxLength, "Boobies unavailable. Humiliation is currently in stock.");
        }
    }

    case Trigger_Gay:
    {
        int recentKiller;

        if (TryGetRecentKiller(author, recentKiller))
        {
            char authorName[MAX_NAME_LENGTH];
            char killerName[MAX_NAME_LENGTH];

            GetClientName(author, authorName, sizeof(authorName));
            GetClientName(recentKiller, killerName, sizeof(killerName));

            switch (selected)
            {
                case 0: Format(output, maxLength, "%s got killed by %s and immediately activated the gaydar.", authorName, killerName);
                case 1: Format(output, maxLength, "%s died to %s and filed an emergency gay complaint.", authorName, killerName);
                case 2: Format(output, maxLength, "%s got folded by %s and responded with gay allegations.", authorName, killerName);
                case 3: Format(output, maxLength, "%s couldn't kill %s, so the gaydar became the backup weapon.", authorName, killerName);
                case 4: Format(output, maxLength, "%s died to %s and reached for the strongest counterattack: gay.", authorName, killerName);
                case 5: Format(output, maxLength, "%s got deleted by %s and opened the Gaylord investigation.", authorName, killerName);
                case 6: Format(output, maxLength, "%s called %s gay because the bullets clearly weren't working.", authorName, killerName);
                case 7: Format(output, maxLength, "%s lost to %s. The appeal has been filed under gay.", authorName, killerName);
            }
        }
        else
        {
            switch (selected)
            {
                case 0: strcopy(output, maxLength, "Who summoned the Gaylord?");
                case 1: strcopy(output, maxLength, "Calling everyone gay won't make your aim straight.");
                case 2: strcopy(output, maxLength, "Gay allegations detected. The evidence seems suspiciously personal.");
                case 3: strcopy(output, maxLength, "That's not gay. That's advanced team bonding.");
                case 4: strcopy(output, maxLength, "Your gaydar works better than your minimap.");
                case 5: strcopy(output, maxLength, "Two gaylords entered chat. The objective immediately felt abandoned.");
                case 6: strcopy(output, maxLength, "That gay accusation came out faster than your bullets.");
                case 7: strcopy(output, maxLength, "The server accepts gay allegations in exchange for actual evidence.");
            }
        }
    }

    case Trigger_Profanity:
    {
        switch (selected)
        {
            case 0: strcopy(output, maxLength, "That's a lot of shit-talk for such a small K/D.");
            case 1: strcopy(output, maxLength, "Keep swearing. Maybe the bullets will get scared.");
            case 2: strcopy(output, maxLength, "Bro learned three swear words and equipped all of them.");
            case 3: strcopy(output, maxLength, "Your mouth is carrying harder than your gameplay.");
            case 4: strcopy(output, maxLength, "Talk your shit, bottom-fragging Shakespeare.");
            case 5: strcopy(output, maxLength, "All that profanity and still not one useful callout.");
            case 6: strcopy(output, maxLength, "The swear jar can now afford a better fucking player.");
            case 7: strcopy(output, maxLength, "Bro's vocabulary has recoil but no accuracy.");
        }
    }

    case Trigger_Stop:
    {
        switch (selected)
        {
            case 0: strcopy(output, maxLength, "Make me, you tactical dildo.");
            case 1: strcopy(output, maxLength, "Stop? We haven't finished ruining your evening.");
            case 2: strcopy(output, maxLength, "The safe word was rejected.");
            case 3: strcopy(output, maxLength, "He said stop. Increase the bullying by twenty percent.");
            case 4: strcopy(output, maxLength, "You can stop this anytime by learning to aim.");
            case 5: strcopy(output, maxLength, "Request denied. The disaster is finally entertaining.");
            case 6: strcopy(output, maxLength, "Stop is not recognized as a valid survival strategy.");
            case 7: strcopy(output, maxLength, "The brakes were removed to make room for more bullshit.");
        }
    }

    case Trigger_Silence:
    {
        switch (selected)
        {
            case 0: strcopy(output, maxLength, "You first, loud-ass.");
            case 1: strcopy(output, maxLength, "Mute me yourself, you lazy bastard.");
            case 2: strcopy(output, maxLength, "Your gameplay wasn't entertaining, so we started talking.");
            case 3: strcopy(output, maxLength, "I'd be quiet too if my score looked like yours.");
            case 4: strcopy(output, maxLength, "Silence costs extra. Your broke ass gets sarcasm.");
            case 5: strcopy(output, maxLength, "Shut up? That's a strange way to request more attention.");
            case 6: strcopy(output, maxLength, "The mute button is nearby, brave warrior.");
            case 7: strcopy(output, maxLength, "Nobody became quieter after hearing your bitching.");
        }
    }
}
}


void SendBotReply(
    int author,
    bool teamOnly,
    const char[] response
)
{
    int authorTeam = GetClientTeam(author);

    for (int target = 1; target <= MaxClients; target++)
    {
        if (!IsValidHuman(target))
        {
            continue;
        }

        if (teamOnly && GetClientTeam(target) != authorTeam)
        {
            continue;
        }

        PrintToChat(
            target,
            "\x01[\x0797D65CBOT\x01] \x03%s",
            response
        );
    }
}


void LogBotReply(
    int client,
    bool teamOnly,
    const char[] original,
    const char[] response
)
{
    char month[16];
    FormatTime(month, sizeof(month), "%Y-%m", GetTime());

    char path[PLATFORM_MAX_PATH];
    BuildPath(
        Path_SM,
        path,
        sizeof(path),
        "logs/ins_chatbot_%s.log",
        month
    );

    LogToFileEx(
        path,
        "scope=%s player=\"%L\" message=\"%s\" reply=\"%s\"",
        teamOnly ? "TEAM" : "ALL",
        client,
        original,
        response
    );
}


bool MessageMentionsSpawn(
    const char[] text,
    const char[] squeezed
)
{
    return ContainsAlias(text, squeezed, "spawn", "spawn");
}


bool MessageMentionsCamping(
    const char[] text,
    const char[] squeezed
)
{
    return ContainsAlias(text, squeezed, "camp", "camp")
        || ContainsAlias(text, squeezed, "camper", "camper")
        || ContainsAlias(text, squeezed, "campers", "campers")
        || ContainsAlias(text, squeezed, "camping", "camping")
        || ContainsAlias(text, squeezed, "camped", "camped");
}


bool MessageMentionsKilling(
    const char[] text,
    const char[] squeezed
)
{
    return ContainsAlias(text, squeezed, "kill", "kil")
        || ContainsAlias(text, squeezed, "kills", "kils")
        || ContainsAlias(text, squeezed, "killed", "kiled")
        || ContainsAlias(text, squeezed, "killer", "kiler")
        || ContainsAlias(text, squeezed, "killers", "kilers")
        || ContainsAlias(text, squeezed, "killing", "kiling");
}


bool MessageMentionsJoinedSpawnKill(
    const char[] text,
    const char[] squeezed
)
{
    return ContainsAlias(text, squeezed, "spawnkill", "spawnkil")
        || ContainsAlias(text, squeezed, "spawnkiller", "spawnkiler")
        || ContainsAlias(text, squeezed, "spawnkilling", "spawnkiling");
}


bool MessageHasSpawnCalloutLanguage(
    const char[] text,
    const char[] squeezed
)
{
    return ContainsAlias(text, squeezed, "near", "near")
        || ContainsAlias(text, squeezed, "at", "at")
        || ContainsAlias(text, squeezed, "by", "by")
        || ContainsAlias(text, squeezed, "check", "check")
        || ContainsAlias(text, squeezed, "go", "go")
        || ContainsAlias(text, squeezed, "watch", "watch")
        || ContainsAlias(text, squeezed, "enemy", "enemy")
        || ContainsAlias(text, squeezed, "our", "our")
        || ContainsAlias(text, squeezed, "their", "their");
}


bool ContainsAlias(
    const char[] text,
    const char[] squeezed,
    const char[] alias,
    const char[] squeezedAlias
)
{
    return ContainsWholeWord(text, alias)
        || ContainsWholeWord(squeezed, squeezedAlias);
}


bool ContainsWholeWord(
    const char[] text,
    const char[] word
)
{
    int textLength = strlen(text);
    int wordLength = strlen(word);

    if (wordLength == 0 || wordLength > textLength)
    {
        return false;
    }

    for (int start = 0; start <= textLength - wordLength; start++)
    {
        bool matches = true;

        for (int offset = 0; offset < wordLength; offset++)
        {
            if (text[start + offset] != word[offset])
            {
                matches = false;
                break;
            }
        }

        if (!matches)
        {
            continue;
        }

        bool leftBoundary = start == 0 || !IsAsciiWordCharacter(text[start - 1]);
        int after = start + wordLength;
        bool rightBoundary = after >= textLength || !IsAsciiWordCharacter(text[after]);

        if (leftBoundary && rightBoundary)
        {
            return true;
        }
    }

    return false;
}


bool IsAsciiWordCharacter(int character)
{
    return (character >= 'a' && character <= 'z')
        || (character >= 'A' && character <= 'Z')
        || (character >= '0' && character <= '9')
        || character == '_';
}


void LowercaseAscii(char[] text)
{
    for (int i = 0; text[i] != '\0'; i++)
    {
        if (text[i] >= 'A' && text[i] <= 'Z')
        {
            text[i] = text[i] + ('a' - 'A');
        }
    }
}


void CollapseRepeatedAscii(
    const char[] input,
    char[] output,
    int maxLength
)
{
    int write = 0;
    int previous = -1;

    for (int read = 0; input[read] != '\0' && write < maxLength - 1; read++)
    {
        int current = input[read];

        // Compress repeated ASCII letters only. UTF-8 player chat is otherwise
        // copied byte-for-byte and cannot be damaged by this normalization.
        bool asciiLetter = current >= 'a' && current <= 'z';

        if (asciiLetter && current == previous)
        {
            continue;
        }

        output[write++] = current;
        previous = asciiLetter ? current : -1;
    }

    output[write] = '\0';
}


bool TryGetRecentKiller(
    int victim,
    int &killer
)
{
    killer = 0;

    if (!IsValidHuman(victim) || g_RecentKillerUserId[victim] <= 0)
    {
        return false;
    }

    float age = GetGameTime() - g_RecentDeathTime[victim];

    if (age < 0.0 || age > g_CvarDeathContextWindow.FloatValue)
    {
        ClearDeathContext(victim);
        return false;
    }

    killer = GetClientOfUserId(g_RecentKillerUserId[victim]);

    if (!IsValidHuman(killer) || killer == victim)
    {
        ClearDeathContext(victim);
        killer = 0;
        return false;
    }

    return true;
}


void ResetTransientState()
{
    g_NextGlobalReplyTime = 0.0;

    for (int client = 1; client <= MaxClients; client++)
    {
        ResetClientState(client);
    }
}


void ResetClientState(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    g_NextClientReplyTime[client] = 0.0;
    ClearDeathContext(client);
}


void ClearDeathContext(int client)
{
    if (client < 1 || client > MaxClients)
    {
        return;
    }

    g_RecentKillerUserId[client] = 0;
    g_RecentDeathTime[client] = 0.0;
}


bool IsValidHuman(int client)
{
    return client >= 1
        && client <= MaxClients
        && IsClientInGame(client)
        && !IsFakeClient(client);
}
