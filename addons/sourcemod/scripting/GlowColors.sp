#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <regex>
#include <multicolors>
#include <glowcolors>

#undef REQUIRE_PLUGIN
#tryinclude <zombiereloaded>
#tryinclude <vip_core>
#define REQUIRE_PLUGIN

#pragma semicolon 1
#pragma newdecls required

#define CHAT_PREFIX "{green}[SM]{default}"

public Plugin myinfo =
{
    name = "GlowColors & Master Chief colors",
    author = "BotoX, inGame, .Rushaway, +SyntX",
    description = "Change your clients colors.",
    version = GlowColors_VERSION,
    url = "https://github.com/srcdslab/sm-plugin-GlowColors"
}

Menu 
    g_GlowColorsMenu;

Handle 
    g_hClientCookie = INVALID_HANDLE,
    g_hClientCookieRainbow = INVALID_HANDLE,
    g_hClientFrequency = INVALID_HANDLE,
    g_Cvar_PluginTimer = INVALID_HANDLE,
    g_hClientCookieEnabled = INVALID_HANDLE;

ConVar 
    g_Cvar_PluginEnabled,
    g_Cvar_RequiredFlags,
    g_Cvar_MinBrightness,
    g_Cvar_MinRainbowFrequency,
    g_Cvar_MaxRainbowFrequency,
    g_Cvar_DebugMode,
    g_Cvar_RestoreTimer;

Regex 
    g_Regex_RGB,
    g_Regex_HEX;

int 
    g_aGlowColor[MAXPLAYERS + 1][3];

float 
    g_aRainbowFrequency[MAXPLAYERS + 1];

bool 
    g_bRainbowEnabled[MAXPLAYERS+1] = {false,...},
    g_Plugin_ZR = false,
    g_Plugin_VIP = false,
    g_bSettingsRestored[MAXPLAYERS + 1] = {false, ...};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    CreateNative("GlowColors_SetRainbow", Native_SetRainbow);
    CreateNative("GlowColors_RemoveRainbow", Native_RemoveRainbow);

    RegPluginLibrary("glowcolors");
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_Cvar_PluginEnabled = CreateConVar("sm_glowcolors_enabled", "1", "Enable/disable the GlowColors plugin", FCVAR_NONE, true, 0.0, true, 1.0);
    g_Cvar_RequiredFlags = CreateConVar("sm_glowcolors_flags", "a", "Admin flags required to use glowcolors (empty = all players can use)");
    g_Cvar_RestoreTimer = CreateConVar("sm_restore_glowcolors", "10.0", "Seconds to wait before restoring glow settings", FCVAR_NONE, true, 0.5, true, 10.0);
    
    g_hClientCookie = RegClientCookie("glowcolor", "Player glowcolor", CookieAccess_Protected);
    g_hClientCookieRainbow = RegClientCookie("rainbow", "Rainbow status", CookieAccess_Protected);
    g_hClientFrequency = RegClientCookie("rainbow_frequency", "Rainbow frequency", CookieAccess_Protected);
    g_hClientCookieEnabled = RegClientCookie("glowcolor_enabled", "Glow color enabled status", CookieAccess_Protected);

    SetCookieMenuItem(CookieMenuHandler_GlowEnabled, 0, "Glow Enabled");
    SetCookieMenuItem(CookieMenuHandler_GlowColor, 0, "Glow Color");

    g_Regex_RGB = CompileRegex("^(([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])\\s+){2}([01]?[0-9]?[0-9]|2[0-4][0-9]|25[0-5])$");
    g_Regex_HEX = CompileRegex("^(#?)([A-Fa-f0-9]{6})$");

    RegConsoleCmd("sm_glowcolors", Command_GlowColors, "Change your players glowcolor.");
    RegConsoleCmd("sm_glowcolours", Command_GlowColors, "Change your players glowcolor.");
    RegConsoleCmd("sm_glowcolor", Command_GlowColors, "Change your players glowcolor.");
    RegConsoleCmd("sm_glowcolour", Command_GlowColors, "Change your players glowcolor.");
    RegConsoleCmd("sm_colors", Command_GlowColors, "Change your players glowcolor.");
    RegConsoleCmd("sm_colours", Command_GlowColors, "Change your players glowcolor.");
    RegConsoleCmd("sm_color", Command_GlowColors, "Change your players glowcolor.");
    RegConsoleCmd("sm_colour", Command_GlowColors, "Change your players glowcolor.");
    RegConsoleCmd("sm_glow", Command_GlowColors, "Change your players glowcolor.");
    RegConsoleCmd("sm_mccmenu", Command_GlowColors, "Change your MasterChief color.");
    RegConsoleCmd("sm_rainbow", Command_Rainbow, "Enable rainbow glowcolors. sm_rainbow [frequency]");

    RegAdminCmd("sm_glowprefs", Command_GlowPrefs, ADMFLAG_GENERIC, "Open glow color preferences menu");

    HookEvent("player_disconnect", Event_ClientDisconnect, EventHookMode_Pre);
    HookEvent("player_spawn", Event_ApplyGlowcolor, EventHookMode_Post);
    HookEvent("player_team", Event_ApplyGlowcolor, EventHookMode_Post);

    g_Cvar_MinBrightness = CreateConVar("sm_glowcolor_minbrightness", "100", "Lowest brightness value for glowcolor.", 0, true, 0.0, true, 255.0);
    g_Cvar_PluginTimer = CreateConVar("sm_glowcolors_timer", "5.0", "When the colors should spawn again (in seconds)");
    g_Cvar_MinRainbowFrequency = CreateConVar("sm_glowcolors_minrainbowfrequency", "1.0", "Lowest frequency value for rainbow glowcolors.", 0, true, 0.1);
    g_Cvar_MaxRainbowFrequency = CreateConVar("sm_glowcolors_maxrainbowfrequency", "10.0", "Highest frequency value for rainbow glowcolors.", 0, true, 0.1);
    g_Cvar_DebugMode = CreateConVar("sm_glowcolors_debug", "1", "Enable debug logging (0 = off, 1 = on)", FCVAR_NONE, true, 0.0, true, 1.0);

    LoadConfig();
    LoadTranslations("GlowColors.phrases");

    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client) && !IsFakeClient(client) && AreClientCookiesCached(client))
        {
            g_bSettingsRestored[client] = false;
            CreateTimer(g_Cvar_RestoreTimer.FloatValue, Timer_RestoreGlowSettings, GetClientSerial(client));
        }
    }

    AutoExecConfig(true);
}

public void OnAllPluginsLoaded()
{
    g_Plugin_ZR = LibraryExists("zombiereloaded");
    g_Plugin_VIP = LibraryExists("vip_core");
}

public void OnLibraryAdded(const char[] sName)
{
    if (strcmp(sName, "zombiereloaded", false) == 0)
        g_Plugin_ZR = true;
    if (strcmp(sName, "vip_core", false) == 0)
        g_Plugin_VIP = true;
}

public void OnLibraryRemoved(const char[] sName)
{
    if (strcmp(sName, "zombiereloaded", false) == 0)
        g_Plugin_ZR = false;
    if (strcmp(sName, "vip_core", false) == 0)
        g_Plugin_VIP = false;
}

public void OnPluginEnd()
{
    for(int client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client) && !IsFakeClient(client) && AreClientCookiesCached(client))
        {
            OnClientDisconnect(client);
        }
    }

    delete g_GlowColorsMenu;
    CloseHandle(g_hClientCookie);
    CloseHandle(g_hClientCookieRainbow);
    CloseHandle(g_hClientFrequency);
    CloseHandle(g_hClientCookieEnabled);
}

void LoadConfig()
{
    char sConfigFile[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, sConfigFile, sizeof(sConfigFile), "configs/GlowColors.cfg");
    if(!FileExists(sConfigFile))
    {
        SetFailState("Could not find config: \"%s\"", sConfigFile);
    }

    KeyValues Config = new KeyValues("GlowColors");
    if(!Config.ImportFromFile(sConfigFile))
    {
        delete Config;
        SetFailState("ImportFromFile() failed!");
    }
    if(!Config.GotoFirstSubKey(false))
    {
        delete Config;
        SetFailState("GotoFirstSubKey() failed!");
    }

    g_GlowColorsMenu = new Menu(MenuHandler_GlowColorsMenu, MenuAction_Select);
    g_GlowColorsMenu.SetTitle("GlowColors");
    g_GlowColorsMenu.ExitButton = true;

    g_GlowColorsMenu.AddItem("255 255 255", "None");

    char sKey[32];
    char sValue[16];
    int colorCount = 1;
    do
    {
        Config.GetSectionName(sKey, sizeof(sKey));
        Config.GetString(NULL_STRING, sValue, sizeof(sValue));
        g_GlowColorsMenu.AddItem(sValue, sKey);
        colorCount++;
    }
    while(Config.GotoNextKey(false));

    if(g_Cvar_DebugMode.BoolValue)
        PrintToServer("[GlowColors Debug] Loaded %d colors from config file", colorCount);
    
    delete Config;
}

public void OnClientConnected(int client)
{
    g_aGlowColor[client][0] = 255;
    g_aGlowColor[client][1] = 255;
    g_aGlowColor[client][2] = 255;
    g_aRainbowFrequency[client] = 0.0;
    g_bRainbowEnabled[client] = false;
    g_bSettingsRestored[client] = false;
}

public void OnClientCookiesCached(int client)
{
    if(IsClientAuthorized(client))
    {
        CreateTimer(g_Cvar_RestoreTimer.FloatValue, Timer_RestoreGlowSettings, GetClientSerial(client));
    }
}

public Action Timer_RestoreGlowSettings(Handle timer, int serial)
{
    int client = GetClientFromSerial(serial);
    if (!client || !IsClientInGame(client) || !AreClientCookiesCached(client))
        return Plugin_Continue;

    if (!IsPlayerAlive(client))
    {
        CreateTimer(5.0, Timer_WaitForAlive, GetClientSerial(client), TIMER_REPEAT);
        return Plugin_Continue;
    }

    RestoreGlowSettings(client);
    g_bSettingsRestored[client] = true;
    return Plugin_Continue;
}

public Action Timer_WaitForAlive(Handle timer, int serial)
{
    int client = GetClientFromSerial(serial);
    if (!client || !IsClientInGame(client) || !AreClientCookiesCached(client))
        return Plugin_Stop;

    if (IsPlayerAlive(client))
    {
        RestoreGlowSettings(client);
        g_bSettingsRestored[client] = true;
        return Plugin_Stop;
    }

    return Plugin_Continue;
}

void RestoreGlowSettings(int client)
{
    if (!IsClientValid(client) || !AreClientCookiesCached(client) || !IsPlayerAlive(client))
        return;

    bool hasAccess = CheckClientAccess(client);
    
    if (hasAccess)
    {
        char sCookie[16];
        GetClientCookie(client, g_hClientCookie, sCookie, sizeof(sCookie));
        if (strlen(sCookie) > 0)
            ColorStringToArray(sCookie, g_aGlowColor[client]);
            
        GetClientCookie(client, g_hClientCookieRainbow, sCookie, sizeof(sCookie));
        if (strlen(sCookie) > 0)
            g_bRainbowEnabled[client] = StringToInt(sCookie) == 1;
            
        GetClientCookie(client, g_hClientFrequency, sCookie, sizeof(sCookie));
        if (strlen(sCookie) > 0)
            g_aRainbowFrequency[client] = StringToFloat(sCookie);
            
        if (g_bRainbowEnabled[client])
            StartRainbow(client, g_aRainbowFrequency[client]);
        else
            ApplyGlowColor(client);

        if (g_Cvar_DebugMode.BoolValue)
        {
            char authId[32];
            GetClientAuthId(client, AuthId_Steam2, authId, sizeof(authId));
            PrintToServer("[GlowColors Debug] Restored and applied settings for %N (%s): R:%d G:%d B:%d, Rainbow:%d, Freq:%.1f",
                client, authId, g_aGlowColor[client][0], g_aGlowColor[client][1], g_aGlowColor[client][2],
                g_bRainbowEnabled[client], g_aRainbowFrequency[client]);
        }
    }
    else
    {
        SetClientCookie(client, g_hClientCookieEnabled, "0");
        SetClientCookie(client, g_hClientCookieRainbow, "0");
        SetClientCookie(client, g_hClientFrequency, "0.0");
        SetClientCookie(client, g_hClientCookie, "255 255 255");
        
        g_aGlowColor[client][0] = 255;
        g_aGlowColor[client][1] = 255;
        g_aGlowColor[client][2] = 255;
        g_bRainbowEnabled[client] = false;
        g_aRainbowFrequency[client] = 0.0;
        
        StopRainbow(client);
        SetEntityRenderMode(client, RENDER_NORMAL);
        SetEntityRenderColor(client, 255, 255, 255, 255);
        
        if (g_Cvar_DebugMode.BoolValue)
        {
            char authId[32];
            GetClientAuthId(client, AuthId_Steam2, authId, sizeof(authId));
            PrintToServer("[GlowColors Debug] Forced disabled glow for %N (%s) - no access", client, authId);
        }
    }
}

public void OnClientDisconnect(int client)
{
    if(!client || !IsClientInGame(client) || IsFakeClient(client))
        return;

    char sCookie[16];
    FormatEx(sCookie, sizeof(sCookie), "%d %d %d", g_aGlowColor[client][0], g_aGlowColor[client][1], g_aGlowColor[client][2]);
    SetClientCookie(client, g_hClientCookie, sCookie);
    FormatEx(sCookie, sizeof(sCookie), "%d", g_bRainbowEnabled[client]);
    SetClientCookie(client, g_hClientCookieRainbow, sCookie);
    FormatEx(sCookie, sizeof(sCookie), "%0.1f", g_aRainbowFrequency[client]);
    SetClientCookie(client, g_hClientFrequency, sCookie);
    
    char enabled[4];
    GetClientCookie(client, g_hClientCookieEnabled, enabled, sizeof(enabled));
    SetClientCookie(client, g_hClientCookieEnabled, enabled);
    
    StopRainbow(client);
}

void CheckAndDisableGlow(int client)
{
    if (!IsClientInGame(client) || !g_bSettingsRestored[client])
        return;

    bool hasAccess = CheckClientAccess(client);
    char enabled[4];
    GetClientCookie(client, g_hClientCookieEnabled, enabled, sizeof(enabled));
    bool isEnabled = StringToInt(enabled) == 1;

    if (isEnabled && !hasAccess)
    {
        SetClientCookie(client, g_hClientCookieEnabled, "0");
        SetClientCookie(client, g_hClientCookieRainbow, "0");
        SetClientCookie(client, g_hClientFrequency, "0.0");
        SetClientCookie(client, g_hClientCookie, "255 255 255");
        
        g_aGlowColor[client][0] = 255;
        g_aGlowColor[client][1] = 255;
        g_aGlowColor[client][2] = 255;
        
        StopRainbow(client);
        SetEntityRenderMode(client, RENDER_NORMAL);
        SetEntityRenderColor(client, 255, 255, 255, 255);
        
        if (g_Cvar_DebugMode.BoolValue)
        {
            char authId[32];
            GetClientAuthId(client, AuthId_Steam2, authId, sizeof(authId));
            PrintToServer("[GlowColors Debug] Auto-disabled glow for %N (%s) due to lost access", client, authId);
        }
        
        CPrintToChat(client, "%s Your glow effects have been disabled due to lost VIP/admin access.", CHAT_PREFIX);
    }
}

public void CookieMenuHandler_GlowEnabled(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
    if (action == CookieMenuAction_DisplayOption)
    {
        char enabled[4];
        GetClientCookie(client, g_hClientCookieEnabled, enabled, sizeof(enabled));
        bool isEnabled = StringToInt(enabled) == 1;
        bool hasAccess = CheckClientAccess(client);
        
        Format(buffer, maxlen, "Glow Enabled: %s%s", isEnabled ? "Yes" : "No", hasAccess ? "" : " [No Access]");
        if (!hasAccess)
            strcopy(buffer, maxlen, "Glow Enabled: Locked [No Access]");
    }
    else if (action == CookieMenuAction_SelectOption)
    {
        if (CheckClientAccess(client))
        {
            char enabled[4];
            GetClientCookie(client, g_hClientCookieEnabled, enabled, sizeof(enabled));
            bool isEnabled = StringToInt(enabled) == 1;
            SetClientCookie(client, g_hClientCookieEnabled, isEnabled ? "0" : "1");
            
            if (!isEnabled)
                ApplyGlowColor(client);
            else
            {
                StopRainbow(client);
                SetEntityRenderMode(client, RENDER_NORMAL);
            }
                
            if (g_Cvar_DebugMode.BoolValue)
                PrintToServer("[GlowColors Debug] %N toggled glow %s via cookie menu", client, isEnabled ? "off" : "on");
                    
            ShowCookieMenu(client);
        }
        else
            CPrintToChat(client, "%s You don't have access to modify glow settings.", CHAT_PREFIX);
    }
}

public void CookieMenuHandler_GlowColor(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
    if (action == CookieMenuAction_DisplayOption)
    {
        char enabled[4];
        GetClientCookie(client, g_hClientCookieEnabled, enabled, sizeof(enabled));
        bool isEnabled = StringToInt(enabled) == 1;
        bool hasAccess = CheckClientAccess(client);
        
        if (hasAccess && isEnabled)
            Format(buffer, maxlen, "Glow Color: #%02X%02X%02X", g_aGlowColor[client][0], g_aGlowColor[client][1], g_aGlowColor[client][2]);
        else
            strcopy(buffer, maxlen, "Glow Color: Locked [Disabled/No Access]");
    }
    else if (action == CookieMenuAction_SelectOption)
    {
        char enabled[4];
        GetClientCookie(client, g_hClientCookieEnabled, enabled, sizeof(enabled));
        bool isEnabled = StringToInt(enabled) == 1;
        
        if (CheckClientAccess(client) && isEnabled)
            DisplayGlowColorMenu(client);
        else
            CPrintToChat(client, "%s Enable glow and have proper access to change colors.", CHAT_PREFIX);
    }
}

public void OnPostThinkPost(int client)
{
    if (!CheckClientAccess(client))
    {
        CheckAndDisableGlow(client);
        return;
    }

    float i = GetGameTime();
    float Frequency = g_aRainbowFrequency[client];
    int Red = RoundFloat(Sine(Frequency * i + 0.0) * 127.0 + 128.0);
    int Green = RoundFloat(Sine(Frequency * i + 2.0943951) * 127.0 + 128.0);
    int Blue = RoundFloat(Sine(Frequency * i + 4.1887902) * 127.0 + 128.0);

    ToolsSetEntityColor(client, Red, Green, Blue);
}

public Action Command_GlowPrefs(int client, int args)
{
    if (!g_Cvar_PluginEnabled.BoolValue)
    {
        CPrintToChat(client, "%s Glow colors are currently disabled.", CHAT_PREFIX);
        return Plugin_Handled;
    }

    if (!CheckClientAccess(client))
    {
        CPrintToChat(client, "%s You don't have access to this command.", CHAT_PREFIX);
        CheckAndDisableGlow(client);
        return Plugin_Handled;
    }

    ShowPreferencesMenu(client);
    return Plugin_Handled;
}

void ShowPreferencesMenu(int client)
{
    Menu menu = new Menu(MenuHandler_Preferences);
    menu.SetTitle("Glow Color Preferences");
    
    char buffer[128];
    bool hasAccess = CheckClientAccess(client);
    char enabled[4];
    GetClientCookie(client, g_hClientCookieEnabled, enabled, sizeof(enabled));
    bool isEnabled = StringToInt(enabled) == 1;
    
    Format(buffer, sizeof(buffer), "Enable Glow: %s", isEnabled ? "Yes" : "No");
    menu.AddItem("enable", buffer, hasAccess ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    
    Format(buffer, sizeof(buffer), "Glow Color: \x07%02X%02X%02XCurrent", g_aGlowColor[client][0], g_aGlowColor[client][1], g_aGlowColor[client][2]);
    menu.AddItem("color", buffer, hasAccess && isEnabled ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    
    Format(buffer, sizeof(buffer), "Rainbow Mode: %s", g_bRainbowEnabled[client] ? "Enabled" : "Disabled");
    menu.AddItem("rainbow", buffer, hasAccess && isEnabled ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    
    if (g_bRainbowEnabled[client])
    {
        Format(buffer, sizeof(buffer), "Rainbow Frequency: %.1f", g_aRainbowFrequency[client]);
        menu.AddItem("frequency", buffer, hasAccess && isEnabled ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    }
    
    menu.ExitButton = true;
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Preferences(Menu menu, MenuAction action, int client, int param2)
{
    if (action == MenuAction_Select)
    {
        char info[32];
        menu.GetItem(param2, info, sizeof(info));
        
        if (StrEqual(info, "enable"))
        {
            char enabled[4];
            GetClientCookie(client, g_hClientCookieEnabled, enabled, sizeof(enabled));
            bool isEnabled = StringToInt(enabled) == 1;
            SetClientCookie(client, g_hClientCookieEnabled, isEnabled ? "0" : "1");
            
            if(g_Cvar_DebugMode.BoolValue)
                PrintToServer("[GlowColors Debug] %N toggled glow %s", client, isEnabled ? "off" : "on");
                
            if(!isEnabled) 
                ApplyGlowColor(client);
            else
                StopRainbow(client);
            ShowPreferencesMenu(client);
        }
        else if (StrEqual(info, "color"))
        {
            DisplayGlowColorMenu(client);
        }
        else if (StrEqual(info, "rainbow"))
        {
            if (CheckClientAccess(client))
            {
                g_bRainbowEnabled[client] = !g_bRainbowEnabled[client];
                if (g_bRainbowEnabled[client])
                    StartRainbow(client, g_aRainbowFrequency[client] > 0 ? g_aRainbowFrequency[client] : 1.0);
                else
                {
                    StopRainbow(client);
                    ApplyGlowColor(client);
                }
                ShowPreferencesMenu(client);
            }
            else
            {
                CPrintToChat(client, "%s You lost access to rainbow mode.", CHAT_PREFIX);
                CheckAndDisableGlow(client);
            }
        }
        else if (StrEqual(info, "frequency"))
        {
            CPrintToChat(client, "%s Type !rainbow <frequency> to change rainbow frequency.", CHAT_PREFIX);
            ShowPreferencesMenu(client);
        }
    }
    else if (action == MenuAction_End)
    {
        delete menu;
    }
    return 0;
}

public Action Command_GlowColors(int client, int args)
{
    if (!g_Cvar_PluginEnabled.BoolValue)
    {
        CPrintToChat(client, "%s Glow colors are currently disabled.", CHAT_PREFIX);
        return Plugin_Handled;
    }

    if (!CheckClientAccess(client))
    {
        CPrintToChat(client, "%s You don't have access to this command.", CHAT_PREFIX);
        CheckAndDisableGlow(client);
        return Plugin_Handled;
    }

    if(args < 1)
    {
        DisplayGlowColorMenu(client);
        return Plugin_Handled;
    }

    int Color;
    if(args == 1)
    {
        char sColorString[32];
        GetCmdArgString(sColorString, sizeof(sColorString));

        if(!IsValidHex(sColorString))
        {
            CPrintToChat(client, "%s Invalid HEX color code supplied.", CHAT_PREFIX);
            return Plugin_Handled;
        }

        Color = StringToInt(sColorString, 16);
        g_aGlowColor[client][0] = (Color >> 16) & 0xFF;
        g_aGlowColor[client][1] = (Color >> 8) & 0xFF;
        g_aGlowColor[client][2] = (Color >> 0) & 0xFF;
    }
    else if(args == 3)
    {
        char sColorString[32];
        GetCmdArgString(sColorString, sizeof(sColorString));

        if(!IsValidRGBNum(sColorString))
        {
            CPrintToChat(client, "%s Invalid RGB color code supplied.", CHAT_PREFIX);
            return Plugin_Handled;
        }

        ColorStringToArray(sColorString, g_aGlowColor[client]);
        Color = (g_aGlowColor[client][0] << 16) + (g_aGlowColor[client][1] << 8) + (g_aGlowColor[client][2] << 0);
    }
    else
    {
        char sCommand[32];
        GetCmdArg(0, sCommand, sizeof(sCommand));
        CPrintToChat(client, "%s Usage: %s <RRGGBB HEX | 0-255 0-255 0-255 RGB CODE>", CHAT_PREFIX, sCommand);
        return Plugin_Handled;
    }

    if(!ApplyGlowColor(client))
        return Plugin_Handled;

    if(GetCmdReplySource() == SM_REPLY_TO_CHAT)
    {
        StopRainbow(client);
        CPrintToChat(client, "%s \x07%06X Set color to: %06X", CHAT_PREFIX, Color, Color);    
    }
    return Plugin_Handled;
}

public Action Command_Rainbow(int client, int args)
{
    if (!g_Cvar_PluginEnabled.BoolValue)
    {
        CPrintToChat(client, "%s Glow colors are currently disabled.", CHAT_PREFIX);
        return Plugin_Handled;
    }

    if (!CheckClientAccess(client))
    {
        CPrintToChat(client, "%s You don't have access to this command.", CHAT_PREFIX);
        CheckAndDisableGlow(client);
        return Plugin_Handled;
    }

    float Frequency = 1.0;
    if(args >= 1)
    {
        char sArg[32];
        GetCmdArg(1, sArg, sizeof(sArg));
        Frequency = StringToFloat(sArg);
    }

    if(!Frequency || (args < 1 && g_aRainbowFrequency[client]))
    {
        StopRainbow(client);
        CPrintToChat(client, "%s{olive} Disabled {default}rainbow glowcolors.", CHAT_PREFIX);
        ApplyGlowColor(client);
    }
    else
    {
        StartRainbow(client, Frequency);
        CPrintToChat(client, "%s{olive} Enabled {default}rainbow glowcolors. (Frequency = {olive}%0.1f{default})", CHAT_PREFIX, Frequency);
    }
    return Plugin_Handled;
}

void DisplayGlowColorMenu(int client)
{
    if (!CheckClientAccess(client))
    {
        CPrintToChat(client, "%s You don't have access to this command.", CHAT_PREFIX);
        CheckAndDisableGlow(client);
        return;
    }

    if (IsClientInGame(client) && !IsPlayerAlive(client))
    {       
        CPrintToChat(client, "%T", "NotAlive", client);
        return;
    }
#if defined _zr_included
    if (g_Plugin_ZR && IsClientInGame(client) && IsPlayerAlive(client) && ZR_IsClientZombie(client))
    {   
        CPrintToChat(client, "%T", "Zombie", client);
        return;
    }
    if (g_Plugin_ZR && view_as<bool>(ZR_GetActiveClass(client) != ZR_GetClassByName("Master Chief")) && !ZR_IsClientZombie(client))
    {   
        CPrintToChat(client, "%T", "WrongModel", client);
        return;
    }
#endif
    g_GlowColorsMenu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_GlowColorsMenu(Menu menu, MenuAction action, int param1, int param2)
{
    switch(action)
    {
        case MenuAction_Select:
        {
            if (!CheckClientAccess(param1))
            {
                CheckAndDisableGlow(param1);
                CPrintToChat(param1, "%s Your access to glow colors was removed.", CHAT_PREFIX);
                return 0;
            }

            char aItem[16];
            menu.GetItem(param2, aItem, sizeof(aItem));
            ColorStringToArray(aItem, g_aGlowColor[param1]);
            int Color = (g_aGlowColor[param1][0] << 16) + (g_aGlowColor[param1][1] << 8) + (g_aGlowColor[param1][2] << 0);

            StopRainbow(param1);
            ApplyGlowColor(param1);
            
            if(g_Cvar_DebugMode.BoolValue)
            {
                char authId[32];
                GetClientAuthId(param1, AuthId_Steam2, authId, sizeof(authId));
                PrintToServer("[GlowColors Debug] %N (%s) selected color from menu: R:%d G:%d B:%d",
                    param1, authId, g_aGlowColor[param1][0], g_aGlowColor[param1][1], g_aGlowColor[param1][2]);
            }

            CPrintToChat(param1, "%s \x07%06X Set color to: %06X", CHAT_PREFIX, Color, Color);
        }
    }
    return 0;
}

public void Event_ClientDisconnect(Handle event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    if(!client)
        return;

    g_bRainbowEnabled[client] = false;
    OnClientDisconnect(client);
}

public void Event_ApplyGlowcolor(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(GetEventInt(event, "userid"));
    if(!client)
        return;

    CheckAndDisableGlow(client);
    CreateTimer(GetConVarFloat(g_Cvar_PluginTimer), Timer_ApplyGlowColor, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ApplyGlowColor(Handle timer, int serial)
{
    int client = GetClientFromSerial(serial);
    if(client)
    {
        CheckAndDisableGlow(client);
        if (g_bRainbowEnabled[client])
            StartRainbow(client, g_aRainbowFrequency[client]);
        else
            ApplyGlowColor(client);
    }
    return Plugin_Continue;
}

public int ZR_OnClientInfected(int client, int attacker, bool motherInfect, bool respawnOverride, bool respawn)
{
    ApplyGlowColor(client);
    return Plugin_Continue;
}

public int ZR_OnClientHumanPost(int client, bool respawn, bool protect)
{
    ApplyGlowColor(client);
    return Plugin_Continue;
}

bool ApplyGlowColor(int client)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
    {
        if (g_Cvar_DebugMode.BoolValue)
            PrintToServer("[GlowColors Debug] Failed to apply glow for %N - not in game or not alive", client);
        return false;
    }

    if (!g_bSettingsRestored[client]) // Skip if settings not restored yet
        return false;

    char enabled[4];
    GetClientCookie(client, g_hClientCookieEnabled, enabled, sizeof(enabled));
    bool isEnabled = StringToInt(enabled) == 1;

    bool hasAccess = CheckClientAccess(client);
    if (!isEnabled || !hasAccess)
    {
        CheckAndDisableGlow(client);
        return false;
    }

    int Brightness = ColorBrightness(g_aGlowColor[client][0], g_aGlowColor[client][1], g_aGlowColor[client][2]);
    if (Brightness < g_Cvar_MinBrightness.IntValue)
    {
        CPrintToChat(client, "%s Your glowcolor is too dark! (brightness = {red}%d{default}/255, allowed values are {green}> %d{default})", 
            CHAT_PREFIX, Brightness, g_Cvar_MinBrightness.IntValue - 1);
        
        g_aGlowColor[client][0] = 255;
        g_aGlowColor[client][1] = 255;
        g_aGlowColor[client][2] = 255;
        
        char sCookie[16];
        FormatEx(sCookie, sizeof(sCookie), "%d %d %d", 255, 255, 255);
        SetClientCookie(client, g_hClientCookie, sCookie);
        
        if (g_Cvar_DebugMode.BoolValue)
            PrintToServer("[GlowColors Debug] Color too dark for %N - reset to white", client);
    }

#if defined _zr_included
    if (g_Plugin_ZR && ZR_IsClientZombie(client) && !hasAccess)
    {
        SetEntityRenderMode(client, RENDER_NORMAL);
        SetEntityRenderColor(client, 255, 255, 255, 255);
        if (g_Cvar_DebugMode.BoolValue)
        {
            char authId[32];
            GetClientAuthId(client, AuthId_Steam2, authId, sizeof(authId));
            PrintToServer("[GlowColors Debug] Reset to default for %N (%s) - ZR zombie without VIP/admin access", client, authId);
        }
        return false;
    }

    if (g_Plugin_ZR && (ZR_GetActiveClass(client) == ZR_GetClassByName("Master Chief") || hasAccess))
    {
        SetEntityRenderMode(client, RENDER_GLOW);
        SetEntityRenderFx(client, RENDERFX_GLOWSHELL);
        SetEntityRenderColor(client, g_aGlowColor[client][0], g_aGlowColor[client][1], g_aGlowColor[client][2], 255);

        if (IsValidEntity(client))
        {
            SetEntProp(client, Prop_Send, "m_bGlowEnabled", 1);
            SetEntPropFloat(client, Prop_Send, "m_flGlowMaxDist", 2000.0);
        }

        if (g_Cvar_DebugMode.BoolValue)
        {
            char authId[32];
            GetClientAuthId(client, AuthId_Steam2, authId, sizeof(authId));
            PrintToServer("[GlowColors Debug] Applied glow for %N (%s): R:%d G:%d B:%d, Brightness:%d, MasterChief:%d",
                client, authId, g_aGlowColor[client][0], g_aGlowColor[client][1], g_aGlowColor[client][2],
                Brightness, ZR_GetActiveClass(client) == ZR_GetClassByName("Master Chief"));
        }
        return true;
    }
#else
    SetEntityRenderMode(client, RENDER_GLOW);
    SetEntityRenderFx(client, RENDERFX_GLOWSHELL);
    SetEntityRenderColor(client, g_aGlowColor[client][0], g_aGlowColor[client][1], g_aGlowColor[client][2], 255);

    if (IsValidEntity(client))
    {
        SetEntProp(client, Prop_Send, "m_bGlowEnabled", 1);
        SetEntPropFloat(client, Prop_Send, "m_flGlowMaxDist", 2000.0);
    }

    if (g_Cvar_DebugMode.BoolValue)
    {
        char authId[32];
        GetClientAuthId(client, AuthId_Steam2, authId, sizeof(authId));
        PrintToServer("[GlowColors Debug] Applied glow for %N (%s): R:%d G:%d B:%d, Brightness:%d",
            client, authId, g_aGlowColor[client][0], g_aGlowColor[client][1], g_aGlowColor[client][2], Brightness);
    }
    return true;
#endif

    return false;
}

stock void StopRainbow(int client)
{
    if(g_aRainbowFrequency[client])
    {
        g_bRainbowEnabled[client] = false;
        SDKUnhook(client, SDKHook_PostThinkPost, OnPostThinkPost);
        g_aRainbowFrequency[client] = 0.0;
        SetClientCookie(client, g_hClientCookieRainbow, "0");
        SetClientCookie(client, g_hClientFrequency, "0.0");
        
        if (g_Cvar_DebugMode.BoolValue)
            PrintToServer("[GlowColors Debug] Stopped rainbow for %N", client);
    }
}

stock void StartRainbow(int client, float Frequency)
{
    if (!CheckClientAccess(client))
    {
        CheckAndDisableGlow(client);
        return;
    }

    float MinFrequency = g_Cvar_MinRainbowFrequency.FloatValue;
    float MaxFrequency = g_Cvar_MaxRainbowFrequency.FloatValue;

    if (Frequency < MinFrequency)
        Frequency = MinFrequency;
    else if (Frequency > MaxFrequency)
        Frequency = MaxFrequency;

    g_aRainbowFrequency[client] = Frequency;
    SDKHook(client, SDKHook_PostThinkPost, OnPostThinkPost);

    g_bRainbowEnabled[client] = true;
    char sCookie[16];
    FormatEx(sCookie, sizeof(sCookie), "%d", g_bRainbowEnabled[client]);
    SetClientCookie(client, g_hClientCookieRainbow, sCookie);
    FormatEx(sCookie, sizeof(sCookie), "%0.1f", g_aRainbowFrequency[client]);
    SetClientCookie(client, g_hClientFrequency, sCookie);
}

stock void ToolsGetEntityColor(int entity, int aColor[4])
{
    static bool s_GotConfig = false;
    static char s_sProp[32];

    if(!s_GotConfig)
    {
        Handle GameConf = LoadGameConfigFile("core.games");
        bool Exists = GameConfGetKeyValue(GameConf, "m_clrRender", s_sProp, sizeof(s_sProp));
        CloseHandle(GameConf);

        if(!Exists)
            strcopy(s_sProp, sizeof(s_sProp), "m_clrRender");

        s_GotConfig = true;
    }

    int Offset = GetEntSendPropOffs(entity, s_sProp);
    for(int i = 0; i < 4; i++)
        aColor[i] = GetEntData(entity, Offset + i, 1);
}

stock void ToolsSetEntityColor(int client, int Red, int Green, int Blue)
{
    int aColor[4];
    ToolsGetEntityColor(client, aColor);
    SetEntityRenderColor(client, Red, Green, Blue, aColor[3]);
}

stock void ColorStringToArray(const char[] sColorString, int aColor[3])
{
    char asColors[4][4];
    ExplodeString(sColorString, " ", asColors, sizeof(asColors), sizeof(asColors[]));
    aColor[0] = StringToInt(asColors[0]) & 0xFF;
    aColor[1] = StringToInt(asColors[1]) & 0xFF;
    aColor[2] = StringToInt(asColors[2]) & 0xFF;
}

bool CheckClientAccess(int client)
{
    if (!IsClientValid(client) || !g_Cvar_PluginEnabled.BoolValue)
        return false;

    char sFlags[32];
    g_Cvar_RequiredFlags.GetString(sFlags, sizeof(sFlags));
    
    bool hasAccess = false;
    int userFlags = GetUserFlagBits(client);
    
    if (strlen(sFlags) == 0)
        hasAccess = true;
    else
    {
        int iFlags = ReadFlagString(sFlags);
        if (userFlags & iFlags)
            hasAccess = true;
    }
    
    if (g_Plugin_VIP && VIP_IsClientVIP(client))
        hasAccess = true;

    if(g_Cvar_DebugMode.BoolValue)
    {
        char authId[32];
        GetClientAuthId(client, AuthId_Steam2, authId, sizeof(authId));
        PrintToServer("[GlowColors Debug] Access check for %N (%s): Flags=%d, VIP=%d, HasAccess=%d, RequiredFlags=%s", 
            client, authId, userFlags, g_Plugin_VIP && VIP_IsClientVIP(client), hasAccess, sFlags);
    }

    return hasAccess;
}

stock bool IsValidRGBNum(char[] sString)
{
    return g_Regex_RGB.Match(sString) > 0;
}

stock bool IsValidHex(char[] sString)
{
    return g_Regex_HEX.Match(sString) > 0;
}

stock int ColorBrightness(int Red, int Green, int Blue)
{
    return RoundToFloor(SquareRoot(Red * Red * 0.241 + Green * Green + 0.691 + Blue * Blue + 0.068));
}

public int Native_SetRainbow(Handle hPlugins, int numParams) {
    int client = GetNativeCell(1);
    
    if (!IsClientValid(client) || !g_Cvar_PluginEnabled.BoolValue || !CheckClientAccess(client))
    {
        CheckAndDisableGlow(client);
        return 0;
    }

    g_aRainbowFrequency[client] = 1.0;
    return 0;
}

public int Native_RemoveRainbow(Handle hPlugins, int numParams) {
    int client = GetNativeCell(1);
    
    if (!IsClientValid(client) || !g_Cvar_PluginEnabled.BoolValue)
        return 0;

    g_aRainbowFrequency[client] = 0.0;
    return 0;
}

bool IsClientValid(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && !IsFakeClient(client));
}
