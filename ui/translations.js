(function () {
    const STORAGE_KEY = 'visionary:language';
    const DEFAULT_LANGUAGE = 'en';

    const translations = {
        en: {
            appearance: {
                toggle: 'Appearance',
                title: 'Customization',
                description: 'Define and save the look of your interface.',
                interface: {
                    title: 'Interface',
                    description: 'Configure the language and layout of your console.',
                    language: 'Language',
                },
                inspector: {
                    title: 'Player inspector',
                    description: 'Adjust the floating live inspection panel.',
                    opacityLabel: 'Inspector transparency',
                    baseColor: 'Background color',
                    accentColor: 'Accent color',
                },
                console: {
                    title: 'Main console',
                    description: 'Define the overall presentation of the admin dashboard.',
                    windowOpacity: 'Window transparency',
                    panelOpacity: 'Panel transparency',
                    backdropOpacity: 'Backdrop opacity',
                    blur: 'Backdrop blur',
                    baseColor: 'Primary color',
                    accentColor: 'Console accent color',
                },
                actions: {
                    reset: 'Reset',
                    save: 'Save',
                },
                status: {
                    default: '',
                    pending: 'Unsaved changes',
                    saving: 'Saving…',
                    error: 'Save failed. Please try again.',
                    reset: 'Preferences reset (not saved)',
                    saved: 'Appearance saved.',
                },
            },
            language: {
                selectorLabel: 'Language selector',
                options: {
                    en: 'English',
                    fr: 'French',
                    es: 'Spanish',
                    de: 'German',
                    pt: 'Portuguese',
                    it: 'Italian',
                    'zh-hans': 'Chinese (Simplified)',
                    ar: 'Arabic',
                },
            },
            header: {
                title: 'Visionary Shield Operations Console',
                subtitle: 'Professional staff-led anti-cheat review interface',
            },
            stats: {
                players: 'Players',
                alerts: 'Alerts',
                bans: 'Active bans',
                spectating: 'Spec sessions',
            },
            actions: {
                refresh: 'Refresh data',
                cloak: 'Staff stealth',
                exitSpectate: 'Leave spectator',
                close: 'Close panel',
            },
            panels: {
                players: {
                    title: 'Connected players',
                    subtitle: 'Select a player to open the live inspector.',
                },
                feed: {
                    title: 'Alert feed',
                    subtitle: 'Latest events reported by Visionary Shield.',
                },
                session: {
                    title: 'Your session',
                    subtitle: 'Admin status and active moderation actions.',
                },
                damage: {
                    title: 'Damage log',
                    subtitle: 'Detailed analysis of recent impacts.',
                },
                bans: {
                    title: 'Active bans',
                    subtitle: 'Quick management of current sanctions.',
                },
                notes: {
                    title: 'Moderation notes',
                    subtitle: 'Shared history of administrative observations.',
                    empty: 'No notes recorded.',
                },
            },
            session: {
                viewerStatus: 'Waiting for information…',
                moderation: {
                    title: 'Moderation in progress',
                    empty: 'No active moderation action.',
                },
            },
            tables: {
                players: {
                    id: 'ID',
                    name: 'Name',
                    ping: 'Ping',
                    status: 'Status',
                },
                damage: {
                    timestamp: 'Timestamp',
                    attacker: 'Attacker',
                    target: 'Target',
                    weapon: 'Weapon',
                    amount: 'Damage',
                    distance: 'Distance',
                    flags: 'Flags',
                },
                bans: {
                    id: 'ID',
                    name: 'Name',
                    reason: 'Reason',
                    expires: 'Expires',
                    author: 'By',
                    actions: 'Actions',
                },
            },
            preview: {
                title: 'Player inspector',
                tools: {
                    lock: 'Lock the player inspector',
                    lockToggle: 'Lock or unlock the player inspector',
                    expand: 'Expand or collapse the card',
                    expandLabel: 'Expand or collapse the card',
                    close: 'Close the player card',
                    closeLabel: 'Close the player card',
                },
                live: {
                    alt: 'Player live feed',
                    waiting: 'Waiting for stream…',
                },
                hud: {
                    health: 'Health —',
                    armor: 'Armor —',
                    speed: 'Speed',
                    altitude: 'Altitude',
                    latency: 'Latency',
                    travel: 'Travel',
                },
                portrait: {
                    alt: 'Player portrait',
                },
                placeholder: {
                    name: 'Select a player',
                    coords: 'No data available',
                },
                status: {
                    idle: '',
                },
                actions: {
                    placeholder: 'Choose a player from the list to display available actions.',
                },
                errors: {
                    disabled: 'Live stream disabled server-side',
                    resourceMissing: 'Capture module unavailable',
                    exportMissing: 'Capture extension incompatible',
                    unavailable: 'Stream unavailable',
                    targetMissing: 'Player not found for the stream',
                    targetLeft: 'The player left the stream',
                    captureFailed: 'Capture unavailable',
                    captureException: 'Internal capture error',
                    invalidImage: 'Invalid video stream',
                    busy: 'Client busy — capture postponed',
                    gameInactive: 'Target game inactive',
                    timeout: 'Capture timed out',
                    generic: 'Live stream unavailable',
                },
            },
            detections: {
                generic: 'Detection',
                unknown: 'Detection ({{detection}})',
                high_speed: 'Abnormal speed',
                invincible: 'Invincibility',
                excessHealth: 'Abnormal health',
                vehicleSpeed: 'Vehicle speed',
                excessArmor: 'Abnormal armor',
                invisible: 'Suspicious invisibility',
                teleport: 'Suspicious teleport',
                airwalk: 'Air movement',
                speedBurst: 'Abnormal acceleration',
                suddenAscent: 'Suspicious ascent',
            },
            forms: {
                freezeReason: 'Visionary Shield control',
                noteMessage: 'Quick observation about the player.',
                warnMessage: 'Suspicious behaviour detected.',
                kickReason: 'Rules violation',
                banReason: 'Suspected cheating',
            },
        },
        fr: {
            appearance: {
                toggle: 'Apparence',
                title: 'Personnalisation',
                description: "Définissez et enregistrez l'apparence de votre interface.",
                interface: {
                    title: 'Interface',
                    description: 'Configurez la langue et la disposition de votre console.',
                    language: 'Langue',
                },
                inspector: {
                    title: 'Inspecteur joueur',
                    description: "Ajustez le panneau flottant d'inspection en direct.",
                    opacityLabel: "Transparence de l'inspecteur",
                    baseColor: 'Couleur de fond',
                    accentColor: "Couleur d'accent",
                },
                console: {
                    title: 'Console principale',
                    description: 'Définissez le rendu général du tableau de bord administrateur.',
                    windowOpacity: 'Transparence de la fenêtre',
                    panelOpacity: 'Transparence des panneaux',
                    backdropOpacity: "Opacité de l'arrière-plan",
                    blur: "Flou d'arrière-plan",
                    baseColor: 'Couleur principale',
                    accentColor: "Couleur d'accent console",
                },
                actions: {
                    reset: 'Réinitialiser',
                    save: 'Enregistrer',
                },
                status: {
                    default: '',
                    pending: 'Modifications non enregistrées',
                    saving: 'Enregistrement en cours…',
                    error: "Échec de l'enregistrement. Réessayez.",
                    reset: 'Préférences réinitialisées (non enregistrées)',
                    saved: 'Apparence enregistrée.',
                },
            },
            language: {
                selectorLabel: 'Sélecteur de langue',
                options: {
                    en: 'Anglais',
                    fr: 'Français',
                    es: 'Espagnol',
                    de: 'Allemand',
                    pt: 'Portugais',
                    it: 'Italien',
                    'zh-hans': 'Chinois (simplifié)',
                    ar: 'Arabe',
                },
            },
            header: {
                title: 'Console Opérations Visionary Shield',
                subtitle: 'Interface professionnelle de revue anti-cheat pilotée par le staff',
            },
            stats: {
                players: 'Joueurs',
                alerts: 'Alertes',
                bans: 'Bans actifs',
                spectating: 'Sessions spec',
            },
            actions: {
                refresh: 'Actualiser les données',
                cloak: 'Furtivité staff',
                exitSpectate: 'Quitter spectateur',
                close: 'Fermer le panneau',
            },
            panels: {
                players: {
                    title: 'Joueurs connectés',
                    subtitle: "Sélectionnez un joueur pour ouvrir l'inspecteur en direct.",
                },
                feed: {
                    title: "Flux d'alertes",
                    subtitle: 'Derniers évènements signalés par Visionary Shield.',
                },
                session: {
                    title: 'Votre session',
                    subtitle: 'Statut administrateur et actions de modération actives.',
                },
                damage: {
                    title: 'Journal des dégâts',
                    subtitle: 'Analyse détaillée des impacts récents.',
                },
                bans: {
                    title: 'Bans actifs',
                    subtitle: 'Gestion rapide des sanctions en vigueur.',
                },
                notes: {
                    title: 'Notes de modération',
                    subtitle: 'Historique partagé des observations administratives.',
                    empty: 'Aucune note enregistrée.',
                },
            },
            session: {
                viewerStatus: 'En attente des informations…',
                moderation: {
                    title: 'Modération en cours',
                    empty: 'Aucune action de modération active.',
                },
            },
            tables: {
                players: {
                    id: 'ID',
                    name: 'Nom',
                    ping: 'Ping',
                    status: 'Statut',
                },
                damage: {
                    timestamp: 'Horodatage',
                    attacker: 'Attaquant',
                    target: 'Cible',
                    weapon: 'Arme',
                    amount: 'Dégâts',
                    distance: 'Distance',
                    flags: 'Flags',
                },
                bans: {
                    id: 'ID',
                    name: 'Nom',
                    reason: 'Raison',
                    expires: 'Expire',
                    author: 'Par',
                    actions: 'Actions',
                },
            },
            preview: {
                title: 'Inspecteur joueur',
                tools: {
                    lock: "Verrouiller l'inspecteur joueur",
                    lockToggle: "Verrouiller ou déverrouiller l'inspecteur joueur",
                    expand: 'Agrandir ou réduire la fiche',
                    expandLabel: 'Agrandir ou réduire la fiche',
                    close: 'Fermer la fiche joueur',
                    closeLabel: 'Fermer la fiche joueur',
                },
                live: {
                    alt: 'Flux en direct du joueur',
                    waiting: 'Flux en attente…',
                },
                hud: {
                    health: 'Santé —',
                    armor: 'Armure —',
                    speed: 'Vitesse',
                    altitude: 'Altitude',
                    latency: 'Retard',
                    travel: 'Trajet',
                },
                portrait: {
                    alt: 'Portrait du joueur',
                },
                placeholder: {
                    name: 'Sélectionnez un joueur',
                    coords: 'Aucune donnée disponible',
                },
                status: {
                    idle: '',
                },
                actions: {
                    placeholder: 'Choisissez un joueur dans la liste pour afficher les actions détaillées.',
                },
                errors: {
                    disabled: 'Flux désactivé côté serveur',
                    resourceMissing: 'Module de capture indisponible',
                    exportMissing: 'Extension de capture incompatible',
                    unavailable: 'Flux indisponible',
                    targetMissing: 'Joueur introuvable pour le flux',
                    targetLeft: 'Le joueur a quitté le flux',
                    captureFailed: 'Capture indisponible',
                    captureException: 'Erreur interne lors de la capture',
                    invalidImage: 'Flux vidéo invalide',
                    busy: 'Client occupé — capture reportée',
                    gameInactive: 'Jeu inactif côté cible',
                    timeout: 'Capture expirée',
                    generic: 'Flux indisponible',
                },
            },
            detections: {
                generic: 'Détection',
                unknown: 'Détection ({{detection}})',
                high_speed: 'Vitesse anormale',
                invincible: 'Invincibilité',
                excessHealth: 'Santé anormale',
                vehicleSpeed: 'Vitesse véhicule',
                excessArmor: 'Armure anormale',
                invisible: 'Invisibilité suspecte',
                teleport: 'Téléportation suspecte',
                airwalk: 'Déplacement aérien',
                speedBurst: 'Accélération anormale',
                suddenAscent: 'Ascension suspecte',
            },
            forms: {
                freezeReason: 'Contrôle Visionary Shield',
                noteMessage: 'Observation rapide sur le joueur.',
                warnMessage: 'Comportement suspect détecté.',
                kickReason: 'Non-respect des règles',
                banReason: 'Suspicion de triche',
            },
        },
        es: {
            appearance: {
                toggle: 'Apariencia',
                title: 'Personalización',
                description: 'Define y guarda el aspecto de tu interfaz.',
                interface: {
                    title: 'Interfaz',
                    description: 'Configura el idioma y la disposición de tu consola.',
                    language: 'Idioma',
                },
                inspector: {
                    title: 'Inspector de jugadores',
                    description: 'Ajusta el panel flotante de inspección en vivo.',
                    opacityLabel: 'Transparencia del inspector',
                    baseColor: 'Color de fondo',
                    accentColor: 'Color de acento',
                },
                console: {
                    title: 'Consola principal',
                    description: 'Define la presentación general del panel administrativo.',
                    windowOpacity: 'Transparencia de la ventana',
                    panelOpacity: 'Transparencia de los paneles',
                    backdropOpacity: 'Opacidad del fondo',
                    blur: 'Desenfoque del fondo',
                    baseColor: 'Color principal',
                    accentColor: 'Color de acento de la consola',
                },
                actions: {
                    reset: 'Restablecer',
                    save: 'Guardar',
                },
                status: {
                    default: '',
                    pending: 'Cambios sin guardar',
                    saving: 'Guardando…',
                    error: 'Error al guardar. Inténtalo de nuevo.',
                    reset: 'Preferencias restablecidas (no guardadas)',
                    saved: 'Apariencia guardada.',
                },
            },
            language: {
                selectorLabel: 'Selector de idioma',
                options: {
                    en: 'Inglés',
                    fr: 'Francés',
                    es: 'Español',
                    de: 'Alemán',
                    pt: 'Portugués',
                    it: 'Italiano',
                    'zh-hans': 'Chino (simplificado)',
                    ar: 'Árabe',
                },
            },
            header: {
                title: 'Consola Administrativa Visionary',
                subtitle: 'Interfaz de supervisión Visionary Shield',
            },
            stats: {
                players: 'Jugadores',
                alerts: 'Alertas',
                bans: 'Baneos activos',
                spectating: 'Sesiones de espectador',
            },
            actions: {
                refresh: 'Actualizar datos',
                cloak: 'Modo sigiloso pro',
                exitSpectate: 'Salir del espectador',
                close: 'Cerrar panel',
            },
            panels: {
                players: {
                    title: 'Jugadores conectados',
                    subtitle: 'Selecciona un jugador para abrir el inspector en vivo.',
                },
                feed: {
                    title: 'Flujo de alertas',
                    subtitle: 'Últimos eventos reportados por Visionary Shield.',
                },
                session: {
                    title: 'Tu sesión',
                    subtitle: 'Estado administrativo y acciones de moderación activas.',
                },
                damage: {
                    title: 'Registro de daños',
                    subtitle: 'Análisis detallado de los impactos recientes.',
                },
                bans: {
                    title: 'Baneos activos',
                    subtitle: 'Gestión rápida de las sanciones vigentes.',
                },
                notes: {
                    title: 'Notas de moderación',
                    subtitle: 'Historial compartido de observaciones administrativas.',
                    empty: 'No hay notas registradas.',
                },
            },
            session: {
                viewerStatus: 'Esperando información…',
                moderation: {
                    title: 'Moderación en curso',
                    empty: 'No hay acciones de moderación activas.',
                },
            },
            tables: {
                players: {
                    id: 'ID',
                    name: 'Nombre',
                    ping: 'Ping',
                    status: 'Estado',
                },
                damage: {
                    timestamp: 'Marca de tiempo',
                    attacker: 'Atacante',
                    target: 'Objetivo',
                    weapon: 'Arma',
                    amount: 'Daño',
                    distance: 'Distancia',
                    flags: 'Indicadores',
                },
                bans: {
                    id: 'ID',
                    name: 'Nombre',
                    reason: 'Motivo',
                    expires: 'Expira',
                    author: 'Por',
                    actions: 'Acciones',
                },
            },
        },
        de: {
            appearance: {
                toggle: 'Erscheinung',
                title: 'Anpassung',
                description: 'Definiere und speichere das Aussehen deiner Oberfläche.',
                interface: {
                    title: 'Benutzeroberfläche',
                    description: 'Konfiguriere Sprache und Anordnung deiner Konsole.',
                    language: 'Sprache',
                },
                inspector: {
                    title: 'Spielerinspektor',
                    description: 'Passe das schwebende Live-Inspektionsfenster an.',
                    opacityLabel: 'Transparenz des Inspektors',
                    baseColor: 'Hintergrundfarbe',
                    accentColor: 'Akzentfarbe',
                },
                console: {
                    title: 'Hauptkonsole',
                    description: 'Lege das Erscheinungsbild des Admin-Dashboards fest.',
                    windowOpacity: 'Fenstertransparenz',
                    panelOpacity: 'Paneltransparenz',
                    backdropOpacity: 'Hintergrundopazität',
                    blur: 'Hintergrundunschärfe',
                    baseColor: 'Grundfarbe',
                    accentColor: 'Akzentfarbe der Konsole',
                },
                actions: {
                    reset: 'Zurücksetzen',
                    save: 'Speichern',
                },
                status: {
                    default: '',
                    pending: 'Nicht gespeicherte Änderungen',
                    saving: 'Wird gespeichert…',
                    error: 'Speichern fehlgeschlagen. Bitte erneut versuchen.',
                    reset: 'Einstellungen zurückgesetzt (nicht gespeichert)',
                    saved: 'Erscheinungsbild gespeichert.',
                },
            },
            language: {
                selectorLabel: 'Sprachauswahl',
                options: {
                    en: 'Englisch',
                    fr: 'Französisch',
                    es: 'Spanisch',
                    de: 'Deutsch',
                    pt: 'Portugiesisch',
                    it: 'Italienisch',
                    'zh-hans': 'Chinesisch (vereinfacht)',
                    ar: 'Arabisch',
                },
            },
            header: {
                title: 'Visionary Admin-Konsole',
                subtitle: 'Überwachungsoberfläche von Visionary Shield',
            },
            stats: {
                players: 'Spieler',
                alerts: 'Alarme',
                bans: 'Aktive Sperren',
                spectating: 'Zuschauersitzungen',
            },
            actions: {
                refresh: 'Daten aktualisieren',
                cloak: 'Pro-Tarnmodus',
                exitSpectate: 'Zuschauermodus verlassen',
                close: 'Panel schließen',
            },
            panels: {
                players: {
                    title: 'Verbunden Spieler',
                    subtitle: 'Wähle einen Spieler, um den Live-Inspektor zu öffnen.',
                },
                feed: {
                    title: 'Alarmfeed',
                    subtitle: 'Neueste Ereignisse von Visionary Shield.',
                },
                session: {
                    title: 'Deine Sitzung',
                    subtitle: 'Adminstatus und aktive Moderationsmaßnahmen.',
                },
                damage: {
                    title: 'Schadensprotokoll',
                    subtitle: 'Detaillierte Analyse der jüngsten Treffer.',
                },
                bans: {
                    title: 'Aktive Sperren',
                    subtitle: 'Schnelle Verwaltung aktueller Sanktionen.',
                },
                notes: {
                    title: 'Moderationsnotizen',
                    subtitle: 'Gemeinsame Historie administrativer Beobachtungen.',
                    empty: 'Keine Notizen vorhanden.',
                },
            },
            session: {
                viewerStatus: 'Warte auf Informationen…',
                moderation: {
                    title: 'Moderation aktiv',
                    empty: 'Keine aktiven Moderationsmaßnahmen.',
                },
            },
            tables: {
                players: {
                    id: 'ID',
                    name: 'Name',
                    ping: 'Ping',
                    status: 'Status',
                },
                damage: {
                    timestamp: 'Zeitstempel',
                    attacker: 'Angreifer',
                    target: 'Ziel',
                    weapon: 'Waffe',
                    amount: 'Schaden',
                    distance: 'Entfernung',
                    flags: 'Flags',
                },
                bans: {
                    id: 'ID',
                    name: 'Name',
                    reason: 'Grund',
                    expires: 'Läuft ab',
                    author: 'Von',
                    actions: 'Aktionen',
                },
            },
        },
        pt: {
            appearance: {
                toggle: 'Aparência',
                title: 'Personalização',
                description: 'Defina e salve o visual da sua interface.',
                interface: {
                    title: 'Interface',
                    description: 'Configure o idioma e o layout da sua consola.',
                    language: 'Idioma',
                },
                inspector: {
                    title: 'Inspetor de jogadores',
                    description: 'Ajuste o painel flutuante de inspeção ao vivo.',
                    opacityLabel: 'Transparência do inspetor',
                    baseColor: 'Cor de fundo',
                    accentColor: 'Cor de destaque',
                },
                console: {
                    title: 'Consola principal',
                    description: 'Defina a apresentação geral do painel administrativo.',
                    windowOpacity: 'Transparência da janela',
                    panelOpacity: 'Transparência dos painéis',
                    backdropOpacity: 'Opacidade do fundo',
                    blur: 'Desfoque do fundo',
                    baseColor: 'Cor principal',
                    accentColor: 'Cor de destaque da consola',
                },
                actions: {
                    reset: 'Redefinir',
                    save: 'Guardar',
                },
                status: {
                    default: '',
                    pending: 'Alterações não salvas',
                    saving: 'Salvando…',
                    error: 'Falha ao salvar. Tente novamente.',
                    reset: 'Preferências redefinidas (não salvas)',
                    saved: 'Aparência salva.',
                },
            },
            language: {
                selectorLabel: 'Seletor de idioma',
                options: {
                    en: 'Inglês',
                    fr: 'Francês',
                    es: 'Espanhol',
                    de: 'Alemão',
                    pt: 'Português',
                    it: 'Italiano',
                    'zh-hans': 'Chinês (simplificado)',
                    ar: 'Árabe',
                },
            },
            header: {
                title: 'Consola Administrativa Visionary',
                subtitle: 'Interface de supervisão Visionary Shield',
            },
            stats: {
                players: 'Jogadores',
                alerts: 'Alertas',
                bans: 'Banimentos ativos',
                spectating: 'Sessões de espectador',
            },
            actions: {
                refresh: 'Atualizar dados',
                cloak: 'Modo furtivo pro',
                exitSpectate: 'Sair do espectador',
                close: 'Fechar painel',
            },
            panels: {
                players: {
                    title: 'Jogadores conectados',
                    subtitle: 'Selecione um jogador para abrir o inspetor ao vivo.',
                },
                feed: {
                    title: 'Feed de alertas',
                    subtitle: 'Últimos eventos relatados pelo Visionary Shield.',
                },
                session: {
                    title: 'Sua sessão',
                    subtitle: 'Estado administrativo e ações de moderação ativas.',
                },
                damage: {
                    title: 'Registo de danos',
                    subtitle: 'Análise detalhada dos impactos recentes.',
                },
                bans: {
                    title: 'Banimentos ativos',
                    subtitle: 'Gestão rápida das sanções em vigor.',
                },
                notes: {
                    title: 'Notas de moderação',
                    subtitle: 'Histórico partilhado de observações administrativas.',
                    empty: 'Nenhuma nota registada.',
                },
            },
            session: {
                viewerStatus: 'A aguardar informações…',
                moderation: {
                    title: 'Moderação em curso',
                    empty: 'Nenhuma ação de moderação ativa.',
                },
            },
            tables: {
                players: {
                    id: 'ID',
                    name: 'Nome',
                    ping: 'Ping',
                    status: 'Estado',
                },
                damage: {
                    timestamp: 'Data e hora',
                    attacker: 'Atacante',
                    target: 'Alvo',
                    weapon: 'Arma',
                    amount: 'Dano',
                    distance: 'Distância',
                    flags: 'Sinais',
                },
                bans: {
                    id: 'ID',
                    name: 'Nome',
                    reason: 'Motivo',
                    expires: 'Expira',
                    author: 'Por',
                    actions: 'Ações',
                },
            },
        },
        it: {
            appearance: {
                toggle: 'Aspetto',
                title: 'Personalizzazione',
                description: "Definisci e salva l'aspetto della tua interfaccia.",
                interface: {
                    title: 'Interfaccia',
                    description: 'Configura la lingua e il layout della console.',
                    language: 'Lingua',
                },
                inspector: {
                    title: 'Ispettore giocatore',
                    description: 'Regola il pannello di ispezione in tempo reale.',
                    opacityLabel: 'Trasparenza dell’ispettore',
                    baseColor: 'Colore di sfondo',
                    accentColor: 'Colore di accento',
                },
                console: {
                    title: 'Console principale',
                    description: 'Definisci la presentazione generale del pannello amministrativo.',
                    windowOpacity: 'Trasparenza della finestra',
                    panelOpacity: 'Trasparenza dei pannelli',
                    backdropOpacity: 'Opacità dello sfondo',
                    blur: 'Sfocatura dello sfondo',
                    baseColor: 'Colore principale',
                    accentColor: 'Colore di accento della console',
                },
                actions: {
                    reset: 'Reimposta',
                    save: 'Salva',
                },
                status: {
                    default: '',
                    pending: 'Modifiche non salvate',
                    saving: 'Salvataggio…',
                    error: 'Salvataggio non riuscito. Riprova.',
                    reset: 'Preferenze ripristinate (non salvate)',
                    saved: 'Aspetto salvato.',
                },
            },
            language: {
                selectorLabel: 'Selettore lingua',
                options: {
                    en: 'Inglese',
                    fr: 'Francese',
                    es: 'Spagnolo',
                    de: 'Tedesco',
                    pt: 'Portoghese',
                    it: 'Italiano',
                    'zh-hans': 'Cinese (semplificato)',
                    ar: 'Arabo',
                },
            },
            header: {
                title: 'Console Amministrativa Visionary',
                subtitle: 'Interfaccia di supervisione Visionary Shield',
            },
            stats: {
                players: 'Giocatori',
                alerts: 'Allerte',
                bans: 'Ban attivi',
                spectating: 'Sessioni spettatore',
            },
            actions: {
                refresh: 'Aggiorna dati',
                cloak: 'Modalità furtiva pro',
                exitSpectate: 'Esci da spettatore',
                close: 'Chiudi pannello',
            },
            panels: {
                players: {
                    title: 'Giocatori connessi',
                    subtitle: 'Seleziona un giocatore per aprire l’ispettore live.',
                },
                feed: {
                    title: 'Feed di allerta',
                    subtitle: 'Ultimi eventi segnalati da Visionary Shield.',
                },
                session: {
                    title: 'La tua sessione',
                    subtitle: 'Stato amministrativo e azioni di moderazione attive.',
                },
                damage: {
                    title: 'Registro dei danni',
                    subtitle: 'Analisi dettagliata degli impatti recenti.',
                },
                bans: {
                    title: 'Ban attivi',
                    subtitle: 'Gestione rapida delle sanzioni in corso.',
                },
                notes: {
                    title: 'Note di moderazione',
                    subtitle: 'Storico condiviso delle osservazioni amministrative.',
                    empty: 'Nessuna nota registrata.',
                },
            },
            session: {
                viewerStatus: 'In attesa di informazioni…',
                moderation: {
                    title: 'Moderazione in corso',
                    empty: 'Nessuna azione di moderazione attiva.',
                },
            },
            tables: {
                players: {
                    id: 'ID',
                    name: 'Nome',
                    ping: 'Ping',
                    status: 'Stato',
                },
                damage: {
                    timestamp: 'Data e ora',
                    attacker: 'Attaccante',
                    target: 'Bersaglio',
                    weapon: 'Arma',
                    amount: 'Danno',
                    distance: 'Distanza',
                    flags: 'Indicatori',
                },
                bans: {
                    id: 'ID',
                    name: 'Nome',
                    reason: 'Motivo',
                    expires: 'Scade',
                    author: 'Da',
                    actions: 'Azioni',
                },
            },
        },
        'zh-hans': {
            appearance: {
                toggle: '外观',
                title: '自定义',
                description: '定义并保存界面的外观。',
                interface: {
                    title: '界面',
                    description: '配置控制台的语言和布局。',
                    language: '语言',
                },
                inspector: {
                    title: '玩家监控',
                    description: '调整悬浮的实时监控面板。',
                    opacityLabel: '监控透明度',
                    baseColor: '背景颜色',
                    accentColor: '强调颜色',
                },
                console: {
                    title: '主控制台',
                    description: '设置管理面板的整体外观。',
                    windowOpacity: '窗口透明度',
                    panelOpacity: '面板透明度',
                    backdropOpacity: '背景不透明度',
                    blur: '背景模糊',
                    baseColor: '主色调',
                    accentColor: '控制台强调色',
                },
                actions: {
                    reset: '重置',
                    save: '保存',
                },
                status: {
                    default: '',
                    pending: '有未保存的更改',
                    saving: '正在保存…',
                    error: '保存失败，请重试。',
                    reset: '已重置偏好设置（未保存）',
                    saved: '外观已保存。',
                },
            },
            language: {
                selectorLabel: '语言选择器',
                options: {
                    en: '英语',
                    fr: '法语',
                    es: '西班牙语',
                    de: '德语',
                    pt: '葡萄牙语',
                    it: '意大利语',
                    'zh-hans': '简体中文',
                    ar: '阿拉伯语',
                },
            },
            header: {
                title: 'Visionary 管理控制台',
                subtitle: 'Visionary 反作弊监管界面',
            },
            stats: {
                players: '玩家',
                alerts: '警报',
                bans: '有效封禁',
                spectating: '观战会话',
            },
            actions: {
                refresh: '刷新数据',
                cloak: '专业隐身模式',
                exitSpectate: '退出观战',
                close: '关闭面板',
            },
            panels: {
                players: {
                    title: '在线玩家',
                    subtitle: '选择一名玩家以打开实时监控。',
                },
                feed: {
                    title: '警报信息流',
                    subtitle: 'Visionary Shield 报告的最新事件。',
                },
                session: {
                    title: '你的会话',
                    subtitle: '管理员状态与当前的管理操作。',
                },
                damage: {
                    title: '伤害日志',
                    subtitle: '近期伤害的详细分析。',
                },
                bans: {
                    title: '有效封禁',
                    subtitle: '快速管理当前的封禁。',
                },
                notes: {
                    title: '管理记录',
                    subtitle: '共享的管理观察历史。',
                    empty: '暂无记录。',
                },
            },
            session: {
                viewerStatus: '正在等待信息…',
                moderation: {
                    title: '进行中的管理',
                    empty: '暂无管理操作。',
                },
            },
            tables: {
                players: {
                    id: '编号',
                    name: '姓名',
                    ping: '延迟',
                    status: '状态',
                },
                damage: {
                    timestamp: '时间戳',
                    attacker: '攻击者',
                    target: '目标',
                    weapon: '武器',
                    amount: '伤害',
                    distance: '距离',
                    flags: '标记',
                },
                bans: {
                    id: '编号',
                    name: '姓名',
                    reason: '原因',
                    expires: '到期',
                    author: '执行者',
                    actions: '操作',
                },
            },
        },
        ar: {
            appearance: {
                toggle: 'المظهر',
                title: 'التخصيص',
                description: 'حدد واحفظ مظهر واجهتك.',
                interface: {
                    title: 'الواجهة',
                    description: 'اضبط لغة وحدة التحكم وتخطيطها.',
                    language: 'اللغة',
                },
                inspector: {
                    title: 'مراقب اللاعبين',
                    description: 'اضبط لوحة التفتيش العائمة المباشرة.',
                    opacityLabel: 'شفافية المراقب',
                    baseColor: 'لون الخلفية',
                    accentColor: 'لون التمييز',
                },
                console: {
                    title: 'وحدة التحكم الرئيسية',
                    description: 'حدد العرض العام للوحة الإدارة.',
                    windowOpacity: 'شفافية النافذة',
                    panelOpacity: 'شفافية اللوحات',
                    backdropOpacity: 'شفافية الخلفية',
                    blur: 'تمويه الخلفية',
                    baseColor: 'اللون الأساسي',
                    accentColor: 'لون التمييز في الوحدة',
                },
                actions: {
                    reset: 'إعادة ضبط',
                    save: 'حفظ',
                },
                status: {
                    default: '',
                    pending: 'تغييرات غير محفوظة',
                    saving: 'جارٍ الحفظ…',
                    error: 'فشل الحفظ. حاول مرة أخرى.',
                    reset: 'تمت إعادة التفضيلات (غير محفوظة)',
                    saved: 'تم حفظ المظهر.',
                },
            },
            language: {
                selectorLabel: 'محدد اللغة',
                options: {
                    en: 'الإنجليزية',
                    fr: 'الفرنسية',
                    es: 'الإسبانية',
                    de: 'الألمانية',
                    pt: 'البرتغالية',
                    it: 'الإيطالية',
                    'zh-hans': 'الصينية المبسطة',
                    ar: 'العربية',
                },
            },
            header: {
                title: 'وحدة إدارة Visionary',
                subtitle: 'واجهة مراقبة Visionary Shield',
            },
            stats: {
                players: 'اللاعبون',
                alerts: 'التنبيهات',
                bans: 'الحظر النشط',
                spectating: 'جلسات المراقبة',
            },
            actions: {
                refresh: 'تحديث البيانات',
                cloak: 'وضع التخفي الاحترافي',
                exitSpectate: 'إنهاء المراقبة',
                close: 'إغلاق اللوحة',
            },
            panels: {
                players: {
                    title: 'اللاعبون المتصلون',
                    subtitle: 'اختر لاعبًا لفتح المراقب المباشر.',
                },
                feed: {
                    title: 'موجز التنبيهات',
                    subtitle: 'أحدث الأحداث المبلغ عنها من Visionary Shield.',
                },
                session: {
                    title: 'جلستك',
                    subtitle: 'حالة المشرف وإجراءات الإشراف النشطة.',
                },
                damage: {
                    title: 'سجل الأضرار',
                    subtitle: 'تحليل مفصل لأحدث الإصابات.',
                },
                bans: {
                    title: 'الحظر النشط',
                    subtitle: 'إدارة سريعة للعقوبات الحالية.',
                },
                notes: {
                    title: 'ملاحظات الإشراف',
                    subtitle: 'سجل مشترك للملاحظات الإدارية.',
                    empty: 'لا توجد ملاحظات مسجلة.',
                },
            },
            session: {
                viewerStatus: 'بانتظار المعلومات…',
                moderation: {
                    title: 'إشراف جارٍ',
                    empty: 'لا توجد إجراءات إشراف نشطة.',
                },
            },
            tables: {
                players: {
                    id: 'المعرف',
                    name: 'الاسم',
                    ping: 'زمن الاستجابة',
                    status: 'الحالة',
                },
                damage: {
                    timestamp: 'الطابع الزمني',
                    attacker: 'المهاجم',
                    target: 'الهدف',
                    weapon: 'السلاح',
                    amount: 'الضرر',
                    distance: 'المسافة',
                    flags: 'الوسوم',
                },
                bans: {
                    id: 'المعرف',
                    name: 'الاسم',
                    reason: 'السبب',
                    expires: 'ينتهي',
                    author: 'بواسطة',
                    actions: 'الإجراءات',
                },
            },
        },
    };

    const LANGUAGE_ALIASES = {
        en: 'en',
        'en-us': 'en',
        'en-gb': 'en',
        fr: 'fr',
        'fr-fr': 'fr',
        es: 'es',
        'es-es': 'es',
        'es-mx': 'es',
        de: 'de',
        'de-de': 'de',
        pt: 'pt',
        'pt-br': 'pt',
        'pt-pt': 'pt',
        it: 'it',
        'it-it': 'it',
        'zh': 'zh-hans',
        'zh-cn': 'zh-hans',
        'zh-sg': 'zh-hans',
        'zh-hans': 'zh-hans',
        ar: 'ar',
        'ar-sa': 'ar',
        'ar-eg': 'ar',
    };

    function normalizeLanguage(language) {
        if (typeof language !== 'string') {
            if (translations[DEFAULT_LANGUAGE]) {
                return DEFAULT_LANGUAGE;
            }
            const [first] = Object.keys(translations);
            return first || DEFAULT_LANGUAGE;
        }

        const sanitized = language.trim().toLowerCase().replace(/_/g, '-');

        if (translations[sanitized]) {
            return sanitized;
        }

        const alias = LANGUAGE_ALIASES[sanitized];
        if (alias && translations[alias]) {
            return alias;
        }

        const [primary] = sanitized.split('-');
        if (primary && translations[primary]) {
            return primary;
        }

        if (translations[DEFAULT_LANGUAGE]) {
            return DEFAULT_LANGUAGE;
        }

        const [first] = Object.keys(translations);
        return first || DEFAULT_LANGUAGE;
    }

    function resolveTranslation(language, key) {
        const segments = key.split('.');
        let cursor = translations[language] || translations[DEFAULT_LANGUAGE];
        for (const segment of segments) {
            if (cursor && Object.prototype.hasOwnProperty.call(cursor, segment)) {
                cursor = cursor[segment];
            } else {
                cursor = null;
                break;
            }
        }
        if (typeof cursor === 'string') {
            return cursor;
        }
        return null;
    }

    function formatTranslation(template, replacements) {
        if (!replacements) {
            return template;
        }
        return template.replace(/\{\{(\w+)\}\}/g, (_, name) =>
            Object.prototype.hasOwnProperty.call(replacements, name) ? replacements[name] : '',
        );
    }

    function translateKey(language, key, replacements) {
        const direct = resolveTranslation(language, key);
        if (direct !== null && direct !== undefined) {
            return formatTranslation(direct, replacements);
        }
        if (language !== DEFAULT_LANGUAGE) {
            const fallback = resolveTranslation(DEFAULT_LANGUAGE, key);
            if (fallback !== null && fallback !== undefined) {
                return formatTranslation(fallback, replacements);
            }
        }
        return formatTranslation(key, replacements);
    }

    function applyElementTranslation(language, element) {
        if (element.dataset.i18n) {
            element.textContent = translateKey(language, element.dataset.i18n);
        }
        if (element.dataset.i18nTitle) {
            element.title = translateKey(language, element.dataset.i18nTitle);
        }
        if (element.dataset.i18nAriaLabel) {
            element.setAttribute('aria-label', translateKey(language, element.dataset.i18nAriaLabel));
        }
        if (element.dataset.i18nAlt) {
            element.setAttribute('alt', translateKey(language, element.dataset.i18nAlt));
        }
    }

    function applyTranslations(language) {
        const lang = normalizeLanguage(language);
        document.documentElement.lang = lang;
        const scope = document.querySelector('[data-i18n-scope="app"]') || document;
        const elements = scope.querySelectorAll('[data-i18n], [data-i18n-title], [data-i18n-aria-label], [data-i18n-alt]');
        elements.forEach((element) => applyElementTranslation(lang, element));
    }

    let currentLanguage = normalizeLanguage(DEFAULT_LANGUAGE);
    const listeners = new Set();

    function setLanguage(language) {
        const normalized = normalizeLanguage(language);
        if (normalized === currentLanguage) {
            return;
        }
        currentLanguage = normalized;
        try {
            window.localStorage.setItem(STORAGE_KEY, currentLanguage);
        } catch (error) {
            console.warn('[Visionary Shield][UI] Unable to persist language preference', error);
        }
        applyTranslations(currentLanguage);
        listeners.forEach((listener) => {
            try {
                listener(currentLanguage);
            } catch (error) {
                console.error('[Visionary Shield][UI] Language change listener error', error);
            }
        });
    }

    function getLanguage() {
        return currentLanguage;
    }

    function t(key, replacements) {
        return translateKey(currentLanguage, key, replacements);
    }

    function onLanguageChange(callback) {
        listeners.add(callback);
        return () => listeners.delete(callback);
    }

    try {
        const stored = window.localStorage.getItem(STORAGE_KEY);
        if (stored) {
            currentLanguage = normalizeLanguage(stored);
        }
    } catch (error) {
        console.warn('[Visionary Shield][UI] Unable to read language preference', error);
    }

    document.addEventListener('DOMContentLoaded', () => {
        applyTranslations(currentLanguage);
        const select = document.getElementById('languageSelect');
        if (select) {
            select.value = normalizeLanguage(currentLanguage);
            select.addEventListener('change', (event) => {
                const value = event.target.value;
                setLanguage(value);
            });
        }
    });

    window.I18N = {
        translations,
        DEFAULT_LANGUAGE,
        normalizeLanguage,
        getLanguage,
        setLanguage,
        t,
        applyTranslations,
        onLanguageChange,
    };
})();
