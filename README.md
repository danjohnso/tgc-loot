# TGC Loot

Guild loot addon for World of Warcraft Forever. Contested main-spec items use a 6-week weighted score. Lowest score wins. The raid sees the roll while it is open, and officers keep the shared record.

## Install

Confirm the client build. In game:

```
/dump select(4, GetBuildInfo())
```

The addon is written for interface **16001**. If that number is different, the three `## Interface:` lines in `TGCLoot.toc`, `TGCLoot_Forever.toc`, and `TGCLoot_Camelot.toc` have to match it or the client will refuse to load the addon.

Link the addon folder into Forever. From PowerShell, as administrator if the game directory is protected:

```
New-Item -ItemType Junction -Path "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\TGCLoot" -Target "C:\Code\tgc-loot\TGCLoot"
```

Use `_classic_beta_` instead of `_forever_` if that is the folder this client loads. Then `/reload`, and open the window with `/tgcloot`.

`/tgcloot test` runs the rules self-test inside the client. It does not change the saved guild record.

## Who can change loot

Everyone in the guild can open the window and read the record. Guild master and officers hold the authoritative copy. Members keep a copy so they can look, and they do not send the full record out.

During a raid, only the raid leader's client writes awards, attendance, specs, and the other record changes. That leader has to be the guild master or an officer. Outside a raid, officers can prepare the lockout, reservations, and settings.

Guild rank index 0 is the guild master. The Notes tab setting **Officer max** is the highest other rank index allowed to edit. The default is 1, so rank 0 and rank 1 can edit. If your officers are rank 2 or higher, raise Officer max before the raid. Until you do, the raid leader is rejected and nothing they click is saved.

A character who is not in a guild can still use the window. That copy stays on the account.

## Raid night

1. Officers put reservations on the Notes tab before the raid. Starting a lockout announces them in raid chat.
2. The raid leader starts a lockout (Molten Core, Blackwing Lair, or whatever the night is). Current-item counts reset. Everyone in the group is marked present.
3. Set loot to master looter with the Master loot button if the client allows it. Alt+click an item in the loot window, bags, or chat. Rare and better loot icons also show on the Roll tab while the corpse is open.
4. Mark Tier when the item is tier. Press Start. Raiders get a popup with Main spec, Off spec, and Pass.
5. Main spec beats off spec. The lowest score among the winning priority takes it. Confirm awards that person. Override awards the selected row and requires a reason, which is recorded.
6. A tie rolls 1-100. The Roll 100 button works from the popup. The highest roll wins. If someone does not roll, the tie stays open. If the rolls tie again, those players roll again.
7. Give item hands the loot over when you are the master looter. If the client refuses, trade the item.
8. Skip leaves the item unawarded. It does not count as a +1 and does not lock the item.
9. Awards are final. Void, on the History tab or with `/tgcloot void`, is an exceptional correction. It is written into the log. It is not an undo button.

Main spec is whatever the raider clicks for that item. The declared spec is shown so officers can judge mixed-use items. Officers decide main-spec eligibility. Say known reservations and priorities before the raid.

Uncontested loot is free: exactly one person in the winning priority, whether that priority is main spec or off spec. Off spec never adds a +1, even when several people contest it. An officer override of a main-spec award counts as a +1 even when the original roll was uncontested.

## Score

Lowest score wins.

Score = current lockout items + (2 x 6-week rate).

Current lockout items are contested main-spec wins on that track during this lockout. Tier and non-tier are separate: separate current counts, separate history, separate scores.

The 6-week rate is contested main-spec wins divided by raid weeks attended, inside the current six-week window. Weeks roll forward. The week starts Tuesday at 15:00 UTC unless officers change the day and hour on the Notes tab.

A new guild member uses the guild's attendance-weighted average rate, or their own rate if that is higher. A higher rate is a worse priority. After 4 separate raid weeks inside the current 6-week window, the personal rate is used on its own. Loot and attendance are tracked from the first raid. A returning raider with fewer than 4 weeks inside the window is treated as new again.

An occasional guest is someone with fewer than 4 raids in that same window. If an occasional guest is actually competing (in the main-spec pool when anyone rolled main spec, otherwise in the off-spec pool), everyone in that contest is scored on current lockout items only. A guest who rolls off spec while members roll main spec does not turn history off. After 4 qualifying raids in the window, a guest uses their personal rate. Qualifying raids are distinct lockouts, not repeats of the same one.

Tied scores roll 1-100. Tied players roll on their own. The winner still needs an officer to confirm the award.

## Sync

Changes go out as small guild addon messages from the raid leader. The roll popup uses raid, party, or instance chat so guests see it too.

If your copy is behind, an officer's client sends the full record. The guild master answers first, then other officers. Members do not serve the full record. During a raid, a newer record that arrives after the leader has already changed something is held. `/tgcloot pull` applies it. That avoids a late sync wiping awards from the current raid.

The record is per guild on the account. Logging into another guild does not mix the two.

## Commands

| Command | Effect |
| --- | --- |
| `/tgcloot` or `/tgc` | Open or close the window |
| `/tgcloot spec Fury` | Save your main spec and send it to the raid leader |
| `/tgcloot lockout MC` | Start a lockout, reset current items, record attendance |
| `/tgcloot attendance` | Add raiders who joined after the lockout started |
| `/tgcloot push` | Officers send the full record |
| `/tgcloot pull` | Apply a newer record that was held during a raid |
| `/tgcloot scores` | Print tier and non-tier scores |
| `/tgcloot void Name 12 reason` | Remove award number 12 from Name and log the reason |
| `/tgcloot test` | Run the rules self-test |
| `/tgcloot debug` | Print leader, officer, and revision details |
| `/tgcloot help` | Print the command list |

The minimap button opens the window. Right-click toggles the roll popup. Drag moves the button. Escape closes the window.

## Rules check outside the game

From the repo root, with Lua 5.1 on the path:

```
lua tests/logic_test.lua
```

It prints `ok` when the score, the saved-record codec, and the award log agree.
