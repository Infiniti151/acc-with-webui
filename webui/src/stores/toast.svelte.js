/**
SPDX-FileCopyrightText: 2026 Infiniti151
SPDX-License-Identifier: GPL-3.0-or-later
**/

export const toastState = $state({
    message: '',
    type: 'info', // 'info' | 'success' | 'warning' | 'error' | 'confirm'
    icon: null,
    visible: false,
    bannerOffset: 0,
    loading: false,
    onConfirm: null,
    onCancel: null
});

let toastTimeout = null;

export const toast = {
    get message() { return toastState.message; },
    get type() { return toastState.type; },
    get icon() { return toastState.icon; },
    get visible() { return toastState.visible; },
    get loading() { return toastState.loading; },
    get onConfirm() { return toastState.onConfirm; },
    get onCancel() { return toastState.onCancel; },

    show(message, type = 'info', duration = 4000) {
        if (toastTimeout) clearTimeout(toastTimeout);

        toastState.message = message;
        toastState.type = type;
        toastState.visible = true;
        toastState.loading = false;

        if (duration > 0) {
            toastTimeout = setTimeout(() => {
                this.hide();
            }, duration);
        }
    },

    info(message, duration = 4000) { this.show(message, 'info', duration); },
    success(message, duration = 4000) { this.show(message, 'success', duration); },
    warning(message, duration = 4000) { this.show(message, 'warning', duration); },
    error(message, duration = 4000) { this.show(message, 'error', duration); },

    setBannerOffset(px) {
        toastState.bannerOffset = px;
    },

    confirm(message, options = {}) {
        const opts = typeof options === 'function' ? { action: options } : options;
        const { icon = null, action = null } = opts;

        return new Promise((resolve) => {
            toastState.loading = false;
            toastState.icon = icon;

            toastState.onConfirm = async () => {
                this.hide(); // Dismiss immediately on Yes
                resolve(true);
                if (action) {
                    try {
                        await action();
                    } catch (e) {
                        console.error(e);
                    }
                }
            };

            toastState.onCancel = () => {
                this.hide(); // Dismiss immediately on No
                resolve(false);
            };

            this.show(message, 'confirm', 0);
        });
    },

    hide() {
        if (toastTimeout) clearTimeout(toastTimeout);
        toastState.visible = false;
        toastState.loading = false;
    }
};