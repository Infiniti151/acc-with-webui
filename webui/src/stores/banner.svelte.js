/**
SPDX-FileCopyrightText: 2026 Infiniti151
SPDX-License-Identifier: GPL-3.0-or-later
**/

import { exec } from "../utils/exec.js";

const RESTART_FLAG = "/data/local/tmp/acc_restart_required";

export const bannerState = $state({ items: [] });

// Set once by whoever owns the daemon (see registerRestart)
let restartHandler = null;
let restartBlocked = null;

export const banner = {
    get items() { return bannerState.items; },

    /**
     * Add a banner, or update it in place if the id already exists.
     * order: lower = higher on screen. icon: "warning" | "restart" (see BannerStack).
     * actionDisabled: optional function, so it stays reactive to the caller's state.
     */
    show(id, { order = 0, icon = null, text, actionLabel = null, onAction = null, actionDisabled = null, pulse = false }) {
        const item = { id, order, icon, text, actionLabel, onAction, actionDisabled, pulse };
        const i = bannerState.items.findIndex((b) => b.id === id);
        if (i === -1) bannerState.items.push(item);
        else bannerState.items[i] = item;
    },

    hide(id) {
        bannerState.items = bannerState.items.filter((b) => b.id !== id);
    },

    // ---- Daemon restart banner (persisted with a flag file) ----

    /** onRestart: () => void, isBlocked: () => boolean (reactive, read from the button) */
    registerRestart({ onRestart, isBlocked }) {
        restartHandler = onRestart;
        restartBlocked = isBlocked;
    },

    _showRestart() {
        this.show("restart", {
            order: 1,
            icon: "restart",
            text: "Daemon restart required to apply changes.",
            actionLabel: "Restart",
            onAction: () => restartHandler?.(),
            actionDisabled: () => (restartBlocked ? restartBlocked() : false),
        });
    },

    /** Restore the banner after a reload if a restart was still pending */
    async checkRestart() {
        const res = await exec(`test -f ${RESTART_FLAG}`);
        if (res.errno === 0) this._showRestart();
        else this.hide("restart");
    },

    async requireRestart() {
        this._showRestart();
        await exec(`touch ${RESTART_FLAG}`);
    },

    async clearRestart() {
        this.hide("restart");
        await exec(`rm -f ${RESTART_FLAG}`);
    },
};