import en from "./locales/en.json";
import ru from "./locales/ru.json";

const locale = navigator.language.startsWith("ru")
    ? "ru"
    : "en";

const messages = {
    en,
    ru
};

export function t(key, params = {}) {
    const message = messages[locale]?.[key] ??
        messages.en[key] ??
        key;

    return message.replace(/\{(\w+)\}/g, (placeholder, name) =>
        params[name] ?? placeholder
    );
}
