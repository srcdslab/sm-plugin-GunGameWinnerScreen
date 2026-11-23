# sm-plugin-GunGameWinnerScreen

[GunGame:SM](https://github.com/srcdslab/sm-plugin-GunGame) companion plugin. When a match is won it:

1. POSTs the match result as JSON to a web endpoint (HTTPS, `Authorization: Bearer <token>`), through
   [REST in Pawn](https://github.com/srcdslab/sm-ext-ripext);
2. once the endpoint answered `200`, opens the winner page in the MOTD panel of every human player:
   `<page_url>?s=<viewer SteamID64>&m=<map>`.

If the push fails (timeout, HTTP error), the screen is not opened, so players never see an older match. Errors go to
the SourceMod error log.

## Requirements

- SourceMod 1.12 or 1.13, CS:S
- GunGame:SM 2.0.0 or newer (companion API: `GG_GetRanking`, `GG_OnMatchStart`, `GG_OnKnifeSteal`, ...)
- REST in Pawn (`rip.ext`)

## ConVars (`cfg/sourcemod/plugin.GunGameWinnerScreen.cfg`)

| ConVar | Default | Description |
| --- | --- | --- |
| `sm_gg_winnerscreen_enable` | `1` | Push the result and open the winner screen when a match is won |
| `sm_gg_winnerscreen_push_url` | `""` | HTTPS URL the match result is POSTed to |
| `sm_gg_winnerscreen_push_token` | `""` | Bearer token of the push URL (`FCVAR_PROTECTED`). Keep it in the server config only, never commit it |
| `sm_gg_winnerscreen_page_url` | `""` | Winner page opened in every player's MOTD |
| `sm_gg_winnerscreen_server` | `css_gg` | Server key sent in the push |
| `sm_gg_winnerscreen_timeout` | `5` | Seconds before the push is given up |
| `sm_gg_winnerscreen_delay` | `3` | Seconds after the win before the screen opens (push time included), so the match end fireworks are seen first |

Keep `mp_chattime` long enough for players to read the screen before the next map loads (it opens `sm_gg_winnerscreen_delay` seconds after the win).

## Payload

```json
{"v":1,"server":"css_gg","sent_at":1763800000,"current_map":"de_dust2",
 "match":{"map":"de_dust2","started_at":1763799000,"ended_at":1763799900,
   "winner":{"steamid64":"7656119...","name":"...","kills":31,"deaths":9,"bot":false,"headshots":12,"knife_steals":2},
   "ranking":[{"steamid64":"7656119...","name":"...","kills":31,"deaths":9,"bot":false,"level":23}]}}
```

- `steamid64` is empty for bots and for clients without a valid Steam ID (NoSteam servers).
- `ranking` holds at most 16 players, from `GG_GetRanking` (winner first), `kills` from `GG_GetClientKills`.
- Deaths, headshots and knife steals are counted by this plugin from the match start (`GG_OnMatchStart`).

The receiving page must treat every name as hostile input (escape on output).
