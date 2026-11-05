#!/usr/bin/env node
// SPDX-FileCopyrightText: 2026 Infiniti151
// SPDX-License-Identifier: GPL-3.0-or-later

'use strict';

const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '..');

const CROWDIN_DIR = path.join(ROOT, 'crowdin');
const WEBUI_LOCALES_DIR = path.join(ROOT, 'webui/src/locales');
const SHELL_TRANSLATIONS_DIR = path.join(ROOT, 'install/translations');

// Map Crowdin locale codes to ACC's existing shell translation directories.
// WebUI locale filenames always use the original Crowdin locale.
const shellLocaleMap = {
    de: 'de-DE',
    pt: 'pt-PT',
    'zh-CN': 'zh-rCN',
    'zh-TW': 'zh-rTW',
};

const colors = {
    reset: '\x1b[0m',
    bold: '\x1b[1m',
    dim: '\x1b[2m',
    cyan: '\x1b[36m',
    green: '\x1b[32m',
    yellow: '\x1b[33m',
};

const SHELL_FILE_HEADER = [
    '#!/system/bin/sh',
    '#',
    '# SPDX-FileCopyrightText: 2026 Infiniti151',
    '# SPDX-License-Identifier: GPL-3.0-or-later',
    '',
    '',
].join('\n');

const NON_TRANSLATABLE_WEBUI_KEYS = new Set([
    'webUiName',
    'advancedChargingController',
]);

function fail(message) {
    throw new Error(message);
}

function isObject(value) {
    return value !== null &&
        typeof value === 'object' &&
        !Array.isArray(value);
}

function readJson(file) {
    try {
        return JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (error) {
        fail(`Failed to read ${path.relative(ROOT, file)}: ${error.message}`);
    }
}

function writeIfChanged(file, content) {
    if (fs.existsSync(file) && fs.readFileSync(file, 'utf8') === content) {
        return false;
    }

    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, content, 'utf8');
    return true;
}

// -----------------------------------------------------------------------------
// Crowdin loading and validation
// -----------------------------------------------------------------------------

function loadTranslations() {
    if (!fs.existsSync(CROWDIN_DIR)) {
        fail(`Crowdin directory not found: ${CROWDIN_DIR}`);
    }

    const files = fs.readdirSync(CROWDIN_DIR)
        .filter(file => file.endsWith('.json'))
        .sort();

    if (!files.includes('en.json')) {
        fail('Missing Crowdin English source: crowdin/en.json');
    }

    const translations = new Map();

    for (const file of files) {
        const locale = path.basename(file, '.json');

        if (!/^[a-z]{2}(?:-[A-Za-z0-9]+)?$/.test(locale)) {
            fail(`Invalid locale filename: ${file}`);
        }

        const data = readJson(path.join(CROWDIN_DIR, file));

        if (!isObject(data)) {
            fail(`${file}: expected a JSON object.`);
        }

        translations.set(locale, data);
    }

    return translations;
}

function validateEnglish(english) {
    if (!isObject(english?.webui) || !isObject(english?.shell)) {
        fail('crowdin/en.json must contain "webui" and "shell" objects.');
    }

    for (const namespace of ['webui', 'shell']) {
        for (const [key, value] of Object.entries(english[namespace])) {
            if (typeof value !== 'string') {
                fail(`Invalid English value: ${namespace}.${key}`);
            }

            if (
                namespace === 'shell' &&
                !/^[A-Z_][A-Z0-9_]*$/.test(key)
            ) {
                fail(`Invalid shell variable name: "${key}".`);
            }
        }
    }
}

// -----------------------------------------------------------------------------
// Synchronize all locale JSON files against English
// -----------------------------------------------------------------------------

function syncNamespace(localeCode, namespace, existing, english) {
    if (!isObject(existing)) {
        fail(
            `${localeCode}.json: "${namespace}" namespace must be an object.`
        );
    }

    const synchronized = {};

    for (const key of Object.keys(english)) {
        if (
            namespace === 'webui' &&
            NON_TRANSLATABLE_WEBUI_KEYS.has(key)
        ) {
            synchronized[key] = english[key];
            continue;
        }

        const value = Object.hasOwn(existing, key)
            ? existing[key]
            : '';

        if (typeof value !== 'string') {
            fail(
                `Invalid value for ${localeCode}.${namespace}.${key}. ` +
                'Expected a string.'
            );
        }

        synchronized[key] = value;
    }

    return synchronized;
}

function logSyncedLocales(locales) {
    if (locales.length === 0) {
        return;
    }

    console.log(
        `\n${colors.cyan}${colors.bold}Crowdin Sync${colors.reset}`
    );

    for (const locale of locales) {
        console.log(`  ${colors.green}✓${colors.reset} ${locale}`);
    }
}

function logIncompleteLocales(translations, english) {
    const incompleteWebui = [];
    const incompleteShell = [];

    for (const [localeCode, data] of translations) {
        if (localeCode === 'en') {
            continue;
        }

        const webui = resolveWebuiNamespace(data, english.webui);
        const shell = resolveShellNamespace(data, english.shell);

        if (!hasCompleteTranslation(
            webui,
            english.webui,
            NON_TRANSLATABLE_WEBUI_KEYS
        )) {
            incompleteWebui.push(localeCode);
        }

        if (!hasCompleteTranslation(shell, english.shell)) {
            incompleteShell.push(localeCode);
        }
    }

    if (incompleteWebui.length > 0) {
        console.log(
            `  ${colors.yellow}⚠${colors.reset} WebUI incomplete: ` +
            `[${incompleteWebui.join(', ')}]`
        );
    }

    if (incompleteShell.length > 0) {
        console.log(
            `  ${colors.yellow}⚠${colors.reset} Shell incomplete: ` +
            `[${incompleteShell.join(', ')}]`
        );
    }
}

function syncLocaleFiles(translations, english) {
    const namespaces = ['webui', 'shell'];
    const updates = [];

    // Validate and prepare all locale updates before writing anything.
    for (const [localeCode, data] of translations) {
        if (localeCode === 'en') {
            continue;
        }

        const synced = { ...data };

        for (const namespace of namespaces) {
            synced[namespace] = syncNamespace(
                localeCode,
                namespace,
                data[namespace] ?? {},
                english[namespace]
            );
        }

        updates.push({
            localeCode,
            file: path.join(CROWDIN_DIR, `${localeCode}.json`),
            content: `${JSON.stringify(synced, null, 2)}\n`,
            synced,
        });
    }

    // Write synchronized files and update in-memory locale data.
    let updated = 0;
    const synchronizedLocales = [];

    for (const { localeCode, file, content, synced } of updates) {
        translations.set(localeCode, synced);

        if (writeIfChanged(file, content)) {
            updated++;
            synchronizedLocales.push(localeCode);
        }
    }

    logSyncedLocales(synchronizedLocales);

    return updated;
}

// -----------------------------------------------------------------------------
// Resolve WebUI and shell namespaces
// -----------------------------------------------------------------------------

function resolveWebuiNamespace(locale, englishStrings) {
    const translated = locale.webui ?? {};

    if (!isObject(translated)) {
        fail('The "webui" namespace must be an object.');
    }

    const resolved = {};

    for (const key of Object.keys(englishStrings)) {
        const value = translated[key] ?? '';

        if (typeof value !== 'string') {
            fail(`Invalid value for "webui.${key}". Expected a string.`);
        }

        resolved[key] = value;
    }

    return resolved;
}

function resolveShellNamespace(locale, englishStrings) {
    const translated = locale.shell ?? {};

    if (!isObject(translated)) {
        fail('The "shell" namespace must be an object.');
    }

    const resolved = {};

    for (const key of Object.keys(englishStrings)) {
        const value = translated[key];

        if (value !== undefined && typeof value !== 'string') {
            fail(`Invalid value for "shell.${key}". Expected a string.`);
        }

        // Only generate nonempty translations.
        // Missing or empty values inherit English at runtime.
        if (value) {
            resolved[key] = value;
        }
    }

    return resolved;
}

// -----------------------------------------------------------------------------
// Shell translation generation
// -----------------------------------------------------------------------------

// Check whether a dollar sign should remain expandable in shell.
//
// Only $id, ${id}, $domain and ${domain} are preserved.
function isAllowedShellExpansion(value, index) {
    const next = value[index + 1];

    if (next === '{') {
        const end = value.indexOf('}', index + 2);

        if (end === -1) {
            return false;
        }

        const name = value.slice(index + 2, end);

        return name === 'id' || name === 'domain';
    }

    for (const name of ['id', 'domain']) {
        if (!value.startsWith(name, index + 1)) {
            continue;
        }

        const nextChar = value[index + 1 + name.length];

        if (
            nextChar === undefined ||
            !(
                (nextChar >= 'a' && nextChar <= 'z') ||
                (nextChar >= 'A' && nextChar <= 'Z') ||
                (nextChar >= '0' && nextChar <= '9') ||
                nextChar === '_'
            )
        ) {
            return true;
        }
    }

    return false;
}

// Quote a translation for a shell double-quoted assignment.
function shellQuote(value) {
    let escaped = '';

    for (let i = 0; i < value.length; i++) {
        const char = value[i];

        if (
            char === '\\' ||
            char === '"' ||
            char === '`' ||
            (char === '$' && !isAllowedShellExpansion(value, i))
        ) {
            escaped += '\\';
        }

        escaped += char;
    }

    return `"${escaped}"`;
}

function shellAssignmentPattern(key) {
    return new RegExp(
        String.raw`^${key}="(?:\\.|[^"\\])*"(?=\r?$)`,
        'gm'
    );
}

function validateShellAssignment(file, content, key) {
    const declarations = [
        ...content.matchAll(new RegExp(`^${key}=`, 'gm'))
    ];

    const pattern = shellAssignmentPattern(key);
    const matches = [...content.matchAll(pattern)];

    if (declarations.length > 1 || matches.length > 1) {
        fail(
            `${path.relative(ROOT, file)}: expected at most one ` +
            `${key} assignment, found ${declarations.length}.`
        );
    }

    if (declarations.length !== matches.length) {
        fail(
            `${path.relative(ROOT, file)}: invalid format for ${key}. ` +
            'Expected a double-quoted assignment.'
        );
    }

    return { pattern, matches };
}

function updateShellAssignment(
    file,
    content,
    key,
    strings,
    missingAssignments
) {
    const { pattern, matches } = validateShellAssignment(
        file,
        content,
        key
    );

    if (!Object.hasOwn(strings, key) || strings[key] === '') {
        return matches.length === 1
            ? content.replace(
                new RegExp(String.raw`^${key}="(?:\\.|[^"\\])*"\r?\n?`, 'gm'),
                ''
            )
            : content;
    }

    const assignment = `${key}=${shellQuote(strings[key])}`;

    if (matches.length === 1) {
        return content.replace(pattern, () => assignment);
    }

    missingAssignments.push(assignment);
    return content;
}

function findLastShellAssignment(content, keys) {
    let lastMatch = null;

    const pattern = /^([A-Z_][A-Z0-9_]*)="(?:\\.|[^"\\])*"(?=\r?$)/gm;

    for (const match of content.matchAll(pattern)) {
        if (keys.has(match[1])) {
            lastMatch = match;
        }
    }

    return lastMatch;
}

function insertMissingShellAssignments(content, assignments, keys) {
    const lastMatch = findLastShellAssignment(content, keys);
    let insertAt;

    if (lastMatch) {
        const end = lastMatch.index + lastMatch[0].length;
        const newline = content.indexOf('\n', end);

        if (newline !== -1) {
            insertAt = newline + 1;
        } else {
            content += '\n';
            insertAt = content.length;
        }
    } else {
        if (content.length > 0 && !content.endsWith('\n')) {
            content += '\n';
        }

        insertAt = content.length;
    }

    const additions = `${assignments.join('\n')}\n`;

    return (
        content.slice(0, insertAt) +
        additions +
        content.slice(insertAt)
    );
}

function updateShellStrings(file, strings, allKeys) {
    const fileExists = fs.existsSync(file);

    let content = fileExists
        ? fs.readFileSync(file, 'utf8')
        : SHELL_FILE_HEADER;

    // Include obsolete assignments so they can be removed.
    const existingKeys = [
        ...content.matchAll(/^([A-Z_][A-Z0-9_]*)=/gm)
    ].map(match => match[1]);

    const keysToProcess = new Set([...allKeys, ...existingKeys]);
    const missingAssignments = [];

    for (const key of keysToProcess) {
        content = updateShellAssignment(
            file,
            content,
            key,
            strings,
            missingAssignments
        );
    }

    if (missingAssignments.length > 0) {
        content = insertMissingShellAssignments(
            content,
            missingAssignments,
            keysToProcess
        );
    }

    // Don't create an empty shell translation file.
    if (!fileExists && missingAssignments.length === 0) {
        return false;
    }

    return writeIfChanged(file, content);
}

// -----------------------------------------------------------------------------
// Generate locale files
// -----------------------------------------------------------------------------

function hasCompleteTranslation(translated, english, excludedKeys = []) {
    const excluded = new Set(excludedKeys);

    const translatableKeys = Object.keys(english).filter(
        key => !excluded.has(key)
    );

    return (
        translatableKeys.length > 0 &&
        translatableKeys.every(
            key => typeof translated[key] === 'string' &&
                translated[key].trim() !== ''
        )
    );
}

function generateLocale(localeCode, data, english) {
    const webui = resolveWebuiNamespace(data, english.webui);

    const shell = localeCode === 'en'
        ? english.shell
        : resolveShellNamespace(data, english.shell);

    const webuiFile = path.join(
        WEBUI_LOCALES_DIR,
        `${localeCode}.json`
    );

    // Generate WebUI locale files only when every translatable key is translated.
    const hasCompleteWebuiTranslation = hasCompleteTranslation(
        webui,
        english.webui,
        NON_TRANSLATABLE_WEBUI_KEYS
    );

    let webuiUpdated = false;

    if (localeCode === 'en' || hasCompleteWebuiTranslation) {
        webuiUpdated = writeIfChanged(
            webuiFile,
            `${JSON.stringify(webui, null, 2)}\n`
        );
    }

    const shellDirectory = localeCode === 'en'
        ? ''
        : (shellLocaleMap[localeCode] || localeCode);

    const shellFile = localeCode === 'en'
        ? path.join(ROOT, 'install/strings.sh')
        : path.join(
            SHELL_TRANSLATIONS_DIR,
            shellDirectory,
            'strings.sh'
        );

    // Generate Shell locale files only when every translatable key is translated.
    const hasCompleteShellTranslation = localeCode === 'en' ||
        hasCompleteTranslation(shell, english.shell);

    let shellUpdated = false;

    if (hasCompleteShellTranslation) {
        shellUpdated = updateShellStrings(
            shellFile,
            shell,
            Object.keys(english.shell)
        );
    }

    return { localeCode, webuiUpdated, shellUpdated };
}

// -----------------------------------------------------------------------------
// Main
// -----------------------------------------------------------------------------

function main() {
    const translations = loadTranslations();
    const english = translations.get('en');

    validateEnglish(english);

    // Always synchronize Crowdin locales before generating translations.
    const crowdinUpdated = syncLocaleFiles(translations, english);

    // Report incomplete translations grouped by namespace.
    logIncompleteLocales(translations, english);

    const results = [];

    for (const [localeCode, data] of translations) {
        results.push(generateLocale(localeCode, data, english));
    }

    const webuiLocales = results
        .filter(result => result.webuiUpdated)
        .map(result => result.localeCode);

    const shellLocales = results
        .filter(result => result.shellUpdated)
        .map(result => result.localeCode);

    const webuiUpdated = webuiLocales.length;
    const shellUpdated = shellLocales.length;

    // Print grouped generation output.
    if (webuiLocales.length > 0) {
        console.log(
            `\n${colors.yellow}${colors.bold}WebUI Locales${colors.reset}`
        );

        for (const locale of webuiLocales) {
            console.log(`  ${colors.green}✓${colors.reset} ${locale}`);
        }
    }

    if (shellLocales.length > 0) {
        console.log(
            `\n${colors.yellow}${colors.bold}Shell Locales${colors.reset}`
        );

        for (const locale of shellLocales) {
            console.log(`  ${colors.green}✓${colors.reset} ${locale}`);
        }
    }

    // Final summary.
    console.log(
        `\n${colors.green}${colors.bold}✓ Translation generation complete!${colors.reset}\n` +
        `${colors.dim}Updated:${colors.reset}\n` +
        `  ${colors.cyan}${crowdinUpdated}${colors.reset} Crowdin locale file(s)\n` +
        `  ${colors.cyan}${webuiUpdated}${colors.reset} WebUI file(s)\n` +
        `  ${colors.cyan}${shellUpdated}${colors.reset} Shell file(s)\n`
    );
}

try {
    main();
} catch (error) {
    console.error(`Translation generation failed: ${error.message}`);
    process.exitCode = 1;
}
