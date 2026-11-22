#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <ripext>
#include <gungame>

#define PLUGIN_VERSION "1.0.0"

// Limits of the winner page push contract (README)
#define MAX_RANKING 16
#define STEAMID64_PREFIX "7656119"

ConVar g_cvEnable;
ConVar g_cvPushUrl;
ConVar g_cvPushToken;
ConVar g_cvPageUrl;
ConVar g_cvServer;
ConVar g_cvTimeout;

int g_iMatchStart;
int g_iMatchSerial;
int g_iDeaths[MAXPLAYERS + 1];
int g_iHeadshots[MAXPLAYERS + 1];
int g_iKnifeSteals[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "GunGame Winner Screen",
	author = "Rushaway",
	description = "Sends the GunGame match result to a web page and opens it in every player's MOTD",
	version = PLUGIN_VERSION,
	url = "https://github.com/srcdslab/sm-plugin-GunGameWinnerScreen"
};

public void OnPluginStart()
{
	CreateConVar("sm_gg_winnerscreen_version", PLUGIN_VERSION, "GunGame Winner Screen version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cvEnable = CreateConVar("sm_gg_winnerscreen_enable", "1", "Push the result and open the winner screen when a GunGame match is won, 0 = off/1 = on", _, true, 0.0, true, 1.0);
	g_cvPushUrl = CreateConVar("sm_gg_winnerscreen_push_url", "", "HTTPS URL the match result is POSTed to (JSON)");
	// FCVAR_PROTECTED: clients never see the value in cvar queries
	g_cvPushToken = CreateConVar("sm_gg_winnerscreen_push_token", "", "Bearer token of the push URL. Set it on the server only, never commit it", FCVAR_PROTECTED);
	g_cvPageUrl = CreateConVar("sm_gg_winnerscreen_page_url", "", "Winner page opened in the MOTD of every player once the push succeeded");
	g_cvServer = CreateConVar("sm_gg_winnerscreen_server", "css_gg", "Server key sent in the push", _);
	g_cvTimeout = CreateConVar("sm_gg_winnerscreen_timeout", "5", "Seconds before the push is given up (the screen is not opened then)", _, true, 1.0, true, 30.0);
	AutoExecConfig(true);

	HookEvent("player_death", Event_PlayerDeath);
}

public void OnMapStart()
{
	// Plugin loaded mid-map or no GG_OnMatchStart yet: count from the map start
	g_iMatchStart = GetTime();
	ResetStats();
}

public void OnClientPutInServer(int client)
{
	g_iDeaths[client] = 0;
	g_iHeadshots[client] = 0;
	g_iKnifeSteals[client] = 0;
}

public void GG_OnMatchStart()
{
	g_iMatchStart = GetTime();
	ResetStats();
}

void ResetStats()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		g_iDeaths[i] = 0;
		g_iHeadshots[i] = 0;
		g_iKnifeSteals[i] = 0;
	}
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	if (!GG_IsMatchStarted() || GG_GetWinner())
		return;

	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));

	if (victim)
		g_iDeaths[victim]++;

	if (attacker && attacker != victim && event.GetBool("headshot"))
		g_iHeadshots[attacker]++;
}

public void GG_OnKnifeSteal(int killer, int victim, int killerLevel, int victimLevel, bool victimLost)
{
	if (killer > 0 && killer <= MaxClients)
		g_iKnifeSteals[killer]++;
}

/* ---------------------------------------------------------------------------------------------- */
/* Push                                                                                           */
/* ---------------------------------------------------------------------------------------------- */

public void GG_OnWinner(int client, const char[] Weapon, int victim)
{
	if (!g_cvEnable.BoolValue)
		return;

	char sUrl[512], sToken[256];
	g_cvPushUrl.GetString(sUrl, sizeof(sUrl));
	g_cvPushToken.GetString(sToken, sizeof(sToken));
	if (!sUrl[0] || !sToken[0])
	{
		LogError("sm_gg_winnerscreen_push_url or sm_gg_winnerscreen_push_token is empty, no winner screen");
		return;
	}

	char sMap[PLATFORM_MAX_PATH];
	GetMapName(sMap, sizeof(sMap));

	int iNow = GetTime();
	JSONObject payload = new JSONObject();
	char sServer[32];
	g_cvServer.GetString(sServer, sizeof(sServer));
	payload.SetInt("v", 1);
	payload.SetString("server", sServer);
	payload.SetInt("sent_at", iNow);
	payload.SetString("current_map", sMap);

	JSONObject match = new JSONObject();
	match.SetString("map", sMap);
	match.SetInt("started_at", g_iMatchStart < iNow ? g_iMatchStart : iNow - 1);
	match.SetInt("ended_at", iNow);

	JSONObject winner = BuildPlayer(client, true);
	match.Set("winner", winner);
	delete winner;

	int iClients[MAXPLAYERS];
	int iCount = GG_GetRanking(iClients, sizeof(iClients));
	if (iCount > MAX_RANKING)
		iCount = MAX_RANKING;

	JSONArray ranking = new JSONArray();
	for (int i = 0; i < iCount; i++)
	{
		JSONObject entry = BuildPlayer(iClients[i], false);
		ranking.Push(entry);
		delete entry;
	}
	match.Set("ranking", ranking);
	delete ranking;

	payload.Set("match", match);
	delete match;

	HTTPRequest request = new HTTPRequest(sUrl);
	request.SetHeader("Authorization", "Bearer %s", sToken);
	request.Timeout = g_cvTimeout.IntValue;
	request.Post(payload, OnPushed, ++g_iMatchSerial);
	delete payload;
}

// Winner: steamid64, name, kills, deaths, headshots, knife_steals. Ranking entry: steamid64, name, bot, level, kills, deaths.
JSONObject BuildPlayer(int client, bool bWinner)
{
	JSONObject player = new JSONObject();

	char sSteamID[32], sName[MAX_NAME_LENGTH];
	GetSteamID64(client, sSteamID, sizeof(sSteamID));
	GetClientName(client, sName, sizeof(sName));

	player.SetString("steamid64", sSteamID);
	player.SetString("name", sName);
	player.SetInt("kills", GG_GetClientKills(client));
	player.SetInt("deaths", g_iDeaths[client]);

	if (bWinner)
	{
		player.SetInt("headshots", g_iHeadshots[client]);
		player.SetInt("knife_steals", g_iKnifeSteals[client]);
	}
	else
	{
		player.SetBool("bot", IsFakeClient(client));
		player.SetInt("level", GG_GetClientLevel(client));
	}

	return player;
}

// Empty for bots and for clients without a valid Steam ID (NoSteam): the page then shows the name only
void GetSteamID64(int client, char[] sBuffer, int iMaxLen)
{
	sBuffer[0] = '\0';
	if (IsFakeClient(client))
		return;

	if (!GetClientAuthId(client, AuthId_SteamID64, sBuffer, iMaxLen, true)
		|| strlen(sBuffer) != 17 || strncmp(sBuffer, STEAMID64_PREFIX, sizeof(STEAMID64_PREFIX) - 1) != 0)
	{
		sBuffer[0] = '\0';
	}
}

// Display name without the workshop path, as the page accepts it (^[A-Za-z0-9_-]{1,64}$)
void GetMapName(char[] sMap, int iMaxLen)
{
	char sPath[PLATFORM_MAX_PATH];
	GetCurrentMap(sPath, sizeof(sPath));
	if (!GetMapDisplayName(sPath, sMap, iMaxLen))
		strcopy(sMap, iMaxLen, sPath);
}

public void OnPushed(HTTPResponse response, any serial, const char[] error)
{
	if (response.Status != HTTPStatus_OK)
	{
		LogError("Winner push failed: HTTP %d %s", response.Status, error);
		return;
	}

	// A late answer from a previous match must not open an old screen
	if (serial != g_iMatchSerial)
		return;

	OpenWinnerScreen();
}

/* ---------------------------------------------------------------------------------------------- */
/* Winner screen                                                                                  */
/* ---------------------------------------------------------------------------------------------- */

void OpenWinnerScreen()
{
	char sPage[512];
	g_cvPageUrl.GetString(sPage, sizeof(sPage));
	if (!sPage[0])
		return;

	char sMap[PLATFORM_MAX_PATH];
	GetMapName(sMap, sizeof(sMap));
	if (!IsSafeMapName(sMap))
		sMap[0] = '\0';

	char sSteamID[32], sUrl[768];
	int iTime = GetTime();
	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientInGame(client) || IsFakeClient(client) || IsClientSourceTV(client))
			continue;

		GetSteamID64(client, sSteamID, sizeof(sSteamID));
		// t: changes for every match so the in-game browser never shows a cached older screen
		FormatEx(sUrl, sizeof(sUrl), "%s%ss=%s&m=%s&t=%d", sPage, StrContains(sPage, "?") == -1 ? "?" : "&", sSteamID, sMap, iTime);
		ShowMOTDPanel(client, "GunGame winner", sUrl, MOTDPANEL_TYPE_URL);
	}
}

bool IsSafeMapName(const char[] sMap)
{
	int iLen = strlen(sMap);
	if (iLen < 1 || iLen > 64)
		return false;

	for (int i = 0; i < iLen; i++)
	{
		if (!IsCharAlpha(sMap[i]) && !IsCharNumeric(sMap[i]) && sMap[i] != '_' && sMap[i] != '-')
			return false;
	}

	return true;
}
