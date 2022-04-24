#if defined _sf2_game_events_included
 #endinput
#endif
#define _sf2_game_events_included

public Action Event_RoundStart(Handle event, const char[] name, bool dB)
{
	if (!g_bEnabled) return;
	
	#if defined DEBUG
	Handle hProf = CreateProfiler();
	StartProfiling(hProf);
	SendDebugMessageToPlayers(DEBUG_EVENT, 0, "(Event_RoundStart) Started profiling...");
	
	if (g_cvDebugDetail.IntValue > 0) DebugMessage("EVENT START: Event_RoundStart");
	#endif
	
	// Reset some global variables.
	g_iRoundCount++;
	g_hRoundTimer = null;
	g_bRoundTimerPaused = false;
	
	SetRoundState(SF2RoundState_Invalid);
	
	SetPageCount(0);
	g_iPageMax = 0;
	g_flPageFoundLastTime = GetGameTime();
	
	g_hVoteTimer = null;
	//Stop the music if needed.
	NPCStopMusic();
	// Remove all bosses from the game.
	NPCRemoveAll();
	// Collect trigger_multiple to prevent touch bug.
	SF_CollectTriggersMultiple();
	// Refresh groups.
	for (int i = 0; i < SF2_MAX_PLAYER_GROUPS; i++)
	{
		SetPlayerGroupPlaying(i, false);
		CheckPlayerGroup(i);
	}
	
	// Refresh players.
	for (int i = 1; i <= MaxClients; i++)
	{
		ClientSetGhostModeState(i, false);
		
		g_bPlayerPlaying[i] = false;
		g_bPlayerEliminated[i] = true;
		g_bPlayerEscaped[i] = false;
	}
	SF_RemoveAllSpecialRound();
	// Calculate the new round state.
	if (g_bRoundWaitingForPlayers)
	{
		int ent = -1;
		while ((ent = FindEntityByClassname(ent, "func_regenerate")) != -1)
		{
			AcceptEntityInput(ent, "Disable");
		}
		SetRoundState(SF2RoundState_Waiting);
	}
	else if (g_cvWarmupRound.BoolValue && g_iRoundWarmupRoundCount < g_cvWarmupRoundNum.IntValue)
	{
		int ent = -1;
		while ((ent = FindEntityByClassname(ent, "func_regenerate")) != -1)
		{
			AcceptEntityInput(ent, "Disable");
		}
		
		g_iRoundWarmupRoundCount++;
		
		SetRoundState(SF2RoundState_Waiting);
		
		ServerCommand("mp_restartgame 15");
		PrintCenterTextAll("Round restarting in 15 seconds");
	}
	else
	{
		g_iRoundActiveCount++;
		
		InitializeNewGame();
	}
	
	PvP_OnRoundStart();
	#if defined DEBUG
	if (g_cvDebugDetail.IntValue > 0) DebugMessage("EVENT END: Event_RoundStart");
	
	StopProfiling(hProf);
	SendDebugMessageToPlayers(DEBUG_EVENT, 0, "(Event_RoundStart) Stopped profiling, total execution time: %f", GetProfilerTime(hProf));
	delete hProf;
	
	#endif
	//Nextbot doesn't trigger the triggers with npc flags, for map backward compatibility we are going to change the trigger filter and force a custom one.
	/*int iEnt = -1;
	while ((iEnt = FindEntityByClassname(iEnt, "trigger_*")) != -1)
	{
		if(IsValidEntity(iEnt))
		{
			int flags = GetEntProp(iEnt, Prop_Data, "m_spawnflags");
			if ((flags & TRIGGER_NPCS) && !(flags & TRIGGER_EVERYTHING_BUT_PHYSICS_DEBRIS))
			{
				//Set the trigger to allow every entity, our custom filter will discard the unwanted entities.
				SetEntProp(iEnt, Prop_Data, "m_spawnflags", flags|TRIGGER_EVERYTHING_BUT_PHYSICS_DEBRIS);
				SDKHook(iEnt, SDKHook_StartTouch, Hook_TriggerNPCTouch);
				SDKHook(iEnt, SDKHook_Touch, Hook_TriggerNPCTouch);
				SDKHook(iEnt, SDKHook_EndTouch, Hook_TriggerNPCTouch);
			}
		}
	}*/
}

public Action Event_WinPanel(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bEnabled) return Plugin_Continue;
	
	char cappers[7];
	int i = 0;
	for (int client; client <= MaxClients; client++)
	{
		if (IsValidClient(client) && DidClientEscape(client) && i < 7)
		{
			cappers[i] = client;
			event.SetString("cappers", cappers);
			i += 1;
		}
	}
	delete event;
	return Plugin_Continue;
}

public Action Event_Audio(Event event, const char[] name, bool dB)
{
	char strAudio[PLATFORM_MAX_PATH];
	
	GetEventString(event, "sound", strAudio, sizeof(strAudio));
	if (strncmp(strAudio, "Game.Your", 9) == 0 || strcmp(strAudio, "Game.Stalemate") == 0)
	{
		for (int iBossIndex = 0; iBossIndex < MAX_BOSSES; iBossIndex++)
		{
			if (NPCGetUniqueID(iBossIndex) == -1) continue;
			if (!g_bSlenderCustomOutroSong[iBossIndex]) continue;
			
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

public Action Event_RoundEnd(Handle event, const char[] name, bool dB)
{
	if (!g_bEnabled) return;
	
	#if defined DEBUG
	if (g_cvDebugDetail.IntValue > 0) DebugMessage("EVENT START: Event_RoundEnd");
	#endif
	
	SF_FailEnd();

	if (SF_IsRenevantMap() && g_hRenevantWaveTimer != null) KillTimer(g_hRenevantWaveTimer);
	
	for (int i = 1; i < MaxClients; i++)
	{
		if (!IsValidClient(i)) continue;
		g_bPlayerDied1Up[i] = false;
		g_bPlayerIn1UpCondition[i] = false;
		g_bPlayerFullyDied1Up[i] = true;
	}
	
	ArrayList aRandomBosses = new ArrayList();
	char sMusic[MAX_BOSSES][PLATFORM_MAX_PATH];
	
	for (int iNPCIndex = 0; iNPCIndex < MAX_BOSSES; iNPCIndex++)
	{
		if (NPCGetUniqueID(iNPCIndex) == -1) continue;
		
		if (g_bSlenderCustomOutroSong[iNPCIndex])
		{
			char profile[SF2_MAX_PROFILE_NAME_LENGTH];
			NPCGetProfile(iNPCIndex, profile, sizeof(profile));
			GetRandomStringFromProfile(profile, "sound_music_outro", sMusic[iNPCIndex], sizeof(sMusic[]));
			if (sMusic[iNPCIndex][0] != '\0') aRandomBosses.Push(iNPCIndex);
		}
	}
	if (aRandomBosses.Length > 0)
	{
		int iNewBossIndex = aRandomBosses.Get(GetRandomInt(0, aRandomBosses.Length - 1));
		if (NPCGetUniqueID(iNewBossIndex) != -1)
			EmitSoundToAll(sMusic[iNewBossIndex], _, SNDCHAN_AUTO, SNDLEVEL_SCREAMING);
	}
	
	delete aRandomBosses;
	
	SpecialRound_RoundEnd();
	
	SetRoundState(SF2RoundState_Outro);
	
	DistributeQueuePointsToPlayers();
	
	g_iRoundEndCount++;
	CheckRoundLimitForBossPackVote(g_iRoundEndCount);
	
	#if defined DEBUG
	if (g_cvDebugDetail.IntValue > 0) DebugMessage("EVENT END: Event_RoundEnd");
	#endif
	delete event;
}

public Action Event_PlayerTeamPre(Handle event, const char[] name, bool dB)
{
	if (!g_bEnabled) return Plugin_Continue;
	
	#if defined DEBUG
	if (g_cvDebugDetail.IntValue > 1) DebugMessage("EVENT START: Event_PlayerTeamPre");
	#endif
	
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client > 0)
	{
		if (GetEventInt(event, "team") > 1 || GetEventInt(event, "oldteam") > 1) SetEventBroadcast(event, true);
	}
	
	#if defined DEBUG
	if (g_cvDebugDetail.IntValue > 1) DebugMessage("EVENT END: Event_PlayerTeamPre");
	#endif
	
	delete event;
	
	return Plugin_Continue;
}

public Action Event_PlayerTeam(Handle event, const char[] name, bool dB)
{
	if (!g_bEnabled) return;
	
	#if defined DEBUG
	if (g_cvDebugDetail.IntValue > 0) DebugMessage("EVENT START: Event_PlayerTeam");
	#endif
	
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client > 0)
	{
		int iintTeam = GetEventInt(event, "team");
		if (iintTeam <= TFTeam_Spectator)
		{
			if (!IsRoundPlaying())
			{
				if (g_bPlayerPlaying[client] && !g_bPlayerEliminated[client])
				{
					ForceInNextPlayersInQueue(1, true);
				}
			}
			
			// You're not playing anymore.
			if (g_bPlayerPlaying[client])
			{
				ClientSetQueuePoints(client, 0);
			}
			
			g_bPlayerPlaying[client] = false;
			g_bPlayerEliminated[client] = true;
			g_bPlayerEscaped[client] = false;
			
			ClientSetGhostModeState(client, false);
			
			if (!view_as<bool>(GetEntProp(client, Prop_Send, "m_bIsCoaching")))
			{
				// This is to prevent player spawn spam when someone is coaching. Who coaches in SF2, anyway?
				TF2_RespawnPlayer(client);
			}
			
			// Special round.
			if (g_bSpecialRound) g_bPlayerPlayedSpecialRound[client] = true;
			
			// Boss round.
			if (g_bNewBossRound) g_bPlayerPlayedNewBossRound[client] = true;
			
			if (!g_cvFullyEnableSpectator.BoolValue) g_hPlayerSwitchBlueTimer[client] = CreateTimer(0.5, Timer_PlayerSwitchToBlue, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		}
		else
		{
			if (!g_bPlayerChoseTeam[client])
			{
				g_bPlayerChoseTeam[client] = true;
				
				if (g_iPlayerPreferences[client].PlayerPreference_ProjectedFlashlight)
				{
					EmitSoundToClient(client, SF2_PROJECTED_FLASHLIGHT_CONFIRM_SOUND);
					CPrintToChat(client, "%T", "SF2 Projected Flashlight", client);
				}
				else
				{
					CPrintToChat(client, "%T", "SF2 Normal Flashlight", client);
				}
				
				CreateTimer(5.0, Timer_WelcomeMessage, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
			}
			if (SF_SpecialRound(SPECIALROUND_THANATOPHOBIA) && !g_bPlayerEliminated[client] && iintTeam == TFTeam_Red && 
				TF2_GetPlayerClass(client) == TFClass_Medic && !DidClientEscape(client))
			{
				ShowVGUIPanel(client, "class_red");
				EmitSoundToClient(client, THANATOPHOBIA_MEDICNO);
				TFClassType newClass;
				int iRandom = GetRandomInt(1, 8);
				switch (iRandom)
				{
					case 1: newClass = TFClass_Scout;
					case 2: newClass = TFClass_Soldier;
					case 3: newClass = TFClass_Pyro;
					case 4: newClass = TFClass_DemoMan;
					case 5: newClass = TFClass_Heavy;
					case 6: newClass = TFClass_Engineer;
					case 7: newClass = TFClass_Sniper;
					case 8: newClass = TFClass_Spy;
				}
				TF2_SetPlayerClass(client, newClass);
				TF2_RegeneratePlayer(client);
			}
		}
	}
	
	// Check groups.
	if (!IsRoundEnding())
	{
		for (int i = 0; i < SF2_MAX_PLAYER_GROUPS; i++)
		{
			if (!IsPlayerGroupActive(i)) continue;
			CheckPlayerGroup(i);
		}
	}
	
	#if defined DEBUG
	if (g_cvDebugDetail.IntValue > 0) DebugMessage("EVENT END: Event_PlayerTeam");
	#endif
	delete event;
}

public Action Event_PlayerSpawn(Handle event, const char[] name, bool dB)
{
	if (!g_bEnabled) return;
	
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client <= 0) return;
	#if defined DEBUG
	
	Handle hProf = CreateProfiler();
	StartProfiling(hProf);
	SendDebugMessageToPlayers(DEBUG_EVENT, 0, "(Event_PlayerSpawn) Started profiling...");

	//PrintToChatAll("(SPAWN) Spawn event called.");
	if (g_cvDebugDetail.IntValue > 0) DebugMessage("EVENT START: Event_PlayerSpawn(%d)", client);
	#endif
	
	if (GetClientTeam(client) > 1)
	{
		g_flLastVisibilityProcess[client] = GetGameTime();
		ClientResetStatic(client);
		if (!g_bSeeUpdateMenu[client])
		{
			g_bSeeUpdateMenu[client] = true;
			DisplayMenu(g_hMenuUpdate, client, 30);
		}
	}
	if (!IsClientParticipating(client))
	{
		TF2Attrib_SetByName(client, "increased jump height", 1.0);
		TF2Attrib_RemoveByDefIndex(client, 10);
		
		ClientSetGhostModeState(client, false);
		SetEntityGravity(client, 1.0);
		g_iPlayerPageCount[client] = 0;
		
		ClientResetStatic(client);
		ClientResetSlenderStats(client);
		ClientResetCampingStats(client);
		ClientResetOverlay(client);
		ClientResetJumpScare(client);
		ClientUpdateListeningFlags(client);
		ClientUpdateMusicSystem(client);
		ClientChaseMusicReset(client);
		ClientChaseMusicSeeReset(client);
		ClientAlertMusicReset(client);
		ClientIdleMusicReset(client);
		Client20DollarsMusicReset(client);
		Client90sMusicReset(client);
		ClientMusicReset(client);
		ClientResetProxy(client);
		ClientResetHints(client);
		ClientResetScare(client);
		
		ClientResetDeathCam(client);
		ClientResetFlashlight(client);
		ClientDeactivateUltravision(client);
		ClientResetSprint(client);
		ClientResetBreathing(client);
		ClientResetBlink(client);
		ClientResetInteractiveGlow(client);
		ClientDisableConstantGlow(client);
		
		ClientHandleGhostMode(client);

		for (int iNPCIndex = 0; iNPCIndex < MAX_BOSSES; iNPCIndex++)
		{
			if (NPCGetUniqueID(iNPCIndex) == -1) continue;
			if (g_aNPCChaseOnLookTarget[iNPCIndex] == null) continue;
			int iFoundClient = g_aNPCChaseOnLookTarget[iNPCIndex].FindValue(client);
			if (iFoundClient != -1) g_aNPCChaseOnLookTarget[iNPCIndex].Erase(iFoundClient);
		}
	}
	
	if (SF_IsBoxingMap() && IsRoundInEscapeObjective())
	{
		CreateTimer(0.2, Timer_CheckAlivePlayers, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	
	g_hPlayerPostWeaponsTimer[client] = null;
	g_hPlayerIgniteTimer[client] = null;
	g_hPlayerResetIgnite[client] = null;
	g_hPlayerPageRewardTimer[client] = null;
	g_hPlayerPageRewardCycleTimer[client] = null;
	g_hPlayerFireworkTimer[client] = null;

	g_iPlayerBossKillSubject[client] = INVALID_ENT_REFERENCE;
	
	g_bPlayerGettingPageReward[client] = false;
	g_iPlayerHitsToCrits[client] = 0;
	g_iPlayerHitsToHeads[client] = 0;
	
	g_bPlayerTrapped[client] = false;
	g_iPlayerTrapCount[client] = 0;
	
	g_iPlayerRandomClassNumber[client] = 1;
	
	if (IsPlayerAlive(client) && IsClientParticipating(client))
	{
		if (MusicActive() || SF_SpecialRound(SPECIALROUND_TRIPLEBOSSES)) //A boss is overriding the music.
		{
			char sPath[PLATFORM_MAX_PATH];
			GetBossMusic(sPath, sizeof(sPath));
			if (sPath[0] != '\0') StopSound(client, MUSIC_CHAN, sPath);
			if (SF_SpecialRound(SPECIALROUND_TRIPLEBOSSES))
			{
				StopSound(client, MUSIC_CHAN, TRIPLEBOSSESMUSIC);
			}
		}
		g_bBackStabbed[client] = false;
		TF2_RemoveCondition(client, TFCond_HalloweenKart);
		TF2_RemoveCondition(client, TFCond_HalloweenKartDash);
		TF2_RemoveCondition(client, TFCond_HalloweenKartNoTurn);
		TF2_RemoveCondition(client, TFCond_HalloweenKartCage);
		TF2_RemoveCondition(client, TFCond_SpawnOutline);
		
		if (HandlePlayerTeam(client))
		{
			#if defined DEBUG
			if (g_cvDebugDetail.IntValue > 0) DebugMessage("client->HandlePlayerTeam()");
			#endif
		}
		else
		{
			g_iPlayerPageCount[client] = 0;
			
			ClientResetStatic(client);
			ClientResetSlenderStats(client);
			ClientResetCampingStats(client);
			ClientResetOverlay(client);
			ClientResetJumpScare(client);
			ClientUpdateListeningFlags(client);
			ClientUpdateMusicSystem(client);
			ClientChaseMusicReset(client);
			ClientChaseMusicSeeReset(client);
			ClientAlertMusicReset(client);
			ClientIdleMusicReset(client);
			Client20DollarsMusicReset(client);
			Client90sMusicReset(client);
			ClientMusicReset(client);
			ClientResetProxy(client);
			ClientResetHints(client);
			ClientResetScare(client);
			
			ClientResetDeathCam(client);
			ClientResetFlashlight(client);
			ClientDeactivateUltravision(client);
			ClientResetSprint(client);
			ClientResetBreathing(client);
			ClientResetBlink(client);
			ClientResetInteractiveGlow(client);
			ClientDisableConstantGlow(client);
			
			ClientHandleGhostMode(client);

			for (int iNPCIndex = 0; iNPCIndex < MAX_BOSSES; iNPCIndex++)
			{
				if (NPCGetUniqueID(iNPCIndex) == -1) continue;
				if (g_aNPCChaseOnLookTarget[iNPCIndex] == null) continue;
				int iFoundClient = g_aNPCChaseOnLookTarget[iNPCIndex].FindValue(client);
				if (iFoundClient != -1) g_aNPCChaseOnLookTarget[iNPCIndex].Erase(iFoundClient);
			}
			
			TF2Attrib_SetByName(client, "increased jump height", 1.0);
			
			if (!g_bPlayerEliminated[client])
			{
				if ((SF_IsRaidMap() || SF_IsBoxingMap()) && !IsRoundPlaying())
					TF2Attrib_SetByDefIndex(client, 10, 7.0);
				else
					TF2Attrib_RemoveByDefIndex(client, 10);
				
				TF2Attrib_SetByDefIndex(client, 49, 1.0);
				
				ClientStartDrainingBlinkMeter(client);
				ClientSetScareBoostEndTime(client, -1.0);
				
				ClientStartCampingTimer(client);
				
				HandlePlayerIntroState(client);
				
				if (IsFakeClient(client))
				{
					CreateTimer(0.1, Timer_SwitchBot, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
				}
				
				// screen overlay timer
				if (!SF_IsRaidMap() && !SF_IsBoxingMap())
				{
					g_hPlayerOverlayCheck[client] = CreateTimer(0.0, Timer_PlayerOverlayCheck, GetClientUserId(client), TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
					TriggerTimer(g_hPlayerOverlayCheck[client], true);
				}
				if (DidClientEscape(client))
				{
					CreateTimer(0.1, Timer_TeleportPlayerToEscapePoint, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
				}
				else
				{
					int iRed[4] = { 184, 56, 59, 255 };
					ClientEnableConstantGlow(client, "head", iRed);
					ClientActivateUltravision(client);
				}

				if (SF_IsRenevantMap() && g_bRenevantMarkForDeath && !DidClientEscape(client))
				{
					TF2_AddCondition(client, TFCond_MarkedForDeathSilent, -1.0);
				}
				
				if (SF_SpecialRound(SPECIALROUND_1UP) && !g_bPlayerIn1UpCondition[client] && !g_bPlayerDied1Up[client])
				{
					g_bPlayerDied1Up[client] = false;
					g_bPlayerIn1UpCondition[client] = true;
					g_bPlayerFullyDied1Up[client] = false;
				}
				
				if (SF_SpecialRound(SPECIALROUND_PAGEDETECTOR))
					ClientSetSpecialRoundTimer(client, 0.0, Timer_ClientPageDetector, GetClientUserId(client));

				if (SF_SpecialRound(SPECIALROUND_THANATOPHOBIA) && TF2_GetPlayerClass(client) == TFClass_Medic && !DidClientEscape(client))
				{
					ShowVGUIPanel(client, "class_red");
					EmitSoundToClient(client, THANATOPHOBIA_MEDICNO);
					TFClassType newClass;
					int iRandom = GetRandomInt(1, 8);
					switch (iRandom)
					{
						case 1:newClass = TFClass_Scout;
						case 2:newClass = TFClass_Soldier;
						case 3:newClass = TFClass_Pyro;
						case 4:newClass = TFClass_DemoMan;
						case 5:newClass = TFClass_Heavy;
						case 6:newClass = TFClass_Engineer;
						case 7:newClass = TFClass_Sniper;
						case 8:newClass = TFClass_Spy;
					}
					TF2_SetPlayerClass(client, newClass);
					TF2_RegeneratePlayer(client);
				}
			}
			else
			{
				g_hPlayerOverlayCheck[client] = null;
				TF2Attrib_RemoveByDefIndex(client, 10);
				TF2Attrib_RemoveByDefIndex(client, 49);
			}
			ClientSwitchToWeaponSlot(client, TFWeaponSlot_Melee);
			g_hPlayerPostWeaponsTimer[client] = CreateTimer(0.1, Timer_ClientPostWeapons, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
			
			HandlePlayerHUD(client);
		}
	}
	
	PvP_OnPlayerSpawn(client);
	
	#if defined DEBUG
	if (g_cvDebugDetail.IntValue > 0)DebugMessage("EVENT END: Event_PlayerSpawn(%d)", client);
	
	StopProfiling(hProf);
	SendDebugMessageToPlayers(DEBUG_EVENT, 0, "(Event_PlayerSpawn) Stopped profiling, function executed in %f", GetProfilerTime(hProf));
	delete hProf;
	#endif
	
	delete event;
}

public void Event_PlayerClass(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0) return;
	
	int iTeam = GetClientTeam(client);
	
	if (SF_SpecialRound(SPECIALROUND_THANATOPHOBIA) && !g_bPlayerEliminated[client] && 
		iTeam == TFTeam_Red && TF2_GetPlayerClass(client) == TFClass_Medic && !DidClientEscape(client))
	{
		ShowVGUIPanel(client, "class_red");
		EmitSoundToClient(client, THANATOPHOBIA_MEDICNO);
		TFClassType newClass;
		int iRandom = GetRandomInt(1, 8);
		switch (iRandom)
		{
			case 1:newClass = TFClass_Scout;
			case 2:newClass = TFClass_Soldier;
			case 3:newClass = TFClass_Pyro;
			case 4:newClass = TFClass_DemoMan;
			case 5:newClass = TFClass_Heavy;
			case 6:newClass = TFClass_Engineer;
			case 7:newClass = TFClass_Sniper;
			case 8:newClass = TFClass_Spy;
		}
		TF2_SetPlayerClass(client, newClass);
		TF2_RegeneratePlayer(client);
	}
}

public Action Event_PostInventoryApplication(Handle event, const char[] name, bool dB)
{
	if (!g_bEnabled) return;
	
	#if defined DEBUG
	if (g_cvDebugDetail.IntValue > 0) DebugMessage("EVENT START: Event_PostInventoryApplication");
	#endif
	
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client > 0)
	{
		ClientSwitchToWeaponSlot(client, TFWeaponSlot_Melee);
		g_hPlayerPostWeaponsTimer[client] = CreateTimer(0.1, Timer_ClientPostWeapons, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	
	#if defined DEBUG
	if (g_cvDebugDetail.IntValue > 0) DebugMessage("EVENT END: Event_PostInventoryApplication");
	#endif
	delete event;
}
public Action Event_DontBroadcastToClients(Handle event, const char[] name, bool dB)
{
	if (!g_bEnabled) return Plugin_Continue;
	if (IsRoundInWarmup()) return Plugin_Continue;
	
	SetEventBroadcast(event, true);
	delete event;
	return Plugin_Continue;
}

public Action Event_PlayerDeathPre(Event event, const char[] name, bool dB)
{
	if (!g_bEnabled) return Plugin_Continue;
	
	#if defined DEBUG
	if (g_cvDebugDetail.IntValue > 1) DebugMessage("EVENT START: Event_PlayerDeathPre");
	#endif
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	int inflictor = event.GetInt("inflictor_entindex");
	
	// If this player was killed by a boss, play a sound.
	int npcIndex = NPCGetFromEntIndex(inflictor);
	if (npcIndex != -1 && !IsEntityAProjectile(inflictor))
	{
		int iTarget = GetClientOfUserId(g_iSourceTVUserID);
		int attackIndex = NPCGetCurrentAttackIndex(npcIndex);
		if (MaxClients < iTarget || iTarget < 1 || !IsClientInGame(iTarget) || !IsClientSourceTV(iTarget)) //If the server has a source TV bot uses to print boss' name in kill feed.
			iTarget = GetClientForDeath(client);

		if (iTarget != -1)
		{
			if (g_hTimerChangeClientName[iTarget] != null)
				KillTimer(g_hTimerChangeClientName[iTarget]);
			else 
				GetEntPropString(iTarget, Prop_Data, "m_szNetname", g_sOldClientName[iTarget], sizeof(g_sOldClientName[]));
			
			char sBossName[SF2_MAX_NAME_LENGTH], profile[SF2_MAX_PROFILE_NAME_LENGTH];
			NPCGetProfile(npcIndex, profile, sizeof(profile));
			NPCGetBossName(npcIndex, sBossName, sizeof(sBossName));
			
			//TF2_ChangePlayerName(iTarget, sBossName, true);
			SetClientName(iTarget, sBossName);
			SetEntPropString(iTarget, Prop_Data, "m_szNetname", sBossName);
			
			event.SetString("assister_fallback", "");
			if ((NPCGetFlags(npcIndex) & SFF_WEAPONKILLS) || (NPCGetFlags(npcIndex) & SFF_WEAPONKILLSONRADIUS))
			{
				if (NPCGetFlags(npcIndex) & SFF_WEAPONKILLS)
				{
					char sWeaponType[PLATFORM_MAX_PATH];
					int iWeaponNum = NPCChaserGetAttackWeaponTypeInt(npcIndex, attackIndex);
					GetProfileAttackString(profile, "attack_weapontype", sWeaponType, sizeof(sWeaponType), "", attackIndex + 1);
					event.SetString("weapon_logclassname", sWeaponType);
					event.SetString("weapon", sWeaponType);
					event.SetInt("customkill", iWeaponNum);
				}
				else if (NPCGetFlags(npcIndex) & SFF_WEAPONKILLSONRADIUS)
				{
					char sWeaponType[PLATFORM_MAX_PATH];
					int iWeaponNum = GetProfileNum(profile, "kill_weapontypeint", 0);
					GetProfileString(profile, "kill_weapontype", sWeaponType, sizeof(sWeaponType));
					event.SetString("weapon_logclassname", sWeaponType);
					event.SetString("weapon", sWeaponType);
					event.SetInt("customkill", iWeaponNum);
				}
			}
			else
			{
				event.SetString("weapon", "");
				event.SetString("weapon_logclassname", "");
			}
			
			int userid = GetClientUserId(iTarget);
			event.SetInt("attacker", userid);
			g_hTimerChangeClientName[iTarget] = CreateTimer(0.6, Timer_RevertClientName, iTarget, TIMER_FLAG_NO_MAPCHANGE);

			if(IsValidClient(iTarget))
			{
				event.SetInt("ignore", iTarget);

				//Show a different attacker to the user were taking
				iTarget = GetClientForDeath(client, iTarget);
				if (iTarget != -1)
				{
					if (g_hTimerChangeClientName[iTarget] != null)
						KillTimer(g_hTimerChangeClientName[iTarget]);
					else 
						GetEntPropString(iTarget, Prop_Data, "m_szNetname", g_sOldClientName[iTarget], sizeof(g_sOldClientName[]));

					Format(sBossName, sizeof(sBossName), " %s", sBossName);

					//TF2_ChangePlayerName(iTarget, sBossName, true);
					SetClientName(iTarget, sBossName);
					SetEntPropString(iTarget, Prop_Data, "m_szNetname", sBossName);

					g_hTimerChangeClientName[iTarget] = CreateTimer(0.6, Timer_RevertClientName, iTarget, TIMER_FLAG_NO_MAPCHANGE);

					char sString[64];
					Event event2 = CreateEvent("player_death", true);
					event2.SetInt("userid", event.GetInt("userid"));
					event2.SetInt("victim_entindex", event.GetInt("victim_entindex"));
					event2.SetInt("inflictor_entindex", event.GetInt("inflictor_entindex"));
					event2.SetInt("attacker", GetClientUserId(iTarget));
					event2.SetInt("weaponid", event.GetInt("weaponid"));
					event2.SetInt("damagebits", event.GetInt("damagebits"));
					event2.SetInt("customkill", event.GetInt("customkill"));
					event2.SetInt("assister", event.GetInt("assister"));
					event2.SetInt("stun_flags", event.GetInt("stun_flags"));
					event2.SetInt("death_flags", event.GetInt("death_flags"));
					event2.SetBool("silent_kill", event.GetBool("silent_kill"));
					event2.SetInt("playerpenetratecount", event.GetInt("playerpenetratecount"));
					event2.SetInt("kill_streak_total", event.GetInt("kill_streak_total"));
					event2.SetInt("kill_streak_wep", event.GetInt("kill_streak_wep"));
					event2.SetInt("kill_streak_assist", event.GetInt("kill_streak_assist"));
					event2.SetInt("kill_streak_victim", event.GetInt("kill_streak_victim"));
					event2.SetInt("ducks_streaked", event.GetInt("ducks_streaked"));
					event2.SetInt("duck_streak_total", event.GetInt("duck_streak_total"));
					event2.SetInt("duck_streak_assist", event.GetInt("duck_streak_assist"));
					event2.SetInt("duck_streak_victim", event.GetInt("duck_streak_victim"));
					event2.SetBool("rocket_jump", event.GetBool("rocket_jump"));
					event2.SetInt("weapon_def_index", event.GetInt("weapon_def_index"));
					event.GetString("weapon_logclassname", sString, sizeof(sString));
					event2.SetString("weapon_logclassname", sString);
					event.GetString("weapon", sString, sizeof(sString));
					event2.SetString("weapon", sString);
					event2.SetInt("send", userid);

					CreateTimer(0.2, Timer_SendDeathToSpecific, event2);
				}
			}
		}
	}

	#if defined DEBUG
	char sStringName[128];
	event.GetString("weapon", sStringName, sizeof(sStringName));
	SendDebugMessageToPlayers(DEBUG_KILLICONS, 0, "String kill icon is %s, integer kill icon is %i.", sStringName, event.GetInt("customkill"));
	#endif
	
	if (IsEntityAProjectile(inflictor))
	{
		int npcIndex2 = NPCGetFromEntIndex(GetEntPropEnt(inflictor, Prop_Send, "m_hOwnerEntity"));
		if (npcIndex2 != -1)
		{
			int iTarget = GetClientOfUserId(g_iSourceTVUserID);
			if (MaxClients < iTarget || iTarget < 1 || !IsClientInGame(iTarget) || !IsClientSourceTV(iTarget)) //If the server has a source TV bot uses to print boss' name in kill feed.
				iTarget = GetClientForDeath(client);

			if (iTarget != -1)
			{
				if (g_hTimerChangeClientName[iTarget] != null)
					KillTimer(g_hTimerChangeClientName[iTarget]);
				else //No timer running that means the SourceTV bot's current name is the correct one, we can safely update our last known SourceTV bot's name.
				GetEntPropString(iTarget, Prop_Data, "m_szNetname", g_sOldClientName[iTarget], sizeof(g_sOldClientName[]));
				
				char sBossName[SF2_MAX_NAME_LENGTH], profile[SF2_MAX_PROFILE_NAME_LENGTH];
				NPCGetProfile(npcIndex2, profile, sizeof(profile));
				NPCGetBossName(npcIndex2, sBossName, sizeof(sBossName));
				
				//TF2_ChangePlayerName(iTarget, sBossName, true);
				SetClientName(iTarget, sBossName);
				SetEntPropString(iTarget, Prop_Data, "m_szNetname", sBossName);
				
				event.SetString("assister_fallback", "");
				
				switch (ProjectileGetFlags(inflictor))
				{
					case PROJ_ROCKET:
					{
						event.SetString("weapon_logclassname", "tf_projectile_rocket");
						event.SetString("weapon", "tf_projectile_rocket");
					}
					case PROJ_MANGLER:
					{
						event.SetString("weapon_logclassname", "cow_mangler");
						event.SetString("weapon", "cow_mangler");
					}
					case PROJ_GRENADE:
					{
						event.SetString("weapon_logclassname", "tf_projectile_pipe");
						event.SetString("weapon", "tf_projectile_pipe");
					}
					case PROJ_FIREBALL, PROJ_ICEBALL, PROJ_FIREBALL_ATTACK, PROJ_ICEBALL_ATTACK:
					{
						event.SetString("weapon_logclassname", "spellbook_fireball");
						event.SetString("weapon", "spellbook_fireball");
					}
					case PROJ_SENTRYROCKET:
					{
						event.SetString("weapon_logclassname", "obj_sentrygun3");
						event.SetString("weapon", "obj_sentrygun3");
					}
				}
				
				int userid = GetClientUserId(iTarget);
				event.SetInt("attacker", userid);
				g_hTimerChangeClientName[iTarget] = CreateTimer(0.6, Timer_RevertClientName, iTarget, TIMER_FLAG_NO_MAPCHANGE);

				if(IsValidClient(iTarget))
				{
					event.SetInt("ignore", iTarget);

					//Show a different attacker to the user were taking
					iTarget = GetClientForDeath(client, iTarget);
					if (iTarget != -1)
					{
						if (g_hTimerChangeClientName[iTarget] != null)
							KillTimer(g_hTimerChangeClientName[iTarget]);
						else 
							GetEntPropString(iTarget, Prop_Data, "m_szNetname", g_sOldClientName[iTarget], sizeof(g_sOldClientName[]));

						Format(sBossName, sizeof(sBossName), " %s", sBossName);

						//TF2_ChangePlayerName(iTarget, sBossName, true);
						SetClientName(iTarget, sBossName);
						SetEntPropString(iTarget, Prop_Data, "m_szNetname", sBossName);

						g_hTimerChangeClientName[iTarget] = CreateTimer(0.6, Timer_RevertClientName, iTarget, TIMER_FLAG_NO_MAPCHANGE);

						char sString[64];
						Event event2 = CreateEvent("player_death", true);
						event2.SetInt("userid", event.GetInt("userid"));
						event2.SetInt("victim_entindex", event.GetInt("victim_entindex"));
						event2.SetInt("inflictor_entindex", event.GetInt("inflictor_entindex"));
						event2.SetInt("attacker", GetClientUserId(iTarget));
						event2.SetInt("weaponid", event.GetInt("weaponid"));
						event2.SetInt("damagebits", event.GetInt("damagebits"));
						event2.SetInt("customkill", event.GetInt("customkill"));
						event2.SetInt("assister", event.GetInt("assister"));
						event2.SetInt("stun_flags", event.GetInt("stun_flags"));
						event2.SetInt("death_flags", event.GetInt("death_flags"));
						event2.SetBool("silent_kill", event.GetBool("silent_kill"));
						event2.SetInt("playerpenetratecount", event.GetInt("playerpenetratecount"));
						event2.SetInt("kill_streak_total", event.GetInt("kill_streak_total"));
						event2.SetInt("kill_streak_wep", event.GetInt("kill_streak_wep"));
						event2.SetInt("kill_streak_assist", event.GetInt("kill_streak_assist"));
						event2.SetInt("kill_streak_victim", event.GetInt("kill_streak_victim"));
						event2.SetInt("ducks_streaked", event.GetInt("ducks_streaked"));
						event2.SetInt("duck_streak_total", event.GetInt("duck_streak_total"));
						event2.SetInt("duck_streak_assist", event.GetInt("duck_streak_assist"));
						event2.SetInt("duck_streak_victim", event.GetInt("duck_streak_victim"));
						event2.SetBool("rocket_jump", event.GetBool("rocket_jump"));
						event2.SetInt("weapon_def_index", event.GetInt("weapon_def_index"));
						event.GetString("weapon_logclassname", sString, sizeof(sString));
						event2.SetString("weapon_logclassname", sString);
						event.GetString("weapon", sString, sizeof(sString));
						event2.SetString("weapon", sString);
						event2.SetInt("send", userid);

						CreateTimer(0.2, Timer_SendDeathToSpecific, event2);
					}
				}
			}
		}
	}
	
	if (!IsRoundInWarmup())
	{
		if (client > 0)
		{
			if (g_bBackStabbed[client])
			{
				event.SetInt("customkill", TF_CUSTOM_BACKSTAB);
				g_bBackStabbed[client] = false;
			}
		}
	}
	if (MAX_BOSSES > npcIndex >= 0 && (g_bSlenderHasAshKillEffect[npcIndex] || g_bSlenderHasCloakKillEffect[npcIndex]
			 || g_bSlenderHasDecapKillEffect[npcIndex] || g_bSlenderHasDeleteKillEffect[npcIndex]
			 || g_bSlenderHasDissolveRagdollOnKill[npcIndex]
			 || g_bSlenderHasElectrocuteKillEffect[npcIndex] || g_bSlenderHasGoldKillEffect[npcIndex]
			 || g_bSlenderHasIceKillEffect[npcIndex] || g_bSlenderHasPlasmaRagdollOnKill[npcIndex]
			 || g_bSlenderHasPushRagdollOnKill[npcIndex] || g_bSlenderHasResizeRagdollOnKill[npcIndex]
			 || g_bSlenderHasBurnKillEffect[npcIndex] || g_bSlenderHasGibKillEffect[npcIndex]))
	{
		CreateTimer(0.01, Timer_ModifyRagdoll, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
	}
	if (MAX_BOSSES > npcIndex >= 0 && g_bSlenderPlayerCustomDeathFlag[npcIndex])
	{
		event.SetInt("death_flags", g_iSlenderPlayerSetDeathFlag[npcIndex]);
	}
	if (MAX_BOSSES > npcIndex >= 0 && g_bSlenderHasDecapOrGibKillEffect[npcIndex])
	{
		CreateTimer(0.01, Timer_DeGibRagdoll, GetClientUserId(client));
	}

	if (MAX_BOSSES > npcIndex >= 0 && g_bSlenderHasMultiKillEffect[npcIndex])
	{
		CreateTimer(0.01, Timer_MultiRagdoll, GetClientUserId(client));
	}
	if (IsEntityAProjectile(inflictor))
	{
		switch (ProjectileGetFlags(inflictor))
		{
			case PROJ_MANGLER: CreateTimer(0.01, Timer_ManglerRagdoll, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
			case PROJ_ICEBALL: CreateTimer(0.01, Timer_IceRagdoll, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
			case PROJ_ICEBALL_ATTACK: CreateTimer(0.01, Timer_IceRagdoll, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		}
	}
	if (MAX_BOSSES > npcIndex >= 0 && NPCHasAttribute(npcIndex, "ignite player on death"))
	{
		float flValue = NPCGetAttributeValue(npcIndex, "ignite player on death");
		if (flValue > 0.0) TF2_IgnitePlayer(client, client);
	}

	#if defined DEBUG
	if (g_cvDebugDetail.IntValue > 1) DebugMessage("EVENT END: Event_PlayerDeathPre");
	#endif
	event.BroadcastDisabled = true;
	return Plugin_Changed;
}

public Action Event_PlayerHurt(Handle event, const char[] name, bool dB)
{
	if (!g_bEnabled) return;
	
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (client <= 0) return;
	
	#if defined DEBUG
	if (g_cvDebugDetail.IntValue > 0) DebugMessage("EVENT START: Event_PlayerHurt");
	#endif
	
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	if (attacker > 0)
	{
		if (g_bPlayerProxy[attacker])
		{
			g_iPlayerProxyControl[attacker] = 100;
		}
	}
	
	// Play any sounds, if any.
	if (g_bPlayerProxy[client])
	{
		int proxyMaster = NPCGetFromUniqueID(g_iPlayerProxyMaster[client]);
		if (proxyMaster != -1)
		{
			char profile[SF2_MAX_PROFILE_NAME_LENGTH];
			NPCGetProfile(proxyMaster, profile, sizeof(profile));
			
			char sBuffer[PLATFORM_MAX_PATH];
			if (GetRandomStringFromProfile(profile, "sound_proxy_hurt", sBuffer, sizeof(sBuffer)) && sBuffer[0] != '\0')
			{
				int iChannel = g_iSlenderProxyHurtChannel[proxyMaster];
				int iLevel = g_iSlenderProxyHurtLevel[proxyMaster];
				int iFlags = g_iSlenderProxyHurtFlags[proxyMaster];
				float flVolume = g_flSlenderProxyHurtVolume[proxyMaster];
				int iPitch = g_iSlenderProxyHurtPitch[proxyMaster];
				
				EmitSoundToAll(sBuffer, client, iChannel, iLevel, iFlags, flVolume, iPitch);
			}
		}
	}
	delete event;
	#if defined DEBUG
	if (g_cvDebugDetail.IntValue > 0) DebugMessage("EVENT END: Event_PlayerHurt");
	#endif
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dB)
{
	if (!g_bEnabled) return;

	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client <= 0) return;
	
	#if defined DEBUG
	if (g_cvDebugDetail.IntValue > 0) DebugMessage("EVENT START: Event_PlayerDeath(%d)", client);
	#endif
	
	bool fake = view_as<bool>(event.GetInt("death_flags") & TF_DEATHFLAG_DEADRINGER);
	int inflictor = event.GetInt("inflictor_entindex");
	
	#if defined DEBUG
	if (g_cvDebugDetail.IntValue > 0) DebugMessage("inflictor = %d", inflictor);
	#endif
	
	if (!fake)
	{
		ClientResetStatic(client);
		ClientResetSlenderStats(client);
		ClientResetCampingStats(client);
		ClientResetOverlay(client);
		ClientResetJumpScare(client);
		ClientResetInteractiveGlow(client);
		ClientDisableConstantGlow(client);
		ClientChaseMusicReset(client);
		ClientChaseMusicSeeReset(client);
		ClientAlertMusicReset(client);
		ClientIdleMusicReset(client);
		Client20DollarsMusicReset(client);
		Client90sMusicReset(client);
		ClientMusicReset(client);
		
		ClientResetFlashlight(client);
		ClientDeactivateUltravision(client);
		ClientResetSprint(client);
		ClientResetBreathing(client);
		ClientResetBlink(client);
		ClientResetDeathCam(client);
		
		ClientUpdateMusicSystem(client);

		for (int iNPCIndex = 0; iNPCIndex < MAX_BOSSES; iNPCIndex++)
		{
			if (NPCGetUniqueID(iNPCIndex) == -1) continue;
			if (g_aNPCChaseOnLookTarget[iNPCIndex] == null) continue;
			int iFoundClient = g_aNPCChaseOnLookTarget[iNPCIndex].FindValue(client);
			if (iFoundClient != -1) g_aNPCChaseOnLookTarget[iNPCIndex].Erase(iFoundClient);
		}
		
		PvP_SetPlayerPvPState(client, false, false, false);
		
		if (IsRoundInWarmup())
		{
			CreateTimer(0.3, Timer_RespawnPlayer, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
		}
		else
		{
			if (!g_bPlayerEliminated[client])
			{
				if (IsFakeClient(client))
				{
					TF2_SetPlayerClass(client, TFClass_Sniper);
				}
				if (SF_SpecialRound(SPECIALROUND_MULTIEFFECT) || g_bRenevantMultiEffect)
					CreateTimer(0.1, Timer_ReplacePlayerRagdoll, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
				if (IsRoundInIntro() || !IsRoundPlaying() || DidClientEscape(client) || (SF_SpecialRound(SPECIALROUND_1UP) && g_bPlayerIn1UpCondition[client] && !g_bPlayerDied1Up[client]))
				{
					CreateTimer(0.3, Timer_RespawnPlayer, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
				}
				else
				{
					g_bPlayerEliminated[client] = true;
					g_bPlayerEscaped[client] = false;
					g_bPlayerFullyDied1Up[client] = true;
					g_hPlayerSwitchBlueTimer[client] = CreateTimer(0.5, Timer_PlayerSwitchToBlue, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
				}
				if (g_iPlayerPreferences[client].PlayerPreference_GhostModeToggleState == 2)
					CreateTimer(0.25, Timer_ToggleGhostModeCommand, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
				if (SF_SpecialRound(SPECIALROUND_THANATOPHOBIA) && IsRoundPlaying() && !DidClientEscape(client))
				{
					for (int iReds = 1; iReds <= MaxClients; iReds++)
					{
						if (!IsValidClient(iReds) || 
							g_bPlayerEliminated[iReds] || 
							DidClientEscape(iReds) || 
							GetClientTeam(iReds) != TFTeam_Red || 
							!IsPlayerAlive(iReds)) continue;
						int iRandomNegative = GetRandomInt(1, 5);
						switch (iRandomNegative)
						{
							case 1:
							{
								TF2_MakeBleed(iReds, iReds, 4.0);
								EmitSoundToClient(iReds, BLEED_ROLL, iReds, SNDCHAN_AUTO, SNDLEVEL_SCREAMING);
							}
							case 2:
							{
								TF2_AddCondition(iReds, TFCond_Jarated, 5.0);
								EmitSoundToClient(iReds, JARATE_ROLL, iReds, SNDCHAN_AUTO, SNDLEVEL_SCREAMING);
							}
							case 3:
							{
								TF2_AddCondition(iReds, TFCond_Gas, 5.0);
								EmitSoundToClient(iReds, GAS_ROLL, iReds, SNDCHAN_AUTO, SNDLEVEL_SCREAMING);
							}
							case 4:
							{
								int iMaxHealth = SDKCall(g_hSDKGetMaxHealth, iReds);
								float damageToTake = float(iMaxHealth) / 10.0;
								SDKHooks_TakeDamage(iReds, iReds, iReds, damageToTake, 128, _, view_as<float>( { 0.0, 0.0, 0.0 } ));
							}
							case 5:
							{
								TF2_AddCondition(iReds, TFCond_MarkedForDeath, 5.0);
							}
						}
					}
				}
			}
			else
			{
			}
			
			
			// If this player was killed by a boss, play a sound, or print a message.
			int npcIndex = NPCGetFromEntIndex(inflictor);
			if (npcIndex != -1)
			{
				int iSlender = NPCGetEntIndex(npcIndex);
				if (iSlender && iSlender != INVALID_ENT_REFERENCE) g_iPlayerBossKillSubject[client] = EntIndexToEntRef(iSlender);
				
				char npcProfile[SF2_MAX_PROFILE_NAME_LENGTH], buffer[PLATFORM_MAX_PATH], sBossName[SF2_MAX_NAME_LENGTH];
				NPCGetProfile(npcIndex, npcProfile, sizeof(npcProfile));
				NPCGetBossName(npcIndex, sBossName, sizeof(sBossName));

				#if defined _store_included
				int difficulty = GetLocalGlobalDifficulty(npcIndex);
				if (NPCGetDrainCreditState(npcIndex))
				{
					Store_SetClientCredits(client, Store_GetClientCredits(client) - NPCGetDrainCreditAmount(npcIndex, difficulty));
					CPrintToChat(client, "{valve}%s{default} has stolen {green}%i credits{default} from you.", sBossName, NPCGetDrainCreditAmount(npcIndex, difficulty));
				}
				#endif
				
				if (GetRandomStringFromProfile(npcProfile, "sound_attack_killed_client", buffer, sizeof(buffer)) && buffer[0] != '\0')
				{
					if (g_bPlayerEliminated[client])
					{
						EmitSoundToClient(client, buffer, _, SNDCHAN_STATIC, SNDLEVEL_HELICOPTER);
					}
				}
				
				if (GetRandomStringFromProfile(npcProfile, "sound_attack_killed_all", buffer, sizeof(buffer)) && buffer[0] != '\0')
				{
					if (g_bPlayerEliminated[client])
					{
						EmitSoundToAll(buffer, _, SNDCHAN_STATIC, SNDLEVEL_HELICOPTER);
					}
				}
				
				SlenderPrintChatMessage(npcIndex, client);
				
				SlenderPerformVoice(npcIndex, "sound_attack_killed");
			}
			
			if (IsEntityAProjectile(inflictor))
			{
				int npcIndex2 = NPCGetFromEntIndex(GetEntPropEnt(inflictor, Prop_Send, "m_hOwnerEntity"));
				if (npcIndex2 != -1)
				{
					int iSlender = NPCGetEntIndex(npcIndex2);
					if (iSlender && iSlender != INVALID_ENT_REFERENCE)g_iPlayerBossKillSubject[client] = EntIndexToEntRef(iSlender);
					
					char npcProfile[SF2_MAX_PROFILE_NAME_LENGTH], buffer[PLATFORM_MAX_PATH], sBossName[SF2_MAX_NAME_LENGTH];
					NPCGetProfile(npcIndex2, npcProfile, sizeof(npcProfile));
					NPCGetBossName(npcIndex2, sBossName, sizeof(sBossName));

					#if defined _store_included
					int difficulty = GetLocalGlobalDifficulty(npcIndex2);
					if (NPCGetDrainCreditState(npcIndex2))
					{
						Store_SetClientCredits(client, Store_GetClientCredits(client) - NPCGetDrainCreditAmount(npcIndex2, difficulty));
						CPrintToChat(client, "{valve}%s{default} has stolen {green}%i credits{default} from you.", sBossName, NPCGetDrainCreditAmount(npcIndex2, difficulty));
					}
					#endif
					
					
					if (GetRandomStringFromProfile(npcProfile, "sound_attack_killed_client", buffer, sizeof(buffer)) && buffer[0] != '\0')
					{
						if (g_bPlayerEliminated[client])
						{
							EmitSoundToClient(client, buffer, _, SNDCHAN_STATIC);
						}
					}
					
					if (GetRandomStringFromProfile(npcProfile, "sound_attack_killed_all", buffer, sizeof(buffer)) && buffer[0] != '\0')
					{
						if (g_bPlayerEliminated[client])
						{
							EmitSoundToAll(buffer, _, SNDCHAN_STATIC, SNDLEVEL_HELICOPTER);
						}
					}
					
					SlenderPrintChatMessage(npcIndex2, client);
					
					SlenderPerformVoice(npcIndex2, "sound_attack_killed");
				}
			}
			
			CreateTimer(0.2, Timer_CheckRoundWinConditions, _, TIMER_FLAG_NO_MAPCHANGE);
			
			// Notify to other bosses that this player has died.
			for (int i = 0; i < MAX_BOSSES; i++)
			{
				if (NPCGetUniqueID(i) == -1) continue;
				
				if (EntRefToEntIndex(g_iSlenderTarget[i]) == client)
				{
					g_iSlenderInterruptConditions[i] |= COND_CHASETARGETINVALIDATED;
					GetClientAbsOrigin(client, g_flSlenderChaseDeathPosition[i]);
				}
			}
			
			if (g_cvIgnoreRedPlayerDeathSwap.BoolValue)
			{
				g_bPlayerEliminated[client] = false;
				g_bPlayerEscaped[client] = false;
			}
		}
		
		if (g_bPlayerProxy[client])
		{
			// We're a proxy, so play some sounds.
			
			int proxyMaster = NPCGetFromUniqueID(g_iPlayerProxyMaster[client]);
			if (proxyMaster != -1)
			{
				char profile[SF2_MAX_PROFILE_NAME_LENGTH];
				NPCGetProfile(proxyMaster, profile, sizeof(profile));
				
				char sBuffer[PLATFORM_MAX_PATH];
				if (GetRandomStringFromProfile(profile, "sound_proxy_death", sBuffer, sizeof(sBuffer)) && sBuffer[0] != '\0')
				{
					int iChannel = g_iSlenderProxyDeathChannel[proxyMaster];
					int iLevel = g_iSlenderProxyDeathLevel[proxyMaster];
					int iFlags = g_iSlenderProxyDeathFlags[proxyMaster];
					float flVolume = g_flSlenderProxyDeathVolume[proxyMaster];
					int iPitch = g_iSlenderProxyDeathPitch[proxyMaster];
					
					EmitSoundToAll(sBuffer, client, iChannel, iLevel, iFlags, flVolume, iPitch);
				}
			}
		}
		
		ClientResetProxy(client, false);
		ClientUpdateListeningFlags(client);
		
		// Half-Zatoichi nerf code.
		int iKatanaHealthGain = 10;
		if (iKatanaHealthGain >= 0)
		{
			int iAttacker = GetClientOfUserId(event.GetInt("attacker"));
			if (iAttacker > 0)
			{
				if (!IsClientInPvP(iAttacker) && (!g_bPlayerEliminated[iAttacker] || g_bPlayerProxy[iAttacker]))
				{
					char sWeapon[64];
					event.GetString("weapon", sWeapon, sizeof(sWeapon));
					
					if (strcmp(sWeapon, "demokatana") == 0)
					{
						int iAttackerPreHealth = GetEntProp(iAttacker, Prop_Send, "m_iHealth");
						Handle hPack = CreateDataPack();
						WritePackCell(hPack, GetClientUserId(iAttacker));
						WritePackCell(hPack, iAttackerPreHealth + iKatanaHealthGain);
						
						CreateTimer(0.0, Timer_SetPlayerHealth, hPack, TIMER_FLAG_NO_MAPCHANGE);
					}
				}
			}
		}
		
		g_hPlayerPostWeaponsTimer[client] = null;
		g_hPlayerIgniteTimer[client] = null;
		g_hPlayerResetIgnite[client] = null;
		g_hPlayerPageRewardTimer[client] = null;
		g_hPlayerPageRewardCycleTimer[client] = null;
		g_hPlayerFireworkTimer[client] = null;
		
		g_bPlayerGettingPageReward[client] = false;
		g_iPlayerHitsToCrits[client] = 0;
		g_iPlayerHitsToHeads[client] = 0;
		
		g_bPlayerTrapped[client] = false;
		g_iPlayerTrapCount[client] = 0;
		
		g_iPlayerRandomClassNumber[client] = 1;
	}
	if (!IsRoundEnding() && !g_bRoundWaitingForPlayers)
	{
		int iAttacker = GetClientOfUserId(event.GetInt("attacker"));
		if (IsRoundPlaying() && client != iAttacker)
		{
			//Copy the data
			char sString[64];
			Event event2 = CreateEvent("player_death", true);
			event2.SetInt("userid", event.GetInt("userid"));
			event2.SetInt("victim_entindex", event.GetInt("victim_entindex"));
			event2.SetInt("inflictor_entindex", event.GetInt("inflictor_entindex"));
			event2.SetInt("attacker", event.GetInt("attacker"));
			event2.SetInt("weaponid", event.GetInt("weaponid"));
			event2.SetInt("damagebits", event.GetInt("damagebits"));
			event2.SetInt("customkill", event.GetInt("customkill"));
			event2.SetInt("assister", event.GetInt("assister"));
			event2.SetInt("stun_flags", event.GetInt("stun_flags"));
			event2.SetInt("death_flags", event.GetInt("death_flags"));
			event2.SetBool("silent_kill", event.GetBool("silent_kill"));
			event2.SetInt("playerpenetratecount", event.GetInt("playerpenetratecount"));
			event2.SetInt("kill_streak_total", event.GetInt("kill_streak_total"));
			event2.SetInt("kill_streak_wep", event.GetInt("kill_streak_wep"));
			event2.SetInt("kill_streak_assist", event.GetInt("kill_streak_assist"));
			event2.SetInt("kill_streak_victim", event.GetInt("kill_streak_victim"));
			event2.SetInt("ducks_streaked", event.GetInt("ducks_streaked"));
			event2.SetInt("duck_streak_total", event.GetInt("duck_streak_total"));
			event2.SetInt("duck_streak_assist", event.GetInt("duck_streak_assist"));
			event2.SetInt("duck_streak_victim", event.GetInt("duck_streak_victim"));
			event2.SetBool("rocket_jump", event.GetBool("rocket_jump"));
			event2.SetInt("weapon_def_index", event.GetInt("weapon_def_index"));
			event.GetString("weapon_logclassname", sString, sizeof(sString));
			event2.SetString("weapon_logclassname", sString);
			event.GetString("assister_fallback", sString, sizeof(sString));
			event2.SetString("assister_fallback", sString);
			event.GetString("weapon", sString, sizeof(sString));
			event2.SetString("weapon", sString);

			event2.SetInt("ignore", event.GetInt("ignore"));
			CreateTimer(0.2, Timer_SendDeath, event2, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
		}
	}
	if (SF_IsBoxingMap() && IsRoundInEscapeObjective())
	{
		CreateTimer(0.2, Timer_CheckAlivePlayers, _, TIMER_FLAG_NO_MAPCHANGE);
	}
	PvP_OnPlayerDeath(client, fake);
	
	#if defined DEBUG
	if (g_cvDebugDetail.IntValue > 0) DebugMessage("EVENT END: Event_PlayerDeath(%d)", client);
	#endif
	delete event;
}
