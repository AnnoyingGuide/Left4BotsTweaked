//--------------------------------------------------------------------------------------------------
//     GitHub:		https://github.com/smilz0/Left4Bots
//     Workshop:	https://steamcommunity.com/sharedfiles/filedetails/?id=3022416274
//--------------------------------------------------------------------------------------------------

Msg("Including left4bots_events...\n");

::Left4Bots.Events.OnGameEvent_round_start <- function (params)
{
	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_round_start - MapName: " + Left4Bots.MapName + " - MapNumber: " + Director.GetMapNumber());

	// Apparently, when scriptedmode is enabled and this director option isn't set, there is a big stutter (for the host)
	// when a witch is chasing a survivor and that survivor enters the saferoom. Simply having a value for this key, removes the stutter
	if (!("AllowWitchesInCheckpoints" in DirectorScript.GetDirectorOptions()))
		DirectorScript.GetDirectorOptions().AllowWitchesInCheckpoints <- false;

	Left4Bots.L4F = ("Left4Fun" in getroottable() && "PingEnt" in ::Left4Fun);
	Left4Bots.Log(LOG_LEVEL_DEBUG, "L4F = " + Left4Bots.L4F.tostring());

	// Start receiving concepts
	::ConceptsHub.SetHandler("Left4Bots", Left4Bots.OnConcept);

	// Start receiving user commands
	::HooksHub.SetChatCommandHandler("l4b", ::Left4Bots.HandleCommand);
	::HooksHub.SetConsoleCommandHandler("l4b", ::Left4Bots.HandleCommand);
	::HooksHub.SetAllowTakeDamage("L4B", ::Left4Bots.AllowTakeDamage);

	// Start the cleaner
	Left4Timers.AddTimer("Cleaner", 0.5, Left4Bots.OnCleaner, {}, true);

	// Start the inventory manager
	Left4Timers.AddTimer("InventoryManager", 0.5, Left4Bots.OnInventoryManager, {}, true);

	// Start the thinker
	Left4Timers.AddThinker("L4BThinker", 0.0333, Left4Bots.OnThinker, {});

	DirectorScript.GetDirectorOptions().cm_ShouldHurry <- Left4Bots.Settings.should_hurry;
}

::Left4Bots.Events.OnGameEvent_round_end <- function (params)
{
	local winner = params["winner"];
	local reason = params["reason"];
	local message = params["message"];
	local time = params["time"];

	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_round_end - winner: " + winner + " - reason: " + reason + " - message: " + message + " - time: " + time);

	if (Left4Bots.Settings.anti_pipebomb_bug)
		Left4Bots.ClearPipeBombs();

	Left4Bots.AddonStop();
}

::Left4Bots.Events.OnGameEvent_map_transition <- function (params)
{
	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_map_transition");

	if (Left4Bots.Settings.anti_pipebomb_bug)
		Left4Bots.ClearPipeBombs();

	Left4Bots.AddonStop();
}

::Left4Bots.Events.OnGameEvent_server_pre_shutdown <- function (params)
{
	//local reason = params["reason"];

	if (Left4Bots.Settings.anti_pipebomb_bug)
		Left4Bots.ClearPipeBombs();
}

::Left4Bots.Events.OnGameEvent_player_spawn <- function (params)
{
	local player = null;
	if ("userid" in params)
		player = g_MapScript.GetPlayerFromUserID(params["userid"]);

	if (!player || !player.IsValid())
		return;

	Left4Timers.AddTimer(null, 0.01, @(params) Left4Bots.OnPostPlayerSpawn(params.player), { player = player });
}

::Left4Bots.OnPostPlayerSpawn <- function (player)
{
	if (!player || !player.IsValid())
		return;

	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnPostPlayerSpawn - player: " + player.GetPlayerName());

	player.SetContext("userid", player.GetPlayerUserId().tostring(), -1);

	if (Left4Bots.IsValidSurvivor(player))
	{
		::Left4Bots.Survivors[player.GetPlayerUserId()] <- player;

		if (IsPlayerABot(player))
		{
			::Left4Bots.Bots[player.GetPlayerUserId()] <- player;

			Left4Bots.AddBotThink(player);
		}
		else if (Left4Bots.Settings.play_sounds)
		{
			// Precache sounds for human players
			player.PrecacheScriptSound("Hint.BigReward");
			player.PrecacheScriptSound("Hint.LittleReward");
			player.PrecacheScriptSound("BaseCombatCharacter.AmmoPickup");
		}

		Left4Bots.PrintSurvivorsCount();
	}
	else
	{
		local team = NetProps.GetPropInt(player, "m_iTeamNum");
		if (team == TEAM_INFECTED)
		{
			if (player.GetZombieType() == Z_TANK)
			{
				::Left4Bots.Tanks[player.GetPlayerUserId()] <- player;

				if (Left4Bots.Tanks.len() == 1) // At least 1 tank has spawned
					Left4Bots.OnTankActive();

				Left4Bots.Log(LOG_LEVEL_DEBUG, "Active tanks: " + ::Left4Bots.Tanks.len());
			}
			else
			{
				::Left4Bots.Specials[player.GetPlayerUserId()] <- player;

				Left4Bots.Log(LOG_LEVEL_DEBUG, "Active specials: " + ::Left4Bots.Specials.len());
			}
		}
		else if (team == TEAM_L4D1_SURVIVORS && Left4Bots.Settings.handle_l4d1_survivors == 1)
		{
			::Left4Bots.L4D1Survivors[player.GetPlayerUserId()] <- player;
			Left4Bots.AddL4D1BotThink(player);

			Left4Bots.PrintL4D1SurvivorsCount();
		}
	}
}

::Left4Bots.Events.OnGameEvent_witch_spawn <- function (params)
{
	local witch = null;
	if ("witchid" in params)
		witch = EntIndexToHScript(params["witchid"]);

	if (!witch || !witch.IsValid())
		return;

	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_witch_spawn - witch spawned");

	::Left4Bots.Witches[witch.GetEntityIndex()] <- witch;

	Left4Bots.Log(LOG_LEVEL_DEBUG, "Active witches: " + ::Left4Bots.Witches.len());
}

::Left4Bots.Events.OnGameEvent_player_death <- function (params)
{
	local victim = null;
	local victimIsPlayer = false;
	local victimUserId = null;

	if ("userid" in params)
		victim = g_MapScript.GetPlayerFromUserID(params["userid"]);

	if (victim && victim.IsValid())
	{
		victimIsPlayer = true;
		victimUserId = victim.GetPlayerUserId();
	}
	else if ("entityid" in params)
		victim = EntIndexToHScript(params["entityid"]);

	if (!victim || !victim.IsValid())
		return;

	local attacker = null;
	local attackerIsPlayer = false;

	if ("attacker" in params)
		attacker = g_MapScript.GetPlayerFromUserID(params["attacker"]);

	if (attacker && attacker.IsValid())
		attackerIsPlayer = true;
	else if ("attackerentid" in params)
		attacker = EntIndexToHScript(params["attackerentid"]);

	local weapon = null;
	local abort = null;
	local type = null;

	if ("weapon" in params)
		weapon = params["weapon"];

	if ("abort" in params)
		abort = params["abort"];

	if ("type" in params)
		type = params["type"];

	local victimName = "?";
	if (victim)
	{
		if (victimIsPlayer)
			victimName = victim.GetPlayerName();
		else
			victimName = victim.GetClassname(); // It's called victimName but it's the class name in case it's not a player
	}

	local attackerName = "?";
	if (attacker)
	{
		if (attackerIsPlayer)
			attackerName = attacker.GetPlayerName();
		else
			attackerName = attacker.GetClassname(); // It's called attackerName but it's the class name in case it's not a player
	}

	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_player_death - victim: " + victimName + " - attacker: " + attackerName + " - weapon: " + weapon + " - abort: " + abort + " - type: " + type);

	local victimTeam = NetProps.GetPropInt(victim, "m_iTeamNum");
	if (victimTeam == TEAM_INFECTED)
	{
		if (victimIsPlayer)
		{
			if  (victim.GetZombieType() == Z_TANK)
			{
				if (victimUserId in ::Left4Bots.Tanks)
				{
					delete ::Left4Bots.Tanks[victimUserId];

					if (Left4Bots.Tanks.len() == 0) // All the tanks are dead
						Left4Bots.OnTankGone();

					Left4Bots.Log(LOG_LEVEL_DEBUG, "Active tanks: " + ::Left4Bots.Tanks.len());
				}
				else
					Left4Bots.Log(LOG_LEVEL_ERROR, "Dead tank was not in Left4Bots.Tanks");
			}
			else
			{
				if (victimUserId in ::Left4Bots.Specials)
				{
					delete ::Left4Bots.Specials[victimUserId];

					Left4Bots.Log(LOG_LEVEL_DEBUG, "Active specials: " + ::Left4Bots.Specials.len());
				}
				else
					Left4Bots.Log(LOG_LEVEL_WARN, "Dead special was not in Left4Bots.Specials");
			}

			if (attacker && attackerIsPlayer && Left4Bots.IsHandledBot(attacker))
			{
				Left4Bots.NiceShootSurv = attacker;
				Left4Bots.NiceShootTime = Time();
			}
		}
		else
		{
			if (victimName == "infected")
			{
				// Common infected
			}
			else if (victimName == "witch")
			{
				// Witch
				if (victim.GetEntityIndex() in ::Left4Bots.Witches)
				{
					delete ::Left4Bots.Witches[victim.GetEntityIndex()];

					Left4Bots.Log(LOG_LEVEL_DEBUG, "Active witches: " + ::Left4Bots.Witches.len());
				}
				else
					Left4Bots.Log(LOG_LEVEL_ERROR, "Dead witch was not in Left4Bots.Witches");

				if (attacker && attackerIsPlayer && Left4Bots.IsHandledBot(attacker))
				{
					Left4Bots.NiceShootSurv = attacker;
					Left4Bots.NiceShootTime = Time();
				}
			}
		}
	}
	else if (victimTeam == TEAM_SURVIVORS && victimIsPlayer)
	{
		if (victimUserId in ::Left4Bots.Survivors)
			delete ::Left4Bots.Survivors[victimUserId];

		if (IsPlayerABot(victim))
		{
			if (victimUserId in ::Left4Bots.Bots)
				delete ::Left4Bots.Bots[victimUserId];

			Left4Bots.RemoveBotThink(victim);
		}

		Left4Bots.PrintSurvivorsCount();

		//

		local chr = NetProps.GetPropInt(victim, "m_survivorCharacter");
		local sdm = Left4Utils.GetSurvivorDeathModelByChar(chr);
		if (sdm)
		{
			if (attacker && !attackerIsPlayer && attackerName == "trigger_hurt" /*&& (Left4Utils.DamageContains(type, DMG_DROWN) || Left4Utils.DamageContains(type, DMG_CRUSH))*/)
				Left4Bots.Log(LOG_LEVEL_INFO, "Ignored possible unreachable survivor_death_model for dead survivor: " + victim.GetPlayerName());
			else
				Left4Bots.Deads[chr] <- { dmodel = sdm, player = victim };
		}
		else
			Left4Bots.Log(LOG_LEVEL_WARN, "Couldn't find a survivor_death_model for the dead survivor: " + victim.GetPlayerName() + "!!!");
	}
	else if (victimTeam == TEAM_L4D1_SURVIVORS && victimIsPlayer)
	{
		if (victimUserId in ::Left4Bots.L4D1Survivors)
			delete ::Left4Bots.L4D1Survivors[victimUserId];

		Left4Bots.RemoveBotThink(victim);
	}
}

::Left4Bots.Events.OnGameEvent_player_disconnect <- function (params)
{
	if ("userid" in params)
	{
		local userid = params["userid"].tointeger();
		local player = g_MapScript.GetPlayerFromUserID(userid);

		if (player && player.IsValid() && IsPlayerABot(player))
			return;

		//Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_player_disconnect - player: " + player.GetPlayerName());

		if (userid in ::Left4Bots.Survivors)
			delete ::Left4Bots.Survivors[userid];
	}
}

::Left4Bots.Events.OnGameEvent_player_bot_replace <- function (params)
{
	local player = g_MapScript.GetPlayerFromUserID(params["player"]);
	local bot = g_MapScript.GetPlayerFromUserID(params["bot"]);

	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_player_bot_replace - bot: " + bot.GetPlayerName() + " replaced player: " + player.GetPlayerName());

	if (player.GetPlayerUserId() in ::Left4Bots.Survivors)
		delete ::Left4Bots.Survivors[player.GetPlayerUserId()];

	if (Left4Bots.IsValidSurvivor(bot))
	{
		::Left4Bots.Survivors[bot.GetPlayerUserId()] <- bot;
		::Left4Bots.Bots[bot.GetPlayerUserId()] <- bot;

		Left4Bots.AddBotThink(bot);
	}

	Left4Bots.PrintSurvivorsCount();
}

::Left4Bots.Events.OnGameEvent_bot_player_replace <- function (params)
{
	local player = g_MapScript.GetPlayerFromUserID(params["player"]);
	local bot = g_MapScript.GetPlayerFromUserID(params["bot"]);

	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_bot_player_replace - player: " + player.GetPlayerName() + " replaced bot: " + bot.GetPlayerName());

	if (bot.GetPlayerUserId() in ::Left4Bots.Survivors)
		delete ::Left4Bots.Survivors[bot.GetPlayerUserId()];

	if (bot.GetPlayerUserId() in ::Left4Bots.Bots)
		delete ::Left4Bots.Bots[bot.GetPlayerUserId()];

	Left4Bots.RemoveBotThink(bot);

	// This should fix https://github.com/smilz0/Left4Bots/issues/47
	Left4Bots.PlayerResetAll(player);
	Left4Bots.PlayerResetAll(bot);

	if (Left4Bots.IsValidSurvivor(player))
		::Left4Bots.Survivors[player.GetPlayerUserId()] <- player;

	Left4Bots.PrintSurvivorsCount();
}

::Left4Bots.Events.OnGameEvent_item_pickup <- function (params)
{
	local player = g_MapScript.GetPlayerFromUserID(params["userid"]);
	local item = params["item"];

	if (!Left4Bots.IsHandledSurvivor(player))
		return;

	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_item_pickup - player: " + player.GetPlayerName() + " picked up: " + item);

	// This is meant to prevent the bot from accidentally using the pills/adrenaline you give them while they are shooting the infected
	if (item == "pain_pills" || item == "adrenaline")
		Left4Timers.AddTimer(null, 1, @(params) Left4Bots.CheckBotPickup(params.bot, params.item), { bot = player, item = "weapon_" + item });

	// Update the inventory items
	Left4Bots.OnInventoryManager(params);
	//Left4Timers.AddTimer(null, 0.1, Left4Bots.OnInventoryManager, { });
}

::Left4Bots.Events.OnGameEvent_player_use <- function (params)
{
	local player = null;
	local entity = null;

	if ("userid" in params)
		player = g_MapScript.GetPlayerFromUserID(params["userid"]);

	if ("targetid" in params)
		entity = EntIndexToHScript(params["targetid"]);

	if (player == null || !player.IsValid() || entity == null || !entity.IsValid())
		return;

	Left4Bots.Log(LOG_LEVEL_DEBUG, "Left4Bots.OnGameEvent_player_use - " + player.GetPlayerName() + " -> " + entity);

	Left4Bots.OnPlayerUse(player, entity);
}

::Left4Bots.Events.OnGameEvent_weapon_fire <- function (params)
{
	local player = g_MapScript.GetPlayerFromUserID(params["userid"]);
	local weapon = params["weapon"];

	//Left4Bots.Log(LOG_LEVEL_DEBUG, "Left4Bots.OnWeaponFired - player: " + player.GetPlayerName() + " - weapon: " + weapon);

	if (weapon == "pipe_bomb" || weapon == "vomitjar")
	{
		Left4Bots.Log(LOG_LEVEL_DEBUG, player.GetPlayerName() + " threw " + weapon);

		Left4Bots.LastNadeTime = Time();
	}
	else if (weapon == "molotov")
	{
		Left4Bots.Log(LOG_LEVEL_DEBUG, player.GetPlayerName() + " threw " + weapon);

		Left4Bots.LastMolotovTime = Time();
	}
}

::Left4Bots.Events.OnGameEvent_spit_burst <- function (params)
{
	local spitter = g_MapScript.GetPlayerFromUserID(params["userid"]);
	local spit = EntIndexToHScript(params["subject"]);

	if (!spitter || !spit || !spitter.IsValid() || !spit.IsValid())
		return;

	Left4Bots.Log(LOG_LEVEL_DEBUG, "Left4Bots.OnGameEvent_spit_burst - spitter: " + spitter.GetPlayerName());

	if (!Left4Bots.Settings.dodge_spit)
		return;

	foreach (bot in ::Left4Bots.Bots)
	{
		if (bot.IsValid() && !Left4Bots.SurvivorCantMove(bot, bot.GetScriptScope().Waiting))
			Left4Bots.TryDodgeSpit(bot, spit);
	}

	if (Left4Bots.Settings.spit_block_nav)
		Left4Timers.AddTimer(null, 3.8, Left4Bots.SpitterSpitBlockNav, { spit_ent = spit });
}

::Left4Bots.Events.OnGameEvent_charger_charge_start <- function (params)
{
	local charger = g_MapScript.GetPlayerFromUserID(params["userid"]);
	if (!charger || !charger.IsValid())
		return;

	Left4Bots.Log(LOG_LEVEL_DEBUG, "Left4Bots.OnChargerChargeStart - charger: " + charger.GetPlayerName());

	if (!Left4Bots.Settings.dodge_charger)
		return;

	local chargerOrig = charger.GetOrigin();
	local chargerLeft = charger.EyeAngles().Left();
	local chargerForwardY = charger.EyeAngles().Forward();
	chargerForwardY.Norm();
	chargerForwardY = Left4Utils.VectorAngles(chargerForwardY).y;

	foreach (bot in ::Left4Bots.Bots)
	{
		if (bot.IsValid() && !Left4Bots.SurvivorCantMove(bot, bot.GetScriptScope().Waiting))
		{
			local d = (chargerOrig - bot.GetOrigin()).Length();
			if (d <= 1200 /*&& Left4Utils.CanTraceTo(bot, charger, Left4Bots.Settings.tracemask_others)*/)
			{
				if (d <= 500)
					Left4Bots.CheckShouldDodgeCharger(bot, charger, chargerOrig, chargerLeft, chargerForwardY);
				else
					Left4Timers.AddTimer(null, Left4Bots.Settings.dodge_charger_distdelay_factor * d, @(params) Left4Bots.CheckShouldDodgeCharger(params.bot, params.charger, params.chargerOrig, params.chargerLeft, params.chargerForwardY), { bot = bot, charger = charger, chargerOrig = chargerOrig, chargerLeft = chargerLeft, chargerForwardY = chargerForwardY });
			}
		}
	}
}

::Left4Bots.Events.OnGameEvent_player_jump <- function (params)
{
	local player = g_MapScript.GetPlayerFromUserID(params["userid"]);

	if (!player || !player.IsValid())
		return;

	//Left4Bots.Log(LOG_LEVEL_DEBUG, "Left4Bots.OnPlayerJump - player: " + player.GetPlayerName());

	if (RandomInt(1, 100) > Left4Bots.Settings.shove_deadstop_chance)
		return;

	local z = NetProps.GetPropInt(player, "m_zombieClass");
	if (z != Z_HUNTER && z != Z_JOCKEY)
		return;

	// Victim is supposed to be the infected's lookat survivor but if another survivor gets in the way, he will be the victim without trying to deadstop the special
	local victim = NetProps.GetPropEntity(player, "m_lookatPlayer");
	if (!victim || !victim.IsValid() || !victim.IsPlayer() || !("IsSurvivor" in victim) || !victim.IsSurvivor() || !IsPlayerABot(victim) || Time() < NetProps.GetPropFloat(victim, "m_flNextShoveTime"))
		return;

	local d = (victim.GetOrigin() - player.GetOrigin()).Length();

	Left4Bots.Log(LOG_LEVEL_DEBUG, "Left4Bots.OnPlayerJump - " + player.GetPlayerName() + " -> " + victim.GetPlayerName() + " - " + d);

	if (d > 700) // Too far to be a threat
		return;

	if (d <= 150)
		Left4Utils.PlayerPressButton(victim, BUTTON_SHOVE, Left4Bots.Settings.button_holdtime_tap, player, Left4Bots.Settings.shove_deadstop_deltapitch, 0, false);
	else
		Left4Timers.AddTimer(null, 0.001 * d, @(params) Left4Utils.PlayerPressButton(params.player, BUTTON_SHOVE, Left4Bots.Settings.button_holdtime_tap, params.destination, Left4Bots.Settings.shove_deadstop_deltapitch, 0, false), { player = victim, destination = player });
}

::Left4Bots.Events.OnGameEvent_player_entered_checkpoint <- function (params)
{
	if (!Left4Bots.ModeStarted)
		return;

	local player = null;
	if ("userid" in params)
		player = g_MapScript.GetPlayerFromUserID(params["userid"]);

	if (!Left4Bots.IsHandledSurvivor(player))
		return;

	local door = null;
	if ("door" in params)
		door = EntIndexToHScript(params["door"]);

	//local doorname = null;
	//if ("doorname" in params)
	//	doorname = params["doorname"];

	local allBots = RandomInt(1, 100) <= Left4Bots.Settings.close_saferoom_door_all_chance;

	if (Left4Bots.Settings.close_saferoom_door && door && door.IsValid() && (allBots || Left4Bots.IsHandledBot(player)) && Left4Bots.OtherSurvivorsInCheckpoint(player.GetPlayerUserId()))
	{
		local state = NetProps.GetPropInt(door, "m_eDoorState"); // 0 = closed - 1 = opening - 2 = open - 3 = closing
		if (state != 0 && state != 3)
		{
			local area = null;
			if ("area" in params)
				area = NavMesh.GetNavAreaByID(params["area"]);
			else
				area = NavMesh.GetNearestNavArea(door.GetOrigin(), 200, false, false);

			local doorZ = player.GetOrigin().z;
			if (area)
			{
				doorZ = area.GetCenter().z;

				Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_player_entered_checkpoint - area: " + area.GetID() + " - DoorZ: " + doorZ);
			}
			else
				Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_player_entered_checkpoint - area is null! - DoorZ: " + doorZ);

			if (allBots)
			{
				foreach (bot in Left4Bots.Bots)
				{
					local scope = bot.GetScriptScope();
					scope.DoorAct = AI_DOOR_ACTION.Saferoom;
					scope.DoorEnt = door; // This tells the bot to close the door. From now on, the bot will start looking for the best moment to close the door without locking himself out (will try at least)
					scope.DoorZ = doorZ;
				}
			}
			else
			{
				local scope = player.GetScriptScope();
				scope.DoorAct = AI_DOOR_ACTION.Saferoom;
				scope.DoorEnt = door; // This tells the bot to close the door. From now on, the bot will start looking for the best moment to close the door without locking himself out (will try at least)
				scope.DoorZ = doorZ;
			}
		}
	}
}

::Left4Bots.Events.OnGameEvent_revive_begin <- function (params)
{
	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_revive_begin");

	local player = g_MapScript.GetPlayerFromUserID(params["userid"]);
	if (!Left4Bots.IsHandledBot(player))
		return;

	local item = Left4Utils.GetInventoryItemInSlot(player, INV_SLOT_THROW);
	if (!item || !item.IsValid())
		return;

	local itemClass = item.GetClassname();
	if (((Left4Bots.Settings.throw_pipebomb && itemClass == "weapon_pipe_bomb") || (Left4Bots.Settings.throw_vomitjar && itemClass == "weapon_vomitjar")) &&
		//NetProps.GetPropInt(player, "m_hasVisibleThreats") &&
		(Time() - Left4Bots.LastNadeTime) >= Left4Bots.Settings.throw_nade_interval &&
		Left4Bots.CountOtherStandingSurvivorsWithin(player, 300) < 2 &&
		Left4Bots.HasAngryCommonsWithin(player.GetOrigin(), 3, 500, 150))
	{
		local pos = Left4Utils.BotGetFarthestPathablePos(player, Left4Bots.Settings.throw_nade_radius);
		if (pos && (pos - player.GetOrigin()).Length() >= Left4Bots.Settings.throw_nade_mindistance)
			Left4Timers.AddTimer(null, 0.1, @(params) Left4Bots.CancelReviveAndThrowNade(params.bot, params.subject, params.pos), { bot = player, subject = g_MapScript.GetPlayerFromUserID(params["subject"]), pos = pos });
	}
}

::Left4Bots.Events.OnGameEvent_finale_escape_start <- function (params)
{
	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_finale_escape_start");

	Left4Bots.EscapeStarted = true;
}

::Left4Bots.Events.OnGameEvent_finale_vehicle_ready <- function (params)
{
	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_finale_vehicle_ready");

	Left4Bots.EscapeStarted = true;
}

::Left4Bots.Events.OnGameEvent_door_close <- function (params)
{
	local checkpoint = params["checkpoint"];
	// TODO: is there any other way to know if we are in the exit checkpoint? Director.IsAnySurvivorInExitCheckpoint() doesn't even work. It returns true for the starting checkpoint too
	if (checkpoint && Left4Bots.Settings.anti_pipebomb_bug /*&& Director.IsAnySurvivorInExitCheckpoint()*/ && Left4Bots.OtherSurvivorsInCheckpoint(-1)) // -1 is like: is everyone in checkpoint?
	{
		Left4Bots.ClearPipeBombs();

		// If someone is holding a pipe bomb we'll also force them to switch to another weapon to make sure they don't throw the bomb while the door is closing
		foreach (surv in ::Left4Bots.Survivors)
		{
			local activeWeapon = surv.GetActiveWeapon();
			if (activeWeapon && activeWeapon.GetClassname() == "weapon_pipe_bomb")
				Left4Bots.BotSwitchToAnotherWeapon(surv);
		}
	}
}

::Left4Bots.Events.OnGameEvent_friendly_fire <- function (params)
{
	local attacker = null;
	local victim = null;
	local guilty = null;
	//local dmgType = null;

	if ("attacker" in params)
		attacker = g_MapScript.GetPlayerFromUserID(params["attacker"]);
	if ("victim" in params)
		victim = g_MapScript.GetPlayerFromUserID(params["victim"]);
	if ("guilty" in params)
		guilty = g_MapScript.GetPlayerFromUserID(params["guilty"]);
	//if ("type" in params)
	//	dmgType = params["type"];

	local attackerName = "";
	local victimName = "";
	local guiltyName = "";

	if (attacker)
		attackerName = attacker.GetPlayerName();
	if (victim)
		victimName = victim.GetPlayerName();
	if (guilty)
		guiltyName = guilty.GetPlayerName();

	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_friendly_fire - attacker: " + attackerName + " - victim: " + victimName + " - guilty: " + guiltyName);

	if (victim && guilty && victim.GetPlayerUserId() != guilty.GetPlayerUserId() && IsPlayerABot(guilty) /*&& !IsPlayerABot(victim)*/ && RandomInt(1, 100) <= Left4Bots.Settings.vocalizer_sorry_chance)
		DoEntFire("!self", "SpeakResponseConcept", "PlayerSorry", RandomFloat(0.6, 2), null, guilty);
}

::Left4Bots.Events.OnGameEvent_heal_begin <- function (params)
{
	local player = g_MapScript.GetPlayerFromUserID(params["userid"]);
	local subject = g_MapScript.GetPlayerFromUserID(params["subject"]);

	if(!player || !subject || !player.IsValid() || !subject.IsValid())
		return;

	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_heal_begin - player: " + player.GetPlayerName() + " - subject: " + subject.GetPlayerName());

	if (Left4Bots.IsHandledBot(player) && player.GetPlayerUserId() == subject.GetPlayerUserId()) // Bot healing himself
	{
		// Don't let survivor bots heal themselves if their health is >= Left4Bots.Settings.min_start_health (usually they do it in the start saferoom) and there are not enough spare medkits around
		// ... and there are humans in the team (otherwise they won't leave the saferoom)
		// ... and it's not a "heal" order
		if (player.GetHealth() >= Left4Bots.Settings.heal_interrupt_minhealth && Left4Bots.Bots.len() < Left4Bots.Survivors.len() && (NetProps.GetPropInt(player, "m_afButtonForced") & BUTTON_ATTACK) == 0 && !Left4Bots.HasSpareMedkitsAround(player))
			player.GetScriptScope().BotReset(); // TODO: Maybe handle this from the Think func?
		else if (Left4Bots.Settings.heal_force && !Left4Bots.HasAngryCommonsWithin(player.GetOrigin(), 3, 100) && !Left4Bots.HasSpecialInfectedWithin(player.GetOrigin(), 400))
		{
			// Force healing without interrupting or they won't heal when not "feeling safe" resulting sometimes in not healing until they die

			Left4Bots.Log(LOG_LEVEL_DEBUG, player.GetPlayerName() + " FORCE HEAL");

			Left4Utils.PlayerPressButton(player, BUTTON_ATTACK, Left4Bots.Settings.button_holdtime_heal, null, 0, 0, true); // <- Without lockLook the vanilla AI will be able to interrupt the healing
		}
	}
}

::Left4Bots.Events.OnGameEvent_finale_win <- function (params)
{
	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_finale_win");
	/*
	local ggLines = Left4Utils.FileToStringList(Left4Bots.Settings.file_gg);
	local bgLines = Left4Utils.FileToStringList(Left4Bots.Settings.file_bg);

	foreach (id, bot in ::Left4Utils.GetAllSurvivors())
	{
		if (bot && bot.IsValid() && IsPlayerABot(bot))
		{
			local line = null;
			if (!bot.IsIncapacitated() && !bot.IsDead() && !bot.IsDying())
			{
				if (ggLines && ggLines.len() > 0 && RandomInt(1, 100) <= Left4Bots.Settings.chat_gg_chance)
					line = ggLines[RandomInt(0, ggLines.len() - 1)];
			}
			else
			{
				if (bgLines && bgLines.len() > 0 && RandomInt(1, 100) <= Left4Bots.Settings.chat_bg_chance)
					line = bgLines[RandomInt(0, bgLines.len() - 1)];
			}

			if (line)
				Left4Timers.AddTimer(null, RandomFloat(2.0, 5.0), @(params) Left4Bots.SayLine(params.bot, params.line), { bot = bot, line = line });
		}
	}
	*/

	foreach (id, bot in ::Left4Utils.GetAllSurvivors())
	{
		if (bot && bot.IsValid() && IsPlayerABot(bot))
		{
			local line = null;
			if (!bot.IsIncapacitated() && !bot.IsDead() && !bot.IsDying())
			{
				if (Left4Bots.ChatGGLines.len() > 0 && RandomInt(1, 100) <= Left4Bots.Settings.chat_gg_chance)
					line = Left4Bots.ChatGGLines[RandomInt(0, Left4Bots.ChatGGLines.len() - 1)];
			}
			else
			{
				if (Left4Bots.ChatBGLines.len() > 0 && RandomInt(1, 100) <= Left4Bots.Settings.chat_bg_chance)
					line = Left4Bots.ChatBGLines[RandomInt(0, Left4Bots.ChatBGLines.len() - 1)];
			}

			if (line)
				Left4Timers.AddTimer(null, RandomFloat(1.0, 7.0), @(params) Left4Bots.SayLine(params.bot, params.line), { bot = bot, line = line });
		}
	}
}

::Left4Bots.Events.OnGameEvent_player_hurt <- function (params)
{
	local player = g_MapScript.GetPlayerFromUserID(params["userid"]);
	local attacker = g_MapScript.GetPlayerFromUserID(params["attacker"]);
	if (!attacker && ("attackerentid" in params))
		attacker = EntIndexToHScript(params["attackerentid"]);

	/*
	local weapon = "";
	if ("weapon" in params)
		weapon = params["weapon"];
	local type = -1;
	if ("type" in params)
		type = params["type"]; // commons do DMG_CLUB

	if (attacker)
		Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_player_hurt - player: " + player.GetPlayerName() + " - attacker: " + attacker + " - weapon: " + weapon + " - type: " + type);
	else
		Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_player_hurt - player: " + player.GetPlayerName() + " - weapon: " + weapon + " - type: " + type);
	*/

	if (Left4Bots.IsHandledBot(player))
	{
		local weapon = "";
		if ("weapon" in params)
			weapon = params["weapon"];

		if (weapon == "insect_swarm" || weapon == "inferno")
		{
			// Pause the 'wait' order if the bot is being damaged by the spitter's spit or the fire
			local scope = player.GetScriptScope();
			if (scope.Waiting && !scope.Paused)
				scope.BotPause();
		}
	}
}

::Left4Bots.Events.OnGameEvent_ammo_pile_weapon_cant_use_ammo <- function (params)
{
	local player = null;
	if ("userid" in params)
		player = g_MapScript.GetPlayerFromUserID(params["userid"]);

	if (!player || !player.IsValid())
		return;

	local pWeapon = Left4Utils.GetInventoryItemInSlot(player, INV_SLOT_PRIMARY);
	if (!pWeapon || !pWeapon.IsValid())
		return;

	local cWeapon = pWeapon.GetClassname();

	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_ammo_pile_weapon_cant_use_ammo - player: " + player.GetPlayerName() + " - weapon: " + cWeapon);

	if (cWeapon == "weapon_grenade_launcher" || cWeapon == "weapon_rifle_m60")
	{
		if ((IsPlayerABot(player) && Left4Bots.Settings.t3_ammo_bots) || (!IsPlayerABot(player) && Left4Bots.Settings.t3_ammo_human))
		{
			local ammoType = NetProps.GetPropInt(pWeapon, "m_iPrimaryAmmoType");
			local maxAmmo = Left4Utils.GetMaxAmmo(ammoType);
			NetProps.SetPropIntArray(player, "m_iAmmo", maxAmmo + (pWeapon.GetMaxClip1() - pWeapon.Clip1()), ammoType);

			if (!IsPlayerABot(player))
				EmitSoundOnClient("BaseCombatCharacter.AmmoPickup", player);

			Left4Bots.Log(LOG_LEVEL_INFO, "Player: " + player.GetPlayerName() + " replenished ammo for T3 weapon " + cWeapon);
		}
	}
}

::Left4Bots.Events.OnGameEvent_survivor_call_for_help <- function (params)
{
	local player = null;
	if ("userid" in params)
		player = g_MapScript.GetPlayerFromUserID(params["userid"]);

	if (!player || !player.IsValid())
		return;

	// info_survivor_rescue
	local subject = null;
	if ("subject" in params)
		subject = EntIndexToHScript(params["subject"]);

	if (!subject || !subject.IsValid())
		return;

	//Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_survivor_call_for_help - player: " + player.GetPlayerName() + " - pos: " + subject.GetOrigin());
	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_survivor_call_for_help - player: " + player.GetPlayerName() + " - " + player.GetOrigin() + " - " + subject + ": " + subject.GetOrigin());

	foreach (bot in Left4Bots.Bots)
	{
		if (!Left4Bots.BotHasOrderDestEnt(bot, "info_survivor_rescue"))
			Left4Bots.BotOrderAdd(bot, "goto", null, subject);
	}
}

::Left4Bots.Events.OnGameEvent_survivor_rescued <- function (params)
{
	//local rescuer = null;
	//if ("rescuer" in params)
	//	rescuer = g_MapScript.GetPlayerFromUserID(params["rescuer"]);

	local victim = null;
	if ("victim" in params)
		victim = g_MapScript.GetPlayerFromUserID(params["victim"]);

	if (!victim || !victim.IsValid())
		return;

	//local door = null;
	//if ("dooridx" in params)
	//	door = EntIndexToHScript(params["dooridx"]);

	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_survivor_rescued - victim: " + victim.GetPlayerName());

	foreach (bot in Left4Bots.Bots)
		bot.GetScriptScope().BotCancelOrdersDestEnt("info_survivor_rescue");
}

::Left4Bots.Events.OnGameEvent_survivor_rescue_abandoned <- function (params)
{
	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_survivor_rescue_abandoned");

	foreach (bot in Left4Bots.Bots)
		bot.GetScriptScope().BotCancelOrdersDestEnt("info_survivor_rescue");
}

::Left4Bots.Events.OnGameEvent_player_say <- function (params)
{
	local player = 0;
	if ("userid" in params)
		player = params["userid"];
	if (player != 0)
		player = g_MapScript.GetPlayerFromUserID(player);
	else
		player = null;
	local text = params["text"];

	if (!player || !text || !player.IsValid() || IsPlayerABot(player))
		return;

	// Handle 'hello' replies
	local playerid = player.GetPlayerUserId();
	if (Left4Bots.ChatHelloReplies.len() > 0 && Left4Bots.Bots.len() > 0 && Left4Users.IsJustJoined(playerid) && !(playerid in Left4Bots.ChatHelloAlreadyReplied))
	{
		local helloTriggers = "," + Left4Bots.Settings.chat_hello_triggers + ",";
		if (helloTriggers.find("," + text.tolower() + ",") != null)
		{
			Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_player_say - Hello triggered");
			foreach (bot in Left4Bots.Bots)
			{
				if (RandomInt(1, 100) <= Left4Bots.Settings.chat_hello_chance)
					Left4Timers.AddTimer(null, RandomFloat(2.5, 6.5), @(params) Left4Bots.SayLine(params.bot, params.line), { bot = bot, line = Left4Bots.ChatHelloReplies[RandomInt(0, Left4Bots.ChatHelloReplies.len() - 1)] });
			}
			Left4Bots.ChatHelloAlreadyReplied[playerid] <- 1;
		}
	}

	// Also handle chat bot commands given without chat trigger
	if (Left4Users.GetOnlineUserLevel(player.GetPlayerUserId()) < Left4Bots.Settings.userlevel_orders)
		return;

	local args = split(text, " ");
	if (args.len() < 2)
		return;

	local arg1 = strip(args[0].tolower());
	if (arg1 != "bot" && arg1 != "bots" && Left4Bots.GetBotByName(arg1) == null)
		return;

	local arg2 = strip(args[1].tolower());
	if (::Left4Bots.UserCommands.find(arg2) == null && ::Left4Bots.AdminCommands.find(arg2) == null)
		return;

	local arg3 = null;
	if (args.len() > 2)
		arg3 = strip(args[2]);

	Left4Bots.OnUserCommand(player, arg1, arg2, arg3);
}

::Left4Bots.Events.OnGameEvent_infected_hurt <- function (params)
{
	local attacker = null;
	local infected = null;
	local damage = 0;
	local dmgType = 0;

	if ("attacker" in params)
		attacker = g_MapScript.GetPlayerFromUserID(params["attacker"]);

	if ("entityid" in params)
		infected = EntIndexToHScript(params["entityid"]);

	if ("amount" in params)
		damage = params["amount"].tointeger();

	if ("type" in params)
		dmgType = params["type"].tointeger();

	//Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_infected_hurt");

	if (!attacker || !infected || !attacker.IsValid() || !infected.IsValid() || attacker.GetClassname() != "player" || infected.GetClassname() != "witch" || !IsPlayerABot(attacker))
		return;

	local attackerTeam = NetProps.GetPropInt(attacker, "m_iTeamNum");
	if (attackerTeam != TEAM_SURVIVORS && attackerTeam != TEAM_L4D1_SURVIVORS)
		return;

	//Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_infected_hurt - attacker: " + attacker.GetPlayerName() + " - damage: " + damage + " - dmgType: " + dmgType);

	if (Left4Bots.Settings.trigger_witch && NetProps.GetPropFloat(infected, "m_rage") < 1.0 && !NetProps.GetPropInt(infected, "m_mobRush") && (dmgType & DMG_BURN) == 0)
	{
		Left4Bots.Log(LOG_LEVEL_DEBUG, "OnGameEvent_infected_hurt - Bot " + attacker.GetPlayerName() + " startled witch (damage: " + damage + " - dmgType: " + dmgType + ")");

		/* Fire method
		if (!NetProps.GetPropInt(infected, "m_bIsBurning"))
			Left4Timers.AddTimer(null, 0.01, Left4Bots.ExtinguishWitch, { witch = infected }, false);

		infected.TakeDamage(0.001, DMG_BURN, attacker); // Startle the witch
		*/

		// Easier method
		NetProps.SetPropFloat(infected, "m_rage", 1.0);
		NetProps.SetPropFloat(infected, "m_wanderrage", 1.0);
		Left4Utils.BotCmdAttack(infected, attacker);
	}
}

::Left4Bots.Events.OnGameEvent_charger_carry_start <- function (params)
{
	local player = g_MapScript.GetPlayerFromUserID(params["userid"]);
	local victim = g_MapScript.GetPlayerFromUserID(params["victim"]);

	Left4Bots.SpecialGotSurvivor(player, victim, "charger_carry_start");
}

::Left4Bots.Events.OnGameEvent_charger_pummel_start <- function (params)
{
	local player = g_MapScript.GetPlayerFromUserID(params["userid"]);
	local victim = g_MapScript.GetPlayerFromUserID(params["victim"]);

	Left4Bots.SpecialGotSurvivor(player, victim, "charger_pummel_start");
}

::Left4Bots.Events.OnGameEvent_tongue_grab <- function (params)
{
	local player = g_MapScript.GetPlayerFromUserID(params["userid"]);
	local victim = g_MapScript.GetPlayerFromUserID(params["victim"]);

	Left4Bots.SpecialGotSurvivor(player, victim, "tongue_grab");
}

::Left4Bots.Events.OnGameEvent_jockey_ride <- function (params)
{
	local player = g_MapScript.GetPlayerFromUserID(params["userid"]);
	local victim = g_MapScript.GetPlayerFromUserID(params["victim"]);

	Left4Bots.SpecialGotSurvivor(player, victim, "jockey_ride");
}

::Left4Bots.Events.OnGameEvent_lunge_pounce <- function (params)
{
	local player = g_MapScript.GetPlayerFromUserID(params["userid"]);
	local victim = g_MapScript.GetPlayerFromUserID(params["victim"]);

	Left4Bots.SpecialGotSurvivor(player, victim, "lunge_pounce");
}

//

::Left4Bots.OnConcept <- function (concept, query)
{
	if (!Left4Bots.ModeStarted && "gamemode" in query)
	{
		Left4Bots.ModeStarted = true;
		Left4Bots.OnModeStart();
	}

	if (concept == "PlayerExertionMinor" || concept.find("VSLib") != null)
		return;

	local who = null;
	if ("userid" in query)
		who = g_MapScript.GetPlayerFromUserID(query.userid.tointeger());
	else if ("who" in query)
		who = Left4Bots.GetSurvivorFromActor(query.who);
	else if ("Who" in query)
		who = Left4Bots.GetSurvivorFromActor(query.Who);

	local subjectid = null;
	if ("subjectid" in query)
		subjectid = query.subjectid.tointeger();
	
	local subject = null;
	if ("subject" in query)
		subject = query.subject;
	else if ("Subject" in query)
		subject = query.Subject;

	if (who && who.IsValid())
	{
		//Left4Bots.Log(LOG_LEVEL_DEBUG, "OnConcept(" + concept + ") - who: " + who.GetPlayerName() + " - subjectid: " + subjectid + " - subject: " + subject);
		
		if (Left4Bots.IsHandledBot(who))
		{
			// WHO is a bot

			if (concept == "SurvivorBotEscapingFlames")
			{
				local scope = who.GetScriptScope();
				if (scope.CanReset)
				{
					scope.CanReset = false; // Do not send RESET commands to the bot if the bot is trying to escape from the fire or the spitter's spit or it will get stuck there

					Left4Bots.Log(LOG_LEVEL_DEBUG, "Bot " + who.GetPlayerName() + " CanReset = false");
				}
			}
			else if (concept == "SurvivorBotHasEscapedSpit" || concept == "SurvivorBotHasEscapedFlames")
			{
				local scope = who.GetScriptScope();
				if (!scope.CanReset)
				{
					scope.CanReset = true; // Now we can safely send RESET commands again

					Left4Bots.Log(LOG_LEVEL_DEBUG, "Bot " + who.GetPlayerName() + " CanReset = true");

					// Delayed resets are executed as soon as we can reset again
					if (scope.DelayedReset)
						Left4Timers.AddTimer(null, 0.01, @(params) params.scope.BotReset(true), { scope = scope });
						//scope.BotReset(true); // Apparently, sending a RESET command to the bot from this OnConcept, makes the game crash
				}

				// Bot's vanilla escape flames/spit algorithm interfered with any previous MOVE so the MOVE must be refreshed
				if (scope.MovePos && scope.NeedMove <= 0)
					scope.NeedMove = 2;
			}
			else if (concept == "SurvivorBotRegroupWithTeam")
			{
				local scope = who.GetScriptScope();
				if (!scope.CanReset)
				{
					scope.CanReset = true; // Now we can safely send RESET commands again

					Left4Bots.Log(LOG_LEVEL_DEBUG, "Bot " + who.GetPlayerName() + " CanReset = true");

					// Delayed resets are executed as soon as we can reset again
					if (scope.DelayedReset)
						Left4Timers.AddTimer(null, 0.01, @(params) params.scope.BotReset(true), { scope = scope });
						//scope.BotReset(true); // Apparently, sending a RESET command to the bot from this OnConcept, makes the game crash
				}

				// Receiving this concept from a bot who is executing a move command means that the bot got nav stuck and teleported somewhere.
				// After the teleport the move command is lost and needs to be refreshed.
				if (scope.MovePos && scope.NeedMove <= 0 && !scope.Paused)
					scope.NeedMove = 2;
			}
			else if (concept == "TLK_IDLE" || concept == "SurvivorBotNoteHumanAttention" || concept == "SurvivorBotHasRegroupedWithTeam")
			{
				if (Left4Bots.Settings.deploy_upgrades)
				{
					local itemClass = Left4Bots.ShouldDeployUpgrades(who, query);
					if (itemClass)
					{
						Left4Bots.Log(LOG_LEVEL_DEBUG, "Bot " + who.GetPlayerName() + " switching to upgrade " + itemClass);

						who.SwitchToItem(itemClass);

						Left4Timers.AddTimer(null, 1, @(params) Left4Bots.DoDeployUpgrade(params.player), { player = who });
					}
				}
			}

			// ...
		}
		else if (Left4Bots.IsHandledL4D1Bot(who))
		{
			if (concept == "SurvivorBotEscapingFlames")
			{
				local scope = who.GetScriptScope();
				if (scope.CanReset)
				{
					scope.CanReset = false; // Do not send RESET commands to the bot if the bot is trying to escape from the fire or the spitter's spit or it will get stuck there

					Left4Bots.Log(LOG_LEVEL_DEBUG, "L4D1 Bot " + who.GetPlayerName() + " CanReset = false");
				}
			}
			else if (concept == "SurvivorBotHasEscapedSpit" || concept == "SurvivorBotHasEscapedFlames")
			{
				local scope = who.GetScriptScope();
				if (!scope.CanReset)
				{
					scope.CanReset = true; // Now we can safely send RESET commands again

					Left4Bots.Log(LOG_LEVEL_DEBUG, "L4D1 Bot " + who.GetPlayerName() + " CanReset = true");

					// Delayed resets are executed as soon as we can reset again
					if (scope.DelayedReset)
						Left4Timers.AddTimer(null, 0.01, @(params) params.scope.BotReset(true), { scope = scope });
				}

				// Bot's vanilla escape flames/spit algorithm interfered with any previous MOVE so the MOVE must be refreshed
				if (scope.MovePos && scope.NeedMove <= 0)
					scope.NeedMove = 2;
			}
			else if (concept == "SurvivorBotRegroupWithTeam")
			{
				local scope = who.GetScriptScope();
				if (!scope.CanReset)
				{
					scope.CanReset = true; // Now we can safely send RESET commands again

					Left4Bots.Log(LOG_LEVEL_DEBUG, "L4D1 Bot " + who.GetPlayerName() + " CanReset = true");

					// Delayed resets are executed as soon as we can reset again
					if (scope.DelayedReset)
						Left4Timers.AddTimer(null, 0.01, @(params) params.scope.BotReset(true), { scope = scope });
				}

				// Receiving this concept from a bot who is executing a move command means that the bot got nav stuck and teleported somewhere.
				// After the teleport the move command is lost and needs to be refreshed.
				if (scope.MovePos && scope.NeedMove <= 0 && !scope.Paused)
					scope.NeedMove = 2;
			}
		}
		else
		{
			// WHO is a human

			if (concept == "OfferItem")
			{
				if (subjectid != null)
					subject = g_MapScript.GetPlayerFromUserID(subjectid);
				else if (subject)
					subject = Left4Bots.GetSurvivorFromActor(subject);

				if (subject && subject.IsValid() && IsPlayerABot(subject))
					Left4Bots.LastGiveItemTime = Time();

				return;
			}

			local lvl = Left4Users.GetOnlineUserLevel(who.GetPlayerUserId());

			if (Left4Bots.Settings.vocalizer_commands && lvl >= Left4Bots.Settings.userlevel_orders)
			{
				if (concept == "PlayerLook" || concept == "PlayerLookHere")
				{
					// Bot selection
					if (subjectid != null)
						subject = g_MapScript.GetPlayerFromUserID(subjectid);
					else if (subject)
						subject = Left4Bots.GetSurvivorFromActor(subject);

					if (Left4Bots.IsHandledBot(subject))
					{
						Left4Bots.VocalizerBotSelection[who.GetPlayerUserId()] <- { bot = subject, time = Time() };

						Left4Bots.Log(LOG_LEVEL_DEBUG, who.GetPlayerName() + " selected bot " + subject.GetPlayerName());
					}
				}
				else if (concept in Left4Bots.VocalizerCommands)
				{
					local cmd = Left4Bots.VocalizerCommands[concept].all;
					local userid = who.GetPlayerUserId();
					if ((userid in Left4Bots.VocalizerBotSelection) && (Time() - Left4Bots.VocalizerBotSelection[userid].time) <= Left4Bots.Settings.vocalize_botselect_timeout && Left4Bots.VocalizerBotSelection[userid].bot && Left4Bots.VocalizerBotSelection[userid].bot.IsValid())
					{
						local botname = Left4Bots.VocalizerBotSelection[userid].bot.GetPlayerName().tolower();
						cmd = Left4Utils.StringReplace(Left4Bots.VocalizerCommands[concept].one, "botname ", botname + " ");
					}
					cmd = "!l4b " + cmd;
					local args = split(cmd, " ");
					Left4Bots.HandleCommand(who, args[1], args, cmd);
				}
				else if (concept == "PlayerImWithYou") // TODO
				{
					Left4Bots.ScavengeStart();
				}
			}

			if (lvl < Left4Bots.Settings.userlevel_vocalizer)
				return;

			if (concept == "PlayerLaugh")
			{
				foreach (bot in ::Left4Bots.Bots)
				{
					if (bot.IsValid() && RandomInt(1, 100) <= Left4Bots.Settings.vocalizer_laugh_chance)
						DoEntFire("!self", "SpeakResponseConcept", "PlayerLaugh", RandomFloat(0.5, 2), null, bot);
				}
			}
			else if (concept == "PlayerThanks")
			{
				if (subjectid != null)
					subject = g_MapScript.GetPlayerFromUserID(subjectid);
				else if (subject)
					subject = Left4Bots.GetSurvivorFromActor(subject);

				if (subject && IsPlayerABot(subject) && RandomInt(1, 100) <= Left4Bots.Settings.vocalizer_youwelcome_chance)
					DoEntFire("!self", "SpeakResponseConcept", "PlayerYouAreWelcome", RandomFloat(1.2, 2.3), null, subject);
			}
			else if (concept == "iMT_PlayerNiceShot")
			{
				if (RandomInt(1, 100) <= Left4Bots.Settings.vocalizer_thanks_chance)
				{
					if (subjectid != null)
						subject = g_MapScript.GetPlayerFromUserID(subjectid);
					else if (subject)
						subject = Left4Bots.GetSurvivorFromActor(subject);

					if (subject && IsPlayerABot(subject))
						DoEntFire("!self", "SpeakResponseConcept", "PlayerThanks", RandomFloat(1.2, 2.3), null, subject);
					else if (Left4Bots.NiceShootSurv && Left4Bots.NiceShootSurv.IsValid() && (Time() - Left4Bots.NiceShootTime) <= 10.0)
						DoEntFire("!self", "SpeakResponseConcept", "PlayerThanks", RandomFloat(0.5, 2), null, Left4Bots.NiceShootSurv);
				}
			}
			/// ...
		}

		if (concept == "PlayerChoke" || concept == "PlayerTonguePullStart")
		{
			if (Left4Bots.Settings.smoker_shoot_tongue)
			{
				local smoker = NetProps.GetPropEntity(who, "m_tongueOwner");
				if (smoker && smoker.IsValid())
					Left4Bots.DealWithSmoker(smoker, who, Left4Bots.Settings.smoker_shoot_tongue_duck);
			}
		}
		else if (concept == "PlayerPourFinished")
		{
			local score = null;
			local towin = null;

			if ("Score" in query)
				score = query.Score.tointeger();
			if ("towin" in query)
				towin = query.towin.tointeger();

			if (score != null && towin != null)
				Left4Bots.Log(LOG_LEVEL_INFO, "Poured: " + score + " - Left: " + towin);

			if (Left4Bots.ScavengeStarted && towin == 0)
			{
				Left4Bots.Log(LOG_LEVEL_INFO, "Scavenge complete");

				Left4Bots.ScavengeStop();
			}
		}
		/// ...
	}
	//else
	//	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnConcept(" + concept + ") - who: " + who + " - subject: " + subject);
}

::Left4Bots.OnModeStart <- function ()
{
	Left4Bots.Log(LOG_LEVEL_DEBUG, "Left4Bots.OnModeStart");

	if (Left4Bots.MapName == "c7m3_port")
	{
		// This stuff allows a full bot team to play The Sacrifice finale by disabling the error message for not enough human survivors
		local bridge_checker = Entities.FindByName(null, "bridge_checker");
		if (bridge_checker)
		{
			DoEntFire("!self", "Kill", "", 0, null, bridge_checker);

			Left4Bots.Log(LOG_LEVEL_DEBUG, "Killed bridge_checker");
		}
		else
			Left4Bots.Log(LOG_LEVEL_WARN, "bridge_checker was not found in c7m3_port map!");

		local generator_start_model = Entities.FindByName(null, "generator_start_model");
		if (generator_start_model)
		{
			DoEntFire("!self", "SacrificeEscapeSucceeded", "", 0, null, generator_start_model);

			Left4Bots.Log(LOG_LEVEL_DEBUG, "Triggered generator_start_model's SacrificeEscapeSucceeded");
		}
		else
			Left4Bots.Log(LOG_LEVEL_WARN, "generator_start_model was not found in c7m3_port map!");
	}
}

// Removes invalid entities from the Survivors, Bots, Tanks and Deads lists
::Left4Bots.OnCleaner <- function (params)
{
	// Survivors
	foreach (id, surv in ::Left4Bots.Survivors)
	{
		if (!surv || !surv.IsValid())
		{
			delete ::Left4Bots.Survivors[id];
			Left4Bots.Log(LOG_LEVEL_DEBUG, "Removed an invalid survivor from ::Left4Bots.Survivors");
		}
	}

	// Bots
	foreach (id, bot in ::Left4Bots.Bots)
	{
		if (!bot || !bot.IsValid())
		{
			delete ::Left4Bots.Bots[id];
			Left4Bots.Log(LOG_LEVEL_DEBUG, "Removed an invalid bot from ::Left4Bots.Bots");
		}
	}

	// Deads
	foreach (chr, dead in ::Left4Bots.Deads)
	{
		if (!dead.dmodel || !dead.dmodel.IsValid())
		{
			delete ::Left4Bots.Deads[chr];
			Left4Bots.Log(LOG_LEVEL_DEBUG, "Removed an invalid death model from ::Left4Bots.Deads");
		}
	}

	// Specials
	foreach (id, special in ::Left4Bots.Specials)
	{
		if (!special || !special.IsValid())
		{
			delete ::Left4Bots.Specials[id];
			Left4Bots.Log(LOG_LEVEL_DEBUG, "Removed an invalid special from ::Left4Bots.Specials");
		}
	}

	// Tanks
	foreach (id, tank in ::Left4Bots.Tanks)
	{
		if (!tank || !tank.IsValid())
		{
			delete ::Left4Bots.Tanks[id];
			Left4Bots.Log(LOG_LEVEL_DEBUG, "Removed an invalid tank from ::Left4Bots.Tanks");

			if (Left4Bots.Tanks.len() == 0)
				Left4Bots.OnTankGone();
		}
	}

	// Witches
	foreach (id, witch in ::Left4Bots.Witches)
	{
		if (!witch || !witch.IsValid())
		{
			delete ::Left4Bots.Witches[id];
			Left4Bots.Log(LOG_LEVEL_DEBUG, "Removed an invalid witch from ::Left4Bots.Witches");
		}
	}

	// Extra L4D2 Survivors
	foreach (id, surv in ::Left4Bots.L4D1Survivors)
	{
		if (!surv || !surv.IsValid())
		{
			delete ::Left4Bots.L4D1Survivors[id];
			Left4Bots.Log(LOG_LEVEL_DEBUG, "Removed an invalid L4D1 survivor from ::Left4Bots.L4D1Survivors");
		}
	}

	// Vocalizer bot selections
	foreach (id, sel in ::Left4Bots.VocalizerBotSelection)
	{
		if ((Time() - sel.time) > Left4Bots.Settings.vocalize_botselect_timeout || !sel.bot || !sel.bot.IsValid())
		{
			delete ::Left4Bots.VocalizerBotSelection[id];
			Left4Bots.Log(LOG_LEVEL_DEBUG, "Removed an invalid vocalizer bot selection from ::Left4Bots.VocalizerBotSelection");
		}
	}

}

// Tells the bots which items to pick up based on the current team situation
::Left4Bots.OnInventoryManager <- function (params)
{
	// First count how many medkits, defibs, chainsaws and throwables we already have in the team
	Left4Bots.TeamShotguns = 0;
	Left4Bots.TeamChainsaws = 0;
	Left4Bots.TeamMelee = 0;
	Left4Bots.TeamMolotovs = 0;
	Left4Bots.TeamPipeBombs = 0;
	Left4Bots.TeamVomitJars = 0;
	Left4Bots.TeamMedkits = 0;
	Left4Bots.TeamDefibs = 0;

	foreach (surv in ::Left4Bots.Survivors)
	{
		if (surv.IsValid())
		{
			local inv = {};
			GetInvTable(surv, inv);

			// Strings are a char array -- start the classname search at index 5, which is after "weapon", and the search should go by quicker.
			Left4Bots.TeamShotguns += (INV_SLOT_PRIMARY in inv && inv[INV_SLOT_PRIMARY].GetClassname().find("shotgun", 5) != null).tointeger();

			if (INV_SLOT_SECONDARY in inv)
			{
				local cls = inv[INV_SLOT_SECONDARY].GetClassname();

				Left4Bots.TeamChainsaws += (cls == "weapon_chainsaw").tointeger();
				Left4Bots.TeamMelee += (cls == "weapon_melee").tointeger();
			}

			if (INV_SLOT_THROW in inv)
			{
				local cls = inv[INV_SLOT_THROW].GetClassname();

				Left4Bots.TeamMolotovs += (cls == "weapon_molotov").tointeger();
				Left4Bots.TeamPipeBombs += (cls == "weapon_pipe_bomb").tointeger();
				Left4Bots.TeamVomitJars += (cls == "weapon_vomitjar").tointeger();
			}

			if (INV_SLOT_MEDKIT in inv)
			{
				local cls = inv[INV_SLOT_MEDKIT].GetClassname();

				Left4Bots.TeamMedkits += (cls == "weapon_first_aid_kit").tointeger();
				Left4Bots.TeamDefibs += (cls == "weapon_defibrillator").tointeger();
			}
		}
	}

	//Left4Bots.Log(LOG_LEVEL_DEBUG, "OnInventoryManager - TeamShotguns: " + Left4Bots.TeamShotguns + " - TeamChainsaws: " + Left4Bots.TeamChainsaws + " - Left4Bots.TeamMelee: " + Left4Bots.TeamMelee);
	//Left4Bots.Log(LOG_LEVEL_DEBUG, "OnInventoryManager - TeamMolotovs: " + Left4Bots.TeamMolotovs + " - TeamPipeBombs: " + Left4Bots.TeamPipeBombs + " - Left4Bots.TeamVomitJars: " + Left4Bots.TeamVomitJars);
	//Left4Bots.Log(LOG_LEVEL_DEBUG, "OnInventoryManager - TeamMedkits: " + Left4Bots.TeamMedkits + " - TeamDefibs: " + Left4Bots.TeamDefibs);

	// Then decide what we need
	foreach (bot in ::Left4Bots.Bots)
	{
		if (bot.IsValid())
			bot.GetScriptScope().BotUpdatePickupToSearch();
	}

	foreach (bot in ::Left4Bots.L4D1Survivors)
	{
		if (bot.IsValid())
			bot.GetScriptScope().BotUpdatePickupToSearch();
	}
}

// Coordinates the scavenge process
::Left4Bots.OnScavengeManager <- function (params)
{
	//Left4Bots.Log(LOG_LEVEL_DEBUG, "OnScavengeManager");

	if (!Left4Bots.ScavengeStarted)
	{
		// This isn't supposed to happen, but...
		Left4Timers.RemoveTimer("ScavengeManager");
		return;
	}

	if (Left4Bots.ScavengeUseTarget == null || !Left4Bots.ScavengeUseTarget.IsValid())
	{
		Left4Bots.Log(LOG_LEVEL_WARN, "ScavengeUseTarget is no longer valid. Stopping the scavenge process..");

		Left4Bots.ScavengeStop();
		return;
	}

	local num_bots = Left4Bots.Settings.scavenge_max_bots;

	// Add the required bots
	while (Left4Bots.ScavengeBots.len() < num_bots && Left4Bots.ScavengeBots.len() < Left4Bots.Bots.len())
	{
		local bot = Left4Bots.GetFirstAvailableBotForOrder("scavenge");
		if (!bot)
			break;

		Left4Bots.ScavengeBots[bot.GetPlayerUserId()] <- bot;

		Left4Bots.Log(LOG_LEVEL_INFO, "Added scavenge order slot for bot " + bot.GetPlayerName());

		Left4Bots.SpeakRandomVocalize(bot, Left4Bots.VocalizerYes, RandomFloat(0.2, 1.0));
	}

	// Remove the excess
	foreach (id, bot in Left4Bots.ScavengeBots)
	{
		if (Left4Bots.ScavengeBots.len() <= Left4Bots.Settings.scavenge_max_bots)
			break;

		delete ::Left4Bots.ScavengeBots[id];

		Left4Bots.Log(LOG_LEVEL_INFO, "Removed scavenge order slot for bot " + bot.GetPlayerName());
	}

	//Left4Bots.Log(LOG_LEVEL_DEBUG, "ScavengeBots len is " + Left4Bots.ScavengeBots.len());

	if (Left4Bots.ScavengeBots.len() <= 0)
		return; // No bot is available for scavenge

	local scavengeItems = Left4Bots.GetAvailableScavengeItems(Left4Bots.ScavengeUseType);
	if (scavengeItems.len() <= 0)
		return; // nothing to do here

	foreach (id, bot in Left4Bots.ScavengeBots)
	{
		if (!bot || !bot.IsValid() || bot.IsDead() || bot.IsDying())
			delete Left4Bots.ScavengeBots[id]; // Remove invalid/dead bots
		else if (!Left4Bots.BotHasOrderOfType(bot, "scavenge"))
		{
			// Assign the order
			while (scavengeItems.len() > 0)
			{
				local idx = Left4Utils.GetNearestEntityInList(bot, scavengeItems); // TODO: add option to search by shortest path
				local item = scavengeItems[idx];

				delete scavengeItems[idx];

				if (!Left4Bots.BotsHaveOrderDestEnt(item))
				{
					Left4Bots.BotOrderAdd(bot, "scavenge", null, item);

					Left4Bots.Log(LOG_LEVEL_INFO, "Assigned a scavenge order to bot " + bot.GetPlayerName());

					break;
				}
			}
		}
	}
}

// Does various stuff
Left4Bots.OnThinker <- function (params)
{
	// Listen for human survivors BUTTON_SHOVE press
	foreach (surv in ::Left4Bots.Survivors)
	{
		if (surv.IsValid() && !IsPlayerABot(surv))
		{
			if ((surv.GetButtonMask() & BUTTON_SHOVE) != 0 || (NetProps.GetPropInt(surv, "m_afButtonPressed") & BUTTON_SHOVE) != 0) // <- With med items (pills and adrenaline) the shove button is disabled when looking at teammates and GetButtonMask never sees the button down but m_afButtonPressed still does
			{
				local userid = surv.GetPlayerUserId();
				if (!(userid in Left4Bots.BtnStatus_Shove) || !Left4Bots.BtnStatus_Shove[userid])
				{
					Left4Bots.Log(LOG_LEVEL_DEBUG, surv.GetPlayerName() + " BUTTON_SHOVE");

					Left4Bots.BtnStatus_Shove[userid] <- true;

					if (Left4Bots.Settings.give_humans_nades || Left4Bots.Settings.give_humans_meds)
						Left4Timers.AddTimer(null, 0.0, Left4Bots.OnShovePressed, { player = surv });
				}
			}
			else
				Left4Bots.BtnStatus_Shove[surv.GetPlayerUserId()] <- false;
		}
	}

	// Attach our think function to newly spawned tank rocks
	if (Left4Bots.Settings.dodge_rock || Left4Bots.Settings.shoot_rock)
	{
		local ent = null;
		while (ent = Entities.FindByClassname(ent, "tank_rock"))
		{
			if (ent.IsValid())
			{
				ent.ValidateScriptScope();
				local scope = ent.GetScriptScope();
				if (!("L4B_RockThink" in scope))
				{
					scope.DodgingBots <- {};
					scope["L4B_RockThink"] <- ::Left4Bots.L4B_RockThink;
					AddThinkToEnt(ent, "L4B_RockThink");

					Left4Bots.Log(LOG_LEVEL_DEBUG, "New tank rock: " + ent.GetEntityIndex());
				}
			}
		}
	}
	
	if (Left4Bots.Settings.orders_debug)
		Left4Bots.RefreshDebugHudText();
}

// params["player"] pressed the SHOVE button. Handle the items give/swap from the humans
::Left4Bots.OnShovePressed <- function (params)
{
	local attacker = params["player"];
	if (!attacker || !attacker.IsValid())
		return;

	local attackerItem = attacker.GetActiveWeapon();
	if (!attackerItem || !attackerItem.IsValid())
		return;

	local slot = Left4Utils.FindSlotForItemClass(attacker, attackerItem.GetClassname());
	if (!(slot == INV_SLOT_THROW && Left4Bots.Settings.give_humans_nades) && !(slot == INV_SLOT_PILLS && Left4Bots.Settings.give_humans_meds))
		return;

	local attackerItemClass = attackerItem.GetClassname();
	local attackerItemSkin = NetProps.GetPropInt(attackerItem, "m_nSkin");

	Left4Bots.Log(LOG_LEVEL_DEBUG, "Left4Bots.OnShovePressed - " + attacker.GetPlayerName() + " - " + attackerItemClass + " - " + attackerItemSkin);

	local t = Time();
	if (((attackerItemClass == "weapon_pipe_bomb" || attackerItemClass == "weapon_vomitjar") && (t - Left4Bots.LastNadeTime) < 1.5) || (attackerItemClass == "weapon_molotov" && (t - Left4Bots.LastMolotovTime) < 1.5))
		return; // Preventing an exploit that allows you to give the item you just threw away. Throw the nade and press RMB immediately, the item is still seen in the players inventory (Drop event comes after a second), so the item was duplicated.

	local victim = Left4Utils.GetPickerEntity(attacker, 270, 0.95, true, null, Left4Bots.Settings.tracemask_others);
	if (!victim || !victim.IsValid() || victim.GetClassname() != "player" || !victim.IsSurvivor())
		return;

	Left4Bots.Log(LOG_LEVEL_DEBUG, "Left4Bots.OnShovePressed - attacker: " + attacker.GetPlayerName() + " - victim: " + victim.GetPlayerName() + " - weapon: " + attackerItemClass + " - skin: " + attackerItemSkin);

	local victimItem = Left4Utils.GetInventoryItemInSlot(victim, slot);
	if (!victimItem && slot == INV_SLOT_THROW)
	{
		DoEntFire("!self", "SpeakResponseConcept", "PlayerAlertGiveItem", 0, null, attacker);

		Left4Bots.GiveItemIndex1 = attackerItem.GetEntityIndex();

		attacker.DropItem(attackerItemClass);

		//Left4Utils.GiveItemWithSkin(victim, attackerItemClass, attackerItemSkin);

		Left4Timers.AddTimer(null, 0.3, Left4Bots.ItemGiven, { player1 = attacker, player2 = victim, item = attackerItem });

		if (IsPlayerABot(victim))
			Left4Bots.LastGiveItemTime = Time();
	}
	else if (victimItem && IsPlayerABot(victim))
	{
		// Swap

		local lvl = Left4Users.GetOnlineUserLevel(attacker.GetPlayerUserId());
		if (lvl >= Left4Bots.Settings.userlevel_give_others)
		{
			local victimItemClass = victimItem.GetClassname();
			local victimItemSkin = NetProps.GetPropInt(victimItem, "m_nSkin");

			if (victimItemClass != attackerItemClass || victimItemSkin != attackerItemSkin)
			{
				DoEntFire("!self", "SpeakResponseConcept", "PlayerAlertGiveItem", 0, null, attacker);
				DoEntFire("!self", "SpeakResponseConcept", "PlayerAlertGiveItem", 0, null, victim);

				Left4Bots.GiveItemIndex1 = attackerItem.GetEntityIndex();
				Left4Bots.GiveItemIndex2 = victimItem.GetEntityIndex();

				attacker.DropItem(attackerItemClass);
				victim.DropItem(victimItemClass);

				//Left4Utils.GiveItemWithSkin(attacker, victimItemClass, victimItemSkin);
				//Left4Utils.GiveItemWithSkin(victim, attackerItemClass, attackerItemSkin);

				Left4Timers.AddTimer(null, 0.3, Left4Bots.ItemSwapped, { player1 = attacker, item1 = victimItem, player2 = victim, item2 = attackerItem });
			}
		}
	}
}

::Left4Bots.OnPlayerUse <- function (player, entity, minCount = 0)
{
	if (Left4Bots.Settings.signal_max_distance <= 0 || !IsPlayerABot(player))
		return;

	switch (entity.GetClassname())
	{
		case "weapon_ammo_spawn":
		{
			if (Left4Bots.SpawnerHasItems(entity, minCount) && Left4Bots.HumansNeedAmmo(player, Left4Bots.Settings.signal_min_distance, Left4Bots.Settings.signal_max_distance))
				Left4Bots.DoSignal(player, entity, "PlayerSpotWeapon", "Ammo", "Ammo here!");

			break;
		}

		/* better handled in default:
		case "weapon_spawn":
		{
			if (Left4Bots.SpawnerHasItems(entity, minCount) && Left4Bots.HumansNeedWeapon(player, NetProps.GetPropInt(entity, "m_weaponID"), Left4Bots.Settings.signal_min_distance, Left4Bots.Settings.signal_max_distance))
				Left4Bots.DoSignal(player, entity, "PlayerSpotOtherWeapon", null, "Weapons here!");

			break;
		}
		*/

		case "weapon_first_aid_kit_spawn":
		{
			local other = Left4Bots.GetOtherMedkitSpawn(entity, 100.0);
			if (other && Left4Bots.HumansNeedMedkit(player, Left4Bots.Settings.signal_min_distance, Left4Bots.Settings.signal_max_distance))
				Left4Bots.DoSignal(player, other, "PlayerSpotWeapon", "FirstAidKit", "Medkits here!");

			break;
		}

		case "weapon_pain_pills_spawn":
		{
			if (Left4Bots.SpawnerHasItems(entity, minCount) && Left4Bots.HumansNeedTempMed(player, Left4Bots.Settings.signal_min_distance, Left4Bots.Settings.signal_max_distance))
				Left4Bots.DoSignal(player, entity, "PlayerSpotWeapon", "PainPills", "Pills here!");

			break;
		}

		case "weapon_adrenaline_spawn":
		{
			if (Left4Bots.SpawnerHasItems(entity, minCount) && Left4Bots.HumansNeedTempMed(player, Left4Bots.Settings.signal_min_distance, Left4Bots.Settings.signal_max_distance))
				Left4Bots.DoSignal(player, entity, "PlayerSpotWeapon", "Adrenaline", "Adrenaline here!");

			break;
		}

		case "weapon_molotov_spawn":
		{
			if (Left4Bots.SpawnerHasItems(entity, minCount) && Left4Bots.HumansNeedThrowable(player, Left4Bots.Settings.signal_min_distance, Left4Bots.Settings.signal_max_distance))
				Left4Bots.DoSignal(player, entity, "PlayerSpotWeapon", "Molotov", "Molotovs here!");

			break;
		}

		case "weapon_pipe_bomb_spawn":
		{
			if (Left4Bots.SpawnerHasItems(entity, minCount) && Left4Bots.HumansNeedThrowable(player, Left4Bots.Settings.signal_min_distance, Left4Bots.Settings.signal_max_distance))
				Left4Bots.DoSignal(player, entity, "PlayerSpotWeapon", "PipeBomb", "Pipe bombs here!");

			break;
		}

		case "weapon_vomitjar_spawn":
		{
			if (Left4Bots.SpawnerHasItems(entity, minCount) && Left4Bots.HumansNeedThrowable(player, Left4Bots.Settings.signal_min_distance, Left4Bots.Settings.signal_max_distance))
				Left4Bots.DoSignal(player, entity, "PlayerSpotWeapon", "VomitJar", "Bile jars here!");

			break;
		}

		case "upgrade_ammo_incendiary":
		{
			if (Left4Bots.SpawnerHasItems(entity, minCount) && Left4Bots.HumansNeedUpgradeAmmo(player, Left4Bots.Settings.signal_min_distance, Left4Bots.Settings.signal_max_distance))
				Left4Bots.DoSignal(player, entity, "PlayerSpotWeapon", "UpgradePack_Incendiary", "Incendiary ammo here!");

			break;
		}

		case "upgrade_ammo_explosive":
		{
			if (Left4Bots.SpawnerHasItems(entity, minCount) && Left4Bots.HumansNeedUpgradeAmmo(player, Left4Bots.Settings.signal_min_distance, Left4Bots.Settings.signal_max_distance))
				Left4Bots.DoSignal(player, entity, "PlayerSpotWeapon", "UpgradePack_Explosive", "Explosive ammo here!");

			break;
		}

		case "upgrade_laser_sight":
		{
			if (Left4Bots.SpawnerHasItems(entity, minCount) && Left4Bots.HumansNeedLaserSight(player, Left4Bots.Settings.signal_min_distance, Left4Bots.Settings.signal_max_distance))
				Left4Bots.DoSignal(player, entity, "PlayerSpotWeapon", "LaserSights", "Laser sights here!");

			break;
		}

		default:
		{
			if (entity.GetClassname().find("weapon_") != null && entity.GetClassname().find("_spawn") != null)
			{
				if (Left4Bots.SpawnerHasItems(entity, minCount) && Left4Bots.HumansNeedWeapon(player, NetProps.GetPropInt(entity, "m_weaponID"), Left4Bots.Settings.signal_min_distance, Left4Bots.Settings.signal_max_distance))
					Left4Bots.DoSignal(player, entity, "PlayerSpotOtherWeapon", null, "Weapons here!");
			}
		}
	}
}

// There is at least 1 tank alive
::Left4Bots.OnTankActive <- function ()
{
	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnTankActive");

	// Settings
	foreach (key, val in ::Left4Bots.OnTankSettings)
	{
		Left4Bots.OnTankSettingsBak[key] <- Left4Bots.Settings[key];
		Left4Bots.Settings[key] <- val;

		Left4Bots.Log(LOG_LEVEL_DEBUG, "Changing setting " + key + " to " + val);
	}

	// Convars
	foreach (key, val in ::Left4Bots.OnTankCvars)
	{
		Left4Bots.OnTankCvarsBak[key] <- Convars.GetStr(key);
		Convars.SetValue(key, val);

		Left4Bots.Log(LOG_LEVEL_DEBUG, "Changing convar " + key + " to " + val);
	}
}

// Last tank alive is dead
::Left4Bots.OnTankGone <- function ()
{
	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnTankGone");

	// Settings
	foreach (key, val in ::Left4Bots.OnTankSettingsBak)
	{
		Left4Bots.Settings[key] <- val;

		Left4Bots.Log(LOG_LEVEL_DEBUG, "Changing setting " + key + " back to " + val);
	}
	Left4Bots.OnTankSettingsBak.clear();

	// Convars
	foreach (key, val in ::Left4Bots.OnTankCvarsBak)
	{
		Convars.SetValue(key, val);

		Left4Bots.Log(LOG_LEVEL_DEBUG, "Changing convar " + key + " back to " + val);
	}
	Left4Bots.OnTankCvarsBak.clear();
}

/* Handle user commands

<botsource> command [parameter]

<botsource> can be:
- bot (the bot is automatically selected)
- bots (all the bots)
- botname (name of the bot)

Available commands:
	<botsource> lead			: The order is added to the given bot(s) orders queue. The bot(s) will start leading the way following the map's flow
	<botsource> follow			: The order is added to the given bot(s) orders queue. The bot(s) will start following you
	<botsource> follow <target>	: The order is added to the given bot(s) orders queue. The bot(s) will follow the given target survivor (you can also use the keyword "me" to follow you)
	<botsource> witch			: The order is added to the given bot(s) orders queue. The bot(s) will try to kill the witch you are looking at
	<botsource> heal			: The order is added to the given bot(s) orders queue. The bot(s) will heal himself/themselves
	<botsource> heal <target>	: The order is added to the given bot(s) orders queue. The bot(s) will heal the target survivor (target can also be the bot himself or the keyword "me" to heal you)
	<botsource> goto			: The order is added to the given bot(s) orders queue. The bot(s) will go to the location you are looking at
	<botsource> goto <target>	: The order is added to the given bot(s) orders queue. The bot(s) will go to the current target's position (target can be another survivor or the keyword "me" to come to you)
	<botsource> come			: The order is added to the given bot(s) orders queue. The bot(s) will come to your current location (alias of "<botsource> goto me")
	<botsource> wait			: The order is added to the given bot(s) orders queue. The bot(s) will hold his/their current position
	<botsource> wait here		: The order is added to the given bot(s) orders queue. The bot(s) will hold position at your current position
	<botsource> wait there		: The order is added to the given bot(s) orders queue. The bot(s) will hold position at the location you are looking at
	<botsource> use				: The order is added to the given bot(s) orders queue. The bot(s) will use the entity (pickup item / press button etc.) you are looking at
	<botsource> carry			: The order is added to the given bot(s) orders queue. The bot(s) will pick and hold the carriable item (gnome, gascan, cola, etc.) you are looking at
	<botsource> deploy			: The order is added to the given bot(s) orders queue or executed immediately. The bot(s) will go pick the deployable item (ammo upgrade packs) you are looking at and deploy it immediately. If you aren't looking at any item and the bot already has a deployable item in his inventory, he will deploy that item immediately
	<botsource> usereset		: The order is executed immediately. The bot(s) will stop using the weapons picked up via "use" order and will go back to its weapon preferences / team weapon rules
	<botsource> warp			: The order is executed immediately. The bot(s) will teleport to your position. If "bot" botsource is used, the selected bot will be the bot you are looking at
	<botsource> warp here		: The order is executed immediately. The bot(s) will teleport to your position. If "bot" botsource is used, the selected bot will be the bot you are looking at
	<botsource> warp there		: The order is executed immediately. The bot(s) will teleport to the location you are looking at. If "bot" botsource is used, the selected bot will be the bot you are looking at
	<botsource> warp move		: The order is executed immediately. The bot(s) will teleport to the current MOVE location (if any). If "bot" botsource is used, the selected bot will be the bot you are looking at
	<botsource> give			: The order is executed immediately. The bot will give you one item from their pills/throwable/medkit inventory slot if your slot is emtpy. "bot" and "bots" botsources are the same here, the first available bot is selected
	<botsource> swap			: The order is executed immediately. You will swap the item you are holding (only for items from the pills/throwable/medkit inventory slots) with the selected bot. "bot" and "bots" botsources will both select the bot you are looking at
	<botsource> tempheal		: The order is executed immediately. The bot(s) will use their pain pils/adrenaline. If "bot" botsource is used, the selected bot will be the bot you are looking at
	<botsource> throw [item]	: The order is executed immediately. The bot(s) will throw their throwable item to the location you are looking at. The bot(s) must have the given [item] type (or any throwable item if [item] is not supplied)
	<botsource> scavenge		: The order is added to the given bot(s) orders queue. The bot(s) will scavenge the item you are looking at (gascan, cola bottles) if a pour target is active. You can give this order to any bot, including the ones that aren't already scavenging automatically
	<botsource> scavenge start	: Starts the scavenge process. The botsource parameter is ignored, the scavenge bot(s) are always selected automatically
	<botsource> scavenge stop	: Stops the scavenge process. The botsource parameter is ignored, the scavenge bot(s) are always selected automatically
	<botsource> hurry			: The order is executed immediately. The bot(s) L4B2 AI will stop doing anything for 'hurry_time' seconds. Basically they will cancel any pending action/order and ignore pickups, defibs, throws etc. for that amount of time
	<botsource> die				: The order is executed immediately. The bot(s) will die. If "bot" botsource is used, the selected bot will be the bot you are looking at. NOTE: only the admins can use this command
	<botsource> pause			: The order is executed immediately. The bot(s) will be forced to start a pause. If "bot" botsource is used, the selected bot will be the bot you are looking at. NOTE: only the admins can use this command
	<botsource> dump			: The order is executed immediately. The bot(s) will print all their L4B2 AI data to the console. If "bot" botsource is used, the selected bot will be the bot you are looking at. NOTE: only the admins can use this command
	<botsource> move			: Alias of "<botsource> cancel all" (see below)


<botsource> cancel [switch]

<botsource> can be:
- bots (all the bots)
- botname (name of the bot)
("bot" botsource is not allowed here)

Available switches:
	current		: The given bot(s) will abort his/their current order and will proceed with the next one in the queue (if any)
	ordertype	: The given bot(s) will abort all his/their orders (current and queued ones) of type 'ordertype' (example: coach cancel lead)
	orders		: The given bot(s) will abort all his/their orders (current and queued ones) of any type
	defib		: The given bot(s) will abort any pending defib task. "botname cancel defib" is temporary (the bot will retry). "bots cancel defib" is permanent (currently dead survivors will be abandoned)
	all			: (or empty) The given bot(s) will abort everything (orders, defib, current pick-up, anything)


botselect [botname]

Selects the given bot as the destination of the next vocalizer command. If "botname" is omitted, the closest bot to your crosshair will be selected


settings

// TODO

*/
::Left4Bots.OnUserCommand <- function (player, arg1, arg2, arg3)
{
	local function GetFormattedCommandList(cmdArray)
	{
		local ret = "";
		for (local i = 0; i < cmdArray.len(); i++)
		{
			if (i == 0)
				ret += PRINTCOLOR_CYAN + cmdArray[i] + PRINTCOLOR_NORMAL;
			else
				ret += ", " + PRINTCOLOR_CYAN + cmdArray[i] + PRINTCOLOR_NORMAL;
		}
		return ret;
	}
	
	Left4Bots.Log(LOG_LEVEL_DEBUG, "OnUserCommand - player: " + player.GetPlayerName() + " - arg1: " + arg1 + " - arg2: " + arg2 + " - arg3: " + arg3);

	if (arg1 == "settings")
	{
		if (Left4Users.GetOnlineUserLevel(player.GetPlayerUserId()) < L4U_LEVEL.Admin)
			return false; // Only admins can change the settings

		if (arg2 in Left4Bots.Settings)
		{
			if (!arg3)
				ClientPrint(player, 3, PRINTCOLOR_NORMAL + "Current value for " + arg2 + ": " + Left4Bots.Settings[arg2]);
			else
			{
				try
				{
					/*
					local script = "::Left4Bots.Settings." + arg2 + " <- " + arg3;

					Left4Bots.Log(LOG_LEVEL_DEBUG, "OnUserCommand - script: " + script);

					local compiledscript = compilestring(script);
					compiledscript();
					*/
					
					Left4Bots.Settings[arg2] <- arg3;

					if (arg2 in ::Left4Bots.OnTankSettingsBak)
						::Left4Bots.OnTankSettingsBak[arg2] <- Left4Bots.Settings[arg2];

					// Probably not the best way to do this but at least we aren't saving the settings override to the settings.txt file and we don't need to worry about the OnTankSettings
					::Left4Bots.SettingsTmp <- {};
					Left4Utils.LoadSettingsFromFile("left4bots2/cfg/settings.txt", "Left4Bots.SettingsTmp.", Left4Bots.Log, true);
					::Left4Bots.SettingsTmp[arg2] <- Left4Bots.Settings[arg2];
					Left4Utils.SaveSettingsToFile("left4bots2/cfg/settings.txt", ::Left4Bots.SettingsTmp, Left4Bots.Log);

					// Maybe we can just keep this in memory and avoid to reload it every time?
					delete ::Left4Bots.SettingsTmp;

					if (arg2 == "should_hurry")
						DirectorScript.GetDirectorOptions().cm_ShouldHurry <- Left4Bots.Settings[arg2];
					else if (arg2 == "orders_debug")
					{
						for (local i = 1; i <= 4; i++)
						{
							local name = "l4b2debug" + i;
							Left4Hud.HideHud(name);
							Left4Hud.RemoveHud(name);
							if (Left4Bots.Settings.orders_debug)
							{
								Left4Hud.AddHud(name, g_ModeScript["HUD_SCORE_" + i], g_ModeScript.HUD_FLAG_NOTVISIBLE | g_ModeScript.HUD_FLAG_ALIGN_LEFT);
								Left4Hud.PlaceHud(name, 0.01, 0.15 + (0.05 * (i - 1)), 0.8, 0.05);
								Left4Hud.ShowHud(name);
							}
						}
					}

					ClientPrint(player, 3, PRINTCOLOR_GREEN + "Value of setting " + arg2 + " changed to: " + Left4Bots.Settings[arg2]);
				}
				catch(exception)
				{
					Left4Bots.Log(LOG_LEVEL_ERROR, "Error changing value of setting: " + arg2 + " - new value: " + arg3 + " - error: " + exception);
					ClientPrint(player, 3, PRINTCOLOR_ORANGE + "Error changing value of setting " + arg2);
				}
			}
		}
		else
			ClientPrint(player, 3, PRINTCOLOR_ORANGE + "Invalid setting: " + arg2);
	}
	else if (arg1 == "botselect")
	{
		local tgtBot = null;
		if (arg2)
			tgtBot = Left4Bots.GetBotByName(arg2);
		else
			tgtBot = Left4Bots.GetPickerBot(player); // player, radius = 999999, threshold = 0.95, visibleOnly = false

		if (!tgtBot)
			return false; // Invalid target

		player.SetContext("subject", Left4Utils.GetActorFromSurvivor(tgtBot), 0.1);
		player.SetContext("subjectid", tgtBot.GetPlayerUserId().tostring(), 0.1);
		//DoEntFire("!self", "AddContext", "subject:" + Left4Utils.GetActorFromSurvivor(tgtBot), 0, null, player);
		DoEntFire("!self", "SpeakResponseConcept", "PlayerLook", 0, null, player);
		//DoEntFire("!self", "ClearContext", "", 0, null, player);
	}
	else if (arg1 == "help")
	{
		if (arg2)
		{
			local adminCommand = ::Left4Bots.AdminCommands.find(arg2) != null;
			if (adminCommand || ::Left4Bots.UserCommands.find(arg2) != null)
			{
				if (adminCommand && Left4Users.GetOnlineUserLevel(player.GetPlayerUserId()) < L4U_LEVEL.Admin)
				{
					ClientPrint(player, 3, PRINTCOLOR_ORANGE + "You don't have access to that command");
					return true; // Not an admin
				}
				
				local helpTxt = Left4Bots["CmdHelp_" + arg2]();
				local helpLines = split(helpTxt, "\n");
				for (local i = 0; i < helpLines.len(); i++)
					ClientPrint(player, 3, helpLines[i]);

				return true;
			}
			
			ClientPrint(player, 3, PRINTCOLOR_ORANGE + "Command not found: " + arg2);
			return true;
		}
		
		if (Left4Users.GetOnlineUserLevel(player.GetPlayerUserId()) >= L4U_LEVEL.Admin)
			ClientPrint(player, 3, PRINTCOLOR_GREEN + "Admin Commands" + PRINTCOLOR_NORMAL + ": " + GetFormattedCommandList(::Left4Bots.AdminCommands));
		ClientPrint(player, 3, PRINTCOLOR_GREEN + "User Commands" + PRINTCOLOR_NORMAL + ": " + GetFormattedCommandList(::Left4Bots.UserCommands));
		ClientPrint(player, 3, PRINTCOLOR_NORMAL + "Type: '" + PRINTCOLOR_GREEN + "!l4b help " + PRINTCOLOR_CYAN + "command" + PRINTCOLOR_NORMAL + "' for more info on a specific command");
	}
	else
{
		// normal bot commands

		local allBots = false;	// true = "bots" keyword was used, tgtBot is ignored (will be null)
		local tgtBot = null;	// (allBots = false) null = "bot" keyword was used, tgtBot will be automatically selected - not null = "[botname]" was used, tgtBot is the selected bot

		if (arg1 == "bots")
			allBots = true;
		else if (arg1 != "bot")
		{
			tgtBot = Left4Bots.GetBotByName(arg1);
			if (!tgtBot)
				return false; // Invalid target
		}

		local adminCommand = ::Left4Bots.AdminCommands.find(arg2) != null;
		if (adminCommand || ::Left4Bots.UserCommands.find(arg2) != null)
		{
			if (adminCommand && Left4Users.GetOnlineUserLevel(player.GetPlayerUserId()) < L4U_LEVEL.Admin)
				return false; // Not an admin
			
			// Call the cmd function (Left4Bots.Cmd_command)
			Left4Bots["Cmd_" + arg2](player, allBots, tgtBot, arg3);
			
			return true;
		}
	}

	return false;
}

//

::Left4Bots.AllowTakeDamage <- function (damageTable)
{
	local victim = damageTable.Victim;
	local attacker = damageTable.Attacker;

	if (victim == null || attacker == null)
		return null;

	local attackerTeam = NetProps.GetPropInt(attacker, "m_iTeamNum");

	if (attackerTeam != TEAM_SURVIVORS && attackerTeam != TEAM_L4D1_SURVIVORS)
	{
		if (victim.IsPlayer() && NetProps.GetPropInt(victim, "m_iTeamNum") == TEAM_SURVIVORS && IsPlayerABot(victim) && "Inflictor" in damageTable && damageTable.Inflictor && damageTable.Inflictor.GetClassname() == "insect_swarm")
		{
			damageTable.DamageDone = damageTable.DamageDone * Left4Bots.Settings.spit_damage_multiplier;
			return (damageTable.DamageDone > 0);
		}
		return null;
	}

	if (!attacker.IsPlayer() || !IsPlayerABot(attacker))
		return null;

	//if (Left4Bots.Settings.trigger_caralarm && victim.GetClassname() == "prop_car_alarm" && (victim.GetOrigin() - attacker.GetOrigin()).Length() <= 730 && damageTable.DamageType != DMG_BURN && damageTable.DamageType != (DMG_BURN + DMG_PREVENT_PHYSICS_FORCE))
	if (Left4Bots.Settings.trigger_caralarm && victim.GetClassname() == "prop_car_alarm" && (victim.GetOrigin() - attacker.GetOrigin()).Length() <= 730 && (!("Inflictor" in damageTable) || !damageTable.Inflictor || damageTable.Inflictor.GetClassname() != "inferno"))
	{
		Left4Bots.TriggerCarAlarm(attacker, victim);
		return null;
	}

	if (!victim.IsPlayer() || attacker.GetPlayerUserId() == victim.GetPlayerUserId() || NetProps.GetPropInt(victim, "m_iTeamNum") != TEAM_SURVIVORS)
		return null;

	if (Left4Bots.Settings.jockey_redirect_damage == 0)
		return null;

	// TODO filter the weapon (damageTable.Weapon) ?

	local jockey = NetProps.GetPropEntity(victim, "m_jockeyAttacker");
	if (!jockey || !jockey.IsValid())
		return null;

	//Left4Bots.Log(LOG_LEVEL_DEBUG, "AllowTakeDamage - attacker: " + attacker.GetPlayerName() + " - victim: " + victim.GetPlayerName() + " - damage: " + damageTable.DamageDone + " - type: " + damageTable.DamageType + " - weapon: " + damageTable.Weapon);

	jockey.TakeDamage(Left4Bots.Settings.jockey_redirect_damage, damageTable.DamageType, attacker);

	return false;
}

::Left4Bots.HandleCommand <- function (player, cmd, args, text)
{
	if (!player || !player.IsValid() || IsPlayerABot(player) || Left4Users.GetOnlineUserLevel(player.GetPlayerUserId()) < Left4Bots.Settings.userlevel_orders)
		return;

	if (cmd != "settings" && cmd != "botselect" && cmd != "help" && args.len() < 3) // Normal bot commands have at least 2 arguments (excluding 'l4b')
		return;

	local arg2 = null;
	if (args.len() > 2)
		arg2 = strip(args[2].tolower());

	local arg3 = null;
	if (args.len() > 3)
		arg3 = strip(args[3]);

	Left4Bots.OnUserCommand(player, cmd, arg2, arg3);
}

// Moved to left4bots.nut
//__CollectEventCallbacks(::Left4Bots.Events, "OnGameEvent_", "GameEventCallbacks", RegisterScriptGameEventListener);
