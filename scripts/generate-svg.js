#!/usr/bin/env node
// SPDX-FileCopyrightText: 2026 Infiniti151
// SPDX-License-Identifier: GPL-3.0-or-later

const fs = require("node:fs");

const URL =
    "https://badges.awesome-crowdin.com/stats-17964331-943657.json";

const OUTPUT = "images/localization-progress.svg";
const GITHUB_RAW_IMAGE_URL =
    "https://raw.githubusercontent.com/Infiniti151/acc-with-webui/dev/images/localization-progress.svg";
const README = "README.md";

const README_START = "<!-- LOCALIZATION_PROGRESS_START -->";
const README_END = "<!-- LOCALIZATION_PROGRESS_END -->";

const GREEN = "\x1b[32m";
const RESET = "\x1b[0m";

const COLORS = {
    bg: "#0d1117",
    header: "#161b22",

    headerText: "#c9d1d9",
    text: "#bfc9d4",
    percentage: "#8b949e",

    green: "#3fb950",
    blue: "#58a6ff",
    red: "#f85149",
};

const BADGE_COLORS = {
    green: "brightgreen",
    blue: "blue",
    red: "red",
};

const SVG_WIDTH = 800;
const HEADER_HEIGHT = 50;
const ROW_HEIGHT = 46;

const BAR_X = 260;
const BAR_WIDTH = 360;

function success(message) {
    console.log(`${GREEN}✅ ${message}${RESET}`);
}

function escapeXml(str) {
    return str
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;");
}

function escapeRegex(value) {
    return value.replace(
        /[.*+?^${}()|[\]\\]/g,
        String.raw`\$&`,
    );
}

function getColor(progress) {
    if (progress === 100) {
        return "green";
    }

    if (progress >= 30) {
        return "blue";
    }

    return "red";
}

function getSvgColor(progress) {
    return COLORS[getColor(progress)];
}

function getBadgeColor(progress) {
    return BADGE_COLORS[getColor(progress)];
}

async function main() {
    const response = await fetch(URL);
    const json = await response.json();

    const languages = json.progress
        .map((item) => ({
            name: item.data.language.name,
            progress: Number(
                item.data.translationProgress.replace("%", ""),
            ),
        }))
        .sort((a, b) => {
            if (b.progress !== a.progress) {
                return b.progress - a.progress;
            }

            return a.name.localeCompare(b.name);
        });

    const height =
        HEADER_HEIGHT +
        languages.length * ROW_HEIGHT +
        20;

    let svg = `
<svg xmlns="http://www.w3.org/2000/svg"
     width="${SVG_WIDTH}"
     height="${height}"
     role="img">

<style>
text {
  font-family: -apple-system, BlinkMacSystemFont,
               "Segoe UI", Helvetica, Arial, sans-serif;
}
</style>

<rect width="100%" height="100%" fill="${COLORS.bg}" />

<rect
  x="0"
  y="0"
  width="${SVG_WIDTH}"
  height="${HEADER_HEIGHT}"
  fill="${COLORS.header}"
  stroke="${COLORS.border}" />

<text
  x="20"
  y="32"
  fill="${COLORS.text}"
  font-size="18"
  font-weight="600">
  Language
</text>

<text
  x="${BAR_X}"
  y="32"
  fill="${COLORS.text}"
  font-size="18"
  font-weight="600">
  Progress
</text>
`;

    languages.forEach((lang, index) => {
        const y = HEADER_HEIGHT + index * ROW_HEIGHT;

        const barWidth =
            (lang.progress / 100) * BAR_WIDTH;

        svg += `
<text
  x="20"
  y="${y + 30}"
  fill="${COLORS.text}"
  font-size="15">
  ${escapeXml(lang.name)}
</text>

<rect
  x="${BAR_X}"
  y="${y + 13}"
  width="${barWidth}"
  height="20"
  rx="10"
  fill="${getSvgColor(lang.progress)}" />

<text
  x="${BAR_X + BAR_WIDTH + 15}"
  y="${y + 30}"
  fill="${COLORS.text}"
  font-size="15">
  ${lang.progress}%
</text>
`;
    });

    svg += "\n</svg>\n";

    fs.mkdirSync("images", { recursive: true });

    fs.writeFileSync(OUTPUT, svg, "utf8");

    success(`Generated ${OUTPUT}`);

    const overallProgress = Math.round(
        languages.reduce(
            (sum, language) => sum + language.progress,
            0,
        ) / languages.length,
    );

    const badgeColor = getBadgeColor(overallProgress);

    const badgeUrl =
        `https://img.shields.io/badge/` +
        `Localized-${overallProgress}%25-${badgeColor}` +
        `?style=for-the-badge&logo=crowdin`;

    success(
        `Generated overall translation progress badge (${overallProgress}%)`,
    );

    const readme = fs.readFileSync(README, "utf8");

    const replacement = [
        README_START,
        "",
        `[![Crowdin](${badgeUrl})](https://crowdin.com/project/acc-with-webui)`,
        "",
        `![Language Progress](${GITHUB_RAW_IMAGE_URL})`,
        "",
        README_END,
    ].join("\n");

    const updatedReadme = readme.replace(
        new RegExp(
            String.raw`${escapeRegex(README_START)}[\s\S]*?${escapeRegex(README_END)}`,
        ),
        replacement,
    );

    fs.writeFileSync(README, updatedReadme, "utf8");

    success(`Updated ${README}`);

}

main().catch((error) => {
    console.error(error);
    process.exit(1);
});