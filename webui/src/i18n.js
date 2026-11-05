// webui/src/i18n.js

const localeModules = import.meta.glob(
    './locales/*.json',
    {
        eager: true,
        import: 'default',
    }
);

const messages = Object.fromEntries(
    Object.entries(localeModules).map(([path, translations]) => {
        const locale = /\/([^/]+)\.json$/.exec(path)[1];
        return [locale, translations];
    })
);

// Match saved locale in localStorage, or detect browser locale, falling back to English.
const savedLocale = localStorage.getItem('acc_locale');
const normalizedBrowserLocale = (navigator.language || 'en').toLowerCase();

let chineseLocale = null;

if (normalizedBrowserLocale.startsWith('zh')) {
    if (
        normalizedBrowserLocale.includes('tw') ||
        normalizedBrowserLocale.includes('hk') ||
        normalizedBrowserLocale.includes('mo')
    ) {
        chineseLocale = 'zh-TW';
    } else {
        chineseLocale = 'zh-CN';
    }
}

const initialLocale =
    (savedLocale && messages[savedLocale] ? savedLocale : null) ||
    Object.keys(messages).find(
        lang => lang.toLowerCase() === normalizedBrowserLocale
    ) ||
    (messages[chineseLocale] ? chineseLocale : null) ||
    Object.keys(messages).find(
        lang => lang.toLowerCase() === normalizedBrowserLocale.split('-')[0]
    ) ||
    'en';

let currentLocale = initialLocale;

export function getLocale() {
    return currentLocale;
}

export function setLocale(newLocale) {
    if (messages[newLocale]) {
        currentLocale = newLocale;
        localStorage.setItem('acc_locale', newLocale);
    }
}

export function getAvailableLocales() {
    const localeNames = {
        en: "English",
        ru: "Русский",
        de: "Deutsch",
        fr: "Français",
        "zh-CN": "简体中文",
        "zh-TW": "繁體中文",
        tr: "Türkçe",
        id: "Bahasa Indonesia",
        pt: "Português"
    };

    return Object.keys(messages).map(code => ({
        value: code,
        label: localeNames[code] || code.toUpperCase()
    }));
}

export function t(key, params = {}) {
    const message =
        messages[currentLocale]?.[key] ||
        messages.en?.[key] ||
        key;

    return message.replace(/\{(\w+)\}/g, (placeholder, name) =>
        params[name] ?? placeholder
    );
}