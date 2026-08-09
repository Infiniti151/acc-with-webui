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

  // Daemon (accd) Status
  let isRunning = $state(false);
  let isTransitioning = $state(false);
  let daemonStatus = $state("Stopped");
  let currentState = $derived(
    isTransitioning ? "transitioning" : isRunning ? "running" : "stopped",
  );

  // Thresholds
  let resumeThresh = $state(85);
  let pauseThresh = $state(90);
  let shutdownThresh = $state(5);

  // Reset Battery Stats Toggle Settings
  let rbsp = $state(false);
  let rbspl = $state(false);
  let rbsu = $state(false);

  // Config Editor
  let configText = $state("");
  let isEditorOpen = $state(false);
  let originalConfigText = $state("");
  let isSaving = $state(false);
  let saveButtonText = $state("Save Config");
  let isConfigDirty = $derived(configText !== originalConfigText);

  // Logs
  let isLogsOpen = $state(false);
  let logsContent = $state("Loading logs...");
  let isExportingLogs = $state(false);
  let logPollInterval = null;

  // Notification Banner Visibility
  let isBannerOpen = $state(false);

  // Background Polling Timer
  let statusPollInterval = null;

  // Toast notification state
  let toastMessage = $state("");
  let isToastVisible = $state(false);
  let toastTimeout = null;

  // --- Global File & Path Constants ---
  const EXPORT_FLAG = "/data/local/tmp/acc_export_done";
  const RESTART_FLAG = "/data/local/tmp/acc_restart_required";
  const CONFIG_PATH = "/data/adb/vr25/acc-data/config.txt";
  const PROP_PATH = "/data/adb/modules/acc/module.prop";

  // --- Global Android Bridge Integration ---
  function exec(cmd, timeoutMs = 10000) {
    return new Promise((resolve) => {
      if (typeof ksu === "undefined" || !ksu.exec) {
        resolve({ errno: -1, stdout: "", stderr: "ksu missing" });
        return;
      }

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
        ksu.exec(cmd, "{}", cbName);
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
      let activeColor = computedStyles.getPropertyValue(color.variable).trim();

      if (
        !activeColor ||
        activeColor.startsWith("var") ||
        !activeColor.startsWith("#")
      ) {
        activeColor = color.defaultHex;
      }

      const complementHex = getComplementaryHex(activeColor);

      root.style.setProperty(`${color.variable}-complement`, complementHex);
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
        exec("cat /sys/class/power_supply/battery/temp 2>/dev/null || echo 0"),
        exec(
          "cat /sys/class/power_supply/battery/voltage_now 2>/dev/null || echo 0",
        ),
        exec(
          "cat /sys/class/power_supply/battery/current_now 2>/dev/null || echo 0",
        ),
        exec("acc -D"),
        exec(`cat ${CONFIG_PATH} 2>/dev/null`),
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
    let shutdownVal = null;
    if (capacityMatch?.[1]) {
      const parts = capacityMatch[1].trim().split(/\s+/);
      resumeVal = parseInt(parts[2]);
      pauseVal = parseInt(parts[3]);
      shutdownVal = parseInt(parts[0]);
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
        shutdownVal !== null &&
        !isNaN(resumeVal) &&
        !isNaN(pauseVal) &&
        !isNaN(shutdownVal)
      ) {
        resumeThresh = resumeVal;
        pauseThresh = pauseVal;
        shutdownThresh = shutdownVal;
      }

      if (resetBattStatsMatch?.[1]) {
        const params = resetBattStatsMatch[1].trim().split(/\s+/);
        rbsp = params[0] === "true"; // Index 0: Pause
        rbsu = params[1] === "true"; // Index 1: Unplug
        rbspl = params[2] === "true"; // Index 2: Plug
      }
      initialLoad = false;
    }
  }

  let debounceTimeout;

  function handleSliderChange(type) {
    if (type === "shutdown") {
      if (shutdownThresh > 20) shutdownThresh = 20;
      if (shutdownThresh < 0) shutdownThresh = 0;

      if (resumeThresh <= shutdownThresh) {
        resumeThresh = shutdownThresh + 1;
      }

      if (pauseThresh <= resumeThresh) {
        pauseThresh = resumeThresh + 1;
        if (pauseThresh > 100) pauseThresh = 100;
      }
    }

    if (type === "resume") {
      if (resumeThresh < 1) resumeThresh = 1;
      if (resumeThresh > 99) resumeThresh = 99;

      if (pauseThresh <= resumeThresh) {
        pauseThresh = resumeThresh + 1;
        if (pauseThresh > 100) {
          pauseThresh = 100;
          resumeThresh = 99;
        }
      }

      if (shutdownThresh >= resumeThresh) {
        shutdownThresh = resumeThresh - 1;
        if (shutdownThresh < 0) shutdownThresh = 0;
      }
    }

    if (type === "pause") {
      if (pauseThresh < 2) pauseThresh = 2;
      if (pauseThresh > 100) pauseThresh = 100;

      if (resumeThresh >= pauseThresh) {
        resumeThresh = pauseThresh - 1;

        if (shutdownThresh >= resumeThresh) {
          shutdownThresh = resumeThresh - 1;
          if (shutdownThresh < 0) shutdownThresh = 0;
        }
      }
    }

    clearTimeout(debounceTimeout);
    debounceTimeout = setTimeout(async () => {
      const res = await exec(
        `/dev/acca -s sc=${shutdownThresh} rc=${resumeThresh} pc=${pauseThresh}`,
      );
      if (res.errno === 0) {
        await requireDaemonRestart();
      }
    }, 450);
  }

  async function toggleSetting(key, checked) {
    const val = checked ? "true" : "false";

    const res = await exec(`/dev/acca -s ${key}=${val}`);

    if (res.errno !== 0) {
      console.error(`Failed to set ${key}:`, res.stderr);
      await updateStatus();
    } else {
      await requireDaemonRestart();
    }
  }

  function controlDaemon(action) {
    isTransitioning = true;
    daemonStatus = `${action.toUpperCase()}${action === "stop" ? "PING..." : "ING..."}`;

    clearDaemonRestart();

    setTimeout(() => {
      const runExec = async () => {
        try {
          if (action === "stop") {
            await exec("/dev/acca -D stop");
          } else {
            await exec(`
              nohup /dev/acca -D ${action} >/dev/null 2>&1 &
              sleep 0.5

              pgrep -f accd | while read -r PID; do
                if [ -n "$PID" ]; then
                  # 1. Move to Root Cgroup (Unified / Freezer)
                  echo $PID > /sys/fs/cgroup/cgroup.procs 2>/dev/null || \
                  echo $PID > /dev/freezer/tasks 2>/dev/null || \
                  echo $PID > /sys/fs/cgroup/freezer/tasks 2>/dev/null || true

                  # 2. Force cpuset to Root (:/)
                  echo $PID > /dev/cpuset/tasks 2>/dev/null || \
                  echo $PID > /sys/fs/cgroup/cpuset/tasks 2>/dev/null || true

                  # 3. Force schedtune / stune to Root (:/)
                  echo $PID > /dev/stune/tasks 2>/dev/null || \
                  echo $PID > /dev/schedtune/tasks 2>/dev/null || \
                  echo $PID > /sys/fs/cgroup/schedtune/tasks 2>/dev/null || true
                fi
              done
            `);
          }
        } catch (e) {
          console.error("Daemon control error:", e);
        }

        setTimeout(async () => {
          isTransitioning = false;
          await updateStatus();

          await updateModuleDescription(action === "stop" ? "❌" : "✅");
        }, 2500);
      };
      runExec();
    }, 150);
  }

  async function updateModuleDescription(status) {
    try {
      await exec(`
        sed -i "/^description=/ {
          s@^description=.*Extend@description=[accd ${status}] | 🟢 ${resumeThresh}% | 🟡 ${pauseThresh}% | 🔴 ${shutdownThresh}% | Extend@
        }" "${PROP_PATH}"
      `);
    } catch (e) {
      console.error("Failed to update module description:", e);
    }
  }

  async function toggleEditor() {
    isEditorOpen = !isEditorOpen;
    if (isEditorOpen) {
      const res = await exec(`cat ${CONFIG_PATH} 2>/dev/null`);
      configText = res.stdout || "";
      originalConfigText = configText;
    }
  }

  async function saveRawConfig() {
    if (isSaving) return;

    if (!isConfigDirty) {
      showToast("No changes to save.");
      return;
    }

    isSaving = true;
    saveButtonText = "Saving...";

    try {
      const sanitizedText = configText.replace(/'/g, "'\\''");
      await exec(`echo '${sanitizedText}' > ${CONFIG_PATH}`);
      initialLoad = true;
      await updateStatus();
      await requireDaemonRestart();

      originalConfigText = configText;
      saveButtonText = "Saved! ✓";
    } catch (e) {
      console.error("Failed to save config:", e);
      saveButtonText = "Error Saving";
    } finally {
      setTimeout(() => {
        saveButtonText = "Save Config";
        isSaving = false;
      }, 2000);
    }
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
      const res = await exec("tail -n 50 /data/adb/vr25/acc-data/logs/*.log");
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

  async function exportLogs() {
    if (isExportingLogs) return;

    isExportingLogs = true;

    try {
      await exec(`rm -f ${EXPORT_FLAG}`);

      await exec(
        `sh -c '(/dev/acca -le; touch ${EXPORT_FLAG}) >/dev/null 2>&1 &'`,
      );

      let attempts = 0;
      const maxAttempts = 60;

      while (attempts < maxAttempts) {
        await new Promise((resolve) => setTimeout(resolve, 500));
        attempts++;

        const checkFlag = await exec(
          `[ -f ${EXPORT_FLAG} ] && echo "done" || true`,
        );

        if (checkFlag.stdout?.trim() === "done") {
          break;
        }
      }

      await exec(`rm -f ${EXPORT_FLAG}`);

      const checkFile = await exec(
        "find /storage/emulated/0/Download /sdcard/Download -name 'acc-logs*' -mmin -2 2>/dev/null | head -n 1",
      );

      const archive_path = checkFile.stdout ? checkFile.stdout.trim() : "";

      if (archive_path) {
        showToast(`Exported to ${archive_path}`);
      } else {
        showToast("Export failed (no archive created)");
      }
    } catch (e) {
      showToast("Error exporting logs");
    } finally {
      isExportingLogs = false;
    }
  }

  function showToast(message, duration = 4000) {
    if (toastTimeout) clearTimeout(toastTimeout);
    toastMessage = message;
    isToastVisible = true;

    toastTimeout = setTimeout(() => {
      isToastVisible = false;
    }, duration);
  }

  async function checkBannerState() {
    const res = await exec(`[ -f ${RESTART_FLAG} ] && echo "yes"`);
    if (res.stdout?.trim() === "yes") {
      isBannerOpen = true;
    }
  }

  async function requireDaemonRestart() {
    isBannerOpen = true;
    await exec(`touch ${RESTART_FLAG}`);
  }

  async function clearDaemonRestart() {
    isBannerOpen = false;
    await exec(`rm -f ${RESTART_FLAG}`);
  }

  onMount(() => {
    setupComplementaryColors();
    detectEnvironment();
    checkBannerState();
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
        <linearGradient id="liquid-gradient" x1="0%" y1="0%" x2="0%" y2="100%">
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

        <pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse">
          <path d="M 40 0 L 0 0 0 40" fill="none" />
        </pattern>

        <mask id="jug-interior-clip">
          <rect x="10" y="10" width="80" height="160" rx="14" fill="#ffffff" />
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
        <span class="card-title">Voltage</span><span class="mi-icon">bolt</span>
      </div>
      <div id="bat-voltage" class="card-value">{voltage}</div>
    </div>
  </div>

  <!-- Daemon (accd) -->
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

  <!-- Charging Thresholds -->
  <section class="m3-card">
    <div class="header-group">
      <span class="mi-icon">battery_charging_full</span>
      <div class="section-title">Charging Thresholds</div>
    </div>

    <div class="slider-wrapper">
      <div class="flex justify-between">
        <div class="label-text">Resume At</div>
        <div class="thresh-label">{resumeThresh}%</div>
      </div>
      <div class="slider-container resume" style="--percent: {resumeThresh}%;">
        <input
          type="range"
          min="0"
          max="100"
          step="1"
          bind:value={resumeThresh}
          oninput={() => handleSliderChange("resume")}
        />
        <div class="slider-track-visual">
          <div class="slider-track-fill"></div>
        </div>
      </div>
    </div>

    <div class="slider-wrapper stop-spacing">
      <div class="flex justify-between">
        <div class="label-text">Pause At</div>
        <div class="thresh-label">{pauseThresh}%</div>
      </div>
      <div class="slider-container pause" style="--percent: {pauseThresh}%;">
        <input
          type="range"
          min="0"
          max="100"
          step="1"
          bind:value={pauseThresh}
          oninput={() => handleSliderChange("pause")}
        />
        <div class="slider-track-visual">
          <div class="slider-track-fill"></div>
        </div>
      </div>
    </div>

    <div class="slider-wrapper stop-spacing">
      <div class="flex justify-between">
        <div class="label-text">Shutdown At</div>
        <div class="thresh-label">{shutdownThresh}%</div>
      </div>
      <div
        class="slider-container shutdown"
        style="--percent: {shutdownThresh}%;"
      >
        <input
          type="range"
          min="0"
          max="100"
          step="1"
          bind:value={shutdownThresh}
          oninput={() => handleSliderChange("shutdown")}
        />
        <div class="slider-track-visual">
          <div class="slider-track-fill"></div>
        </div>
      </div>
    </div>
  </section>

  <!-- Reset Battery Stats -->
  <section class="m3-card">
    <div class="header-group">
      <span class="mi-icon">loop</span>
      <div class="section-title">Reset Battery Stats</div>
    </div>

    <!-- On Pause -->
    <div class="setting-row">
      <div class="label-text">On Pause</div>
      <label class="m3-switch">
        <input
          type="checkbox"
          bind:checked={rbsp}
          onchange={(e) => toggleSetting("rbsp", e.target.checked)}
        />
        <span class="slider"></span>
      </label>
    </div>

    <!-- On Unplug -->
    <div class="setting-row">
      <div class="label-text">On Unplug</div>
      <label class="m3-switch">
        <input
          type="checkbox"
          bind:checked={rbsu}
          onchange={(e) => toggleSetting("rbsu", e.target.checked)}
        />
        <span class="slider"></span>
      </label>
    </div>

    <!-- On Plug -->
    <div class="setting-row">
      <div class="label-text">On Plug</div>
      <label class="m3-switch">
        <input
          type="checkbox"
          bind:checked={rbspl}
          onchange={(e) => toggleSetting("rbspl", e.target.checked)}
        />
        <span class="slider"></span>
      </label>
    </div>
  </section>

  <!-- Config File -->
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
          class="editor-textarea viewer-spacing"
          spellcheck="false"
          bind:value={configText}
        ></textarea>
        <div class="btn-row">
          <button
            onclick={saveRawConfig}
            class="m3-btn btn-primary m3-btn-centered m3-btn-full"
            disabled={isSaving}
          >
            <span>{saveButtonText}</span>
          </button>
        </div>
      </div>
    {/if}
  </section>

  <!-- Logs -->
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
        <div id="logs-content" class="log-box viewer-spacing">
          {logsContent}
        </div>

        <div class="btn-row">
          <button
            onclick={exportLogs}
            disabled={isExportingLogs}
            class="m3-btn btn-primary m3-btn-centered m3-btn-full"
          >
            {#if isExportingLogs}
              <span class="btn-leading-icon">
                <span class="m3-spinner"></span>
              </span>
              <span>Exporting...</span>
            {:else}
              <span>Export Logs</span>
            {/if}
          </button>
        </div>
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
        <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor">
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

  {#if isToastVisible}
    <div
      class="m3-toast"
      style="bottom: {isBannerOpen
        ? 'calc(var(--window-inset-bottom, 0px) + 96px)'
        : 'calc(var(--window-inset-bottom, 0px) + 16px)'}; transition: bottom 0.3s cubic-bezier(0.4, 0, 0.2, 1);"
      transition:fly={{ y: 100, duration: 300, easing: cubicOut }}
    >
      <div style="display: flex; align-items: center; gap: 12px; width: 100%;">
        <span
          class="mi-icon"
          style="font-size: 20px; color: var(--md-sys-color-primary); flex-shrink: 0;"
        >
          info
        </span>
        <span style="flex-grow: 1; word-break: break-word;">{toastMessage}</span
        >
      </div>
    </div>
  {/if}

  {#if isBannerOpen}
    <div
      id="restart-banner"
      class="notification-banner"
      transition:fly={{ y: 100, duration: 300, easing: cubicOut }}
    >
      <div class="notification-content">
        <span
          class="mi-icon"
          style="font-size: 20px; color: var(--md-sys-color-primary);"
        >
          restart_alt
        </span>
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
  /* =========================================
     1. Variables & Global Resets
     ========================================= */
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
  }

  :global(html),
  :global(body) {
    margin: 0;
    padding: 0;
    min-height: 100%;
  }

  :global(body) {
    background-color: var(--md-sys-color-bg) !important;
    color: var(--md-sys-color-on-background);
    padding: 12px;
    box-sizing: border-box;
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

  /* =========================================
     2. Layout Utilities
     ========================================= */
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

  .card-header,
  .header-row,
  .setting-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .card-header {
    margin-bottom: 8px;
  }
  .header-row {
    width: 100%;
    margin-bottom: 12px;
  }
  .setting-row {
    padding: 12px 0;
    border-bottom: 1px solid var(--md-sys-color-outline);
  }
  .setting-row:last-child {
    border-bottom: none;
  }

  .title-group,
  .header-group,
  .notification-content {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .notification-content {
    gap: 12px;
  }
  .header-group {
    margin-bottom: 12px;
  }

  /* =========================================
     3. Shared Glassmorphic Surfaces
     ========================================= */
  /* A. Base Cards & Banners (45% Opacity) */
  .module-banner-wrap,
  .m3-card,
  .github-footer-banner {
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
    box-sizing: border-box;
    width: 100%;
    margin-bottom: 12px;
  }

  .module-banner-wrap {
    overflow: hidden;
  }
  .module-banner-wrap svg {
    display: block;
    width: 100%;
    height: auto;
  }

  .m3-card {
    padding: 20px;
    -webkit-user-select: none;
    user-select: none;
  }

  .github-footer-banner {
    display: flex;
    align-items: center;
    justify-content: space-between;
    text-decoration: none;
    padding: 20px;
    margin: 0; /* Overrides the base 12px margin */
    transition:
      background-color 0.2s cubic-bezier(0.2, 0.8, 0.2, 1),
      transform 0.1s;
    -webkit-user-select: none;
    user-select: none;
  }
  .github-footer-banner:hover {
    background: color-mix(
      in srgb,
      var(--md-sys-color-surface-container) 60%,
      transparent
    );
  }
  .github-footer-banner:active {
    transform: scale(0.98);
    background: color-mix(
      in srgb,
      var(--md-sys-color-surface-variant) 70%,
      transparent
    );
  }

  /* B. Floating Overlays (88% Opacity) */
  .notification-banner,
  .m3-toast {
    display: flex;
    align-items: center;
    position: fixed;
    bottom: calc(var(--window-inset-bottom, 0px) + 16px);
    left: 12px;
    right: 12px;
    margin: 0 auto;
    width: auto;
    max-width: 600px;
    padding: 16px 20px;
    box-sizing: border-box;
    border-radius: 24px;
    box-shadow: 0 12px 36px 0 rgba(0, 0, 0, 0.45);
    background: color-mix(
      in srgb,
      var(--md-sys-color-surface-container) 88%,
      transparent
    );
    backdrop-filter: blur(24px);
    -webkit-backdrop-filter: blur(24px);
  }

  .notification-banner {
    justify-content: space-between;
    gap: 12px;
    z-index: 999;
    border: 1px solid
      color-mix(in srgb, var(--md-sys-color-outline) 50%, transparent);
  }

  .m3-toast {
    justify-content: center;
    z-index: 9999;
    border: 1px solid
      color-mix(in srgb, var(--md-sys-color-outline) 50%, transparent);
    color: var(--md-sys-color-on-surface);
    font-size: 14px;
    font-weight: 500;
    text-align: center;
    pointer-events: none;
    white-space: normal;
    word-break: normal;
    overflow-wrap: break-word;
  }

  /* =========================================
     4. Viewers (Textarea & Logs)
     ========================================= */
  .collapsible-box {
    overflow: hidden;
    width: 100%;
    margin-top: 12px;
  }

  /* Consolidate shared viewer properties */
  .editor-textarea,
  .log-box {
    display: block;
    width: 100%;
    height: 400px;
    box-sizing: border-box;
    padding: 16px;
    border-radius: 20px;
    border: 1px solid var(--md-sys-color-outline);
    background: var(--md-sys-color-surface-variant) !important;
    font-family: "SF Mono", "Roboto Mono", monospace;
    outline: none;
    margin-bottom: 0;
  }

  .editor-textarea {
    color: var(--dynamic-editor-text) !important;
    font-size: 14px;
    line-height: 1.5;
    resize: vertical;
    transition: border-color 0.2s cubic-bezier(0.2, 0.8, 0.2, 1);
  }
  .editor-textarea:focus {
    border-color: var(--md-sys-color-primary) !important;
    box-shadow: 0 0 0 1px var(--md-sys-color-primary) !important;
  }

  .log-box {
    color: var(--dynamic-log-text);
    font-size: 13px;
    line-height: 1.45;
    overflow-y: auto;
    white-space: pre-wrap;
  }

  .viewer-spacing {
    margin-bottom: 0 !important;
  }

  /* =========================================
     5. Typography & Text Labels
     ========================================= */
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
  .thresh-label {
    font-weight: 700;
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

  .notification-text {
    font-size: 14px;
    font-weight: 500;
    color: var(--md-sys-color-on-error-container);
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

  /* =========================================
     6. Buttons
     ========================================= */
  .btn-row {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    margin-top: 16px !important;
    margin-bottom: 4px !important;
    padding-bottom: 0 !important;
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

  .m3-btn-centered {
    position: relative;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    height: 40px;
    padding: 0 24px;
    box-sizing: border-box;
  }
  .m3-btn-centered .btn-leading-icon {
    position: absolute;
    left: 16px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
  }

  .m3-btn-full {
    width: 100%;
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
    background: color-mix(
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

  .btn-notification-action {
    background: color-mix(
      in srgb,
      var(--md-sys-color-primary) 85%,
      transparent
    );
    color: var(--md-sys-color-on-primary);
    border: 1px solid
      color-mix(in srgb, var(--md-sys-color-outline) 30%, transparent);
    backdrop-filter: blur(12px);
    -webkit-backdrop-filter: blur(12px);
    box-shadow: 0 4px 12px 0 rgba(0, 0, 0, 0.2);
    font-weight: 700;
    padding: 8px 16px;
    border-radius: 100px;
    cursor: pointer;
    flex: none;
    transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
  }
  .btn-notification-action:active:not(:disabled) {
    transform: scale(0.95);
    background: var(--md-sys-color-primary);
  }

  /* Disabled States */
  button:disabled,
  .btn-notification-action:disabled,
  #btn-banner-restart:disabled,
  #btn-notification-restart:disabled {
    cursor: not-allowed;
  }
  button:disabled {
    opacity: 0.25 !important;
  }
  .btn-notification-action:disabled,
  #btn-banner-restart:disabled,
  #btn-notification-restart:disabled {
    pointer-events: none;
    opacity: 0.5;
  }

  /* =========================================
     7. Controls (Switches & Sliders)
     ========================================= */
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

  .slider-wrapper {
    margin-bottom: 16px;
  }
  .stop-spacing {
    margin-top: 24px;
    margin-bottom: 0;
  }

  /* Base Slider Container */
  .slider-container {
    position: relative;
    width: 100%;
    margin-top: 16px;
    height: 24px;
    display: flex;
    align-items: center;
  }

  /* Resume Slider Electric Effect */
  .slider-container.resume {
    --neon-glow: rgba(0, 255, 102, 0.4);
    --electric-gradient: linear-gradient(
      to right,
      var(--md-sys-color-primary),
      #00ff66,
      #e0ffec,
      #00ff66,
      var(--md-sys-color-primary)
    );
  }

  /* Pause Slider Electric Effect */
  .slider-container.pause {
    --neon-glow: rgba(255, 235, 59, 0.5);
    --electric-gradient: linear-gradient(
      to right,
      var(--md-sys-color-primary),
      #ffea00,
      #ffffcc,
      #ffea00,
      var(--md-sys-color-primary)
    );
  }

  /* Shutdown Slider Electric Effect */
  .slider-container.shutdown {
    --neon-glow: rgba(255, 0, 85, 0.4);
    --electric-gradient: linear-gradient(
      to right,
      var(--md-sys-color-primary),
      #ff0055,
      #ffe0eb,
      #ff0055,
      var(--md-sys-color-primary)
    );
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

  /* Must keep webkit and moz separate */
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

  /* =========================================
     8. Misc (Icons, Spinners, Ambient Background)
     ========================================= */
  .footer-left-group {
    display: flex;
    align-items: center;
    gap: 16px;
  }
  .footer-right-group {
    display: flex;
    align-items: center;
    gap: 8px;
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

  .mi-icon,
  .open-icon {
    font-family: "Material Icons";
    color: var(--md-sys-color-primary);
  }
  .mi-icon {
    font-size: 20px;
    opacity: 0.9;
  }
  .open-icon {
    font-size: 20px;
    opacity: 0.8;
    padding-right: 4px;
  }
  .warning-icon {
    color: var(--md-sys-color-on-error-container);
  }

  .m3-spinner {
    width: 18px;
    height: 18px;
    border: 2.5px solid rgba(255, 255, 255, 0.2);
    border-top-color: currentColor;
    border-radius: 50%;
    display: inline-block;
    box-sizing: border-box;
    will-change: transform;
    transform: translateZ(0);
    animation: m3-spin 0.8s linear infinite;
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

  /* Status Pill Colors */
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

  /* =========================================
     9. Keyframes
     ========================================= */
  @keyframes m3-spin {
    0% {
      transform: rotate(0deg);
    }
    100% {
      transform: rotate(360deg);
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
</style>
