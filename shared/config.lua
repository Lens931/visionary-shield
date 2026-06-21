--- Visionary Anti-Cheat configuration.
--- Open-source configuration. Adjust this file before production use.
zVS = zVS or {}

---@class zVSConfig
zVS.Config = {
    PerformanceProfile = 'production_zerofootprint',

    -- UI localization. Add your own language by copying one locale table and changing DefaultLocale.
    Localization = {
        Enabled = true,
        DefaultLocale = 'en',
        FallbackLocale = 'en',
        Locales = {
            en = {
                app = {
                    players = 'players', risk = 'risk', bans = 'bans', production = 'production',
                    dashboard = 'Dashboard', close = 'Close', refresh = 'Refresh', lock = 'Lock', minimize = 'Minimize', maximize = 'Maximize'
                },
                main = {
                    playersTitle = 'Players', search = 'Name, ID, ping...', all = 'All', risk = 'Risk', vehicle = 'Vehicle', protected = 'Protected',
                    noPlayers = 'No players', noPlayersHint = 'Manual refresh or filter too strict.',
                    noSelection = 'No player selected', selectPlayer = 'Select a player on the left.', readOnly = 'UI read-only. Staff keeps the final decision.',
                    overview = 'Overview', history = 'Audit', defenses = 'Runtime', alerts = 'Alerts', notes = 'Notes', damage = 'Damage',
                    topRisk = 'Top risk', approvals = 'Approvals', recentAudit = 'Recent audit', runtimeReal = 'Real runtime', noGhost = 'no ghost options', serverStates = 'server states',
                    timeline = 'Timeline', noRecentEvent = 'No recent event for the selected player.', empty = 'Nothing to display yet.'
                },
                actions = {
                    inspect = 'Inspect', pin = 'Pin', spectate = 'Spectate', goto = 'Goto', bring = 'Bring', freeze = 'Freeze', heal = 'Heal', capture = 'Capture', warn = 'Warn', kick = 'Kick', ban = 'Ban', noclip = 'NoClip', ui = 'UI', validate = 'Confirm', cancel = 'Cancel'
                },
                inspector = {
                    title = 'Player', name = 'Name', id = 'ID', health = 'Health', armor = 'Armor', speed = 'Speed', ping = 'Ping', risk = 'Risk', position = 'Position', vehicle = 'Vehicle', protection = 'Protection'
                },
                settings = {
                    title = 'UI Settings', interface = 'Interface', active = 'active', scale = 'Scale', text = 'Text', theme = 'Theme', language = 'Language', languageHint = 'configured in shared/config.lua', windows = 'Windows', persistent = 'persistent', compact = 'Compact mode', dock = 'Floating quick dock', note = 'The dashboard can close without closing floating windows. Visibility is runtime; position, size, lock and opacity remain saved.', reset = 'Reset UI', save = 'Save now'
                },
                dock = {
                    title = 'Quick Tools', live = 'live', refreshHint = 'Update data', inspectorHint = 'No player selected', spectateHint = 'Watch the target', gotoHint = 'Go to target', noclipDisabled = 'Unavailable', settingsHint = 'Scale, theme and windows', windows = 'Windows', runtime = 'runtime', closeDashboard = 'Close dashboard', hideDock = 'Hide dock'
                },
                dialogs = {
                    staffAction = 'Staff action', target = 'Target', reason = 'Reason', reasonPlaceholder = 'Write a clear and short reason...', actionHint = 'This action is sent to the zVS backend. Browser prompts are not used.', understood = 'Understood', screenshotReceived = 'Screenshot received', evidence = 'Evidence', screenshotAvailable = 'Screenshot available.', localCapture = 'local screenshot', uploadAvailable = 'upload available', saved = 'UI saved.', reset = 'UI reset.'
                },
                forms = { warn = 'Suspicious behaviour detected.', kick = 'Staff action.', ban = 'Cheat / exploit suspicion.' }
            },
            fr = {
                app = {
                    players = 'joueurs', risk = 'risque', bans = 'bans', production = 'production',
                    dashboard = 'Dashboard', close = 'Fermer', refresh = 'Rafraîchir', lock = 'Verrouiller', minimize = 'Réduire', maximize = 'Agrandir'
                },
                main = {
                    playersTitle = 'Joueurs', search = 'Nom, ID, ping...', all = 'Tous', risk = 'Risque', vehicle = 'Véhicule', protected = 'Protégés',
                    noPlayers = 'Aucun joueur', noPlayersHint = 'Refresh manuel ou filtre trop strict.',
                    noSelection = 'Aucun joueur sélectionné', selectPlayer = 'Sélectionne un joueur à gauche.', readOnly = 'UI read-only. Pas d’action punitive automatique.',
                    overview = 'Overview', history = 'Audit', defenses = 'Runtime', alerts = 'Alertes', notes = 'Notes', damage = 'Damage',
                    topRisk = 'Top risque', approvals = 'Approbations', recentAudit = 'Audit récent', runtimeReal = 'Runtime réel', noGhost = 'pas d’options fantômes', serverStates = 'états serveur',
                    timeline = 'Timeline', noRecentEvent = 'Aucun événement récent lié au joueur sélectionné.', empty = 'Rien à afficher pour le moment.'
                },
                actions = {
                    inspect = 'Inspect', pin = 'Pin', spectate = 'Spectate', goto = 'Goto', bring = 'Bring', freeze = 'Freeze', heal = 'Heal', capture = 'Capture', warn = 'Warn', kick = 'Kick', ban = 'Ban', noclip = 'NoClip', ui = 'UI', validate = 'Valider', cancel = 'Annuler'
                },
                inspector = {
                    title = 'Joueur', name = 'Nom', id = 'ID', health = 'Santé', armor = 'Armure', speed = 'Vitesse', ping = 'Ping', risk = 'Risque', position = 'Position', vehicle = 'Véhicule', protection = 'Protection'
                },
                settings = {
                    title = 'Paramètres UI', interface = 'Interface', active = 'actif', scale = 'Échelle', text = 'Texte', theme = 'Thème', language = 'Langue', languageHint = 'configurée dans shared/config.lua', windows = 'Fenêtres', persistent = 'persistant', compact = 'Compact mode', dock = 'Dock flottant rapide', note = 'Le dashboard peut se fermer sans fermer les fenêtres flottantes. La visibilité est runtime ; position, taille, lock et opacité restent sauvegardés.', reset = 'Reset UI', save = 'Sauvegarder maintenant'
                },
                dock = {
                    title = 'Outils rapides', live = 'live', refreshHint = 'Mettre à jour les données', inspectorHint = 'Aucun joueur sélectionné', spectateHint = 'Suivre la cible', gotoHint = 'Aller sur la cible', noclipDisabled = 'Indisponible', settingsHint = 'Échelle, thème et fenêtres', windows = 'Fenêtres', runtime = 'runtime', closeDashboard = 'Fermer dashboard', hideDock = 'Masquer dock'
                },
                dialogs = {
                    staffAction = 'Action staff', target = 'Cible', reason = 'Motif', reasonPlaceholder = 'Indique un motif clair et court...', actionHint = 'Cette action sera envoyée au backend zVS. Aucun prompt navigateur n’est utilisé.', understood = 'J’ai compris', screenshotReceived = 'Capture reçue', evidence = 'Evidence', screenshotAvailable = 'Capture disponible.', localCapture = 'capture locale', uploadAvailable = 'upload disponible', saved = 'UI sauvegardée.', reset = 'UI réinitialisée.'
                },
                forms = { warn = 'Comportement suspect détecté.', kick = 'Action staff.', ban = 'Suspicion de cheat / exploitation.' }
            }
        }
    },
    --- Toggle bypass behaviour for trusted staff.
    AdminBypass = true,

    --- Identifiers that should bypass detections entirely.
    --- Accepts any identifier returned by `GetPlayerIdentifiers`.
    AdminIdentifiers = {
        -- Add your trusted staff identifiers here before production use.
        -- Example: 'license:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
        -- Example: 'discord:112233445566778899',
    },

    --- Discord webhook that receives all security logs.
    Webhook = '',

    --- Optional advanced webhook routing.
    --- `Default` falls back to `Webhook` when empty.
    --- `Detections` supports keys like:
    ---  - full event key (`auto_detection_teleport`)
    ---  - short detection key (`teleport`)
    ---  - generic fallback (`auto_detection_default`)
    Webhooks = {
        Default = '',
        Monitoring = '',
        Detections = {
            -- auto_detection_default = 'https://discord.com/api/webhooks/...',
            -- teleport = 'https://discord.com/api/webhooks/...',
            -- auto_detection_teleport = 'https://discord.com/api/webhooks/...',
        },
    },

    --- Enable verbose logging inside the server console (do not enable in production).
    EnableDebug = false,

    Performance = {
        ZeroFootprint = true, -- profile production: no permanent cosmetic threads, low active cadence, event-driven UI where possible
        StaffOverlayTickMs = 650,
        PreviewCameraTickMs = 500,
        PreviewCloneTickMs = 1000,
        SpectateCameraTickMs = 80, -- needs near-frame cadence only while spectate is active
        SpectateHudTickMs = 900, -- draw natives require frame cadence; only active during spectate
    },

    DiscordLogging = {
        QueueMax = 90, -- protects the server from webhook bursts during raids
        DedupeWindowMs = 6500, -- collapses identical Discord events for a few seconds
        RetryAttempts = 3,
        MinSnapshotRisk = 35,
    },

    Heartbeat = {
        Enabled = false, -- passive SOC mode: avoids a permanent client/server heartbeat thread; set true if you want anti-stop heartbeat monitoring.
        Interval = 15000, -- milliseconds between heartbeats sent by clients
        Tolerance = 45000, -- milliseconds before a player is considered timed-out
    },

    VehicleSpam = {
        Window = 10000, -- milliseconds window for counting spawned vehicles
        Threshold = 10, -- number of vehicles allowed inside the window
        CancelOnTrip = true, -- cancel the spawn when the threshold is exceeded
        Cooldown = 5000, -- milliseconds before another vehicle can be spawned after a trip
        FreeroamWindow = 12000, -- alternate window used for routine freeroam spawning
        FreeroamThreshold = 16, -- relaxed threshold for routine freeroam vehicle usage
        FreeroamCooldown = 2500, -- shorter cooldown for routine freeroam spawning
        FreeroamModelGrace = { -- hashes or model names that should use freeroam thresholds
            'adder',
            'zentorno',
            'bati',
            'buzzard',
            'sanchez',
        },
        CooldownLogInterval = 1500,
    },

    ResourceGuard = {
        Enabled = false, -- ZeroFootprint: disable passive monitor thread by default; enable if you explicitly want auto-restart protection.
        ProtectedResources = {}, -- additional resource names to keep online (zvs-ac is protected automatically)
        RestartDelayMs = 600, -- delay before attempting to restart a protected resource
        RestartAttempts = 3, -- number of restart attempts before raising a failure alert
        AlertCooldownMs = 12000, -- throttle identical alerts in milliseconds
        MonitorIntervalMs = 30000, -- passive cadence for protected-resource health checks
        HealthCheckGraceMs = 3500, -- time a resource can remain offline before auto-restart kicks in
    },

    SpawnAbuse = {
        VehicleCooldown = 5000, -- milliseconds per vehicle spawn per player
        ObjectCooldown = 8000, -- milliseconds per object spawn per player
        HeavyDimensionThreshold = 5.0, -- metres, bounding-box diagonal considered heavy
        CacheModelDimensions = true, -- memoise model dimensions to avoid repeated native lookups
        DimensionCacheSize = 512, -- max model dimension entries kept in memory
        CleanupIntervalMs = 300000, -- cleanup cadence for per-player cooldown state
        PlayerStateTtlMs = 600000, -- idle lifetime before cooldown state is discarded
        FreeroamVehicleCooldown = 1200, -- relaxed cooldown for regular freeroam vehicle spawns
        FreeroamObjectCooldown = 2500, -- relaxed cooldown for regular freeroam object spawns
        FreeroamModelGrace = { -- hashes or model names allowed to use freeroam thresholds
            'prop_beachball_02',
            'prop_roadcone02a',
            'prop_barrier_work05',
            'adder',
            'zentorno',
            'bati',
            'buzzard',
            'sanchez',
        },
    },

    GodmodeProbe = {
        Enabled = true,
        Interval = 300000, -- production cadence: extremely low-cost and avoids spawn false positives
        Damage = 1, -- health removed during the probe
        MinimumHealth = 140, -- minimum health required to run the probe (prevents killing low HP players)
        RestoreHealth = true, -- restore the player's health after probing
        RestoreDelay = 200, -- milliseconds before health restoration
        AllowedRecovery = 0, -- allowed health recovery above the expected post-damage value
        JoinGraceMs = 120000, -- avoid false positives while the player is still loading/spawning
        SpawnGraceMs = 60000, -- client-side grace after playerSpawned/playerLoaded
        ConsecutiveFlags = 3, -- require several bad probes before logging godmode
        ProbeCooldownMs = 120000, -- Discord/risk cooldown per player for godmode probe flags
        RequireCollisionLoaded = true, -- skip probe when local world collision is not loaded
    },

    HeadshotLog = {
        Enabled = true,
        DistancePrecision = 2, -- decimal places for logged distances
    },

    AttachmentsAudit = {
        Enabled = true,
        LogAttachedObjects = true,
        LogAttachedVehicles = false, -- enable if you want to monitor vehicle-to-vehicle attachments
        IgnoreModels = {}, -- list of model hashes (numbers) ignored by the audit
    },

    DamageMonitor = {
        Enabled = true,
        ScorePerFlag = {
            excessive_damage = 35,
            blacklisted_weapon = 55,
            rapid_fire = 30,
            kill_streak = 25,
            headshot_streak = 25,
        },
        ScoreDecayMs = 120000, -- how fast suspicion score decays back to zero
        MonitoringCooldownMs = 20000, -- throttle risk profile events sent to monitoring/webhooks
        IgnoreAdmins = true,
        MaxLogEntries = 50,
        ShotWindow = 8000, -- milliseconds considered for rapid-fire detection
        MaxShotsPerWindow = 18, -- number of hits allowed inside the shot window
        KillWindow = 45000, -- milliseconds considered for kill-streak detection
        KillThreshold = 5, -- kills inside the window required to trigger a flag
        HeadshotWindow = 45000, -- milliseconds window for headshot streaks
        HeadshotThreshold = 4, -- headshots inside the window before a flag is raised
        MaxDamagePerHit = 150, -- damage threshold considered suspicious for a single hit
        NotifyOnSuspicion = true, -- broadcast suspect events to connected admins
        FlagCooldown = 15000, -- milliseconds before the same flag can trigger again for the player
        BlacklistedWeapons = {
            -- `GetHashKey('WEAPON_RAILGUN')`,
            -- `GetHashKey('WEAPON_RPG')`,
        },
    },


    RiskEngine = {
        Enabled = true,
        IgnoreAdmins = true,
        AutomationEnabled = false, -- automatic freeze/kick/ban is disabled by default; staff must approve actions.
        HumanReviewOnly = true, -- hard safety rail: detections can suggest actions, never punish without staff validation.
        SnapshotToDiscord = false, -- ZeroFootprint: event logs still work; passive SOC snapshots are opt-in.
        SnapshotMinScore = 35,
        DecayMs = 180000, -- rolling risk decay cadence
        DecayPerWindow = 18, -- points removed each decay window
        SnapshotIntervalMs = 600000,
        SnapshotLimit = 30,
        TimelineLimit = 40,
        AuditLimit = 120,
        Thresholds = {
            staff_review = 35,
            freeze = 55,
            kick = 78,
            ban = 94,
        },
        ActionCooldownMs = {
            freeze = 60000,
            kick = 90000,
            ban = 120000,
        },
        StaffApproval = {
            Enabled = true,
            RequireFor = {
                freeze = true,
                kick = true,
                ban = true,
            },
        },
        Weights = {
            default = 15,
            noclip_v2 = 48,
            silent_aim = 58,
            triggerbot = 45,
            aim_assist = 32,
            spectator_abuse = 30,
            entity_spam = 34,
            event_flood = 36,
            network_anomaly = 30,
            resource_tampering = 65,
            vehicle_spawn_abuse_v2 = 38,
            behaviour_profile = 26,
            server_movement_signature = 42,
            stealth_state_mismatch = 44,
            combat_without_lineage = 52,
            camera_desync_pattern = 28,
            freecam_pov_mismatch = 38,
            damage_rate_signature = 46,
            aim_entropy_signature = 40,
            health_rollback_signature = 30,
        },
    },

    EnhancedDetections = {
        Enabled = true,
        IgnoreAdmins = true,
        ClientTelemetry = true,
        ClientTelemetryIntervalMs = 6000, -- active telemetry cadence; adaptive loop sleeps longer while the player is idle
        ClientIdleTelemetryIntervalMs = 60000, -- idle cadence for 0.00ms-style usage
        CombatTelemetryIntervalMs = 750, -- fast only while aiming/shooting
        CombatIdleIntervalMs = 6000, -- passive combat watcher sleep while idle
        Detectors = {
            noclip_v2 = { Enabled = true, CooldownMs = 30000, VerticalDelta = 7.5, MinHeight = 5.0, MinSpeedKmh = 35 },
            silent_aim = { Enabled = true, CooldownMs = 45000, MinDistance = 70.0 },
            triggerbot = { Enabled = true, CooldownMs = 45000, WindowMs = 5000, ReactionMs = 90, FastLockThreshold = 4 },
            aim_assist = { Enabled = true, CooldownMs = 45000, SnapAngle = 42, LockTimeMs = 160 },
            spectator_abuse = { Enabled = true, CooldownMs = 45000 },
            entity_spam = { Enabled = true, CooldownMs = 30000, WindowMs = 10000, Threshold = 18 },
            event_flood = { Enabled = true, CooldownMs = 30000, WindowMs = 5000, Threshold = 45 },
            network_anomaly = { Enabled = true, CooldownMs = 45000, PingThreshold = 450, SpeedDeltaKmh = 180 },
            resource_tampering = { Enabled = true, CooldownMs = 60000 },
            vehicle_spawn_abuse_v2 = { Enabled = true, CooldownMs = 30000, WindowMs = 10000, Threshold = 8 },
            behaviour_profile = { Enabled = true, CooldownMs = 60000, SampleSize = 8, HeadingSnapDegrees = 135, MinSpeedKmh = 18, ErraticThreshold = 4 },
            server_movement_signature = {
                Enabled = true,
                CooldownMs = 35000,
                IntervalMs = 15000,
                StrikeWindowMs = 18000,
                StrikeThreshold = 2,
                MaxOnFootKmh = 135.0,
                MaxVehicleKmh = 520.0,
                TeleportDistance = 180.0,
                VerticalDelta = 18.0,
                IgnoreAfterJoinMs = 25000,
            },
            stealth_state_mismatch = {
                Enabled = true,
                CooldownMs = 45000,
                AlphaThreshold = 180,
                MaxHealth = 250,
                MaxArmor = 100,
            },
            combat_without_lineage = {
                Enabled = true,
                CooldownMs = 45000,
                WindowMs = 6500,
                MissingCombatTelemetryMs = 2200,
                StrikeThreshold = 3,
            },
            camera_desync_pattern = {
                Enabled = true,
                CooldownMs = 60000,
                CameraDistanceThreshold = 28.0,
                StrikeWindowMs = 16000,
                StrikeThreshold = 3,
            },
            freecam_pov_mismatch = {
                Enabled = true,
                CooldownMs = 45000,
                CameraDistanceThreshold = 26.0,
                RayDistance = 220.0,
                RayRadius = 3.0,
                StrikeWindowMs = 18000,
                StrikeThreshold = 2,
            },
            damage_rate_signature = {
                Enabled = true,
                CooldownMs = 35000,
                WindowMs = 2200,
                HitThreshold = 7,
                DamageThreshold = 520,
                KillThreshold = 3,
            },
            aim_entropy_signature = {
                Enabled = true,
                CooldownMs = 45000,
                WindowMs = 9000,
                SampleThreshold = 7,
                ReactionVarianceMs = 18,
                SnapVarianceDegrees = 2.4,
                MaxReactionMs = 115,
            },
            health_rollback_signature = {
                Enabled = true,
                CooldownMs = 45000,
                StrikeWindowMs = 18000,
                StrikeThreshold = 2,
                HealDelta = 45,
                MinPreviousHealth = 101,
                MaxAllowedHealth = 220,
            },
        },
    },

    Monitoring = {
        Enabled = false, -- ZeroFootprint: detection logs still work; passive snapshots are opt-in.
        SnapshotIntervalMs = 600000, -- cadence for compact Discord monitoring snapshots
        OnlyWhenActive = true, -- skip empty heartbeat-style Discord messages
        MinRiskToLog = 35,
        IncludePlayerRisk = true,
        MaxTrackedPlayers = 12,
        Webhook = '', -- optional dedicated webhook for monitoring snapshots (falls back to Webhook)
        DetectionWebhook = '', -- optional dedicated webhook receiving all detections
    },

    AdminTools = {
        Enabled = true,
        Command = 'zvsadmin',
        ToggleKey = 'F5', -- touche par défaut pour ouvrir/fermer le menu (reconfigurable)
        CloakToggleCommand = 'zvsac_togglecloak', -- commande pour activer/désactiver le mode furtif (reconfigurable)
        CloakToggleKey = 'F6', -- touche par défaut pour le mode furtif (reconfigurable dans FiveM)
        FeedLimit = 80,
        NotifyInChat = true,
        AllowNotes = true,
        NotesHistoryLimit = 60, -- number of recent notes kept in the shared history
        NoteMaxLength = 400, -- maximum number of characters per note
        AllowBans = true,
        Moderation = {
            AllowKick = true,
            AllowFreeze = true,
            AllowWarn = true,
            AllowTeleport = true,
            AllowHeal = true,
            AllowWeaponClear = true,
            AllowWeaponDisable = true,
            AllowVehicleEject = true,
            AllowSpectate = true,
            AllowCloak = true, -- V1.2: internal staff NoClip restored, admin-only, zero-footprint when inactive
            SilentSpectate = true,
            -- V20: camera-only spectate. The admin ped is never hidden/frozen/teleported and collision/gravity are never touched.
            -- Only scripted camera/focus are used. Native spectator remains OFF unless SpectateCameraOnly is disabled.
            SpectateMode = 'remote_camera', -- 'remote_camera' or 'native'
            SpectateCameraOnly = true, -- keep true: no ped collision/gravity/freeze/visibility changes during spectate
            UseNativeSpectator = false,
            NativeSpectatorFallback = false,
            RequestTargetCamera = true, -- required for target POV preview; server-throttled and admin-only
            SpectateTargetCameraIntervalMs = 1200, -- low-cost camera probe cadence while a staff member spectates
            SpectateTargetCameraStaleMs = 2200, -- after this, the staff camera falls back to orbit mode
            SpectateViewMode = 'target_pov', -- 'target_pov', 'orbit', or 'hybrid'
            SpectateSyncIntervalMs = 750,
            SpectateFocusIntervalMs = 650,
            SpectateMaxDistance = 2500.0,
            SpectateShowHud = false, -- Release V1: no GTA DrawText/DrawRect HUD; NUI floating panel only
            SpectateSmartEsp = false, -- NUI panel only; no world ESP/DrawText in production
            SpectateMinimalHud = true, -- compact overlay: no heavy side panels, only live status + small reticle
            SpectateDrawWorldEsp = false, -- keep false for 0.00ms-style spectate; enable only if staff wants world markers/frustum
            SpectateBottomHelp = true, -- clear staff hints at the bottom of the screen while spectating
            SpectateSafeReturnMs = 0, -- disabled: spectate never touches or repairs the admin ped
            SpectateReturnFreezeMaxMs = 0, -- disabled: no freeze on return
            SpectateReturnUnderMapDelta = 5.5, -- if ped drops this far below origin, safe-return relocates it to ground
            SpectateReturnMaxDistance = 7.5, -- if ped somehow moved away from origin, safe-return corrects it
            SpectateCameraLerp = 0.22, -- smoother target POV/orbit transitions; lower = softer
            SpectateInputPrevious = 'LEFT', -- visual hint only; UI previous/next buttons use this same philosophy
            SpectateInputNext = 'RIGHT',
        },
        StaffNoClip = {
            Enabled = true,
            UseExternalNoClip = false,
            DoNotModifyPed = false,
            RestoreOnDisable = true,
            HideAdmin = false, -- keep admin visible by default; avoids confusing cloak states
            InvincibleWhileActive = true,
            DisableCollisionWhileActive = true,
            Hud = 'nui',
        },
        AdminDock = {
            Enabled = true,
            DefaultVisible = false, -- V1.4: clean base like earlier build; dock is optional, not forced
            AllowOpacity = true,
            MinOpacity = 0.35,
            MaxOpacity = 1.0,
            DefaultOpacity = 0.90,
            KeepVisibleWhenPanelClosed = false,
        },
        AdminSettings = {
            Enabled = true,
            StoragePath = 'data/admin_settings',
            SaveDebounceMs = 900,
            MaxJsonBytes = 32768,
            ResetCommand = 'zvs_resetui',
            Default = {
                version = 1,
                ui = {
                    theme = 'visionary_dark',
                    scale = 1.0,
                    compactMode = true,
                    animations = true,
                    soundFeedback = false,
                },
                windows = {
                    main = { x = 72, y = 54, width = 980, height = 610, opacity = 0.94, locked = false, minimized = false, maximized = false, visible = true },
                    playerInspector = { x = 1070, y = 108, width = 336, height = 340, opacity = 0.92, locked = false, minimized = false, maximized = false, visible = false },
                    spectateInfo = { x = 72, y = 690, width = 390, height = 178, opacity = 0.92, locked = false, minimized = false, maximized = false, visible = false },
                    settings = { x = 140, y = 110, width = 520, height = 500, opacity = 0.94, locked = false, minimized = false, maximized = false, visible = false },
                    adminDock = { x = 18, y = 230, width = 46, height = 210, opacity = 0.90, locked = false, minimized = false, maximized = false, visible = false },
                },
                spectate = {
                    defaultMode = 'pov',
                    showInfoPanel = true,
                    updateIntervalMs = 1000,
                    closeSpectateWithPanel = false,
                },
                notifications = {
                    discordLogLevel = 'normal',
                    showLocalToasts = true,
                    soundFeedback = false,
                },
                binds = { openPanel = 'F5' },
                dock = { enabled = false },
                tabs = { main = 'overview', right = 'alerts' },
            },
        },
        AdminPreview = {
            Enabled = false,
        },
        DefenseControl = {
            Enabled = true, -- allow trusted admins to disable specific defenses in real-time
            Defenses = {
                heartbeat = true,
                godmode_probe = true,
                vehicle_spam = true,
                spawn_abuse = true,
                attachments_audit = true,
                damage_monitor = true,
                auto_detections = true,
                risk_engine = true,
                enhanced_detections = true,
            },
        },
        TargetedSpawnProtection = {
            Enabled = true, -- expose targeted anti-spawn toggles in the staff panel
            DefaultProtectAll = false, -- false = protections apply only to tagged players; true = keep legacy global behavior
        },
        StaffOverlay = {
            Enabled = true,
            Default = false,
            DrawDistance = 40.0,
            MinScale = 0.3,
            MaxScale = 0.55,
        },
        AutoDetections = {
            PortraitCooldownMs = 4000,
            HighSpeedThreshold = 140.0,
            HighSpeedCooldownMs = 15000,
            VehicleSpeedThreshold = 260.0,
            VehicleSpeedCooldownMs = 20000,
            InvincibleCooldownMs = 45000,
            ExcessHealthTolerance = 15,
            ExcessHealthCooldownMs = 30000,
            ArmorThreshold = 100,
            ArmorCooldownMs = 30000,
            InvisibleCooldownMs = 45000,
            TeleportDistance = 150.0,
            TeleportWindowMs = 5000,
            TeleportCooldownMs = 45000,
            TeleportSpeedThreshold = 220.0,
            AirwalkHeightThreshold = 6.5,
            AirwalkSpeedTolerance = 28.0,
            AirwalkCooldownMs = 35000,
            AirwalkSustainMs = 2000,
            AccelerationThreshold = 90.0,
            AccelerationWindowMs = 1200,
            AccelerationCooldownMs = 25000,
            AccelerationMinSpeed = 120.0,
            AscentHeightThreshold = 9.0,
            AscentWindowMs = 1500,
            AscentCooldownMs = 32000,
            AscentHorizontalTolerance = 25.0,
            AscentVerticalSpeed = 6.0,
            GodmodeHealthFloor = 170,
            GodmodeStationaryWindowMs = 4500,
            GodmodeCooldownMs = 45000,
            SpectatorCameraDetection = true,
            SpectatorCameraMinDistance = 28.0,
            SpectatorCameraRayDistance = 220.0,
            SpectatorCameraRayRadius = 3.0,
            SpectatorCameraCooldownMs = 45000,
            EvidenceScreenshot = {
                Enabled = true,
                CooldownMs = 90000, -- cooldown per target between automatic evidence screenshots
                Encoding = 'jpg',
                Quality = 65, -- keep moderate quality to reduce client impact/bandwidth
                UploadWebhook = '', -- optional dedicated webhook for automatic detection screenshots
            },
        },
        LivePreview = {
            Mode = 'disabled',
            Enabled = false,
            RefreshInterval = 120000, -- disabled in production; kept only as fallback
            Quality = 20,
            Encoding = 'jpg',
            Width = 640,
            Height = 360,
            LatentThreshold = 524288,
            LatentBytesPerSecond = 131072,
            Camera = {
                Distance = 3.2,
                Height = 1.2,
                LookHeight = 0.9,
                Fov = 55.0,
                Focus = true,
                UpdateIntervalMs = 1000, -- preview disabled; safe fallback only
                FocusIntervalMs = 5000, -- preview disabled; no streaming focus spam
            },
            ClonePreview = {
                Enabled = false,
                Position = 'front',
                ScreenX = 0.11,
                ScreenY = 0.77,
                ScreenXZoom = 0.5,
                ScreenYZoom = 1.9,
                Depth = 3.1,
                DepthZoom = 1.8,
                BufferSize = 5,
                SyncInterval = 2000,
                UpdateIntervalMs = 100, -- lighter clone update while the staff menu/preview is active
                HeadingOffset = nil,
                RotationOffset = 170.0,
                Alpha = 254,
            },
        },
    },
}
