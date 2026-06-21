(() => {
    'use strict';

    const resourceName = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'zvs-ac';
    const $ = (selector, root = document) => root.querySelector(selector);
    const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));
    const cssEscape = (value) => (window.CSS && typeof window.CSS.escape === 'function') ? window.CSS.escape(String(value)) : String(value).replace(/[^a-zA-Z0-9_-]/g, '\\$&');

    const DEFAULT_SETTINGS = {
        version: 1,
        ui: { theme: 'visionary_dark', scale: 1.0, textScale: 1.0, compactMode: true, animations: true, soundFeedback: false },
        windows: {
            main: { x: 72, y: 54, width: 980, height: 610, opacity: 0.94, locked: false, minimized: false, maximized: false, visible: true },
            playerInspector: { x: 1180, y: 96, width: 336, height: 340, opacity: 0.92, locked: false, minimized: false, maximized: false, visible: false },
            spectateInfo: { x: 72, y: 690, width: 390, height: 178, opacity: 0.92, locked: false, minimized: false, maximized: false, visible: false },
            settings: { x: 160, y: 120, width: 500, height: 420, opacity: 0.94, locked: false, minimized: false, maximized: false, visible: false },
            adminDock: { x: 32, y: 112, width: 336, height: 414, opacity: 0.93, locked: false, minimized: false, maximized: false, visible: false },
        },
        spectate: { defaultMode: 'pov', showInfoPanel: true, updateIntervalMs: 1000, closeSpectateWithPanel: false },
        notifications: { discordLogLevel: 'normal', showLocalToasts: true, soundFeedback: false },
        binds: { openPanel: 'F5' },
        dock: { enabled: false },
        tabs: { main: 'overview', right: 'alerts' },
    };

    const app = $('#app');
    const state = {
        open: false,
        data: {},
        runtime: {},
        settings: structuredCloneSafe(DEFAULT_SETTINGS),
        selectedId: null,
        selectedPlayer: null,
        mainTab: 'overview',
        rightTab: 'alerts',
        renderQueued: false,
        autoRefreshTimer: null,
        saveTimer: null,
        settingsDirty: false,
        suppressSave: false,
        spectate: { active: false },
        noclip: { enabled: false, speed: 0, speedIndex: 0 },
        inspector: { manualClosed: false, lastPlayerId: null, snapshot: {} },
        floating: { playerInspector: false, settings: false, adminDock: false },
        floatingFocusActive: '',
        pauseSuspended: false,
        pauseSnapshot: null,
        dialog: { active: false, action: null, target: null, targetName: '', defaultText: '', severity: 'info' },
        notice: { active: false, title: '', subtitle: '', message: '', severity: 'info' },
        screenshot: { active: false, image: '', title: '', subtitle: '', meta: '' },
        textInputActive: false,
        locale: { current: 'en', fallback: 'en', strings: {}, fallbackStrings: {} },
        refs: { inspector: {} },
    };

    function structuredCloneSafe(value) {
        try { return structuredClone(value); } catch (_) { return JSON.parse(JSON.stringify(value)); }
    }

    function deepMerge(target, source) {
        if (!source || typeof source !== 'object') return target;
        for (const [key, value] of Object.entries(source)) {
            if (value && typeof value === 'object' && !Array.isArray(value)) {
                if (!target[key] || typeof target[key] !== 'object' || Array.isArray(target[key])) target[key] = {};
                deepMerge(target[key], value);
            } else {
                target[key] = value;
            }
        }
        return target;
    }

    function clamp(value, min, max, fallback) {
        const n = Number(value);
        if (!Number.isFinite(n)) return fallback;
        return Math.min(max, Math.max(min, n));
    }

    function getUiScale() {
        return clamp(state.settings?.ui?.scale, 0.75, 1.35, 1);
    }

    function getLogicalViewport() {
        const scale = getUiScale();
        return {
            width: Math.max(640, (window.innerWidth || 1920) / scale),
            height: Math.max(360, (window.innerHeight || 1080) / scale),
            scale,
        };
    }

    function sanitizeText(value, fallback = '—') {
        if (value === null || value === undefined || value === '') return fallback;
        return String(value);
    }

    function getPathValue(object, path) {
        if (!object || !path) return undefined;
        return String(path).split('.').reduce((acc, part) => (acc && typeof acc === 'object') ? acc[part] : undefined, object);
    }

    function L(key, fallback = '') {
        const value = getPathValue(state.locale.strings, key);
        if (typeof value === 'string') return value;
        const fallbackValue = getPathValue(state.locale.fallbackStrings, key);
        if (typeof fallbackValue === 'string') return fallbackValue;
        return fallback || key;
    }

    function setAttrIfChanged(el, attr, value) {
        if (!el) return;
        const text = sanitizeText(value, '');
        if (el.getAttribute(attr) !== text) el.setAttribute(attr, text);
    }

    function applyRuntimeLocalization(runtime) {
        const loc = runtime?.localization || runtime?.runtimeConfig?.localization;
        if (!loc || loc.enabled === false) return;
        state.locale.current = sanitizeText(loc.locale, 'en').toLowerCase();
        state.locale.fallback = sanitizeText(loc.fallback, 'en').toLowerCase();
        state.locale.strings = (loc.strings && typeof loc.strings === 'object') ? loc.strings : {};
        state.locale.fallbackStrings = (loc.fallbackStrings && typeof loc.fallbackStrings === 'object') ? loc.fallbackStrings : {};
        document.documentElement.lang = state.locale.current;
    }

    function applyLocaleTexts() {
        const textMap = [
            ['#statPlayersLabel', 'app.players', 'joueurs'],
            ['#statRiskLabel', 'app.risk', 'risque'],
            ['#statBansLabel', 'app.bans', 'bans'],
            ['#playerPaneTitle', 'main.playersTitle', 'Joueurs'],
            ['[data-tab="overview"]', 'main.overview', 'Overview'],
            ['[data-tab="risk"]', 'main.risk', 'Risk'],
            ['[data-tab="history"]', 'main.history', 'Audit'],
            ['[data-tab="defenses"]', 'main.defenses', 'Runtime'],
            ['[data-right-tab="alerts"]', 'main.alerts', 'Alertes'],
            ['[data-right-tab="notes"]', 'main.notes', 'Notes'],
            ['[data-right-tab="bans"]', 'main.bans', 'Bans'],
            ['[data-right-tab="damage"]', 'main.damage', 'Damage'],
            ['#saveNoteBtn', 'main.addNote', 'Ajouter note'],
            ['#settingsTitle', 'settings.title', 'UI Settings'],
            ['#settingsInterfaceTitle', 'settings.interface', 'Interface'],
            ['#settingsInterfaceStatus', 'settings.active', 'actif'],
            ['#settingsScaleLabel', 'settings.scale', 'Scale'],
            ['#settingsTextLabel', 'settings.text', 'Texte'],
            ['#settingsThemeLabel', 'settings.theme', 'Theme'],
            ['#settingsLocaleLabel', 'settings.language', 'Language'],
            ['#settingsLocaleHint', 'settings.languageHint', 'configured in shared/config.lua'],
            ['#settingsWindowsTitle', 'settings.windows', 'Fenêtres'],
            ['#settingsWindowsStatus', 'settings.persistent', 'persistant'],
            ['#compactModeLabel', 'settings.compact', 'Compact mode'],
            ['#dockVisibleLabel', 'settings.dock', 'Dock flottant rapide'],
            ['#settingsStatus', 'settings.note', 'Le dashboard peut se fermer sans fermer les fenêtres flottantes.'],
            ['#resetUiBtn', 'settings.reset', 'Reset UI'],
            ['#saveUiBtn', 'settings.save', 'Sauvegarder maintenant'],
            ['#dockTitle', 'dock.title', 'Outils rapides'],
            ['#dockSectionTitle', 'dock.title', 'Outils rapides'],
            ['#dockLiveLabel', 'dock.live', 'live'],
            ['#dockRefreshTitle', 'app.refresh', 'Refresh'],
            ['#dockRefreshHint', 'dock.refreshHint', 'Mettre à jour les données'],
            ['#dockInspectorTitle', 'actions.inspect', 'Inspect'],
            ['#dockSpectateTitle', 'actions.spectate', 'Spectate'],
            ['#dockSpectateHint', 'dock.spectateHint', 'Suivre la cible'],
            ['#dockGotoTitle', 'actions.goto', 'Goto'],
            ['#dockGotoHint', 'dock.gotoHint', 'Aller sur la cible'],
            ['#dockNoclipTitle', 'actions.noclip', 'NoClip'],
            ['#dockSettingsTitle', 'settings.title', 'Paramètres UI'],
            ['#dockSettingsHint', 'dock.settingsHint', 'Échelle, thème et fenêtres'],
            ['#dockWindowsTitle', 'settings.windows', 'Fenêtres'],
            ['#dockRuntimeLabel', 'dock.runtime', 'runtime'],
            ['#dockCloseDashboardBtn', 'dock.closeDashboard', 'Fermer dashboard'],
            ['#dockHideBtn', 'dock.hideDock', 'Masquer dock'],
            ['#actionDialogTitle', 'dialogs.staffAction', 'Action staff'],
            ['#actionDialogSubtitle', 'dialogs.target', 'Cible'],
            ['#actionDialogReasonLabel', 'dialogs.reason', 'Motif'],
            ['#actionDialogHint', 'dialogs.actionHint', 'Cette action sera envoyée au backend zVS.'],
            ['#actionDialogCancel', 'actions.cancel', 'Annuler'],
            ['#actionDialogConfirm', 'actions.validate', 'Valider'],
            ['#noticeClose', 'dialogs.understood', 'J’ai compris'],
            ['#screenshotTitle', 'dialogs.screenshotReceived', 'Capture reçue'],
            ['#screenshotSubtitle', 'dialogs.evidence', 'Evidence'],
            ['#screenshotMeta', 'dialogs.screenshotAvailable', 'Capture disponible.'],
            ['#screenshotClose', 'app.close', 'Fermer'],
        ];
        textMap.forEach(([selector, key, fallback]) => $$(selector).forEach(el => setTextIfChanged(el, L(key, fallback))));
        const attrMap = [
            ['#playerSearch', 'placeholder', 'main.search', 'Nom, ID, ping...'],
            ['#noteInput', 'placeholder', 'main.notePlaceholder', 'Note staff sur le joueur sélectionné...'],
            ['#actionReason', 'placeholder', 'dialogs.reasonPlaceholder', 'Indique un motif clair et court...'],
        ];
        attrMap.forEach(([selector, attr, key, fallback]) => setAttrIfChanged($(selector), attr, L(key, fallback)));
        const filterOptions = {
            all: L('main.all', 'Tous'), risk: L('main.risk', 'Risk'), vehicle: L('main.vehicle', 'Véhicule'), protected: L('main.protected', 'Protégés')
        };
        $$('#playerRiskFilter option').forEach(opt => { if (filterOptions[opt.value]) setTextIfChanged(opt, filterOptions[opt.value]); });
        const inspectorLabels = ['name','id','health','armor','speed','ping','risk','position','vehicle','protection'];
        inspectorLabels.forEach(key => $(`[data-inspector-label="${key}"]`) && setTextIfChanged($(`[data-inspector-label="${key}"]`), L(`inspector.${key}`, key)));
        setTextIfChanged($('#settingsLocaleValue'), state.locale.current.toUpperCase());
        renderActionLabels();
    }

    function renderActionLabels() {
        const actionLabels = {
            inspect: L('actions.inspect', 'Inspect'), spectate: L('actions.spectate', 'Spectate'), goto: L('actions.goto', 'Goto'), bring: L('actions.bring', 'Bring'),
            freeze: L('actions.freeze', 'Freeze'), heal: L('actions.heal', 'Heal'), screenshot: L('actions.capture', 'Capture'), warn: L('actions.warn', 'Warn'), kick: L('actions.kick', 'Kick'), ban: L('actions.ban', 'Ban')
        };
        $$('[data-player-action]').forEach(btn => {
            const action = btn.dataset.playerAction;
            if (btn.closest('.zvs-dock-action')) return;
            if (action === 'inspect' && btn.closest('.zvs-inspector')) setTextIfChanged(btn, L('actions.pin', 'Pin'));
            else if (actionLabels[action]) setTextIfChanged(btn, actionLabels[action]);
        });
        setTextIfChanged($('#settingsBtn'), L('actions.ui', 'UI'));
    }

    function post(action, payload = {}) {
        return fetch(`https://${resourceName}/${action}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(payload),
        }).catch(() => null);
    }

    function setTextIfChanged(el, value) {
        if (!el) return;
        const text = sanitizeText(value);
        if (el.textContent !== text) el.textContent = text;
    }

    function setClassIfChanged(el, className, enabled) {
        if (!el) return;
        const has = el.classList.contains(className);
        if (has !== enabled) el.classList.toggle(className, enabled);
    }

    function initInspectorRefs() {
        if (state.refs.inspector.ready) return;
        state.refs.inspector.title = $('#inspectorTitle');
        $$('[data-inspector-value]').forEach(el => {
            state.refs.inspector[el.dataset.inspectorValue] = el;
        });
        state.refs.inspector.ready = true;
    }

    function normalizeSettings(incoming) {
        const normalized = structuredCloneSafe(DEFAULT_SETTINGS);
        deepMerge(normalized, incoming && typeof incoming === 'object' ? incoming : {});
        normalized.ui = normalized.ui || {};
        normalized.ui.scale = clamp(normalized.ui.scale, 0.75, 1.35, 1);
        normalized.ui.textScale = clamp(normalized.ui.textScale, 0.85, 1.25, 1);
        normalized.ui.theme = typeof normalized.ui.theme === 'string' && normalized.ui.theme ? normalized.ui.theme : 'visionary_dark';
        normalized.ui.compactMode = normalized.ui.compactMode !== false;
        normalized.tabs = normalized.tabs || {};
        normalized.tabs.main = normalized.tabs.main || normalized.lastTab || 'overview';
        normalized.tabs.right = normalized.tabs.right || 'alerts';
        normalized.windows = normalized.windows || {};
        for (const [id, fallback] of Object.entries(DEFAULT_SETTINGS.windows)) {
            normalized.windows[id] = normalizeWindowSettings(normalized.windows[id], fallback, id);
        }
        normalized.windows.main.visible = true;
        normalized.windows.main.minimized = false;
        // Floating window visibility is runtime-only. JSON may keep geometry, but must never hide/show them.
        for (const floatingId of ['playerInspector', 'settings', 'adminDock', 'spectateInfo']) {
            if (normalized.windows[floatingId]) normalized.windows[floatingId].visible = false;
        }
        return normalized;
    }

    function normalizeWindowSettings(input, fallback, id) {
        const base = { ...fallback, ...(input && typeof input === 'object' ? input : {}) };
        const min = windowMinimums(id);
        base.width = Math.round(clamp(base.width, min.width, Math.min(2200, window.innerWidth || 1920), fallback.width));
        base.height = Math.round(clamp(base.height, min.height, Math.min(1600, window.innerHeight || 1080), fallback.height));
        base.x = Math.round(clamp(base.x, -200, 7680, fallback.x));
        base.y = Math.round(clamp(base.y, -200, 4320, fallback.y));
        base.opacity = clamp(base.opacity, 0.45, 1, fallback.opacity);
        base.locked = base.locked === true;
        base.minimized = base.minimized === true;
        base.maximized = base.maximized === true;
        base.visible = base.visible === true;
        return keepWindowOnScreen(base, id);
    }

    function windowMinimums(id) {
        if (id === 'main') return { width: 760, height: 460 };
        if (id === 'playerInspector') return { width: 340, height: 230 };
        if (id === 'spectateInfo') return { width: 320, height: 142 };
        if (id === 'settings') return { width: 430, height: 320 };
        if (id === 'adminDock') return { width: 300, height: 330 };
        return { width: 300, height: 180 };
    }

    function keepWindowOnScreen(win, id) {
        const margin = 8;
        const viewport = getLogicalViewport();
        const vw = viewport.width;
        const vh = viewport.height;
        const min = windowMinimums(id);
        win.width = Math.min(Math.max(win.width, min.width), Math.max(min.width, vw - margin * 2));
        win.height = Math.min(Math.max(win.height, min.height), Math.max(min.height, vh - margin * 2));
        if (win.x + 80 > vw || win.x + win.width < 80 || win.x < -40) win.x = Math.max(margin, Math.min(DEFAULT_SETTINGS.windows[id]?.x ?? 80, vw - win.width - margin));
        if (win.y + 32 > vh || win.y + win.height < 60 || win.y < -40) win.y = Math.max(margin, Math.min(DEFAULT_SETTINGS.windows[id]?.y ?? 70, vh - win.height - margin));
        win.x = Math.round(Math.min(Math.max(win.x, margin), Math.max(margin, vw - Math.min(80, win.width))));
        win.y = Math.round(Math.min(Math.max(win.y, margin), Math.max(margin, vh - 34)));
        return win;
    }

    const WindowManager = {
        activeDrag: null,
        activeResize: null,
        init() {
            document.addEventListener('pointermove', (event) => this.onPointerMove(event));
            document.addEventListener('pointerup', () => this.endPointerAction());
            $$('[data-drag-handle]').forEach(handle => {
                handle.addEventListener('pointerdown', (event) => this.startDrag(event, handle.closest('[data-window-id]')));
            });
            $$('[data-resize-handle]').forEach(handle => {
                handle.addEventListener('pointerdown', (event) => this.startResize(event, handle.closest('[data-window-id]')));
            });
            $$('[data-window-lock]').forEach(btn => btn.addEventListener('click', () => this.toggleLock(btn.dataset.windowLock)));
            $$('[data-window-minimize]').forEach(btn => btn.addEventListener('click', () => this.toggleMinimize(btn.dataset.windowMinimize)));
            $$('[data-window-maximize]').forEach(btn => btn.addEventListener('click', () => this.toggleMaximize(btn.dataset.windowMaximize)));
            $$('[data-window-hide]').forEach(btn => btn.addEventListener('click', () => this.hide(btn.dataset.windowHide)));
            $$('[data-window-opacity]').forEach(input => {
                input.addEventListener('input', () => this.setOpacity(input.dataset.windowOpacity, Number(input.value) / 100, true));
                input.addEventListener('change', () => markSettingsDirty(true));
            });
            window.addEventListener('resize', () => {
                Object.keys(state.settings.windows).forEach(id => {
                    state.settings.windows[id] = keepWindowOnScreen(state.settings.windows[id], id);
                });
                this.applyAll();
                markSettingsDirty();
            });
        },
        element(id) { return $(`[data-window-id="${cssEscape(id)}"]`); },
        get(id) {
            state.settings.windows[id] ||= normalizeWindowSettings({}, DEFAULT_SETTINGS.windows[id] || DEFAULT_SETTINGS.windows.settings, id);
            return state.settings.windows[id];
        },
        applyAll() {
            for (const id of Object.keys(DEFAULT_SETTINGS.windows)) this.apply(id);
        },
        apply(id) {
            const el = this.element(id);
            if (!el) return;
            const win = keepWindowOnScreen(this.get(id), id);
            const runtime = getRuntime();
            const features = runtime.features || {};
            let effectiveVisible = false;
            if (id === 'main') {
                effectiveVisible = state.open === true;
            } else if (id === 'adminDock') {
                effectiveVisible = features.adminDock === true
                    && state.settings.dock?.enabled === true
                    && state.floating.adminDock === true;
            } else if (id === 'playerInspector') {
                effectiveVisible = !!state.selectedPlayer
                    && state.floating.playerInspector === true
                    && state.inspector.manualClosed !== true;
            } else if (id === 'settings') {
                effectiveVisible = state.floating.settings === true;
            } else if (id === 'spectateInfo') {
                effectiveVisible = state.spectate.active === true && state.spectate.dismissed !== true;
            }
            const nextStyle = {
                left: `${win.x}px`,
                top: `${win.y}px`,
                width: `${win.width}px`,
                height: `${win.height}px`,
                opacity: String(win.opacity),
            };
            for (const [key, value] of Object.entries(nextStyle)) {
                if (el.style[key] !== value) el.style[key] = value;
            }
            setClassIfChanged(el, 'is-hidden', !effectiveVisible);
            setClassIfChanged(el, 'is-locked', win.locked === true);
            setClassIfChanged(el, 'is-minimized', win.minimized === true);
            setClassIfChanged(el, 'is-maximized', win.maximized === true);
            const input = $(`[data-window-opacity="${cssEscape(id)}"]`);
            if (input && document.activeElement !== input) input.value = String(Math.round(win.opacity * 100));
            const lockBtn = $(`[data-window-lock="${cssEscape(id)}"]`);
            if (lockBtn) lockBtn.textContent = win.locked ? '◆' : '◇';
        },
        startDrag(event, el) {
            if (!el || event.button !== 0) return;
            if (event.target.closest('button,input,select,textarea,label')) return;
            const id = el.dataset.windowId;
            const win = this.get(id);
            if (win.locked || win.maximized) return;
            event.preventDefault();
            el.setPointerCapture?.(event.pointerId);
            this.activeDrag = { id, startX: event.clientX, startY: event.clientY, x: win.x, y: win.y };
            el.classList.add('is-dragging');
        },
        startResize(event, el) {
            if (!el || event.button !== 0) return;
            const id = el.dataset.windowId;
            const win = this.get(id);
            if (win.locked || win.maximized || win.minimized) return;
            event.preventDefault();
            el.setPointerCapture?.(event.pointerId);
            this.activeResize = { id, startX: event.clientX, startY: event.clientY, width: win.width, height: win.height };
            el.classList.add('is-resizing');
        },
        onPointerMove(event) {
            if (this.activeDrag) {
                const data = this.activeDrag;
                const win = this.get(data.id);
                const scale = getUiScale();
                win.x = Math.round(data.x + (event.clientX - data.startX) / scale);
                win.y = Math.round(data.y + (event.clientY - data.startY) / scale);
                keepWindowOnScreen(win, data.id);
                this.apply(data.id);
            }
            if (this.activeResize) {
                const data = this.activeResize;
                const win = this.get(data.id);
                const min = windowMinimums(data.id);
                const scale = getUiScale();
                const viewport = getLogicalViewport();
                win.width = Math.round(clamp(data.width + (event.clientX - data.startX) / scale, min.width, viewport.width - win.x - 8, data.width));
                win.height = Math.round(clamp(data.height + (event.clientY - data.startY) / scale, min.height, viewport.height - win.y - 8, data.height));
                this.apply(data.id);
            }
        },
        endPointerAction() {
            if (this.activeDrag || this.activeResize) {
                const movedId = this.activeDrag?.id || this.activeResize?.id;
                if (movedId === 'playerInspector') state.inspector.userPlaced = true;
                $$('.is-dragging,.is-resizing').forEach(el => el.classList.remove('is-dragging', 'is-resizing'));
                this.activeDrag = null;
                this.activeResize = null;
                markSettingsDirty();
            }
        },
        toggleLock(id) { const win = this.get(id); win.locked = !win.locked; this.apply(id); markSettingsDirty(); },
        toggleMinimize(id) { const win = this.get(id); if (id === 'main') win.visible = true; win.minimized = !win.minimized; this.apply(id); if (id !== 'playerInspector') markSettingsDirty(); },
        toggleMaximize(id) {
            const win = this.get(id);
            if (win.maximized && win.restore) {
                Object.assign(win, win.restore);
                win.restore = undefined;
                win.maximized = false;
            } else {
                win.restore = { x: win.x, y: win.y, width: win.width, height: win.height };
                const viewport = getLogicalViewport();
                win.x = 12; win.y = 12; win.width = Math.max(760, viewport.width - 24); win.height = Math.max(420, viewport.height - 24);
                win.maximized = true;
                win.minimized = false;
            }
            this.apply(id);
            markSettingsDirty();
        },
        hide(id) {
            if (id === 'spectateInfo') {
                state.spectate.dismissed = true;
                post('setSpectatePanelVisible', { visible: false });
                this.apply(id);
                syncFloatingLayerFocus();
                return;
            }
            if (id === 'playerInspector') {
                state.inspector.manualClosed = true;
                state.floating.playerInspector = false;
                this.apply(id);
                syncRootVisibility();
                return;
            }
            if (id === 'settings') {
                state.floating.settings = false;
                this.apply(id);
                syncRootVisibility();
                return;
            }
            if (id === 'adminDock') {
                state.floating.adminDock = false;
                this.apply(id);
                syncRootVisibility();
                return;
            }
            const win = this.get(id);
            win.visible = false;
            this.apply(id);
            markSettingsDirty(true);
        },
        show(id) {
            if (id === 'playerInspector') {
                state.inspector.manualClosed = false;
                state.floating.playerInspector = true;
                const win = this.get(id);
                win.minimized = false;
                keepWindowOnScreen(win, id);
                this.apply(id);
                syncRootVisibility();
                return;
            }
            if (id === 'settings') {
                state.floating.settings = true;
                const win = this.get(id);
                win.minimized = false;
                keepWindowOnScreen(win, id);
                this.apply(id);
                syncRootVisibility();
                return;
            }
            if (id === 'adminDock') {
                state.floating.adminDock = true;
                const win = this.get(id);
                win.minimized = false;
                keepWindowOnScreen(win, id);
                this.apply(id);
                syncRootVisibility();
                return;
            }
            const win = this.get(id);
            win.visible = true;
            win.minimized = false;
            keepWindowOnScreen(win, id);
            this.apply(id);
            markSettingsDirty();
        },
        setOpacity(id, value, applyOnly = false) {
            const win = this.get(id);
            win.opacity = clamp(value, 0.45, 1, DEFAULT_SETTINGS.windows[id]?.opacity ?? 0.94);
            this.apply(id);
            if (!applyOnly) markSettingsDirty();
        },
    };

    function getRuntime() {
        const raw = state.runtime?.runtimeConfig || state.runtime || state.data?.runtimeConfig || {};
        const features = raw.features || {};
        return {
            ...raw,
            features: {
                adminPreview: raw.AdminPreview?.Enabled === true || features.adminPreview === true,
                livePreview: false,
                preview3d: false,
                adminDock: raw.AdminDock?.Enabled !== false && features.adminDock !== false,
                staffNoClip: raw.StaffNoClip?.Enabled === true || features.staffNoClip === true,
                externalNoClip: raw.StaffNoClip?.UseExternalNoClip === true || features.externalNoClip === true,
                spectateCameraOnly: raw.SpectateCameraOnly !== false && features.spectateCameraOnly !== false,
                spectateNuiOnly: features.spectateNuiOnly === true || raw.SpectateNuiOnly === true,
                discordLogging: raw.DiscordLogging?.Enabled === true || features.discordLogging === true,
                resourceGuard: features.resourceGuard === true,
                monitoring: features.monitoring === true,
                heartbeat: features.heartbeat === true,
            },
            permissions: raw.permissions || {},
            profile: raw.profilePerformance || raw.performanceProfile || 'production',
        };
    }

    function buildSettingsPayload() {
        const payload = structuredCloneSafe(state.settings);
        payload.tabs = { main: state.mainTab, right: state.rightTab };
        payload.lastTab = state.mainTab;

        // Floating window visibility is runtime-only. We persist geometry/opacity/lock,
        // but a stale JSON save must never close an independent floating window.
        for (const id of ['playerInspector', 'settings', 'spectateInfo', 'adminDock']) {
            if (payload.windows?.[id]) delete payload.windows[id].visible;
        }
        return payload;
    }

    function markSettingsDirty(immediate = false) {
        if (state.suppressSave) return;
        state.settingsDirty = true;
        if (state.saveTimer) clearTimeout(state.saveTimer);
        state.saveTimer = setTimeout(() => saveSettings(immediate), immediate ? 60 : 900);
    }

    function saveSettings(immediate = false) {
        if (!state.settingsDirty) return;
        state.settingsDirty = false;
        if (state.saveTimer) clearTimeout(state.saveTimer);
        state.saveTimer = null;
        const payload = buildSettingsPayload();
        post('saveAdminSettings', { settings: payload, immediate: immediate === true });
    }

    function captureRuntimeWindowVisibility() {
        return {
            playerInspector: state.floating.playerInspector === true,
            inspectorManualClosed: state.inspector.manualClosed === true,
            settings: state.floating.settings === true,
            adminDock: state.floating.adminDock === true,
            spectateInfo: state.spectate.active === true && state.spectate.dismissed !== true,
        };
    }

    function restoreRuntimeWindowVisibility(visibility) {
        if (!visibility) return;
        state.floating.playerInspector = visibility.playerInspector === true;
        state.inspector.manualClosed = visibility.inspectorManualClosed === true;
        state.floating.settings = visibility.settings === true;
        state.floating.adminDock = visibility.adminDock === true;
        if (state.settings.windows?.spectateInfo) state.settings.windows.spectateInfo.visible = false;
    }

    function hasFloatingWindows() {
        if (state.dialog.active === true || state.notice.active === true || state.screenshot.active === true) return true;
        const settingsVisible = state.floating.settings === true;
        const dockVisible = state.settings.dock?.enabled === true && state.floating.adminDock === true;
        const inspectorVisible = !!state.selectedPlayer && state.floating.playerInspector === true && state.inspector.manualClosed !== true;
        const spectateVisible = state.spectate.active === true && state.spectate.dismissed !== true;
        return settingsVisible || dockVisible || inspectorVisible || spectateVisible;
    }

    function floatingNeedsInteractiveFocus() {
        // Floating windows are persistent HUD-like windows by default.
        // They must not keep the cursor/focus after closing the dashboard, otherwise
        // the admin cannot cleanly return to gameplay. Only blocking dialogs/notices
        // capture focus outside of the dashboard.
        return state.open !== true && (state.dialog.active === true || state.notice.active === true || state.screenshot.active === true);
    }

    function syncFloatingLayerFocus(force = false) {
        const visible = state.pauseSuspended !== true && hasFloatingWindows();
        const interactive = visible && floatingNeedsInteractiveFocus();
        const key = `${visible ? 1 : 0}:${interactive ? 1 : 0}`;
        if (!force && state.floatingFocusActive === key) return;
        state.floatingFocusActive = key;
        post('setFloatingLayerVisible', { visible, interactive });
    }

    function syncRootVisibility() {
        const hidden = !(state.open === true || hasFloatingWindows());
        document.documentElement.classList.toggle('nui-closed', hidden);
        document.body.classList.toggle('nui-closed', hidden);
        app.classList.toggle('is-hidden', hidden);
        app.setAttribute('aria-hidden', hidden.toString());
        if (!hidden) startAutoRefresh(); else stopAutoRefresh();
        syncFloatingLayerFocus();
    }

    function setOpen(open) {
        state.open = open === true;
        if (state.open) {
            state.settings.windows.main.visible = true;
            state.settings.windows.main.minimized = false;
        }
        syncRootVisibility();
        if (typeof WindowManager !== 'undefined') WindowManager.applyAll();
    }

    function applyIncomingState(incoming) {
        if (!incoming || typeof incoming !== 'object') return;
        // Server updates may be partial. Never wipe players/feeds with a partial packet,
        // otherwise floating windows lose their selected player and disappear.
        const merged = { ...state.data, ...incoming };
        for (const key of ['players', 'suspicious', 'bans', 'damage', 'notes']) {
            if (!Object.prototype.hasOwnProperty.call(incoming, key) && Array.isArray(state.data?.[key])) {
                merged[key] = state.data[key];
            }
        }
        state.data = merged;
        state.runtime = incoming.runtimeConfig || state.runtime || {};
        if (incoming.runtimeConfig) applyRuntimeLocalization(state.runtime);
    }

    function openPanel(payload) {
        const newState = payload?.state || payload || {};
        const runtimeVisibility = captureRuntimeWindowVisibility();
        applyIncomingState(newState);
        state.settings = normalizeSettings(newState.adminSettings || state.settings);
        restoreRuntimeWindowVisibility(runtimeVisibility);
        state.mainTab = state.settings.tabs?.main || state.mainTab || 'overview';
        state.rightTab = state.settings.tabs?.right || state.rightTab || 'alerts';
        state.settings.windows.main.visible = true;
        setOpen(true);
        applyUiSettings();
        selectStillValidPlayer();
        scheduleRender();
        WindowManager.applyAll();
        post('getRuntimeConfig');
    }

    function closePanel() {
        saveSettings(true);
        setTextInputActive(false);
        setOpen(false);
        state.settings.windows.main.visible = true;
        post('closeDashboard', { floatingVisible: hasFloatingWindows(), interactive: false });
    }

    function closeDashboardFromBind() {
        // External keymapping/command close: only hide the main dashboard.
        // Runtime floating windows, tooltips, screenshot dialogs and notices stay alive.
        saveSettings(false);
        setTextInputActive(false);
        setOpen(false);
        state.settings.windows.main.visible = true;
        WindowManager.applyAll();
        syncRootVisibility();
        post('closeDashboard', { floatingVisible: hasFloatingWindows(), interactive: floatingNeedsInteractiveFocus() });
    }

    function toggleDashboardFromBind() {
        if (state.open === true) {
            closeDashboardFromBind();
            return;
        }
        setTextInputActive(false);
        post('requestOpen');
    }

    function hardCloseFromClient() {
        saveSettings(true);
        setTextInputActive(false);
        setOpen(false);
        post('setFloatingLayerVisible', { visible: hasFloatingWindows(), interactive: false });
    }

    function startAutoRefresh() {
        stopAutoRefresh();
        state.autoRefreshTimer = setInterval(() => {
            const floating = hasFloatingWindows();
            if (!state.open && !floating) return;
            const main = state.settings.windows.main;
            if (state.open && main?.minimized && !floating) return;
            if (state.open || state.floating.playerInspector === true || state.spectate.active === true) post('requestRefresh');
        }, 8000);
    }

    function stopAutoRefresh() {
        if (state.autoRefreshTimer) clearInterval(state.autoRefreshTimer);
        state.autoRefreshTimer = null;
    }

    function applyUiSettings() {
        const ui = state.settings.ui || DEFAULT_SETTINGS.ui;
        const scale = clamp(ui.scale, 0.75, 1.35, 1);
        const textScale = clamp(ui.textScale, 0.85, 1.25, 1);
        app.dataset.theme = ui.theme || 'visionary_dark';
        for (const node of [document.documentElement, document.body, app]) {
            node.style.setProperty('--zvs-scale', String(scale));
            node.style.setProperty('--zvs-text-scale', String(textScale));
        }
        app.style.transform = `scale(${scale})`;
        app.style.width = `${100 / scale}%`;
        app.style.height = `${100 / scale}%`;
        app.classList.toggle('compact-off', ui.compactMode === false);
        const scaleInput = $('#uiScale');
        if (scaleInput && document.activeElement !== scaleInput) scaleInput.value = String(Math.round(scale * 100));
        setTextIfChanged($('#uiScaleValue'), `${Math.round(scale * 100)}%`);
        const textScaleInput = $('#uiTextScale');
        if (textScaleInput && document.activeElement !== textScaleInput) textScaleInput.value = String(Math.round(textScale * 100));
        setTextIfChanged($('#uiTextScaleValue'), `${Math.round(textScale * 100)}%`);
        $('#compactMode').checked = ui.compactMode !== false;
        $('#themeSelect').value = ui.theme || 'visionary_dark';
        $('#dockVisible').checked = state.settings.dock?.enabled === true && state.floating.adminDock === true;
        applyLocaleTexts();
        WindowManager.applyAll();
        syncRootVisibility();
    }

    function players() { return Array.isArray(state.data.players) ? state.data.players : []; }
    function suspicious() { return Array.isArray(state.data.suspicious) ? state.data.suspicious : []; }
    function bans() { return Array.isArray(state.data.bans) ? state.data.bans : []; }
    function damage() { return Array.isArray(state.data.damage) ? state.data.damage : []; }
    function notes() { return Array.isArray(state.data.notes) ? state.data.notes : []; }

    function scheduleRender() {
        if (state.renderQueued) return;
        state.renderQueued = true;
        requestAnimationFrame(() => {
            state.renderQueued = false;
            if (state.pauseSuspended === true || (!state.open && !hasFloatingWindows())) return;
            renderAll();
        });
    }

    function selectStillValidPlayer() {
        const list = players();
        const previousId = state.selectedId;
        if (!list.length) {
            // Keep the last selected snapshot on transient/partial refreshes.
            return;
        }
        if (state.selectedId && list.some(p => Number(p.id) === Number(state.selectedId))) {
            state.selectedPlayer = list.find(p => Number(p.id) === Number(state.selectedId));
        } else {
            state.selectedId = list[0]?.id ?? null;
            state.selectedPlayer = list[0] ?? null;
        }
        if (state.selectedPlayer && !state.inspector.manualClosed && (previousId == null || state.floating.playerInspector === true || state.open === true)) {
            state.floating.playerInspector = true;
        }
    }

    function renderAll() {
        renderStats();
        renderTabs();
        renderPlayers();
        renderSelected();
        renderFeeds();
        renderRisk();
        renderFeatures();
        renderActions();
        renderInspector();
        renderDialogs();
        WindowManager.applyAll();
    }

    function renderStats() {
        const list = players();
        const riskTop = state.data?.risk?.top || [];
        $('#statPlayers').textContent = list.length;
        $('#playerCount').textContent = list.length;
        $('#statRisk').textContent = riskTop.length || list.filter(p => riskScore(p) >= 35).length;
        $('#statBans').textContent = bans().filter(b => !b.expired).length;
        const runtime = getRuntime();
        $('#statRuntime').textContent = runtime.profile || 'prod';
        $('#runtimeSubtitle').textContent = runtime.profile || 'production_zerofootprint';
    }

    function riskScore(player) {
        return Number(player?.risk?.score ?? player?.riskScore ?? 0) || 0;
    }

    function riskClass(score) {
        if (score >= 70) return 'zvs-risk-high';
        if (score >= 35) return 'zvs-risk-mid';
        return 'zvs-risk-low';
    }

    function renderPlayers() {
        const root = $('#playerList');
        const query = $('#playerSearch').value.trim().toLowerCase();
        const filter = $('#playerRiskFilter').value;
        let list = players().filter(player => {
            const text = `${player.id} ${player.name} ${player.ping}`.toLowerCase();
            if (query && !text.includes(query)) return false;
            if (filter === 'risk' && riskScore(player) < 35) return false;
            if (filter === 'vehicle' && !player.inVehicle) return false;
            if (filter === 'protected' && !player.spawnProtection) return false;
            return true;
        });
        list.sort((a, b) => riskScore(b) - riskScore(a) || Number(a.id) - Number(b.id));
        root.innerHTML = '';
        if (!list.length) {
            root.innerHTML = `<div class="zvs-feed-item"><strong>${escapeHtml(L('main.noPlayers', 'Aucun joueur'))}</strong><p>${escapeHtml(L('main.noPlayersHint', 'Refresh manuel ou filtre trop strict.'))}</p></div>`;
            return;
        }
        for (const player of list) {
            const score = riskScore(player);
            const btn = document.createElement('button');
            btn.type = 'button';
            btn.className = `zvs-player ${Number(player.id) === Number(state.selectedId) ? 'is-active' : ''}`;
            btn.innerHTML = `
                <span class="zvs-player-id">#${sanitizeText(player.id)}</span>
                <span class="zvs-player-main">
                    <span class="zvs-player-name">${escapeHtml(player.name || 'Inconnu')}</span>
                    <span class="zvs-player-meta">${Number(player.ping) || 0}ms · ${player.inVehicle ? L('main.vehicleShort', 'veh') : L('main.pedShort', 'ped')}${player.spawnProtection ? ' · ' + L('main.protectedShort', 'protected') : ''}</span>
                </span>
                <span class="zvs-risk-pill ${riskClass(score)}">${Math.round(score)}</span>`;
            btn.addEventListener('click', () => selectPlayer(player.id));
            root.appendChild(btn);
        }
    }

    function applyInspectorDefaultPosition(force = false) {
        const win = WindowManager.get('playerInspector');
        const viewport = getLogicalViewport();
        const defaults = DEFAULT_SETTINGS.windows.playerInspector;
        const currentLooksDefaultish = !state.inspector.userPlaced
            || win.x < 20
            || win.y < 20
            || win.x + win.width > viewport.width - 4
            || win.y + 34 > viewport.height;
        if (!force && !currentLooksDefaultish) return;
        win.width = Math.max(320, Math.min(win.width || defaults.width, 360));
        win.height = Math.max(300, Math.min(win.height || defaults.height, 380));
        win.x = Math.max(12, viewport.width - win.width - 54);
        win.y = Math.max(54, Math.min(96, viewport.height - win.height - 12));
        win.locked = false;
        win.minimized = false;
        keepWindowOnScreen(win, 'playerInspector');
    }

    function selectPlayer(id) {
        const numericId = Number(id);
        const samePlayer = Number(state.selectedId) === numericId;
        state.selectedId = numericId;
        state.selectedPlayer = players().find(p => Number(p.id) === numericId) || state.selectedPlayer || null;

        if (samePlayer) {
            if (state.floating.playerInspector === true && state.inspector.manualClosed !== true) {
                WindowManager.hide('playerInspector');
            } else if (state.selectedPlayer) {
                state.inspector.manualClosed = false;
                state.floating.playerInspector = true;
                applyInspectorDefaultPosition(false);
                WindowManager.show('playerInspector');
            }
            scheduleRender();
            return;
        }

        state.inspector.manualClosed = false;
        state.inspector.snapshot = {};
        if (state.selectedPlayer) {
            state.floating.playerInspector = true;
            applyInspectorDefaultPosition(false);
            WindowManager.show('playerInspector');
        }
        scheduleRender();
    }

    function renderTabs() {
        $$('[data-tab]').forEach(btn => btn.classList.toggle('is-active', btn.dataset.tab === state.mainTab));
        $$('[data-tab-panel]').forEach(panel => panel.classList.toggle('is-active', panel.dataset.tabPanel === state.mainTab));
        $$('[data-right-tab]').forEach(btn => btn.classList.toggle('is-active', btn.dataset.rightTab === state.rightTab));
        $$('[data-right-panel]').forEach(panel => panel.classList.toggle('is-active', panel.dataset.rightPanel === state.rightTab));
    }

    function renderSelected() {
        const p = state.selectedPlayer;
        $('#selectedTitle').textContent = p ? `${p.name || L('inspector.title', 'Joueur')} · ID ${p.id}` : L('main.noSelection', 'Aucun joueur sélectionné');
        $('#selectedSubtitle').textContent = p ? formatCoords(p.coords) : L('main.selectPlayer', 'Sélectionne un joueur à gauche.');
        const score = riskScore(p);
        $('#decisionText').textContent = score >= 70 ? L('decision.review', 'Review now') : score >= 35 ? L('decision.watch', 'Watch') : L('decision.observe', 'Observe');
        $('#decisionDetails').textContent = p?.risk?.lastDetection ? `${L('decision.lastDetection', 'Dernière détection')} : ${p.risk.lastDetection}` : L('main.readOnly', 'UI read-only. Pas d’action punitive automatique.');
        $('#selectedMetrics').innerHTML = metricHtml('HP', p?.health ?? '—') + metricHtml(L('inspector.armor', 'Armure'), p?.armor ?? '—') + metricHtml(L('inspector.speed', 'Vitesse'), fmtNumber(p?.speed, 'km/h')) + metricHtml(L('inspector.ping', 'Ping'), fmtNumber(p?.ping, 'ms'));
        const timeline = $('#selectedTimeline');
        const id = Number(p?.id);
        const related = suspicious().filter(item => Number(item.src || item.target || item.player) === id).slice(0, 6);
        timeline.innerHTML = related.length ? related.map(feedHtml).join('') : `<div class="zvs-feed-item"><strong>${escapeHtml(L('main.timeline', 'Timeline'))}</strong><p>${escapeHtml(L('main.noRecentEvent', 'Aucun événement récent lié au joueur sélectionné.'))}</p></div>`;
    }

    function metricHtml(label, value) {
        return `<div class="zvs-metric"><span>${escapeHtml(label)}</span><strong>${escapeHtml(String(value))}</strong></div>`;
    }

    function renderFeeds() {
        $('#alertFeed').innerHTML = listOrEmpty(suspicious().slice(0, 22), 'Aucune alerte récente', feedHtml);
        $('#notesFeed').innerHTML = listOrEmpty(notes().slice(0, 18), 'Aucune note récente', feedHtml);
        $('#banList').innerHTML = listOrEmpty(bans().slice(0, 18), 'Aucun ban enregistré', banHtml);
        $('#damageFeed').innerHTML = listOrEmpty(damage().slice(0, 18), 'Aucun damage log récent', feedHtml);
    }

    function renderRisk() {
        const top = Array.isArray(state.data?.risk?.top) ? state.data.risk.top : [];
        $('#riskTopList').innerHTML = listOrEmpty(top, 'Aucun profil risque actif', item => {
            const score = Number(item.score ?? item.risk ?? 0) || 0;
            return `<div class="zvs-row"><div><strong>${escapeHtml(item.name || `ID ${item.id || item.src || '?'}`)}</strong><p>${escapeHtml(item.lastDetection || item.reason || 'profil risque')}</p></div><span class="zvs-risk-pill ${riskClass(score)}">${Math.round(score)}</span></div>`;
        });
        const approvals = Array.isArray(state.data?.risk?.approvals) ? state.data.risk.approvals : [];
        $('#approvalCount').textContent = approvals.length;
        $('#approvalList').innerHTML = listOrEmpty(approvals.slice(0, 10), 'Aucune approbation en attente', approvalHtml);
        const audit = Array.isArray(state.data?.risk?.audit) ? state.data.risk.audit : [];
        $('#auditCount').textContent = audit.length;
        $('#auditList').innerHTML = listOrEmpty(audit.slice(0, 24), 'Aucun audit récent', feedHtml);
    }

    function renderFeatures() {
        const runtime = getRuntime();
        const features = runtime.features || {};
        const matrix = [
            ['Preview renderer', false, 'off'],
            ['Ped clone / cam', false, 'removed'],
            ['Dock', features.adminDock && state.settings.dock?.enabled, features.adminDock ? 'optional' : 'backend off'],
            ['Staff NoClip', features.staffNoClip, features.externalNoClip ? 'external' : 'internal'],
            ['Spectate camera-only', features.spectateCameraOnly, 'admin ped untouched'],
            ['Discord logs', features.discordLogging, features.discordLogging ? 'online' : 'webhook off'],
            ['Heartbeat', features.heartbeat, features.heartbeat ? 'online' : 'prod off'],
            ['Resource guard', features.resourceGuard, features.resourceGuard ? 'online' : 'off'],
        ];
        $('#featureMatrix').innerHTML = matrix.map(([name, on, detail]) => `<div class="zvs-feature ${on ? '' : 'is-off'}"><div><strong>${escapeHtml(name)}</strong><p class="zvs-muted">${escapeHtml(detail)}</p></div><span class="zvs-risk-pill ${on ? 'zvs-risk-low' : ''}">${on ? 'ON' : 'OFF'}</span></div>`).join('');
        const defenses = state.data.defenses && typeof state.data.defenses === 'object' ? Object.entries(state.data.defenses) : [];
        $('#defenseList').innerHTML = defenses.length ? defenses.map(([key, value]) => `<div class="zvs-row"><div><strong>${escapeHtml(key)}</strong><p>${value?.label ? escapeHtml(value.label) : 'runtime backend'}</p></div><span class="zvs-risk-pill ${value?.enabled === false ? '' : 'zvs-risk-low'}">${value?.enabled === false ? 'OFF' : 'ON'}</span></div>`).join('') : `<div class="zvs-feed-item"><strong>Aucune donnée défense</strong><p>Le backend n’a pas renvoyé d’état spécifique.</p></div>`;
    }

    function renderActions() {
        const p = state.selectedPlayer;
        const runtime = getRuntime();
        const perms = runtime.permissions || {};
        $$('[data-player-action]').forEach(btn => {
            const action = btn.dataset.playerAction;
            let disabled = !p;
            if (action === 'spectate') disabled ||= perms.canSpectate === false;
            if (action === 'kick') disabled ||= perms.canKick === false;
            if (action === 'freeze') disabled ||= perms.canFreeze === false;
            if (action === 'goto' || action === 'bring') disabled ||= perms.canTeleport === false;
            if (action === 'ban') disabled ||= perms.canBan === false;
            btn.disabled = disabled;
        });
        const dockSelectionLabel = $('#dockSelectionLabel');
        if (dockSelectionLabel) dockSelectionLabel.textContent = p ? `${sanitizeText(p.name, L('inspector.title', 'Joueur'))} #${sanitizeText(p.id, '?')}` : L('dock.inspectorHint', 'Aucun joueur sélectionné');
        const noclipAvailable = runtime.features.staffNoClip === true;
        const noclipLabel = noclipAvailable
            ? (state.noclip.enabled ? `${L('actions.noclip', 'NoClip')}: ON ${state.noclip.speed ? Math.round(state.noclip.speed) + 'm/s' : ''}`.trim() : `${L('actions.noclip', 'NoClip')}: OFF`)
            : (runtime.features.externalNoClip ? `${L('actions.noclip', 'NoClip')}: external` : `${L('actions.noclip', 'NoClip')}: disabled`);
        $('#noclipBtn').textContent = noclipLabel;
        $('#noclipBtn').disabled = !noclipAvailable;
        $('#noclipBtn').classList.toggle('is-live', noclipAvailable && state.noclip.enabled === true);
        $('#dockNoclipBtn').disabled = !noclipAvailable;
        $('#dockNoclipBtn').title = noclipLabel;
        $('#dockNoclipHint').textContent = noclipLabel;
        $('#dockNoclipBtn').classList.toggle('is-live', noclipAvailable && state.noclip.enabled === true);
    }

    function renderInspector() {
        initInspectorRefs();
        const p = state.selectedPlayer;
        if (!p) {
            WindowManager.apply('playerInspector');
            return;
        }

        const snapshot = {
            title: `${p.name || 'Joueur'} #${p.id}`,
            name: p.name || 'Inconnu',
            id: p.id,
            health: p.health ?? '—',
            armor: p.armor ?? '—',
            speed: fmtNumber(p.speed, 'km/h'),
            ping: fmtNumber(p.ping, 'ms'),
            risk: Math.round(riskScore(p)),
            coords: formatCoords(p.coords),
            vehicle: p.inVehicle ? 'Oui' : 'Non',
            protection: p.spawnProtection ? 'Oui' : 'Non',
        };

        const refs = state.refs.inspector;
        for (const [key, value] of Object.entries(snapshot)) {
            if (state.inspector.snapshot[key] === value) continue;
            if (key === 'title') setTextIfChanged(refs.title, value);
            else setTextIfChanged(refs[key], value);
            state.inspector.snapshot[key] = value;
        }

        state.inspector.lastPlayerId = Number(p.id);
        WindowManager.apply('playerInspector');
    }

    function renderSpectate(payload) {
        const nextActive = payload?.active !== false && payload?.hide !== true;
        const previousTarget = state.spectate.target;
        const wasActive = state.spectate.active === true;
        state.spectate = { ...(state.spectate || {}), ...(payload || {}), active: nextActive };
        if (!nextActive || (payload?.target && Number(payload.target) !== Number(previousTarget))) state.spectate.dismissed = false;
        const visible = state.spectate.active && state.spectate.dismissed !== true;
        state.settings.windows.spectateInfo.visible = visible;
        if (visible && (!wasActive || (payload?.target && Number(payload.target) !== Number(previousTarget)))) post('setSpectatePanelVisible', { visible: true });
        if (!visible && wasActive && !state.open) post('setSpectatePanelVisible', { visible: false });
        setOpen(state.open);
        const p = payload || {};
        $('#spectateBody').innerHTML = state.spectate.active ? [
            ['Cible', `${p.name || 'Joueur'} #${p.target || state.selectedId || '?'}`],
            ['Mode', p.mode || 'POV'],
            ['Flux', p.live ? 'LIVE' : (p.status || 'STALE')],
            ['Distance', fmtNumber(p.distance, 'm')],
            ['HP', p.health ?? '—'],
            ['Armure', p.armor ?? '—'],
            ['Vitesse', fmtNumber(p.speed, 'km/h')],
            ['Activité', p.activity || (p.inVehicle ? 'vehicle' : 'ped')],
        ].map(([label, value]) => `<div class="zvs-kv"><span>${escapeHtml(label)}</span><strong>${escapeHtml(sanitizeText(value))}</strong></div>`).join('') : 'Spectate inactif';
        WindowManager.apply('spectateInfo');
    }

    function listOrEmpty(list, empty, mapper) {
        return Array.isArray(list) && list.length ? list.map(mapper).join('') : `<div class="zvs-feed-item"><strong>${escapeHtml(empty)}</strong><p>${escapeHtml(L('main.empty', 'Rien à afficher pour le moment.'))}</p></div>`;
    }

    function feedHtml(item) {
        item = item || {};
        const title = item.title || item.type || item.category || item.event || 'Événement';
        const msg = item.message || item.reason || item.details || item.description || item.name || '—';
        const extra = item.createdAt || item.ts || item.time || '';
        return `<div class="zvs-feed-item"><strong>${escapeHtml(title)}</strong><p>${escapeHtml(msg)}${extra ? ` · ${escapeHtml(formatTime(extra))}` : ''}</p></div>`;
    }

    function banHtml(item) {
        const expired = item.expired ? 'expiré' : 'actif';
        return `<div class="zvs-feed-item"><strong>${escapeHtml(item.name || item.id || 'Ban')}</strong><p>${escapeHtml(item.reason || 'Raison non définie')} · ${expired}</p></div>`;
    }

    function approvalHtml(item) {
        const id = escapeHtml(item.id || '?');
        return `<div class="zvs-feed-item"><strong>${escapeHtml(item.title || item.action || `Approval ${id}`)}</strong><p>${escapeHtml(item.reason || item.message || 'Validation staff requise')}</p><div class="zvs-inline-actions"><button class="zvs-btn zvs-btn-primary" data-approval="yes" data-approval-id="${id}">Approuver</button><button class="zvs-btn zvs-danger-soft" data-approval="no" data-approval-id="${id}">Refuser</button></div></div>`;
    }

    function fmtNumber(value, suffix = '') {
        const n = Number(value);
        if (!Number.isFinite(n)) return '—';
        return `${Math.round(n)}${suffix ? ` ${suffix}` : ''}`;
    }

    function formatCoords(coords) {
        if (!coords || typeof coords !== 'object') return 'Position inconnue';
        return `${Number(coords.x || 0).toFixed(1)}, ${Number(coords.y || 0).toFixed(1)}, ${Number(coords.z || 0).toFixed(1)}`;
    }

    function formatTime(value) {
        const n = Number(value);
        if (!Number.isFinite(n)) return String(value);
        const ms = n > 10_000_000_000 ? n : n * 1000;
        try { return new Date(ms).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }); } catch (_) { return String(value); }
    }

    function escapeHtml(value) {
        return sanitizeText(value, '').replace(/[&<>'"]/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#039;', '"': '&quot;' }[char]));
    }

    function actionConfig(action, targetName) {
        const name = targetName || 'Joueur';
        if (action === 'warn') {
            return {
                title: 'Avertissement staff',
                subtitle: name,
                label: 'Message envoyé au joueur',
                defaultText: L('forms.warn', 'Comportement suspect détecté.'),
                confirm: 'Envoyer',
                hint: 'Le joueur recevra une fenêtre NUI à fermer avec sa souris.',
                severity: 'warn',
            };
        }
        if (action === 'kick') {
            return {
                title: 'Exclure le joueur',
                subtitle: name,
                label: L('dialogs.kickReason', 'Motif du kick'),
                defaultText: L('forms.kick', 'Action staff.'),
                confirm: L('actions.kick', 'Kick'),
                hint: 'Le motif sera transmis au backend avant exclusion.',
                severity: 'danger',
            };
        }
        return {
            title: L('dialogs.banTitle', 'Bannir le joueur'),
            subtitle: name,
            label: L('dialogs.banReason', 'Motif du ban'),
            defaultText: L('forms.ban', 'Cheat / exploitation détectée.'),
            confirm: L('actions.ban', 'Ban'),
            hint: L('dialogs.actionHint', 'Vérifie le motif avant validation. Aucun prompt navigateur n’est utilisé.'),
            severity: 'danger',
        };
    }

    function openActionDialog(action, player) {
        if (!player) return;
        const targetName = `${player.name || 'Joueur'} #${player.id}`;
        const cfg = actionConfig(action, targetName);
        state.dialog = {
            active: true,
            action,
            target: Number(player.id),
            targetName,
            defaultText: cfg.defaultText,
            severity: cfg.severity,
        };
        syncRootVisibility();
        renderDialogs();
        requestAnimationFrame(() => {
            const input = $('#actionReason');
            if (input) {
                input.focus();
                input.select();
            }
        });
    }

    function closeActionDialog() {
        state.dialog.active = false;
        setTextInputActive(false);
        state.dialog.action = null;
        state.dialog.target = null;
        renderDialogs();
        syncRootVisibility();
    }

    function confirmActionDialog() {
        if (!state.dialog.active || !state.dialog.action || state.dialog.target == null) return;
        const input = $('#actionReason');
        const reason = (input?.value || '').trim();
        if (!reason) {
            toast(L('dialogs.reasonRequired', 'Motif requis.'));
            input?.focus();
            return;
        }
        const target = Number(state.dialog.target);
        const action = state.dialog.action;
        if (action === 'warn') post('warnPlayer', { target, reason, message: reason });
        if (action === 'kick') post('kickPlayer', { target, reason });
        if (action === 'ban') post('banPlayer', { target, reason });
        closeActionDialog();
    }

    function openNoticeDialog(data = {}) {
        state.notice = {
            active: true,
            title: sanitizeText(data.title, 'Visionary Shield'),
            subtitle: sanitizeText(data.subtitle || data.admin, 'Notification staff'),
            message: sanitizeText(data.message, 'Message administratif.'),
            severity: sanitizeText(data.severity, 'info'),
        };
        syncRootVisibility();
        renderDialogs();
        requestAnimationFrame(() => $('#noticeClose')?.focus());
    }

    function closeNoticeDialog() {
        state.notice.active = false;
        renderDialogs();
        syncRootVisibility();
        post('closeAdminNotice');
    }


    function openScreenshotDialog(data = {}) {
        const image = sanitizeText(data.image || data.uploadUrl || data.url, '');
        const targetName = sanitizeText(data.targetName || data.name || 'Joueur', 'Joueur');
        const reason = sanitizeText(data.reason || 'Capture staff', 'Capture staff');
        const uploadStatus = sanitizeText(data.uploadStatus || (data.uploadUrl ? 'ok' : 'local'), 'local');
        state.screenshot = {
            active: image !== '',
            image,
            title: L('dialogs.screenshotReceived', 'Capture reçue'),
            subtitle: `${targetName}${data.target ? ` #${data.target}` : ''}`,
            meta: uploadStatus === 'ok' ? `${reason} · ${L('dialogs.uploadAvailable', 'upload disponible')}` : `${reason} · ${L('dialogs.localCapture', 'capture locale')}`,
        };
        if (!image) {
            toast(L('dialogs.screenshotNoImage', 'Capture reçue, mais aucune image exploitable.'));
            return;
        }
        syncRootVisibility();
        renderDialogs();
        requestAnimationFrame(() => $('#screenshotClose')?.focus());
    }

    function closeScreenshotDialog() {
        state.screenshot.active = false;
        state.screenshot.image = '';
        renderDialogs();
        syncRootVisibility();
    }

    function renderDialogs() {
        const layer = $('#modalLayer');
        const actionDialog = $('#actionDialog');
        const noticeDialog = $('#noticeDialog');
        const screenshotDialog = $('#screenshotDialog');
        const showLayer = state.dialog.active === true || state.notice.active === true || state.screenshot.active === true;
        if (layer) {
            setClassIfChanged(layer, 'is-hidden', !showLayer);
            layer.setAttribute('aria-hidden', String(!showLayer));
        }
        if (actionDialog) {
            const cfg = actionConfig(state.dialog.action, state.dialog.targetName);
            setClassIfChanged(actionDialog, 'is-hidden', state.dialog.active !== true);
            actionDialog.dataset.severity = cfg.severity || 'info';
            setTextIfChanged($('#actionDialogTitle'), cfg.title);
            setTextIfChanged($('#actionDialogSubtitle'), cfg.subtitle);
            setTextIfChanged($('.zvs-modal-label', actionDialog), cfg.label || 'Motif');
            setTextIfChanged($('#actionDialogHint'), cfg.hint || 'Action staff.');
            setTextIfChanged($('#actionDialogConfirm'), cfg.confirm || 'Valider');
            const input = $('#actionReason');
            if (input && document.activeElement !== input && state.dialog.active === true && !input.value) input.value = cfg.defaultText || '';
        }
        if (noticeDialog) {
            setClassIfChanged(noticeDialog, 'is-hidden', state.notice.active !== true);
            noticeDialog.dataset.severity = state.notice.severity || 'info';
            setTextIfChanged($('#noticeTitle'), state.notice.title || 'Visionary Shield');
            setTextIfChanged($('#noticeSubtitle'), state.notice.subtitle || 'Notification staff');
            setTextIfChanged($('#noticeMessage'), state.notice.message || 'Message administratif.');
        }
        if (screenshotDialog) {
            setClassIfChanged(screenshotDialog, 'is-hidden', state.screenshot.active !== true);
            setTextIfChanged($('#screenshotTitle'), state.screenshot.title || 'Capture reçue');
            setTextIfChanged($('#screenshotSubtitle'), state.screenshot.subtitle || 'Evidence');
            setTextIfChanged($('#screenshotMeta'), state.screenshot.meta || 'Capture disponible.');
            const img = $('#screenshotImage');
            if (img && img.src !== state.screenshot.image) img.src = state.screenshot.image || '';
        }
    }

    function toast(message) {
        const root = $('#toastStack');
        const item = document.createElement('div');
        item.className = 'zvs-toast';
        item.textContent = message;
        root.appendChild(item);
        setTimeout(() => item.remove(), 2600);
    }

    function runPlayerAction(action) {
        const p = state.selectedPlayer;
        if (!p && action !== 'noclip') return;
        const target = p ? Number(p.id) : undefined;
        const name = p?.name || `ID ${target}`;
        switch (action) {
            case 'inspect': WindowManager.show('playerInspector'); break;
            case 'spectate': post('toggleSpectate', { target }); break;
            case 'goto': post('teleportGoto', { target }); break;
            case 'bring': post('teleportBring', { target }); break;
            case 'freeze': post('toggleFreeze', { target }); break;
            case 'heal': post('healPlayer', { target }); break;
            case 'screenshot': post('requestScreenshot', { target }); break;
            case 'warn': openActionDialog('warn', p); break;
            case 'kick': openActionDialog('kick', p); break;
            case 'ban': openActionDialog('ban', p); break;
        }
    }



    function isTextEditableElement(el) {
        if (!el) return false;
        if (el.isContentEditable) return true;
        const tag = el.tagName?.toLowerCase();
        if (tag === 'textarea' || tag === 'select') return true;
        if (tag !== 'input') return false;
        const type = (el.getAttribute('type') || 'text').toLowerCase();
        return !['button', 'checkbox', 'radio', 'range', 'submit', 'reset', 'file', 'color', 'image'].includes(type);
    }

    function setTextInputActive(active) {
        active = active === true;
        const canCapture = state.open === true || state.dialog.active === true || state.notice.active === true;
        const next = active && canCapture;
        if (state.textInputActive === next) return;
        state.textInputActive = next;
        post('setTextInputActive', { active: next });
    }

    function refreshTextInputActive() {
        setTextInputActive(isTextEditableElement(document.activeElement));
    }

    function setPauseSuspended(active) {
        active = active === true;
        if (state.pauseSuspended === active) return;
        state.pauseSuspended = active;
        if (active) {
            state.pauseSnapshot = {
                open: state.open === true,
                floating: structuredCloneSafe(state.floating),
                inspectorManualClosed: state.inspector.manualClosed === true,
                selectedId: state.selectedId,
            };
            WindowManager.endPointerAction();
        } else if (state.pauseSnapshot) {
            state.floating = { ...state.floating, ...state.pauseSnapshot.floating };
            state.inspector.manualClosed = state.pauseSnapshot.inspectorManualClosed === true;
            if (state.pauseSnapshot.selectedId != null) state.selectedId = state.pauseSnapshot.selectedId;
            if (state.selectedId != null) {
                state.selectedPlayer = players().find(p => Number(p.id) === Number(state.selectedId)) || state.selectedPlayer;
            }
            state.pauseSnapshot = null;
        }
        syncRootVisibility();
        WindowManager.applyAll();
        if (state.open || hasFloatingWindows()) scheduleRender();
    }

    function bindEvents() {
        WindowManager.init();
        $$('[data-close-panel]').forEach(btn => btn.addEventListener('click', closePanel));
        $$('[data-action="refresh"]').forEach(btn => btn.addEventListener('click', () => post('requestRefresh')));
        $('#settingsBtn').addEventListener('click', () => WindowManager.show('settings'));
        $('#dockSettingsBtn')?.addEventListener('click', () => WindowManager.show('settings'));
        $('#saveUiBtn').addEventListener('click', () => saveSettings(true));
        $('#resetUiBtn').addEventListener('click', () => post('resetAdminSettings'));
        $('#noclipBtn').addEventListener('click', () => post('toggleCloak'));
        $('#dockNoclipBtn').addEventListener('click', () => post('toggleCloak'));
        $('#actionDialogClose')?.addEventListener('click', closeActionDialog);
        $('#actionDialogCancel')?.addEventListener('click', closeActionDialog);
        $('#actionDialogConfirm')?.addEventListener('click', confirmActionDialog);
        $('#noticeClose')?.addEventListener('click', closeNoticeDialog);
        $('#screenshotClose')?.addEventListener('click', closeScreenshotDialog);
        $('#screenshotCloseTop')?.addEventListener('click', closeScreenshotDialog);
        $('#actionReason')?.addEventListener('keydown', event => {
            if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') {
                event.preventDefault();
                confirmActionDialog();
            }
        });
        $('#saveNoteBtn').addEventListener('click', () => {
            if (!state.selectedPlayer) return;
            const input = $('#noteInput');
            const note = input.value.trim();
            if (!note) return;
            post('recordNote', { target: state.selectedPlayer.id, note, message: note });
            input.value = '';
        });
        $('#playerSearch').addEventListener('input', renderPlayers);
        $('#playerRiskFilter').addEventListener('change', renderPlayers);
        $$('[data-tab]').forEach(btn => btn.addEventListener('click', () => { state.mainTab = btn.dataset.tab; state.settings.tabs ||= {}; state.settings.tabs.main = state.mainTab; renderTabs(); markSettingsDirty(); }));
        $$('[data-right-tab]').forEach(btn => btn.addEventListener('click', () => { state.rightTab = btn.dataset.rightTab; state.settings.tabs ||= {}; state.settings.tabs.right = state.rightTab; renderTabs(); markSettingsDirty(); }));
        $$('[data-player-action]').forEach(btn => btn.addEventListener('click', () => runPlayerAction(btn.dataset.playerAction)));
        $$('[data-spectate-action]').forEach(btn => btn.addEventListener('click', () => {
            const action = btn.dataset.spectateAction;
            if (action === 'exit') post('toggleSpectate', { target: state.spectate.target || state.selectedId, enabled: false });
            if (action === 'previous' || action === 'next') selectAdjacentPlayer(action === 'next' ? 1 : -1, true);
        }));
        document.addEventListener('click', event => {
            const approval = event.target.closest('[data-approval]');
            if (approval) post('resolveRiskApproval', { id: approval.dataset.approvalId, approved: approval.dataset.approval === 'yes' });
        });
        $('#uiScale').addEventListener('input', event => { state.settings.ui.scale = Number(event.target.value) / 100; applyUiSettings(); markSettingsDirty(); });
        $('#uiTextScale').addEventListener('input', event => { state.settings.ui.textScale = Number(event.target.value) / 100; applyUiSettings(); markSettingsDirty(); });
        $('#compactMode').addEventListener('change', event => { state.settings.ui.compactMode = event.target.checked; applyUiSettings(); markSettingsDirty(); });
        $('#themeSelect').addEventListener('change', event => { state.settings.ui.theme = event.target.value; applyUiSettings(); markSettingsDirty(); });
        $('#dockVisible').addEventListener('change', event => { state.settings.dock ||= {}; state.settings.dock.enabled = event.target.checked; state.floating.adminDock = event.target.checked; WindowManager.apply('adminDock'); syncRootVisibility(); markSettingsDirty(); });
        document.addEventListener('focusin', event => {
            if (isTextEditableElement(event.target)) setTextInputActive(true);
        }, true);
        document.addEventListener('focusout', () => {
            setTimeout(refreshTextInputActive, 0);
        }, true);
        document.addEventListener('pointerdown', event => {
            if (!isTextEditableElement(event.target)) setTimeout(refreshTextInputActive, 0);
        }, true);
        document.addEventListener('keydown', event => {
            const tag = document.activeElement?.tagName?.toLowerCase();
            const inputActive = isTextEditableElement(document.activeElement) || tag === 'input' || tag === 'textarea' || tag === 'select' || document.activeElement?.isContentEditable;
            if (inputActive) {
                setTextInputActive(true);
                event.stopPropagation();
                if (/^F\d{1,2}$/.test(event.key)) event.preventDefault();
            }
            if (event.key === 'Escape') {
                if (state.dialog.active === true) {
                    event.preventDefault();
                    closeActionDialog();
                    return;
                }
                if (state.screenshot.active === true) {
                    event.preventDefault();
                    closeScreenshotDialog();
                    return;
                }
                if (state.open) {
                    event.preventDefault();
                    closePanel();
                    return;
                }
            }
            if (!inputActive && (event.key === 'F5' || event.code === 'KeyO')) {
                event.preventDefault();
                toggleDashboardFromBind();
            }
        });
        window.addEventListener('message', onMessage);
        window.addEventListener('beforeunload', () => post('setTextInputActive', { active: false }));
    }

    function selectAdjacentPlayer(delta, triggerSpectate) {
        const list = players();
        if (!list.length) return;
        const current = list.findIndex(p => Number(p.id) === Number(state.selectedId));
        const next = list[(current + delta + list.length) % list.length];
        if (next) {
            selectPlayer(next.id);
            if (triggerSpectate) post('toggleSpectate', { target: next.id });
        }
    }

    function onMessage(event) {
        const msg = event.data || {};
        switch (msg.action) {
            case 'open': openPanel(msg); break;
            case 'closeDashboardOnly': closeDashboardFromBind(); break;
            case 'toggleDashboardByBind': toggleDashboardFromBind(); break;
            case 'update':
                applyIncomingState(msg.state || {});
                selectStillValidPlayer();
                if (state.open || hasFloatingWindows()) scheduleRender();
                break;
            case 'close': hardCloseFromClient(); break;
            case 'runtimeConfig': {
                const runtimeVisibility = captureRuntimeWindowVisibility();
                state.runtime = msg.data?.runtimeConfig || msg.data || {};
                applyRuntimeLocalization(state.runtime);
                if (msg.data?.adminSettings) state.settings = normalizeSettings(msg.data.adminSettings);
                restoreRuntimeWindowVisibility(runtimeVisibility);
                applyUiSettings();
                if (state.open || hasFloatingWindows()) scheduleRender();
                break;
            }
            case 'settingsSaved': {
                const runtimeVisibility = captureRuntimeWindowVisibility();
                if (msg.data?.reset && msg.data?.settings) {
                    state.settings = normalizeSettings(msg.data.settings);
                    if (state.selectedPlayer && !state.inspector.manualClosed) state.floating.playerInspector = true;
                    applyInspectorDefaultPosition(true);
                }
                restoreRuntimeWindowVisibility(runtimeVisibility);
                applyUiSettings();
                scheduleRender();
                toast(msg.data?.reset ? L('dialogs.reset', 'UI réinitialisée.') : L('dialogs.saved', 'UI sauvegardée.'));
                break;
            }
            case 'appearanceSaved':
                toast(L('dialogs.saved', 'UI sauvegardée.'));
                break;
            case 'spectateInfo':
                renderSpectate(msg.data || {});
                break;
            case 'pauseState':
                setPauseSuspended(msg.data?.active === true || msg.active === true);
                break;
            case 'adminNotice':
                openNoticeDialog(msg.data || msg);
                break;
            case 'screenshotResult':
                openScreenshotDialog(msg.data || msg);
                break;
            case 'noclipStatus':
                state.noclip = {
                    enabled: msg.data?.enabled === true,
                    speed: Number(msg.data?.speed || 0),
                    speedIndex: Number(msg.data?.speedIndex || 0),
                };
                renderActions();
                break;
        }
    }

    function boot() {
        bindEvents();
        initInspectorRefs();
        state.pauseSuspended = false;
        state.pauseSnapshot = null;
        state.settings = normalizeSettings(DEFAULT_SETTINGS);
        applyUiSettings();
        WindowManager.applyAll();
        post('ready');
    }

    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot); else boot();
})();
