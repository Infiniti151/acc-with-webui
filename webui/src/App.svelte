<!--
    Copyright (C) 2026 Infiniti151

    This file is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This file is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/gpl-3.0.html>.
-->
<script>
    import { onMount, onDestroy } from "svelte";
    import { fly, slide } from "svelte/transition";
    import { cubicOut } from "svelte/easing";
    import { version } from "../package.json";

    // --- Svelte 5 Reactive States (Runes) ---

    // Battery Banner
    let initialLoad = $state(true);
    let currentEnv = $state("DETECTING");

    let fillPercentage = $derived(Math.min(Math.max(pauseThresh || 0, 0), 100));
    let fluidHeight = $derived((160 * fillPercentage) / 100);
    let fluidY = $derived(170 - fluidHeight);

    let wavePath1 = $derived(
        `M 10 ${fluidY} Q 30 ${fluidY - 4}, 50 ${fluidY} T 90 ${fluidY} L 90 170 L 10 170 Z`,
    );
    let wavePath2 = $derived(
        `M 10 ${fluidY} Q 30 ${fluidY + 4}, 50 ${fluidY} T 90 ${fluidY} L 90 170 L 10 170 Z`,
    );

    // Battery Status Stats
    let health = $state("--");
    let temperature = $state("--");
    let voltage = $state("--");
    let current = $state("--");

    let isRunning = $state(false);
    let isTransitioning = $state(false);
    let daemonStatus = $state("Stopped");

    let currentState = $derived(
        isTransitioning ? "transitioning" : isRunning ? "running" : "stopped",
    );

    // Thresholds
    let resumeThresh = $state(85);
    let pauseThresh = $state(90);

    // Reset Battery Stats Toggle Settings
    let rbsp = $state(false);
    let rbspl = $state(false);
    let rbsu = $state(false);

    // Config Editor
    let configText = $state("");
    let isEditorOpen = $state(false);

    // Logs
    let isLogsOpen = $state(false);
    let logsContent = $state("Loading logs...");
    let logPollInterval = null;

    // Notification Banner Visibility
    let isBannerOpen = $state(false);

    // Background Polling Timer
    let statusPollInterval = null;

    const configPath = "/data/adb/vr25/acc-data/config.txt";

    let startPercent = $derived(((resumeThresh - 1) / 99) * 100);
    let stopPercent = $derived(((pauseThresh - 1) / 99) * 100);

    // --- Global Android Bridge Integration ---
    function exec(cmd, timeoutMs = 10000) {
        return new Promise((resolve) => {
            if (typeof ksu === "undefined" || !ksu.exec) {
                resolve({ errno: -1, stdout: "", stderr: "ksu missing" });
                return;
            }

            const fullCmd = `export PATH=/data/adb/modules/acc/system/bin:$PATH; ${cmd}`;
            const cbName = `cb_${Math.random().toString(36).slice(2, 11)}_${Date.now()}`;

            let timer = null;

            const cleanup = () => {
                if (timer) clearTimeout(timer);
                if (window[cbName]) delete window[cbName];
            };

            window[cbName] = (errno, stdout = "", stderr = "") => {
                cleanup();
                resolve({
                    errno,
                    stdout: typeof stdout === "string" ? stdout.trim() : "",
                    stderr: typeof stderr === "string" ? stderr.trim() : "",
                });
            };

            timer = setTimeout(() => {
                cleanup();
                resolve({ errno: -3, stdout: "", stderr: "Command timed out" });
            }, timeoutMs);

            try {
                ksu.exec(fullCmd, "{}", cbName);
            } catch (e) {
                cleanup();
                resolve({
                    errno: -2,
                    stdout: "",
                    stderr: e?.message || "Execution exception",
                });
            }
        });
    }

    // Reusable single-color HSL Hue-Rotation engine
    function getComplementaryHex(hex) {
        let cleanHex = hex.trim().replace("#", "");
        if (cleanHex.length === 3) {
            cleanHex = cleanHex
                .split("")
                .map((c) => c + c)
                .join("");
        }

        let r = parseInt(cleanHex.substring(0, 2), 16) / 255;
        let g = parseInt(cleanHex.substring(2, 4), 16) / 255;
        let b = parseInt(cleanHex.substring(4, 6), 16) / 255;

        let max = Math.max(r, g, b),
            min = Math.min(r, g, b);
        let h,
            s,
            l = (max + min) / 2;

        if (max === min) {
            h = s = 0;
        } else {
            let d = max - min;
            s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
            switch (max) {
                case r:
                    h = (g - b) / d + (g < b ? 6 : 0);
                    break;
                case g:
                    h = (b - r) / d + 2;
                    break;
                case b:
                    h = (r - g) / d + 4;
                    break;
            }
            h /= 6;
        }

        // Shift Hue by 180 degrees
        h = (h + 0.5) % 1.0;

        let q = l < 0.5 ? l * (1 + s) : l + s - l * s;
        let p = 2 * l - q;

        const hue2rgb = (p, q, t) => {
            if (t < 0) t += 1;
            if (t > 1) t -= 1;
            if (t < 1 / 6) return p + (q - p) * 6 * t;
            if (t < 1 / 2) return q;
            if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
            return p;
        };

        let rFinal = Math.round(hue2rgb(p, q, h + 1 / 3) * 255);
        let gFinal = Math.round(hue2rgb(p, q, h) * 255);
        let bFinal = Math.round(hue2rgb(p, q, h - 1 / 3) * 255);

        return `#${rFinal.toString(16).padStart(2, "0")}${gFinal.toString(16).padStart(2, "0")}${bFinal.toString(16).padStart(2, "0")}`.toUpperCase();
    }

    function setupComplementaryColors() {
        const root = document.documentElement;
        const computedStyles = window.getComputedStyle(root);

        const targetColors = [
            {
                name: "primary",
                variable: "--md-sys-color-primary",
                defaultHex: "#FBC02D",
            },
            {
                name: "secondary",
                variable: "--md-sys-color-secondary",
                defaultHex: "#AEB0B2",
            },
            {
                name: "tertiary",
                variable: "--md-sys-color-tertiary",
                defaultHex: "#7D5260",
            },
        ];

        targetColors.forEach((color) => {
            let activeColor = computedStyles
                .getPropertyValue(color.variable)
                .trim();

            if (
                !activeColor ||
                activeColor.startsWith("var") ||
                !activeColor.startsWith("#")
            ) {
                activeColor = color.defaultHex;
            }

            const complementHex = getComplementaryHex(activeColor);

            root.style.setProperty(
                `${color.variable}-complement`,
                complementHex,
            );
        });
    }

    // --- Core Methods ---
    async function detectEnvironment() {
        currentEnv = "CHECKING...";
        const cmd = `
            if [ -d /data/adb/magisk ] || [ -d /sbin/.magisk ]; then
                echo "MAGISK";
            elif [ -d /data/adb/ksu ] || [ -d /data/adb/ksu-v ]; then
                echo "KERNELSU";
            elif [ -d /data/adb/ap ]; then
                echo "APATCH";
            else
                echo "UNKNOWN";
            fi
        `;
        try {
            const res = await exec(cmd);
            currentEnv = res.stdout ? res.stdout.trim() : "UNKNOWN";
        } catch (e) {
            currentEnv = "ERROR";
        }
    }

    async function updateStatus() {
        const [healthRes, tempRes, voltRes, currRes, statRes, cfgRes] =
            await Promise.all([
                exec(
                    "cat /sys/class/power_supply/battery/health 2>/dev/null || echo 0",
                ),
                exec(
                    "cat /sys/class/power_supply/battery/temp 2>/dev/null || echo 0",
                ),
                exec(
                    "cat /sys/class/power_supply/battery/voltage_now 2>/dev/null || echo 0",
                ),
                exec(
                    "cat /sys/class/power_supply/battery/current_now 2>/dev/null || echo 0",
                ),
                exec("acc -D"),
                exec(`cat ${configPath} 2>/dev/null`),
            ]);

        let healthValue = healthRes.stdout.trim();
        let tempStr = tempRes.stdout.trim();
        let voltStr = voltRes.stdout.trim();
        let currStr = currRes.stdout.trim();

        if (
            healthValue === "ksu not found" ||
            !healthValue ||
            healthValue === "0"
        ) {
            health = "N/A";
            temperature = "--";
            voltage = "--";
            current = "--";
        } else {
            health = healthValue;
            const temp = parseInt(tempStr);
            temperature = (temp > 100 ? (temp / 10).toFixed(1) : temp) + " °C";

            const rawVolt = parseInt(voltStr);
            const volt = rawVolt > 100000 ? rawVolt / 1000000 : rawVolt / 1000;
            voltage = volt.toFixed(2) + " V";

            current = Math.floor(parseInt(currStr) / 1000) + " mA";
        }

        const rawConfigText = cfgRes.stdout || "";
        const capacityMatch = rawConfigText.match(/capacity=\(([^)]+)\)/);
        const resetBattStatsMatch = rawConfigText.match(
            /resetBattStats=\(([^)]+)\)/,
        );

        let resumeVal = null;
        let pauseVal = null;

        if (capacityMatch?.[1]) {
            const parts = capacityMatch[1].trim().split(/\s+/);
            resumeVal = parseInt(parts[2]);
            pauseVal = parseInt(parts[3]);
        }

        isRunning = (statRes.stdout || "").toLowerCase().includes("is running");

        if (!isTransitioning) {
            daemonStatus = isRunning ? "Running" : "Stopped";
        }

        if (initialLoad && rawConfigText) {
            configText = rawConfigText;

            if (
                resumeVal !== null &&
                pauseVal !== null &&
                !isNaN(resumeVal) &&
                !isNaN(pauseVal)
            ) {
                resumeThresh = resumeVal;
                pauseThresh = pauseVal;
            }

            if (resetBattStatsMatch?.[1]) {
                const params = resetBattStatsMatch[1].trim().split(/\s+/);
                rbsp = params[0] === "true";
                rbspl = params[1] === "true";
                rbsu = params[2] === "true";
            }
            initialLoad = false;
        }
    }

    let debounceTimeout;
    function handleSliderChange(type) {
        if (type === "start" && resumeThresh >= pauseThresh) {
            resumeThresh = pauseThresh - 1;
        }
        if (type === "stop" && pauseThresh <= resumeThresh) {
            pauseThresh = resumeThresh + 1;
        }

        clearTimeout(debounceTimeout);
        debounceTimeout = setTimeout(async () => {
            await exec(`acca -s rc=${resumeThresh} pc=${pauseThresh}`);
        }, 450);
    }

    async function toggleSetting(key, checked) {
        await exec(`acca -s ${key}=${checked ? "true" : "false"}`);
    }

    function controlDaemon(action) {
        isTransitioning = true;
        daemonStatus = `${action.toUpperCase()}${action === "stop" ? "PING..." : "ING..."}`;

        isBannerOpen = false;

        setTimeout(() => {
            const runExec = async () => {
                try {
                    await exec(`nohup acca -D ${action}`);
                } catch (e) {
                    console.error("Daemon control error:", e);
                }
                setTimeout(async () => {
                    isTransitioning = false;
                    await updateStatus();
                }, 2500);
            };
            runExec();
        }, 150);
    }

    async function toggleEditor() {
        isEditorOpen = !isEditorOpen;
        if (isEditorOpen) {
            const res = await exec(`cat ${configPath} 2>/dev/null`);
            configText = res.stdout || "";
        }
    }

    async function saveRawConfig() {
        const sanitizedText = configText.replace(/'/g, "'\\''");
        await exec(`echo '${sanitizedText}' > ${configPath}`);
        initialLoad = true;
        await updateStatus();
        isBannerOpen = true;
    }

    async function toggleLogs() {
        isLogsOpen = !isLogsOpen;
        if (isLogsOpen) {
            logsContent = "Reading logs...";
            startPollingLogs();
        } else {
            stopPollingLogs();
        }
    }

    function startPollingLogs() {
        stopPollingLogs();
        async function poll() {
            if (!isLogsOpen) return;
            const res = await exec(
                "tail -n 50 /data/adb/vr25/acc-data/logs/*.log",
            );
            logsContent = res.stdout || "Empty.";
            if (isLogsOpen) {
                logPollInterval = setTimeout(poll, 2000);
            }
        }
        poll();
    }

    function stopPollingLogs() {
        if (logPollInterval) {
            clearTimeout(logPollInterval);
            logPollInterval = null;
        }
    }

    onMount(() => {
        setupComplementaryColors();
        detectEnvironment();
        updateStatus();
        statusPollInterval = setInterval(updateStatus, 3500);
    });

    onDestroy(() => {
        clearInterval(statusPollInterval);
        stopPollingLogs();
    });
</script>

<div class="ambient-bg">
    <div class="blob blob-1"></div>
    <div class="blob blob-2"></div>
    <div class="blob blob-3"></div>
</div>
<div class="main-layout-wrapper">
    <div class="module-banner-wrap">
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 800 400">
            <defs>
                <linearGradient
                    id="liquid-gradient"
                    x1="0%"
                    y1="0%"
                    x2="0%"
                    y2="100%"
                >
                    <stop
                        offset="0%"
                        stop-color="var(--md-sys-color-primary-complement)"
                    />
                    <stop
                        offset="30%"
                        stop-color="var(--md-sys-color-secondary-complement)"
                    />
                    <stop
                        offset="100%"
                        stop-color="var(--md-sys-color-tertiary-complement)"
                    />
                </linearGradient>

                <pattern
                    id="grid"
                    width="40"
                    height="40"
                    patternUnits="userSpaceOnUse"
                >
                    <path d="M 40 0 L 0 0 0 40" fill="none" />
                </pattern>

                <mask id="jug-interior-clip">
                    <rect
                        x="10"
                        y="10"
                        width="80"
                        height="160"
                        rx="14"
                        fill="#ffffff"
                    />
                </mask>
            </defs>

            <rect width="800" height="400" fill="transparent" />

            <g
                opacity="0.04"
                stroke="var(--md-sys-color-primary-complement)"
                stroke-width="1"
            >
                <rect width="800" height="400" fill="url(#grid)" />
            </g>

            <circle
                cx="580"
                cy="200"
                r="140"
                fill="var(--md-sys-color-primary-complement)"
                opacity="0.06"
                filter="blur(40px)"
            />

            <g transform="translate(60, 20)">
                <rect
                    y="115"
                    width="115"
                    height="28"
                    rx="14"
                    fill="rgba(245, 158, 11, 0.15)"
                    stroke="rgba(245, 158, 11, 0.4)"
                    stroke-width="1"
                />
                <text
                    id="env-badge"
                    x="57.5"
                    y="133"
                    fill="var(--md-sys-color-tertiary-complement)"
                    font-family="system-ui, sans-serif"
                    font-size="11"
                    font-weight="700"
                    letter-spacing="1.5"
                    text-anchor="middle">{currentEnv}</text
                >
                <text
                    x="0"
                    y="195"
                    fill="var(--md-sys-color-primary-complement)"
                    font-family="system-ui, sans-serif"
                    font-size="62"
                    font-weight="800"
                    letter-spacing="-1.5">ACC WebUI</text
                >
                <text
                    x="0"
                    y="240"
                    fill="var(--md-sys-color-secondary-complement)"
                    font-family="system-ui, sans-serif"
                    font-size="26"
                    font-weight="600"
                    opacity="0.95">Advanced Charging Controller</text
                >
            </g>

            <g transform="translate(520, 110)">
                <rect
                    x="10"
                    y="10"
                    width="80"
                    height="160"
                    rx="14"
                    fill="transparent"
                />

                <g mask="url(#jug-interior-clip)">
                    {#if fillPercentage > 0}
                        <path fill="url(#liquid-gradient)" opacity="0.85">
                            <animate
                                attributeName="d"
                                values="{wavePath1}; {wavePath2}; {wavePath1}"
                                dur="2.5s"
                                repeatCount="indefinite"
                            />
                            <animateTransform
                                attributeName="transform"
                                type="translate"
                                from="0 {fluidHeight}"
                                to="0 0"
                                dur="5s"
                                repeatCount="indefinite"
                            />
                        </path>
                    {/if}
                </g>

                <rect
                    x="0"
                    y="0"
                    width="100"
                    height="180"
                    rx="20"
                    fill="none"
                    stroke="#ffffff"
                    stroke-width="5"
                    opacity="0.95"
                />
                <path
                    d="M 35 0 L 65 0 L 60 -6 L 40 -6 Z"
                    fill="#ffffff"
                    opacity="0.95"
                />

                <line
                    x1="-50"
                    y1={fluidY}
                    x2="150"
                    y2={fluidY}
                    stroke="var(--md-sys-color-primary-complement)"
                    stroke-width="2"
                    stroke-dasharray="4 4"
                    opacity="0.8"
                />

                <g transform="translate(90, {fluidY - 12})">
                    <rect
                        x="0"
                        y="0"
                        width="54"
                        height="24"
                        rx="12"
                        fill="var(--md-sys-color-surface-variant)"
                        stroke="var(--md-sys-color-outline)"
                        stroke-width="1.5"
                    />
                    <text
                        id="banner-percentage-text"
                        x="27"
                        y="16"
                        fill="var(--md-sys-color-tertiary-complement)"
                        font-family="monospace"
                        font-size="11"
                        font-weight="700"
                        text-anchor="middle"
                    >
                        {pauseThresh ? `${pauseThresh}%` : "--%"}
                    </text>
                </g>

                <path
                    d="M 53 85 L 37 110 L 48 110 L 45 135 L 61 110 L 50 110 Z"
                    fill="var(--md-sys-color-surface)"
                    opacity="0.3"
                />
            </g>
        </svg>
    </div>

    <div class="grid grid-2">
        <div class="m3-card" style="margin-bottom:0;">
            <div class="card-header">
                <span class="card-title">Health</span><span class="mi-icon"
                    >favorite</span
                >
            </div>
            <div id="bat-health" class="card-value">{health}</div>
        </div>
        <div class="m3-card" style="margin-bottom:0;">
            <div class="card-header">
                <span class="card-title">Temperature</span><span class="mi-icon"
                    >thermostat</span
                >
            </div>
            <div id="bat-temp" class="card-value">{temperature}</div>
        </div>
        <div class="m3-card" style="margin-bottom:0;">
            <div class="card-header">
                <span class="card-title">Current</span><span class="mi-icon"
                    >swap_calls</span
                >
            </div>
            <div id="bat-current" class="card-value">{current}</div>
        </div>
        <div class="m3-card" style="margin-bottom:0;">
            <div class="card-header">
                <span class="card-title">Voltage</span><span class="mi-icon"
                    >bolt</span
                >
            </div>
            <div id="bat-voltage" class="card-value">{voltage}</div>
        </div>
    </div>

    <section class="m3-card">
        <div class="header-row">
            <div class="title-group">
                <span class="mi-icon">build</span>
                <div class="section-title">Daemon (accd)</div>
            </div>
            <span id="bat-status" class={currentState}>
                {daemonStatus}
            </span>
        </div>

        <div class="btn-row">
            <button
                id="btn-start"
                onclick={() => controlDaemon("start")}
                class="m3-btn btn-primary"
                disabled={isTransitioning || isRunning}>Start</button
            >
            <button
                id="btn-stop"
                onclick={() => controlDaemon("stop")}
                class="m3-btn btn-danger"
                disabled={isTransitioning || !isRunning}>Stop</button
            >
            <button
                id="btn-banner-restart"
                onclick={() => controlDaemon("restart")}
                class="m3-btn btn-restart-action"
                disabled={isTransitioning || !isRunning}>Restart</button
            >
        </div>
    </section>

    <section class="m3-card">
        <div class="header-group">
            <span class="mi-icon">battery_charging_full</span>
            <div class="section-title">Charging Thresholds</div>
        </div>

        <div class="slider-wrapper">
            <div class="flex justify-between">
                <div class="label-text">Resume Charging At</div>
                <div class="thresh-label" style="color: var(--start-electric);">
                    {resumeThresh}%
                </div>
            </div>
            <div
                class="slider-container"
                style="--percent: {startPercent}%; --neon-glow: rgba(0, 255, 102, 0.4); --electric-gradient: linear-gradient(to right, #006622, var(--start-electric), #a3ffc2, var(--start-electric), #006622);"
            >
                <input
                    type="range"
                    min="1"
                    max="100"
                    step="1"
                    bind:value={resumeThresh}
                    oninput={() => handleSliderChange("start")}
                />
                <div class="slider-track-visual">
                    <div class="slider-track-fill"></div>
                </div>
            </div>
        </div>

        <div class="slider-wrapper stop-spacing">
            <div class="flex justify-between">
                <div class="label-text">Pause Charging At</div>
                <div class="thresh-label" style="color: var(--stop-electric);">
                    {pauseThresh}%
                </div>
            </div>
            <div
                class="slider-container"
                style="--percent: {stopPercent}%; --neon-glow: rgba(255, 0, 85, 0.4); --electric-gradient: linear-gradient(to right, #660022, var(--stop-electric), #ffb3cc, var(--stop-electric), #660022);"
            >
                <input
                    type="range"
                    min="1"
                    max="100"
                    step="1"
                    bind:value={pauseThresh}
                    oninput={() => handleSliderChange("stop")}
                />
                <div class="slider-track-visual">
                    <div class="slider-track-fill"></div>
                </div>
            </div>
        </div>
    </section>

    <section class="m3-card">
        <div
            style="display: flex; align-items: center; gap: 8px; margin-bottom: 12px;"
        >
            <span class="mi-icon">loop</span>
            <div class="section-title">Reset Battery Stats</div>
        </div>

        <div
            class="flex justify-between items-center"
            style="padding: 12px 0; border-bottom: 1px solid var(--outline);"
        >
            <div class="label-text">On Pause</div>
            <label class="m3-switch">
                <input
                    type="checkbox"
                    bind:checked={rbsp}
                    onchange={() => toggleSetting("rbsp", rbsp)}
                />
                <span class="slider"></span>
            </label>
        </div>

        <div
            class="flex justify-between items-center"
            style="padding: 12px 0; border-bottom: 1px solid var(--outline);"
        >
            <div class="label-text">On Plug</div>
            <label class="m3-switch">
                <input
                    type="checkbox"
                    bind:checked={rbspl}
                    onchange={() => toggleSetting("rbspl", rbspl)}
                />
                <span class="slider"></span>
            </label>
        </div>

        <div class="flex justify-between items-center" style="padding: 12px 0;">
            <div class="label-text">On Unplug</div>
            <label class="m3-switch">
                <input
                    type="checkbox"
                    bind:checked={rbsu}
                    onchange={() => toggleSetting("rbsu", rbsu)}
                />
                <span class="slider"></span>
            </label>
        </div>
    </section>

    <section class="m3-card">
        <div
            class="flex justify-between items-center"
            onclick={toggleEditor}
            role="button"
            tabindex="0"
            onkeydown={(e) => e.key === "Enter" && toggleEditor()}
            style="cursor: pointer; -webkit-user-select: none; user-select: none;"
        >
            <div style="display: flex; align-items: center; gap: 8px;">
                <span class="mi-icon">edit_note</span>
                <div class="section-title">Config File</div>
            </div>
            <div
                id="arrow-editor"
                style="transform: rotate({isEditorOpen
                    ? '180deg'
                    : '0deg'}); transition: transform 0.25s ease;"
            >
                ▼
            </div>
        </div>

        {#if isEditorOpen}
            <div
                id="editor-area"
                class="collapsible-box"
                transition:slide={{ duration: 300, easing: cubicOut }}
                onintroend={(e) => {
                    const card = e.currentTarget.closest(".m3-card");
                    if (card)
                        card.scrollIntoView({
                            behavior: "smooth",
                            block: "end",
                        });
                }}
            >
                <textarea
                    id="config-textarea"
                    class="editor-textarea"
                    spellcheck="false"
                    bind:value={configText}
                ></textarea>
                <div class="btn-row" style="padding-bottom: 4px;">
                    <button onclick={saveRawConfig} class="m3-btn btn-primary"
                        >Save Config</button
                    >
                </div>
            </div>
        {/if}
    </section>

    <section class="m3-card">
        <div
            class="flex justify-between items-center"
            onclick={toggleLogs}
            role="button"
            tabindex="0"
            onkeydown={(e) => e.key === "Enter" && toggleLogs()}
            style="cursor: pointer; -webkit-user-select: none; user-select: none;"
        >
            <div style="display: flex; align-items: center; gap: 8px;">
                <span class="mi-icon">notes</span>
                <div class="section-title">Logs</div>
            </div>
            <div
                id="arrow-logs"
                style="transform: rotate({isLogsOpen
                    ? '180deg'
                    : '0deg'}); transition: transform 0.25s ease;"
            >
                ▼
            </div>
        </div>

        {#if isLogsOpen}
            <div
                id="logs-area"
                class="collapsible-box"
                transition:slide={{ duration: 300, easing: cubicOut }}
                onintroend={(e) => {
                    const card = e.currentTarget.closest(".m3-card");
                    if (card)
                        card.scrollIntoView({
                            behavior: "smooth",
                            block: "end",
                        });
                }}
            >
                <div id="logs-content" class="log-box">{logsContent}</div>
            </div>
        {/if}
    </section>
    <a
        href="https://github.com/Infiniti151/acc-with-webui"
        class="github-footer-banner"
        onclick={(e) => {
            e.preventDefault();
            e.stopPropagation();

            exec(
                `am start -a android.intent.action.VIEW -d "${e.currentTarget.href}"`,
            );
        }}
    >
        <div class="footer-left-group">
            <div class="github-icon-container">
                <svg
                    width="22"
                    height="22"
                    viewBox="0 0 24 24"
                    fill="currentColor"
                >
                    <path
                        d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"
                    />
                </svg>
            </div>
            <div class="repo-details">
                <div class="repo-name">Infiniti151/acc-with-webui</div>
                <div class="repo-action-label">View on GitHub</div>
            </div>
        </div>
        <div class="footer-right-group">
            <span class="version-tag">v{version}</span>
            <span class="material-icons open-icon">open_in_new</span>
        </div>
    </a>

    {#if isBannerOpen}
        <div
            id="restart-banner"
            class="notification-banner"
            transition:fly={{ y: 100, duration: 300, easing: cubicOut }}
        >
            <div class="notification-content">
                <span class="mi-icon warning-icon">warning</span>
                <span class="notification-text"
                    >Daemon restart required to apply changes.</span
                >
            </div>
            <button
                id="btn-notification-restart"
                onclick={() => controlDaemon("restart")}
                class="m3-btn btn-notification-action"
                disabled={isTransitioning}
            >
                Restart
            </button>
        </div>
    {/if}
</div>

<style>
    :global(:root) {
        --md-sys-color-bg: var(--background, #0c0a0f);
        --md-sys-color-surface: var(--surface, #16151a);
        --md-sys-color-surface-variant: var(--surfaceVariant, #232128);
        --md-sys-color-surface-container: var(--surfaceContainer, #211f26);
        --md-sys-color-primary: var(--primary, #fbc02d);
        --md-sys-color-on-primary: var(--onPrimary, #000000);
        --md-sys-color-secondary: var(--secondary, #d7c68d);
        --md-sys-color-on-secondary: var(--onSecondary, #3a3005);
        --md-sys-color-tertiary: var(--tertiary, #e28e75);
        --md-sys-color-on-tertiary: var(--onTertiary, #441a0e);
        --md-sys-color-outline: var(--outline, #ffffff1a);
        --md-sys-color-on-background: var(--onBackground, #e6e1e5);
        --md-sys-color-on-surface-variant: var(--onSurfaceVariant, #a5a1a9);
        --md-sys-color-error: var(--error, #fa6350);
        --md-sys-color-on-error: var(--onError, #690005);
        --md-sys-color-error-container: var(--errorContainer, #312e23);
        --md-sys-color-on-error-container: var(--onErrorContainer, #f9dedc);
        --warning-icon: var(--md-sys-color-primary);
        --dynamic-editor-text: var(--md-sys-color-tertiary);
        --dynamic-log-text: var(--md-sys-color-tertiary);
        --start-electric: var(--primary, #fbc02d);
        --stop-electric: var(--primary, #fbc02d);
    }

    :global(html) {
        margin: 0;
        padding: 0;
        min-height: 100%;
    }

    :global(body) {
        background-color: var(--md-sys-color-bg) !important;
        color: var(--md-sys-color-on-background);
        margin: 0;
        padding: 12px;
        box-sizing: border-box;
        min-height: 100%;
        display: flex;
        flex-direction: column;
        gap: 12px;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
            sans-serif;
        -webkit-font-smoothing: antialiased;
        overflow-y: auto;
        overflow-x: hidden;
    }

    :global(*) {
        -webkit-tap-highlight-color: transparent !important;
        -webkit-user-drag: none;
    }

    :global(button:focus),
    :global([role="button"]:focus) {
        outline: none;
    }

    .ambient-bg {
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 100%;
        z-index: -1;
        pointer-events: none;
        overflow: hidden;
        opacity: 0.6;
        contain: paint;
    }

    .blob {
        position: absolute;
        border-radius: 50%;
        filter: blur(80px);
        -webkit-filter: blur(80px);
        mix-blend-mode: screen;
        will-change: transform;
    }

    .blob-1 {
        top: -10%;
        left: -20%;
        width: 300px;
        height: 300px;
        background: var(--md-sys-color-primary, #fbc02d);
        animation: floatBlobOne 25s infinite alternate ease-in-out;
    }

    .blob-2 {
        bottom: 10%;
        right: -10%;
        width: 350px;
        height: 350px;
        background: var(--md-sys-color-tertiary, #7d5260);
        animation: floatBlobTwo 30s infinite alternate ease-in-out;
    }

    .blob-3 {
        bottom: -15%;
        left: -10%;
        width: 320px;
        height: 320px;
        background: var(--md-sys-color-secondary, #00796b);
        animation: floatBlobThree 28s infinite alternate ease-in-out;
    }

    .main-layout-wrapper {
        width: 100%;
        max-width: 600px;
        margin: 0 auto;
        box-sizing: border-box;
        padding-top: var(--window-inset-top, 24px);
        padding-bottom: var(--window-inset-bottom, 16px);
        overflow-x: hidden;
    }

    .flex {
        display: flex;
    }

    .grid {
        display: grid;
    }

    .justify-between {
        justify-content: space-between;
    }

    .items-center {
        align-items: center;
    }

    .grid-2 {
        grid-template-columns: repeat(2, 1fr);
        gap: 12px;
        margin-bottom: 12px;
    }

    .module-banner-wrap {
        width: 100%;
        border-radius: 24px;
        overflow: hidden;
        margin-bottom: 12px;

        background: color-mix(
            in srgb,
            var(--md-sys-color-surface-container) 45%,
            transparent
        );
        backdrop-filter: blur(16px);
        -webkit-backdrop-filter: blur(16px);
        border: 1px solid
            color-mix(in srgb, var(--md-sys-color-outline) 25%, transparent);
        box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.08);
    }

    .module-banner-wrap svg {
        display: block;
        width: 100%;
        height: auto;
    }

    .m3-card {
        background: color-mix(
            in srgb,
            var(--md-sys-color-surface-container) 45%,
            transparent
        );

        backdrop-filter: blur(16px);
        -webkit-backdrop-filter: blur(16px);

        border: 1px solid
            color-mix(in srgb, var(--md-sys-color-outline) 25%, transparent);

        box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.08);

        border-radius: 24px;
        padding: 20px;
        margin-bottom: 12px;
        -webkit-user-select: none;
        user-select: none;
    }

    .card-header {
        display: flex;
        align-items: center;
        justify-content: space-between;
        margin-bottom: 8px;
    }

    .card-title {
        font-size: 14px;
        color: var(--md-sys-color-on-surface-variant);
        font-weight: 500;
    }

    .card-value {
        font-size: 24px;
        font-weight: 700;
        color: var(--md-sys-color-primary);
    }

    .section-title {
        font-size: 22px;
        font-weight: 700;
        color: var(--md-sys-color-secondary);
        letter-spacing: -0.4px;
    }

    .label-text {
        font-weight: 500;
        color: var(--md-sys-color-tertiary);
    }

    .btn-row {
        display: flex;
        gap: 8px;
    }

    .m3-btn {
        flex: 1;
        border: none;
        border-radius: 100px;
        padding: 14px 12px;
        font-weight: 600;
        font-size: 14px;
        cursor: pointer;
        text-align: center;
        transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
    }

    .m3-btn:active:not(:disabled) {
        transform: scale(0.95);
    }

    .header-row {
        display: flex;
        align-items: center;
        justify-content: space-between;
        width: 100%;
        margin-bottom: 12px;
    }

    .title-group,
    .header-group {
        display: flex;
        align-items: center;
        gap: 8px;
    }

    .header-group {
        margin-bottom: 12px;
    }

    .slider-wrapper {
        margin-bottom: 16px;
    }

    .stop-spacing {
        margin-top: 24px;
        margin-bottom: 0;
    }

    .thresh-label {
        font-weight: 700;
    }

    #bat-status {
        font-size: 12px;
        font-weight: 700;
        text-transform: uppercase;
        padding: 4px 10px;
        border-radius: 100px;
        transition:
            background-color 0.15s ease,
            color 0.15s ease;
    }

    .btn-primary {
        background-color: var(--md-sys-color-primary);
        color: var(--md-sys-color-on-primary);
    }

    .btn-danger {
        background-color: var(--md-sys-color-error);
        color: var(--md-sys-color-on-error);
    }

    .btn-restart-action {
        background-color: color-mix(
            in srgb,
            var(--md-sys-color-surface-variant) 30%,
            transparent
        );
        color: var(--md-sys-color-primary);

        border: 1px solid
            color-mix(in srgb, var(--md-sys-color-outline) 35%, transparent);

        backdrop-filter: blur(4px);
        -webkit-backdrop-filter: blur(4px);
    }

    .transitioning {
        color: #f59e0b;
        background-color: rgba(245, 158, 11, 0.1);
        animation: status-pulse-transitioning 1.5s infinite ease-in-out both;
    }

    .running {
        color: #00ff66;
        background-color: rgba(0, 255, 102, 0.1);
        animation: status-pulse-running 3s infinite ease-in-out;
    }

    .stopped {
        color: var(--danger, #ef4444);
        background-color: rgba(255, 180, 171, 0.1);
        animation: status-pulse-stopped 5s infinite ease-in-out;
    }

    #btn-banner-restart:disabled,
    #btn-notification-restart:disabled {
        pointer-events: none;
        opacity: 0.5;
        cursor: not-allowed;
    }

    .mi-icon {
        font-family: "Material Icons";
        font-size: 20px;
        color: var(--md-sys-color-primary);
        opacity: 0.9;
    }

    button:disabled {
        opacity: 0.25 !important;
        cursor: not-allowed;
    }

    .m3-switch {
        position: relative;
        display: inline-block;
        width: 52px;
        height: 32px;
    }

    .m3-switch .slider {
        position: absolute;
        cursor: pointer;
        top: 0;
        left: 0;
        right: 0;
        bottom: 0;
        background-color: var(--md-sys-color-surface-variant);
        transition: 0.3s cubic-bezier(0.2, 0.8, 0.2, 1);
        border-radius: 100px;
        border: 2px solid var(--md-sys-color-outline);
    }

    .m3-switch .slider:before {
        position: absolute;
        content: "";
        height: 16px;
        width: 16px;
        left: 6px;
        bottom: 6px;
        background-color: var(--md-sys-color-on-surface-variant);
        transition: 0.3s cubic-bezier(0.2, 0.8, 0.2, 1);
        border-radius: 50%;
    }

    .m3-switch input:checked + .slider {
        background-color: var(--md-sys-color-primary);
        border-color: var(--md-sys-color-primary);
    }

    .m3-switch input:checked + .slider:before {
        transform: translateX(20px);
        background-color: var(--md-sys-color-on-primary);
        width: 20px;
        height: 20px;
        left: 4px;
        bottom: 4px;
    }

    .m3-switch input {
        opacity: 0;
        width: 0;
        height: 0;
    }

    .slider-container {
        position: relative;
        width: 100%;
        margin-top: 16px;
        height: 24px;
        display: flex;
        align-items: center;
    }

    input[type="range"] {
        width: 100%;
        height: 24px;
        pointer-events: none;
        background: transparent;
        appearance: none;
        outline: none;
        z-index: 3;
        margin: 0;
    }

    .slider-track-visual {
        position: absolute;
        left: 0;
        top: 9px;
        width: 100%;
        height: 6px;
        background: var(--md-sys-color-surface-variant);
        border-radius: 16px;
        overflow: hidden;
        z-index: 1;
        pointer-events: none;
    }

    .slider-track-fill {
        position: absolute;
        left: 0;
        top: 0;
        height: 100%;
        width: var(--percent, 0%);
        background-image: var(--electric-gradient);
        box-shadow: 0 0 10px var(--neon-glow);
        border-radius: 16px;
        z-index: 2;
        background-size: 200% 100%;
        animation: electricCurrent 1.5s linear infinite;
        pointer-events: none;
    }

    input[type="range"]::-webkit-slider-thumb {
        pointer-events: auto;
        appearance: none;
        width: 6px;
        height: 20px;
        border-radius: 4px;
        background: #ffffff;
        box-shadow: 0 0 8px rgba(255, 255, 255, 0.8);
        cursor: pointer;
        position: relative;
        z-index: 4;
        transition:
            transform 0.25s cubic-bezier(0.2, 0.8, 0.2, 1),
            background-color 0.15s;
    }

    input[type="range"]:active::-webkit-slider-thumb {
        transform: scaleX(2.8) scaleY(1.15);
        background: var(--md-sys-color-primary);
    }

    input[type="range"]::-moz-range-thumb {
        width: 6px;
        height: 20px;
        border: none;
        border-radius: 4px;
        background: #ffffff;
        box-shadow: 0 0 8px rgba(255, 255, 255, 0.8);
        cursor: pointer;
        position: relative;
        z-index: 4;
        transition:
            transform 0.25s cubic-bezier(0.2, 0.8, 0.2, 1),
            background-color 0.15s;
    }

    input[type="range"]:active::-moz-range-thumb {
        transform: scaleX(2.8) scaleY(1.15);
        background: var(--md-sys-color-primary);
    }

    .collapsible-box {
        overflow: hidden;
        width: 100%;
        margin-top: 12px;
    }

    .editor-textarea {
        width: 100%;
        box-sizing: border-box;
        height: 400px;
        background: var(--md-sys-color-surface-variant) !important;
        color: var(--dynamic-editor-text) !important;
        border: 1px solid var(--md-sys-color-outline);
        font-family: "SF Mono", "Roboto Mono", monospace;
        font-size: 14px;
        line-height: 1.5;
        padding: 16px;
        border-radius: 20px;
        resize: vertical;
        outline: none;
        margin-bottom: 12px;
        transition: border-color 0.2s cubic-bezier(0.2, 0.8, 0.2, 1);
    }

    .editor-textarea:focus {
        border-color: var(--md-sys-color-primary) !important;
        box-shadow: 0 0 0 1px var(--md-sys-color-primary) !important;
    }

    .log-box {
        background: var(--md-sys-color-surface-variant);
        color: var(--dynamic-log-text);
        font-family: monospace;
        font-size: 13px;
        line-height: 1.45;
        padding: 16px;
        height: 400px;
        overflow-y: auto;
        white-space: pre-wrap;
        border: 1px solid var(--md-sys-color-outline);
        border-radius: 20px;
        box-sizing: border-box;
    }

    .notification-banner {
        display: flex;
        position: fixed;
        bottom: 24px;
        left: 12px;
        right: 12px;
        margin: 0 auto;
        width: auto;
        max-width: 100%;
        z-index: 999;
        padding: 16px 20px;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        background: var(--md-sys-color-error-container);
        border: 1px solid var(--md-sys-color-outline);
        border-radius: 24px;
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5);
        backdrop-filter: blur(20px);
        -webkit-backdrop-filter: blur(20px);
        box-sizing: border-box;
    }

    .notification-content {
        display: flex;
        align-items: center;
        gap: 12px;
    }

    .warning-icon {
        color: var(--md-sys-color-on-error-container);
    }

    .notification-text {
        font-size: 14px;
        font-weight: 500;
        color: var(--md-sys-color-on-error-container);
    }

    .btn-notification-action {
        background-color: var(--md-sys-color-primary);
        color: var(--md-sys-color-on-primary);
        border: none;
        font-weight: 700;
        padding: 8px 16px;
        border-radius: 100px;
        cursor: pointer;
        flex: none;
        transition: opacity 0.2s ease;
    }

    .btn-notification-action:active:not(:disabled) {
        opacity: 0.8;
    }

    .btn-notification-action:disabled {
        opacity: 0.5;
        cursor: not-allowed;
    }

    .github-footer-banner {
        display: flex;
        align-items: center;
        justify-content: space-between;
        text-decoration: none;

        background: color-mix(
            in srgb,
            var(--md-sys-color-surface-container) 45%,
            transparent
        );
        backdrop-filter: blur(16px);
        -webkit-backdrop-filter: blur(16px);
        border: 1px solid
            color-mix(in srgb, var(--md-sys-color-outline) 25%, transparent);
        box-shadow: 0 8px 32px 0 rgba(0, 0, 0, 0.08);

        width: 100%;
        box-sizing: border-box;
        border-radius: 24px;
        padding: 20px;

        margin: 0;

        transition:
            background-color 0.2s cubic-bezier(0.2, 0.8, 0.2, 1),
            transform 0.1s;
        -webkit-user-select: none;
        user-select: none;
    }

    .github-footer-banner:hover {
        background-color: color-mix(
            in srgb,
            var(--md-sys-color-surface-container) 60%,
            transparent
        );
    }

    .github-footer-banner:active {
        transform: scale(0.98);
        background-color: color-mix(
            in srgb,
            var(--md-sys-color-surface-variant) 70%,
            transparent
        );
    }

    .footer-left-group {
        display: flex;
        align-items: center;
        gap: 16px;
    }

    .github-icon-container {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 40px;
        height: 40px;

        background-color: color-mix(
            in srgb,
            var(--md-sys-color-surface-variant) 50%,
            transparent
        );
        border: 1px solid
            color-mix(in srgb, var(--md-sys-color-outline) 15%, transparent);
        border-radius: 12px;
    }

    .github-footer-banner :global(svg) {
        color: var(--md-sys-color-primary);
    }

    .repo-details {
        display: flex;
        flex-direction: column;
    }

    .repo-name {
        font-weight: 700;
        font-size: 15px;
        letter-spacing: -0.2px;
        color: var(--md-sys-color-secondary);
    }

    .repo-action-label {
        font-size: 12px;
        color: var(--md-sys-color-tertiary);
        opacity: 0.7;
    }

    .footer-right-group {
        display: flex;
        align-items: center;
        gap: 8px;
    }

    .version-tag {
        font-family: monospace;
        font-size: 12px;
        font-weight: 700;
        color: var(--md-sys-color-on-surface-variant);

        background-color: color-mix(
            in srgb,
            var(--md-sys-color-surface-variant) 50%,
            transparent
        );
        padding: 4px 8px;
        border-radius: 8px;
        border: 1px solid
            color-mix(in srgb, var(--md-sys-color-outline) 20%, transparent);
    }

    .open-icon {
        font-size: 20px;
        color: var(--md-sys-color-primary);
        opacity: 0.8;
        padding-right: 4px;
    }

    @keyframes floatBlobOne {
        0% {
            transform: translate(0px, 0px) scale(1);
        }
        50% {
            transform: translate(120px, 80px) scale(1.15);
        }
        100% {
            transform: translate(60px, 180px) scale(0.9);
        }
    }

    @keyframes floatBlobTwo {
        0% {
            transform: translate(0px, 0px) scale(1);
        }
        50% {
            transform: translate(-100px, -120px) scale(0.85);
        }
        100% {
            transform: translate(-40px, -60px) scale(1.1);
        }
    }

    @keyframes floatBlobThree {
        0% {
            transform: translate(0, 0) scale(1) rotate(0deg);
            border-radius: 42% 58% 70% 30% / 45% 45% 55% 55%;
        }
        50% {
            transform: translate(40px, -60px) scale(1.15) rotate(90deg);
            border-radius: 70% 30% 52% 48% / 60% 40% 60% 40%;
        }
        100% {
            transform: translate(-20px, 30px) scale(0.95) rotate(180deg);
            border-radius: 50% 50% 30% 70% / 50% 60% 40% 50%;
        }
    }

    @keyframes status-pulse-transitioning {
        0%,
        100% {
            opacity: 0.7;
            box-shadow: 0 0 0 0 rgba(245, 158, 11, 0.25);
        }
        50% {
            opacity: 1;
            box-shadow: 0 0 8px 2px rgba(245, 158, 11, 0.4);
        }
    }

    @keyframes status-pulse-running {
        0%,
        100% {
            transform: scale(1);
            box-shadow: 0 0 0 0 rgba(0, 255, 102, 0.2);
        }
        50% {
            transform: scale(1.02);
            box-shadow: 0 0 10px 3px rgba(0, 255, 102, 0.35);
        }
    }

    @keyframes status-pulse-stopped {
        0%,
        100% {
            opacity: 0.8;
        }
        50% {
            opacity: 0.5;
        }
    }

    @keyframes electricCurrent {
        0% {
            background-position: 0% 50%;
        }
        100% {
            background-position: -200% 50%;
        }
    }
</style>
