<!--
SPDX-FileCopyrightText: 2026 Infiniti151
SPDX-License-Identifier: GPL-3.0-or-later
-->

<script>
  import { onMount, tick, untrack } from "svelte";
  import { fly, slide, fade, scale } from "svelte/transition";
  import { cubicOut } from "svelte/easing";
  import { listPackages, getPackagesInfo } from "kernelsu";
  import { version, acc_version } from "../package.json";
  import { t } from "./i18n.js";
  import { infoDescriptions } from "./utils/descriptions.js";
  import { exec } from "./utils/exec.js";
  import { toast } from "./stores/toast.svelte.js";
  import { banner } from "./stores/banner.svelte.js";
  import Toast from "./components/Toast.svelte";
  import BannerStack from "./components/BannerStack.svelte";
  import DropdownModal from "./components/DropdownModal.svelte";

  // =========================
  // Global
  // =========================
  const EXPORT_FLAG = "/data/local/tmp/acc_export_done";
  const CONFIG_PATH = "/data/adb/vr25/acc-data/config.txt";
  const DEFAULT_CONFIG_PATH = "/data/adb/modules/acc/default-config.txt";
  const PROP_PATH = "/data/adb/modules/acc/module.prop";

  const SCROLL_KEYS = [
    "acc_scroll_pos",
    "acc_log_scroll",
    "acc_editor_scroll",
    "acc_editor_height",
    "acc_testall_height",
    "acc_logs_height",
  ];
  const TIMESTAMP_KEY = "acc_last_unload";
  const MAX_AGE_MS = 6_000; // 6 seconds
  const isRotationRecovery = checkIsRotation();

  const TEST_LOG = "/data/local/tmp/acc_test_all.log";
  const TEST_HB = "/data/local/tmp/acc_test_all.hb"; // heartbeat touched by the page
  const TEST_KILLED = "/data/local/tmp/acc_test_all.killed"; // set when the watchdog stopped a test
  const TEST_HB_TIMEOUT = 20; // seconds without a heartbeat before the test is stopped
  const TEST_UNPLUG_POLLS = 2; // consecutive polls (~2 s) without a charger before stopping

  // move every accd process out of the app's cgroups
  const MOVE_ACCD_SH = `
    move_accd() {
      pgrep -f '[a]ccd' | while read -r PID; do
        [ -n "$PID" ] || continue
        echo $PID > /sys/fs/cgroup/cgroup.procs 2>/dev/null || echo $PID > /dev/freezer/tasks 2>/dev/null || echo $PID > /sys/fs/cgroup/freezer/tasks 2>/dev/null || true
        echo $PID > /dev/cpuset/tasks 2>/dev/null || echo $PID > /sys/fs/cgroup/cpuset/tasks 2>/dev/null || true
        echo $PID > /dev/stune/tasks 2>/dev/null || echo $PID > /dev/schedtune/tasks 2>/dev/null || echo $PID > /sys/fs/cgroup/schedtune/tasks 2>/dev/null || true
        echo -1000 > /proc/$PID/oom_score_adj 2>/dev/null || true
      done
    }
  `;

  const TEST_CHECK_CHARGER = true;

  const PLUG_SH = `
    plugged() {
      seen=0
      for d in /sys/class/power_supply/*; do
        t=$(cat $d/type 2>/dev/null)
        case "$t" in Battery|BMS|OTG) continue;; esac
        case "$d" in *[Oo][Tt][Gg]*|*source*) continue;; esac
        for k in $1; do
          [ -f $d/$k ] || continue
          seen=1
          [ "$(cat $d/$k 2>/dev/null)" = 1 ] && return 0
        done
      done
      # nothing exposes online/present, so we can't tell: don't block anything
      [ $seen = 0 ] && return 0
      # Android's own view, independent of node names
      dumpsys battery 2>/dev/null | grep -Eq '(AC|USB|Wireless|Dock) powered: true' && return 0
      return 1
    }
  `;

  const STATUS_CMD = `
    cat /sys/class/power_supply/battery/health 2>/dev/null || echo 0
    printf '\\x1E'
    cat /sys/class/power_supply/battery/temp 2>/dev/null || echo 0
    printf '\\x1E'
    cat /sys/class/power_supply/battery/voltage_now 2>/dev/null || echo 0
    printf '\\x1E'
    cat /sys/class/power_supply/battery/current_now 2>/dev/null || echo 0
    printf '\\x1E'
    if pgrep -f '[a]ccd' >/dev/null 2>&1; then echo "is running"; else echo "is not running"; fi
    printf '\\x1E'
    p=0
    for d in /sys/class/power_supply/*; do
      t=$(cat $d/type 2>/dev/null)
      case "$t" in Battery|BMS|OTG) continue;; esac
      case "$d" in *[Oo][Tt][Gg]*|*source*) continue;; esac
      for k in online present; do
        [ -f $d/$k ] || continue
        [ "$(cat $d/$k 2>/dev/null)" = 1 ] && { p=1; break 2; }
      done
    done
    if [ $p = 0 ]; then
      dumpsys battery 2>/dev/null | grep -Eq '(AC|USB|Wireless|Dock) powered: true' && p=1
    fi
    echo $p
    printf '\\x1E'
    f=/dev/.vr25/acc/.testingsw
    if [ -f $f ] && [ $(( $(date +%s) - $(stat -c %Y $f 2>/dev/null || echo 0) )) -lt 600 ]; then echo 1; else echo 0; fi
    printf '\\x1E'
    cat ${CONFIG_PATH} 2>/dev/null
  `;

  const SWITCH_BANNERS = {
    detecting: () => ({
      icon: "spinner",
      pulse: true,
      text: t("bannerDetectingSwitch"),
    }),
    stopped: () => ({
      icon: "warning",
      text: t("bannerDaemonStoppedNoSwitch"),
      actionLabel: t("testAll"),
      onAction: startTestAllFromBanner,
    }),
    select: () => ({
      icon: "warning",
      text: t("bannerSelectSwitch"),
      actionLabel: t("select"),
      onAction: () => (showSwitchModal = true),
    }),
    waiting: () => ({
      icon: "warning",
      text: t("bannerChargerConnected"),
    }),
    none: () => ({
      icon: "warning",
      text: t("bannerNoSwitchFound"),
    }),
  };

  // Fresh start: drop old scroll positions
  if (!isRotationRecovery) {
    SCROLL_KEYS.forEach((key) => localStorage.removeItem(key));
  }

  const SLIDE_PROPS = [
    "height",
    "padding-top",
    "padding-bottom",
    "margin-top",
    "margin-bottom",
    "border-top-width",
    "border-bottom-width",
  ];

  // Background Polling Timer
  let statusPollInterval = null;

  // Button Description State
  let activeDescriptions = $state(load("activeDescriptions", {}));

  const yieldToUI = (ms = 30) => new Promise((r) => setTimeout(r, ms));

  function toggleDescription(key) {
    activeDescriptions[key] = !activeDescriptions[key];
  }

  function startTestAllFromBanner() {
    if (testAllState === "done") testAllState = "idle"; // a finished run has to be reset first
    handleTestAll();
  }

  function slideNoFade(node, { duration = 300, easing = cubicOut } = {}) {
    const s = getComputedStyle(node);
    const sizes = SLIDE_PROPS.map((p) => [
      p,
      parseFloat(s.getPropertyValue(p)) || 0,
    ]);

    return {
      duration,
      easing,
      css: (t) =>
        "overflow: hidden;" +
        sizes.map(([p, v]) => `${p}: ${t * v}px`).join(";"),
    };
  }

  function scrollToMatch(view, index) {
    const mark = view?.querySelectorAll("mark.search-highlight")[index];
    if (!mark) return;

    const viewRect = view.getBoundingClientRect();
    const markRect = mark.getBoundingClientRect();

    // Center the active mark in the view
    view.scrollTop +=
      markRect.top - viewRect.top - viewRect.height / 2 + markRect.height / 2;
  }

  async function updateStatus() {
    const res = await exec(STATUS_CMD);
    if (res.errno !== 0) {
      console.error(
        `exec failed with errno ${res.errno}:`,
        res.stderr || "Unknown error",
      );
    }
    const [
      healthRes,
      tempRes,
      voltRes,
      currRes,
      statRes,
      plugRes,
      tswRes,
      cfgRes,
    ] = (res.stdout || "").split("\x1E").map((s) => s.trim());

    const isValid =
      healthRes && healthRes !== "ksu not found" && healthRes !== "0";

    health = isValid ? healthRes : "N/A";

    if (!isValid) {
      temperature = voltage = current = "—";
    } else {
      const temp = parseInt(tempRes);
      const volt = parseInt(voltRes);
      const curr = parseInt(currRes);

      temperature = isNaN(temp)
        ? "—"
        : `${temp > 100 ? (temp / 10).toFixed(1) : temp} °C`;
      voltage = isNaN(volt)
        ? "—"
        : `${(volt > 100000 ? volt / 1e6 : volt / 1e3).toFixed(2)} V`;
      current = isNaN(curr) ? "—" : `${Math.floor(curr / 1000)} mA`;
    }

    const rawConfigText = cfgRes || "";
    const capacityMatch = rawConfigText.match(/^capacity=\(([^)]+)\)/m);
    const resetBattStatsMatch = rawConfigText.match(
      /^resetBattStats=\(([^)]+)\)/m,
    );
    const aiapcMatch = rawConfigText.match(/^allowIdleAbovePcap=(true|false)/m);
    const pbimMatch = rawConfigText.match(
      /^prioritizeBattIdleMode=(true|false|no)/m,
    );
    const omMatch = rawConfigText.match(/^offMid=(true|false)/m);
    const iaMatch = rawConfigText.match(/^idleApps\s*=\s*(.*)/m);
    const switchMatch = rawConfigText.match(/^chargingSwitch=\(([^)]*)\)/m);
    const foMatch = rawConfigText.match(/^forceOff=(true|false)/m);

    let resumeVal = null;
    let pauseVal = null;
    let shutdownVal = null;
    if (capacityMatch?.[1]) {
      const parts = capacityMatch[1].trim().split(/\s+/);
      resumeVal = parseInt(parts[2]);
      pauseVal = parseInt(parts[3]);
      shutdownVal = parseInt(parts[0]);
    }

    isRunning = statRes.toLowerCase().includes("is running");
    statusReady = true;

    if (plugRes === "1") {
      isPlugged = true;
      unpluggedPolls = 0;
    } else if (++unpluggedPolls >= 2) {
      isPlugged = false;
    }

    if (tswRes === "1") {
      isAutoSelecting = true;
      lastTestingSw = Date.now();
    } else if (Date.now() - lastTestingSw > 10000) {
      isAutoSelecting = false; // 10s hold avoids flicker between switch cycles
    }

    if (!isTransitioning) {
      daemonStatus = isRunning ? t("running") : t("stopped");
    }

    if (initialLoad && rawConfigText) {
      if (keepRestoredEdits) {
        keepRestoredEdits = false; // one-shot: only the first load after rotation
      } else {
        configText = rawConfigText;
      }

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
      if (aiapcMatch?.[1]) {
        aiapc = aiapcMatch[1] === "true";
      }
      if (pbimMatch?.[1]) {
        pbim = pbimMatch[1] === "true";
      }
      if (omMatch?.[1]) {
        om = omMatch[1] === "true";
      }
      if (foMatch?.[1]) {
        fo = foMatch[1] === "true";
      }
      if (iaMatch) {
        let rawVal = iaMatch[1].trim();

        rawVal = rawVal.split("#")[0].trim();

        if (!rawVal || /^(null|""|''|\(\))$/i.test(rawVal)) {
          idleApps = [];
        } else {
          rawVal = rawVal.replace(/^["'(]+|[)"']+$/g, "").trim();

          idleApps = rawVal
            ? rawVal
                .split(/[\s,]+/)
                .map((s) => s.trim())
                .filter(Boolean)
            : [];
        }
      } else {
        idleApps = [];
      }
      initialLoad = false;
    }

    if (!isSavingSwitch) {
      const rawSwitch = switchMatch?.[1]?.trim() ?? "";
      // Strip any accidental remaining parentheses, quotes, or whitespace
      const cfgSwitch = rawSwitch.replace(/^[('"]+|[)'"]+$/g, "").trim();

      const wasEmpty = currentSwitch === "";
      currentSwitch = cfgSwitch;

      // ACC picked a switch on its own: refresh the working-switches list
      if (wasEmpty && cfgSwitch && switchesLoaded) loadChargingSwitches();
    }

    // Keep the module description in step with the real daemon state.
    // Thresholds are loaded by now, and we skip while start/stop is in progress.
    if (!isTransitioning && !initialLoad) syncModuleDescription();
  }

  async function toggleSetting(key, checked) {
    const val = checked ? "true" : "false";

    const res = await exec(`/dev/acca -s ${key}=${val}`);

    if (res.errno !== 0) {
      console.error(`Failed to set ${key}: `, res.stderr);
      await updateStatus();
    } else {
      await syncConfigEditor();
      await banner.requireRestart();
    }
  }

  $effect(() => {
    const mode = switchBannerMode;
    if (!mode) {
      untrack(() => banner.hide("switch"));
      return;
    }
    untrack(() =>
      banner.show("switch", { order: 0, ...SWITCH_BANNERS[mode]() }),
    );
  });

  // ======================================
  // Scroll & State Orientation Persistence
  // ======================================
  const handleLogScroll = createDebouncedScrollHandler("acc_log_scroll");
  const handleEditorScroll = createDebouncedScrollHandler("acc_editor_scroll");
  const lastSaved = new Map();
  let hasRestoredScroll = false;
  let hasRestoredLogScroll = false;
  let hasRestoredEditorScroll = false;

  // Calculate if this is a quick rotation recovery
  function checkIsRotation() {
    try {
      const raw = localStorage.getItem(TIMESTAMP_KEY);
      if (!raw) return false;
      const age = Date.now() - parseInt(raw, 10);
      return age < MAX_AGE_MS;
    } catch (_) {
      return false;
    }
  }

  // Read a persisted value. On a fresh start, always use the fallback.
  // The fallback's type decides how it's parsed (string stays raw, the rest is JSON).
  function load(key, fallback) {
    if (!isRotationRecovery) return fallback;
    try {
      const raw = localStorage.getItem(key);
      if (raw === null) return fallback;
      return typeof fallback === "string" ? raw || fallback : JSON.parse(raw);
    } catch (_) {
      return fallback;
    }
  }

  function saveUnloadTime() {
    localStorage.setItem(TIMESTAMP_KEY, Date.now().toString());
  }

  function createDebouncedScrollHandler(storageKey) {
    let timeout;
    return function (e) {
      clearTimeout(timeout);
      timeout = setTimeout(() => {
        const el = e.target;
        const maxScroll = el.scrollHeight - el.clientHeight;
        if (maxScroll <= 0) return;

        const ratio = el.scrollTop / maxScroll;
        localStorage.setItem(storageKey, ratio.toString());
      }, 150);
    };
  }

  function restoreContainerScroll(el, key) {
    if (!el) return;
    const saved = localStorage.getItem(key);
    if (saved === null) return;

    const ratio = parseFloat(saved);
    el.style.scrollBehavior = "auto";

    requestAnimationFrame(() => {
      const maxScroll = el.scrollHeight - el.clientHeight;
      if (maxScroll > 0) {
        el.scrollTop = Math.round(ratio * maxScroll);
      }
      el.style.scrollBehavior = "";
    });
  }

  function scrollCardIntoView(el) {
    const card = el?.closest(".m3-card");
    if (!card) return;

    card.scrollIntoView({
      behavior: "smooth",
      block: "center",
    });
  }

  function resizable(node, storageKey) {
    const saved = localStorage.getItem(storageKey);
    if (saved) {
      node.style.height = saved;
    }

    let timeout;
    const observer = new ResizeObserver(() => {
      clearTimeout(timeout);
      timeout = setTimeout(() => {
        if (node.style.height) {
          localStorage.setItem(storageKey, node.style.height);
        }
      }, 200);
    });
    observer.observe(node);

    return {
      destroy() {
        observer.disconnect();
      },
    };
  }

  // --- State persistence ---
  $effect(() => {
    const persisted = {
      testAllState,
      testAllLogs,
      testAllPid,
      testWasRunning,
      showAppModal,
      showSystemApps,
      searchQuery,
      userAppsList,
      systemAppsList,
      selectedApps,
      isEditorOpen,
      configText,
      originalConfigText,
      isConfigSearchOpen,
      configSearchQuery,
      configMatchIndex,
      configHistory,
      configHistoryIndex,
      isLogsOpen,
      activeLogType,
      logsContent,
      isLogsPolling,
      isLogsSearchOpen,
      logsSearchQuery,
      logsMatchIndex,
      activeDescriptions,
    };

    for (const [key, value] of Object.entries(persisted)) {
      try {
        const v = $state.snapshot(value);
        const str = typeof v === "string" ? v : JSON.stringify(v);
        if (lastSaved.get(key) === str) continue;
        localStorage.setItem(key, str);
        lastSaved.set(key, str);
      } catch (e) {
        console.error(`Failed to persist ${key}:`, e);
      }
    }
  });

  // --- WebUI scroll persistence ---
  $effect(() => {
    if (isRotationRecovery && !hasRestoredScroll) {
      const savedScroll = localStorage.getItem("acc_scroll_pos");

      if (savedScroll !== null) {
        tick().then(() => {
          window.scrollTo({
            top: parseInt(savedScroll, 10),
            behavior: "instant",
          });
        });
      }
      hasRestoredScroll = true;
    }
  });

  // --- Config scroll persistence (with delay for rotation stability) ---
  $effect(() => {
    if (
      !isRotationRecovery ||
      hasRestoredEditorScroll ||
      !isEditorOpen ||
      !editorScroller ||
      !configText
    )
      return;

    hasRestoredEditorScroll = true;
    setTimeout(() => {
      restoreContainerScroll(editorScroller, "acc_editor_scroll");
    }, 50);
  });

  // --- Logs scroll persistence ---
  $effect(() => {
    if (
      !isRotationRecovery ||
      hasRestoredLogScroll ||
      !isLogsOpen ||
      !logContainer ||
      !logsContent ||
      logsContent === "Loading logs..."
    )
      return;

    hasRestoredLogScroll = true;
    restoreContainerScroll(logContainer, "acc_log_scroll");
  });

  // =========================
  // Battery Banner
  // =========================
  let initialLoad = $state(true);
  let currentEnv = $state(t("detectingEnvironment"));

  let fillPercentage = $derived(Math.min(Math.max(pauseThresh || 0, 0), 100));
  let fluidHeight = $derived((160 * fillPercentage) / 100);
  let fluidY = $derived(170 - fluidHeight);

  let wavePath1 = $derived(
    `M 10 ${fluidY} Q 30 ${fluidY - 4}, 50 ${fluidY} T 90 ${fluidY} L 90 170 L 10 170 Z`,
  );
  let wavePath2 = $derived(
    `M 10 ${fluidY} Q 30 ${fluidY + 4}, 50 ${fluidY} T 90 ${fluidY} L 90 170 L 10 170 Z`,
  );

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
      {
        name: "on-primary",
        variable: "--md-sys-color-on-primary",
        defaultHex: "#000000",
      },
      {
        name: "on-secondary",
        variable: "--md-sys-color-on-secondary",
        defaultHex: "#3A3005",
      },
      {
        name: "on-tertiary",
        variable: "--md-sys-color-on-tertiary",
        defaultHex: "#441A0E",
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

  async function detectEnvironment() {
    currentEnv = t("checking");
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
    const res = await exec(cmd);
    if (res.errno === 0 && res.stdout) {
      currentEnv = res.stdout;
    } else {
      currentEnv = t("error");
    }
  }

  // =========================
  // Battery Stats
  // =========================
  let health = $state("--");
  let temperature = $state("--");
  let voltage = $state("--");
  let current = $state("--");

  // =========================
  // Daemon Status
  // =========================
  let lastDescStatus = null;
  let isRunning = $state(false);
  let isTransitioning = $state(false);
  let statusReady = $state(false);
  let daemonStatus = $state(t("checking"));

  let currentState = $derived(
    isTransitioning || !statusReady
      ? "transitioning"
      : isRunning
        ? "running"
        : "stopped",
  );

  function controlDaemon(action) {
    if (isSectionDisabled) return;
    isTransitioning = true;
    daemonStatus =
      action === "stop"
        ? t("stopping")
        : action === "restart"
          ? t("restarting")
          : t("starting");

    banner.clearRestart();

    setTimeout(() => {
      const runExec = async () => {
        try {
          let res;
          if (action === "stop") {
            res = await exec("/dev/acca -D stop");
          } else {
            res = await exec(`
              ${MOVE_ACCD_SH}
              setsid nohup /dev/acca -D ${action} >/dev/null 2>&1 < /dev/null &
              sleep 0.5
              move_accd
              # keep retrying for ~30s in the background to catch late starts
              ( n=0; while [ $n -lt 30 ]; do sleep 1; move_accd; n=$((n + 1)); done ) >/dev/null 2>&1 &
            `);
          }

          if (res.errno !== 0) {
            console.error(
              `Daemon control (${action}) failed [errno ${res.errno}]:`,
              res.stderr,
            );
          }
        } catch (e) {
          console.error("Daemon control error: ", e);
        }

        setTimeout(async () => {
          isTransitioning = false;
          await updateStatus();

          await syncModuleDescription(true);
        }, 2500);
      };
      runExec();
    }, 150);
  }

  async function updateModuleDescription(status) {
    try {
      const res = await exec(`
        sed -i "/^description=/ {
          s@^description=.*Extend@description=[accd ${status}] | 🟢 ${resumeThresh}% | 🟡 ${pauseThresh}% | 🔴 ${shutdownThresh}% | Extend@
        }" "${PROP_PATH}"
      `);
      if (res.errno !== 0) {
        console.error("Failed to update module description:", res.stderr);
      }
    } catch (e) {
      console.error("Failed to update module description: ", e);
    }
  }

  async function syncModuleDescription(force = false) {
    const status = isRunning ? "✅" : "❌";
    if (!force && status === lastDescStatus) return; // nothing changed, skip the write
    lastDescStatus = status;
    await updateModuleDescription(status);
  }

  // =========================
  // Charging Thresholds
  // =========================
  let resumeThresh = $state(85);
  let pauseThresh = $state(90);
  let shutdownThresh = $state(5);
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
        await syncConfigEditor();
        await banner.requireRestart();
      } else {
        console.error("Failed to update thresholds:", res.stderr);
        await updateStatus();
      }
    }, 450);
  }

  // =========================
  // Charging Switch
  // =========================
  let currentSwitch = $state("");
  let availableSwitches = $state([]);
  let switchesLoaded = $state(false);
  let isSavingSwitch = $state(false);
  let manualSwitchInput = $state("");
  let fo = $state(false);
  let testAllState = $state(load("testAllState", "idle")); // 'idle' | 'running' | 'done'
  let testAllLogs = $state(load("testAllLogs", t("initializingTest")));
  let testAllPid = $state(load("testAllPid", ""));
  let testWasRunning = $state(load("testWasRunning", false));
  let testAllInterval = null;
  let testAllPolling = false;
  let testAllContainer = $state();
  let switchCardRef = $state();
  let showSwitchModal = $state(false);
  let isPlugged = $state(false);
  let isAutoSelecting = $state(false);
  let lastTestingSw = 0;
  let unpluggedPolls = 0;
  let unplugStreak = 0;

  let matchingSwitches = $derived(
    availableSwitches.some((sw) => sw.value === currentSwitch),
  );
  let isSectionDisabled = $derived(testAllState === "running");

  let switchBannerMode = $derived.by(() => {
    if (
      !statusReady ||
      initialLoad ||
      !switchesLoaded ||
      isSectionDisabled ||
      isSaving ||
      isResetting ||
      isSavingSwitch
    )
      return null;

    // Suppress switch banners while a daemon restart is pending
    if (banner.items.some((b) => b.id === "restart")) return null;

    if (currentSwitch !== "") return null;

    const hasWorking = availableSwitches.length > 0;

    if (isRunning || isTransitioning) {
      // Must be plugged in to be detecting; ignores stale test files on disk when unplugged
      if (isPlugged && isAutoSelecting && unpluggedPolls < 3)
        return "detecting";
      if (isPlugged) return "waiting";
    } else if (isPlugged && !hasWorking) {
      return "stopped"; // nothing known yet: Test All is the way forward
    }

    return hasWorking ? "select" : "none";
  });

  let noSwitch = $derived(
    statusReady &&
      !initialLoad &&
      (currentSwitch === "" || currentSwitch === "Automatic"),
  );

  async function handleSelectSwitch(value) {
    if (value === currentSwitch) {
      toast.info(t("switchAlreadySelected"));
      return;
    }
    currentSwitch = value;
    await saveChargingSwitch();
  }

  async function loadChargingSwitches() {
    const res = await exec("/dev/acca -ss::");
    const output = (res.stdout || "") + (res.stderr || "");
    switchesLoaded = true;

    if (res.errno !== 0 && !output.includes("No such file or directory")) {
      console.error(
        `acca -ss:: failed [errno: ${res.errno}]:`,
        res.stderr || output,
      );
    }

    // Check if working-switches.log is missing or if output is empty
    if (output.includes("No such file or directory") || !res.stdout) {
      availableSwitches = [];
      return;
    }

    const lines = res.stdout.split("\n");
    availableSwitches = lines
      .map((line) => {
        const raw = line.trim();
        if (!raw) return null;

        // Matches standard format: "1) [i] battery/..."
        let match = raw.match(/^\s*\d+\)\s*\[([id])\]\s+(.*)$/);
        if (match) {
          return {
            type: match[1],
            value: match[2].trim(),
            label: `${match[2].trim()} [${match[1].toUpperCase()}] — ${match[1] === "i" ? t("idleModeSupported") : t("disableOnly")}`,
          };
        }

        // Matches bracket format: "[i] battery/..."
        match = raw.match(/^\[([id])\]\s+(.*)$/);
        if (match) {
          return {
            type: match[1],
            value: match[2].trim(),
            label: `${match[2].trim()} [${match[1].toUpperCase()}] — ${match[1] === "i" ? t("idleModeSupported") : t("disableOnly")}`,
          };
        }

        return { type: "?", value: raw, label: raw };
      })
      .filter((sw) => sw && sw.value.trim().length > 0);
  }

  async function saveChargingSwitch() {
    isSavingSwitch = true;

    try {
      const valToSet =
        currentSwitch === "Automatic" ? '""' : `"${currentSwitch}"`;

      const res = await exec(`/dev/acca -s s=${valToSet}`);

      if (res.errno === 0) {
        await banner.requireRestart();
        await updateStatus();
        await syncConfigEditor();
        toast.success(t("chargingSwitchUpdated"));
        await yieldToUI();
      } else {
        console.error("Failed to update charging switch:", res.stderr);
        toast.error(t("failedUpdateChargingSwitch"));
      }
    } catch (e) {
      console.error("Error saving charging switch:", e);
      toast.error(t("errorUpdatingChargingSwitch"));
    } finally {
      isSavingSwitch = false;
    }
  }

  async function applyManualSwitch() {
    if (!manualSwitchInput || isSavingSwitch) return;

    // If the user didn't manually append " --", do it for them to disable the automated fallback process
    let value = manualSwitchInput.trim();
    if (!value.endsWith("--")) value += " --";

    isSavingSwitch = true; // keeps the status poll from overwriting currentSwitch mid-save
    try {
      const res = await exec(`/dev/acca -s s="${value}"`);
      if (res.errno === 0) {
        currentSwitch = value;
        toast.success(t("manualSwitchApplied"));
        await updateStatus();
        await syncConfigEditor();
        await banner.requireRestart();
        await yieldToUI();
      } else {
        console.error(
          "Error applying manual charging switch: ",
          res.stderr || "Unknown error",
        );
        toast.error(t("failedApplyManualSwitch"));
      }
    } catch (e) {
      console.error("Error applying manual charging switch:", e);
      toast.error(t("failedApplyManualSwitch"));
    } finally {
      isSavingSwitch = false;
    }
  }

  function stopTestAllPolling() {
    clearInterval(testAllInterval);
    testAllInterval = null;
  }

  function startTestAllPolling() {
    stopTestAllPolling();
    testAllInterval = setInterval(pollTestAll, 2000);
    pollTestAll();
  }

  async function killTestAll(pid) {
    await exec(`
    [ -n "${pid}" ] && kill -TERM -- -${pid} 2>/dev/null
    i=0
    while kill -0 -- -${pid} 2>/dev/null && [ $i -lt 10 ]; do
      sleep 0.2
      i=$((i + 1))
    done
    [ -n "${pid}" ] && kill -KILL -- -${pid} 2>/dev/null

    # Fallbacks matching the real command lines (from your ps output)
    pkill -9 -f '/[a]cc/acc .* (-t|--test)( |$)' 2>/dev/null
    pkill -9 -f '[t]ee -a /sdcard/Download/acc-t_output' 2>/dev/null

    # What ACC's exit trap would normally do
    rm -f /dev/.vr25/acc/.testingsw
    rm -f ${TEST_LOG} ${TEST_HB}
  `);
  }

  async function restoreDaemonAfterTest() {
    const wasRunning = testWasRunning;
    testWasRunning = false;
    if (wasRunning)
      controlDaemon("start"); // also moves accd to the root cgroup
    else await updateStatus();
  }

  async function pollTestAll() {
    if (testAllPolling) return;
    testAllPolling = true;
    try {
      // touch = heartbeat for the watchdog
      const logRes = await exec(
        `touch ${TEST_HB}; cat ${TEST_LOG} 2>/dev/null`,
      );
      if (logRes.errno < 0) {
        console.error(
          `Log read bridge error [errno: ${logRes.errno}]:`,
          logRes.stderr,
        );
      }

      if (logRes.stdout && logRes.stdout !== testAllLogs) {
        const isNearBottom = testAllContainer
          ? testAllContainer.scrollHeight -
              testAllContainer.scrollTop -
              testAllContainer.clientHeight <
            50
          : true;

        testAllLogs = logRes.stdout;
        await tick();
        if (testAllContainer && isNearBottom) {
          testAllContainer.scrollTop = testAllContainer.scrollHeight;
        }
      }

      const pidCheck = await exec(`
  ${PLUG_SH}
  kill -0 ${testAllPid} 2>/dev/null && echo alive
  plugged "online present" && echo plugged
`);
      if (pidCheck.errno < 0) {
        console.error(
          `PID check bridge error [errno: ${pidCheck.errno}]:`,
          pidCheck.stderr,
        );
      }

      if (!pidCheck.stdout.includes("alive")) {
        stopTestAllPolling();
        const last = await exec(
          `cat ${TEST_LOG} 2>/dev/null; rm -f ${TEST_LOG} ${TEST_HB}`,
        );
        if (last.stdout) testAllLogs = last.stdout;
        testAllState = "done";
        await loadChargingSwitches();
        toast.success(t("testAllFinished"));
        await restoreDaemonAfterTest();
        return;
      }

      // Charger monitor
      if (TEST_CHECK_CHARGER) {
        unplugStreak = pidCheck.stdout.includes("plugged")
          ? 0
          : unplugStreak + 1;
        if (unplugStreak >= TEST_UNPLUG_POLLS) {
          unplugStreak = 0;
          stopTestAllPolling();
          await killTestAll(testAllPid);
          testAllState = "idle";
          toast.error(t("chargerDisconnectedTestStopped"));
          await restoreDaemonAfterTest();
        }
      }
    } finally {
      testAllPolling = false;
    }
  }

  async function handleTestAll() {
    if (testAllState === "idle") {
      // Is any power source connected? (dc / pc_port / usb / wireless)
      if (TEST_CHECK_CHARGER) {
        const plug = await exec(`${PLUG_SH} plugged online && echo yes`);
        if (!plug.stdout.includes("yes")) {
          toast.error(
            t("noChargerForTestAll"),
          );
          return;
        }
      }

      unplugStreak = 0;
      testWasRunning = isRunning;
      testAllState = "running";
      testAllLogs = `${t("testRunningCommand")}\n${t("testDurationNotice")}\n\n`;

      const res = await exec(`
      : > ${TEST_LOG}
      rm -f ${TEST_KILLED}
      touch ${TEST_HB}

      # The test gets its own session/process group so the whole tree can be stopped
      setsid nohup sh -c 'yes "" | /dev/acca -t' > ${TEST_LOG} 2>&1 &
      TPID=$!

      # Watchdog: no heartbeat from the WebUI (closed/killed) -> stop the test
      setsid nohup sh -c '
        while kill -0 '"$TPID"' 2>/dev/null; do
          now=$(date +%s)
          last=$(stat -c %Y ${TEST_HB} 2>/dev/null || echo 0)
          if [ $((now - last)) -gt ${TEST_HB_TIMEOUT} ]; then
            kill -TERM -- -'"$TPID"' 2>/dev/null
            sleep 3
            kill -KILL -- -'"$TPID"' 2>/dev/null
            rm -f ${TEST_LOG} ${TEST_HB}
            echo ${testWasRunning ? 1 : 0} > ${TEST_KILLED}
            break
          fi
          sleep 3
        done
      ' >/dev/null 2>&1 &

      echo $TPID
    `);

      if (res.errno !== 0 || !res.stdout) {
        console.error(
          `Failed to start background test process [errno: ${res.errno}]:`,
          res.stderr || "No PID returned",
        );
        testAllPid = "";
        testAllState = "idle";
        return;
      }

      testAllPid = res.stdout.trim();

      await tick();
      setTimeout(() => {
        if (switchCardRef) {
          scrollCardIntoView(switchCardRef);
        }
      }, 320);

      startTestAllPolling();
    } else if (testAllState === "running") {
      stopTestAllPolling();
      await killTestAll(testAllPid);
      testAllState = "idle";
      toast.warning(t("testAllCancelled"));
      await restoreDaemonAfterTest();
    } else if (testAllState === "done") {
      testAllState = "idle";
    }
  }

  $effect(() => {
    if (matchingSwitches) {
      manualSwitchInput = "";
    }
  });

  // =========================
  // Reset Battery Stats
  // =========================
  let rbsp = $state(false);
  let rbspl = $state(false);
  let rbsu = $state(false);

  // =========================
  // Idle Mode
  // =========================
  let aiapc = $state(true);
  let pbim = $state(true);
  let om = $state(true);
  let showAppModal = $state(load("showAppModal", false));
  let showSystemApps = $state(load("showSystemApps", false));
  let searchQuery = $state(load("searchQuery", ""));
  let userAppsList = $state(load("userAppsList", []));
  let systemAppsList = $state(load("systemAppsList", []));
  let selectedApps = $state(load("selectedApps", []));
  let idleApps = $state([]);
  let searchExpanded = $state(false);
  let iconsLoading = $state(false);
  let loadedIconCount = $state(0);
  let iconLoadTotal = $state(0);

  // Combine, filter by search query, and sort reactively based on the System Apps toggle
  const displayedApps = $derived(
    (showSystemApps
      ? [...userAppsList, ...systemAppsList]
      : [
          ...userAppsList,
          ...systemAppsList.filter(
            (app) =>
              idleApps.includes(app.pkg) || selectedApps.includes(app.pkg),
          ),
        ]
    )
      .filter((app) => {
        const query = searchQuery.trim().toLowerCase();
        if (!query) return true;
        return (
          app.name.toLowerCase().includes(query) ||
          app.pkg.toLowerCase().includes(query)
        );
      })
      .sort((a, b) => {
        // Compare against the saved state (idleApps)
        const aSelected = idleApps.includes(a.pkg);
        const bSelected = idleApps.includes(b.pkg);

        // Push already-saved apps above unselected apps
        if (aSelected && !bSelected) return -1;
        if (!aSelected && bSelected) return 1;

        // Fallback to alphabetical sorting by name
        return a.name.localeCompare(b.name);
      }),
  );

  async function saveIdleApps() {
    const isUnchanged =
      idleApps.length === selectedApps.length &&
      idleApps.every((app) => selectedApps.includes(app));

    if (isUnchanged) {
      showAppModal = false;
      toast.info(t("noChangesToApply"));
      return;
    }

    idleApps = [...selectedApps];
    showAppModal = false;

    const appString = idleApps.length > 0 ? idleApps.join(",") : '""';
    const res = await exec(`/dev/acca -s ia=${appString}`);
    if (res.errno === 0) {
      await syncConfigEditor();
      await banner.requireRestart();
    } else {
      console.error("Failed to update idle apps: ", res.stderr);
      toast.error(t("failedUpdateIdleApps"));
    }
  }

  function handleAppIconLoad() {
    loadedIconCount += 1;

    if (loadedIconCount >= iconLoadTotal) {
      iconsLoading = false;
    }
  }

  function handleAppIconError() {
    loadedIconCount += 1;

    if (loadedIconCount >= iconLoadTotal) {
      iconsLoading = false;
    }
  }

  async function openIdleAppsModal() {
    selectedApps = [...idleApps];
    searchQuery = "";
    searchExpanded = false;
    showAppModal = true;
    showSystemApps = false;

    if (userAppsList.length === 0) {
      iconsLoading = true;
      await tick();
      await yieldToUI();
      await loadInstalledApps();
    }
  }

  async function loadInstalledApps() {
    try {
      if (
        typeof listPackages !== "function" ||
        typeof getPackagesInfo !== "function"
      ) {
        console.error(
          "KernelSU package APIs are unavailable. App lists cannot be loaded.",
        );
        iconsLoading = false;
        return;
      }

      const userPkgs = listPackages("user") || [];
      if (userPkgs.length > 0) {
        const userInfos = getPackagesInfo(userPkgs) || [];
        userAppsList = userInfos.map((info) => ({
          pkg: info.packageName,
          name: info.appLabel || info.packageName,
          iconUrl: `ksu://icon/${info.packageName}`,
          initial: (info.appLabel || info.packageName).charAt(0).toUpperCase(),
        }));
      }

      const sysPkgs = listPackages("system") || [];
      if (sysPkgs.length > 0) {
        const sysInfos = getPackagesInfo(sysPkgs) || [];
        systemAppsList = sysInfos.map((info) => ({
          pkg: info.packageName,
          name: info.appLabel || info.packageName,
          iconUrl: `ksu://icon/${info.packageName}`,
          initial: (info.appLabel || info.packageName).charAt(0).toUpperCase(),
        }));
      }

      await tick();

      loadedIconCount = 0;
      iconLoadTotal = displayedApps.length;

      if (iconLoadTotal === 0) {
        iconsLoading = false;
      } else {
        setTimeout(() => {
          iconsLoading = false;
        }, 6000);
      }
    } catch (e) {
      console.error("Failed to load installed apps:", e);
      iconsLoading = false;
    }
  }

  function toggleApp(pkg) {
    if (selectedApps.includes(pkg)) {
      selectedApps = selectedApps.filter((p) => p !== pkg);
    } else {
      selectedApps = [...selectedApps, pkg];
    }
  }

  function clearAllApps() {
    selectedApps = [];
  }

  function checkOverflow(node) {
    const determineOverflow = () => {
      if (node.scrollWidth > node.clientWidth) {
        node.classList.add("is-overflowing");
      } else {
        node.classList.remove("is-overflowing");
      }
    };

    const observer = new ResizeObserver(determineOverflow);
    observer.observe(node);

    return {
      destroy() {
        observer.disconnect();
      },
    };
  }

  $effect(() => {
    if (showAppModal) {
      document.body.style.overflow = "hidden";
    } else {
      document.body.style.overflow = "";
    }
  });

  // =========================
  // Config Editor
  // =========================
  const HISTORY_LIMIT = 50;
  const wasEditorOpen = load("isEditorOpen", false);
  let configText = $state(load("configText", ""));
  let originalConfigText = $state(load("originalConfigText", ""));
  // svelte-ignore state_referenced_locally
  let keepRestoredEdits = configText !== originalConfigText;
  let isConfigSearchOpen = $state(load("isConfigSearchOpen", false));
  let configSearchQuery = $state(load("configSearchQuery", ""));
  let configMatchIndex = $state(load("configMatchIndex", 0));
  let isEditorOpen = $state(false);
  let isSaving = $state(false);
  let saveButtonText = $state(t("save"));
  let isResetting = $state(false);
  let resetButtonText = $state(t("reset"));
  let editorContainer = $state();
  let editorScroller = $state();
  let prevConfigQuery;
  let prevOriginalConfig;
  // svelte-ignore state_referenced_locally
  let configHistory = $state.raw(load("configHistory", [configText]));
  let configHistoryIndex = $state(load("configHistoryIndex", 0));
  let historyTimer;

  let isConfigDirty = $derived(configText !== originalConfigText);
  let configCountLabel = $derived.by(() => {
    if (!configSearchQuery) return "";
    const n = configMatches().length;
    return n > 0 ? `${configMatchIndex + 1}/${n}` : t("noMatches");
  });
  let configMatches = $derived(() => {
    if (!configSearchQuery || !configText) return [];
    const regex = new RegExp(
      configSearchQuery.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"),
      "gi",
    );
    const results = [];
    let match;
    while ((match = regex.exec(configText)) !== null) {
      results.push({ start: match.index, end: match.index + match[0].length });
    }
    return results;
  });
  let highlightedConfigContent = $derived(
    getConfigHighlightedText(
      configText,
      configSearchQuery,
      configMatches(),
      configMatchIndex,
    ),
  );
  let canUndo = $derived(
    configHistoryIndex > 0 || configText !== configHistory[configHistoryIndex],
  );
  let canRedo = $derived(
    configHistoryIndex < configHistory.length - 1 &&
      configText === configHistory[configHistoryIndex],
  );

  function commitHistory() {
    clearTimeout(historyTimer);
    if (configText === configHistory[configHistoryIndex]) return;
    const next = [
      ...configHistory.slice(0, configHistoryIndex + 1),
      configText,
    ].slice(-HISTORY_LIMIT);
    configHistory = next;
    configHistoryIndex = next.length - 1;
  }

  function recordEdit() {
    clearTimeout(historyTimer);
    historyTimer = setTimeout(commitHistory, 400);
  }

  function undoConfig() {
    commitHistory();
    if (configHistoryIndex > 0) {
      configHistoryIndex -= 1;
      configText = configHistory[configHistoryIndex];
    }
  }

  function redoConfig() {
    if (configHistoryIndex < configHistory.length - 1) {
      configHistoryIndex += 1;
      configText = configHistory[configHistoryIndex];
    }
  }

  function resetHistory() {
    clearTimeout(historyTimer);
    configHistory = [configText];
    configHistoryIndex = 0;
  }

  function jumpEditor(toBottom) {
    editorScroller?.scrollTo({
      top: toBottom ? editorScroller.scrollHeight : 0,
      behavior: "smooth",
    });
  }

  async function toggleEditor() {
    isEditorOpen = !isEditorOpen;

    if (isEditorOpen) {
      const res = await exec(`cat ${CONFIG_PATH} 2>/dev/null`);
      configText = res.stdout || "";
      originalConfigText = configText;
      resetHistory();

      await tick();
      setTimeout(() => scrollCardIntoView(editorContainer), 320);
    } else {
      isConfigSearchOpen = false;
      configSearchQuery = "";
      resetHistory();
    }
  }

  async function saveRawConfig() {
    if (isSaving) return;

    if (!isConfigDirty) {
      toast.info(t("noChangesToSave"));
      return;
    }

    isSaving = true;
    saveButtonText = t("saving");
    await tick();
    await yieldToUI();

    try {
      const sanitizedText = configText.replace(/'/g, "'\\''");
      const res = await exec(`echo '${sanitizedText}' > ${CONFIG_PATH}`);
      if (res.errno === 0) {
        await banner.requireRestart();
        initialLoad = true;
        await updateStatus();

        originalConfigText = configText;
        saveButtonText = t("saved");
      } else {
        console.error("Failed to save config:", res.stderr);
        toast.error(t("failedSaveConfig"));
        saveButtonText = t("errorSaving");
      }
    } catch (e) {
      console.error("Failed to save config: ", e);
      toast.error(t("errorSavingConfig"));
      saveButtonText = t("errorSaving");
    } finally {
      setTimeout(() => {
        saveButtonText = t("save");
        isSaving = false;
      }, 2000);
    }
  }

  async function isConfigDefault() {
    try {
      const defaultCfgRes = await exec(
        `cat ${DEFAULT_CONFIG_PATH} 2>/dev/null`,
      );
      const currentCfgRes = await exec(`cat ${CONFIG_PATH} 2>/dev/null`);

      const normalize = (str) => (str || "").replace(/\(\s+\)/g, "()").trim();

      const defaultText = normalize(defaultCfgRes.stdout);
      const currentText = normalize(currentCfgRes.stdout);

      return Boolean(defaultText && currentText && defaultText === currentText);
    } catch (e) {
      console.error("Error comparing config files:", e);
      return false;
    }
  }

  async function resetConfig() {
    if (await isConfigDefault()) {
      toast.info(t("configAlreadyDefault"));
      return;
    }

    await toast.confirm(t("confirmResetConfig"), {
      action: async () => {
        isResetting = true;
        resetButtonText = t("resetting");

        await tick();
        await yieldToUI();

        try {
          const res = await exec("/dev/acca -sr");
          if (res.errno !== 0) {
            console.error("acca -sr failed:", res.stderr);
          }

          if (await isConfigDefault()) {
            await banner.requireRestart();

            await loadChargingSwitches();
            const cfgRes = await exec(`cat ${CONFIG_PATH} 2>/dev/null`);
            configText = cfgRes.stdout || "";
            originalConfigText = configText;
            await updateStatus();

            resetButtonText = t("resetDone");
          } else {
            toast.error(t("failedResetConfig"));
            resetButtonText = t("errorResetting");
          }
        } catch (e) {
          console.error("Error resetting config:", e);
          toast.error(t("errorResetConfig"));
          resetButtonText = t("errorResetting");
        } finally {
          setTimeout(() => {
            resetButtonText = t("reset");
            isResetting = false;
          }, 2000);
        }
      },
    });
  }

  function getConfigHighlightedText(text, query, matches, currentIndex) {
    if (!text) return "";
    const escapeHtml = (str) =>
      str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    if (!query.trim()) return escapeHtml(text);

    let result = "";
    let lastIdx = 0;

    matches.forEach((m, idx) => {
      result += escapeHtml(text.substring(lastIdx, m.start));
      const matchText = escapeHtml(text.substring(m.start, m.end));
      const isCurrent = idx === currentIndex;
      const className = isCurrent
        ? "search-highlight current"
        : "search-highlight";
      result += `<mark class="${className}">${matchText}</mark>`;
      lastIdx = m.end;
    });

    result += escapeHtml(text.substring(lastIdx));
    return result;
  }

  function navigateConfigSearch(direction) {
    const matches = configMatches();
    if (matches.length === 0 || !editorContainer || !editorScroller) return;

    configMatchIndex =
      (configMatchIndex + direction + matches.length) % matches.length;
    const m = matches[configMatchIndex];

    editorContainer.readOnly = true;
    editorContainer.focus({ preventScroll: true });
    // Collapse cursor to match start (avoids triggering native selection box)
    editorContainer.setSelectionRange(m.start, m.start);

    tick().then(() => scrollToMatch(editorScroller, configMatchIndex));
  }

  async function syncConfigEditor() {
    if (isEditorOpen) {
      const cfgRes = await exec(`cat ${CONFIG_PATH} 2>/dev/null`);
      configText = cfgRes.stdout || "";
      originalConfigText = configText;
    }
  }

  // Jump to the first match when the config search query changes
  $effect(() => {
    const q = configSearchQuery;
    const prev = prevConfigQuery;
    prevConfigQuery = q;
    if (prev === undefined || prev === q) return;
    untrack(() => {
      configMatchIndex = 0;
      scrollToMatch(editorScroller, 0);
    });
  });

  // Reset undo history when the file is loaded or saved
  $effect(() => {
    const o = originalConfigText;
    const prev = prevOriginalConfig;
    prevOriginalConfig = o;
    if (prev === undefined || prev === o) return;
    untrack(resetHistory);
  });

  // =========================
  // Logs
  // =========================
  let isLogsOpen = $state(load("isLogsOpen", false));
  let activeLogType = $state(load("activeLogType", ""));
  let logsContent = $state(load("logsContent", t("loadingLogs")));
  let isLogsPolling = $state(load("isLogsPolling", false));
  let isLogsSearchOpen = $state(load("isLogsSearchOpen", false));
  let logsSearchQuery = $state(load("logsSearchQuery", ""));
  let logsMatchIndex = $state(load("logsMatchIndex", 0));
  let isExportingLogs = $state(false);
  let logPollInterval = null;
  let logContainer = $state();
  let prevLogsQuery;

  let highlightedLogsContent = $derived(
    getHighlightedLogs(logsContent, logsSearchQuery, logsMatchIndex),
  );
  let logsMatches = $derived(() => {
    if (!logsSearchQuery || !logsContent) return [];
    const regex = new RegExp(
      logsSearchQuery.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"),
      "gi",
    );
    const results = [];
    let match;
    while ((match = regex.exec(logsContent)) !== null) {
      results.push({ start: match.index, end: match.index + match[0].length });
    }
    return results;
  });
  let logsCountLabel = $derived.by(() => {
    if (!logsSearchQuery || logsContent === t("loadingLogs")) return "";
    const n = logsMatches().length;
    return n > 0 ? `${logsMatchIndex + 1}/${n}` : t("noMatches");
  });

  async function switchLogs(type) {
    if (isLogsOpen && activeLogType === type) {
      isLogsOpen = false;
      isLogsSearchOpen = false;
      logsSearchQuery = "";
      stopPollingLogs();
      return;
    }

    const wasLogsOpen = isLogsOpen;

    if (type !== activeLogType) logsMatchIndex = 0;
    activeLogType = type;
    isLogsOpen = true;
    logsContent = t("loadingLogs");

    const path =
      type === "volatile"
        ? "/dev/.vr25/acc/*.log"
        : "/data/adb/vr25/acc-data/logs/*.log";

    const res = await exec(`tail -n 50 ${path} 2>/dev/null`);
    logsContent = res.stdout || t("empty");

    if (!wasLogsOpen) {
      startPollingLogs();
      await tick();
      setTimeout(() => scrollCardIntoView(logContainer), 320);
    }

    await tick();

    if (logContainer) {
      logContainer.scrollTop = logContainer.scrollHeight;
      setTimeout(() => {
        if (logContainer) logContainer.scrollTop = logContainer.scrollHeight;
      }, 310);
    }
  }

  function startPollingLogs() {
    stopPollingLogs();
    isLogsPolling = true;

    async function poll() {
      if (!isLogsOpen || !isLogsPolling) return;

      const path =
        activeLogType === "volatile"
          ? "/dev/.vr25/acc/*.log"
          : "/data/adb/vr25/acc-data/logs/*.log";

      const res = await exec(`tail -n 50 ${path} 2>/dev/null`);
      const newContent = res.stdout || t("empty");

      if (newContent !== logsContent) {
        const isNearBottom = logContainer
          ? logContainer.scrollHeight -
              logContainer.scrollTop -
              logContainer.clientHeight <
            50
          : true;

        logsContent = newContent;
        await tick();

        if (logContainer && isNearBottom) {
          logContainer.scrollTop = logContainer.scrollHeight;
        }
      }

      if (isLogsOpen && isLogsPolling) {
        logPollInterval = setTimeout(poll, 2000);
      }
    }

    poll();
  }

  function stopPollingLogs() {
    isLogsPolling = false;

    if (logPollInterval) {
      clearTimeout(logPollInterval);
      logPollInterval = null;
    }
  }

  async function clearLogs() {
    const res = await exec(`
    for f in /dev/.vr25/acc/*.log; do
      if [ -f "$f" ]; then
        echo "TRUNCATE: $f"
        : > "$f"
      fi
    done
  `);

    if (res.errno !== 0) {
      console.error("Failed to clear logs:", res.stderr);
    }

    logsContent = t("logsCleared");
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

        if (checkFlag.stdout === "done") {
          break;
        }
      }

      await exec(`rm -f ${EXPORT_FLAG}`);

      const checkFile = await exec(
        "find /storage/emulated/0/Download /sdcard/Download -name 'acc-logs*' -mmin -2 2>/dev/null | head -n 1",
      );

      const archive_path = checkFile.stdout || "";

      if (archive_path) {
        toast.success(t("exportedTo", { path: archive_path }));
      } else {
        toast.error(t("exportFailed"));
      }
    } catch (e) {
      toast.error(t("errorExportingLogs"));
    } finally {
      isExportingLogs = false;
    }
  }

  function getHighlightedLogs(text, query, currentIndex = -1) {
    if (!text) return "";
    const escapeHtml = (str) =>
      str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

    const lines = text.split("\n");
    const trimmedQuery = query ? query.trim() : "";
    const escapedQuery = trimmedQuery
      ? trimmedQuery.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
      : "";
    const queryRegex = escapedQuery
      ? new RegExp(`(${escapedQuery})`, "gi")
      : null;

    const current = Number(currentIndex);
    let matchCounter = 0;

    return lines
      .map((line) => {
        const isHeader = /^==> .+ <==$/.test(line);
        let safeLine = escapeHtml(line);

        if (queryRegex) {
          safeLine = safeLine.replace(queryRegex, (m) => {
            const cls =
              matchCounter++ === current
                ? "search-highlight current"
                : "search-highlight";
            return `<mark class="${cls}">${m}</mark>`;
          });
        }

        if (isHeader) {
          return `<span class="log-file-header">${safeLine}</span>`;
        }
        return safeLine;
      })
      .join("\n");
  }

  function navigateLogsSearch(direction) {
    const matches = logsMatches();
    if (matches.length === 0 || !logContainer) return;

    logsMatchIndex =
      (logsMatchIndex + direction + matches.length) % matches.length;

    tick().then(() => scrollToMatch(logContainer, logsMatchIndex));
  }

  // Jump to the first match when the logs search query changes
  $effect(() => {
    const q = logsSearchQuery;
    const prev = prevLogsQuery;
    prevLogsQuery = q;
    if (prev === undefined || prev === q) return;
    untrack(() => {
      logsMatchIndex = 0;
      scrollToMatch(logContainer, 0);
    });
  });

  // =========================
  // Lifecycle
  // =========================

  onMount(() => {
    banner.registerRestart({
      onRestart: () => controlDaemon("restart"),
      isBlocked: () => isTransitioning || isSectionDisabled,
    });

    const onVis = () => {
      if (document.visibilityState === "hidden") saveUnloadTime();
    };
    let scrollTimeout;
    const onScroll = () => {
      if (isRotationRecovery && !hasRestoredScroll) return;
      clearTimeout(scrollTimeout);
      scrollTimeout = setTimeout(() => {
        localStorage.setItem("acc_scroll_pos", window.scrollY.toString());
      }, 150);
    };

    window.addEventListener("pagehide", saveUnloadTime);
    document.addEventListener("visibilitychange", onVis);
    window.addEventListener("scroll", onScroll, { passive: true });
    const heartbeat = setInterval(saveUnloadTime, 1000);
    setupComplementaryColors();
    detectEnvironment();
    banner.checkRestart();
    updateStatus();
    loadChargingSwitches();
    statusPollInterval = setInterval(updateStatus, 3500);

    (async () => {
      await tick();

      // Open the editor only after the banner/status/switch startup has run
      if (wasEditorOpen) {
        requestAnimationFrame(() => {
          isEditorOpen = true;
        });
      }

      if (isLogsOpen && activeLogType && isLogsPolling) {
        startPollingLogs();
      }

      // Rotation during a test: pick the polling back up (the test keeps running)
      if (testAllState === "running") startTestAllPolling();

      if (testAllState !== "running") {
        exec(
          `pgrep -f '/[a]cc/acc .* (-t|--test)( |$)' >/dev/null || rm -f ${TEST_LOG} ${TEST_HB}`,
        );
      }

      // WebUI was closed mid-test: the watchdog stopped it, so bring accd back
      exec(`cat ${TEST_KILLED} 2>/dev/null; rm -f ${TEST_KILLED}`).then((r) => {
        if (r.stdout?.trim() === "1") controlDaemon("start");
      });
    })();

    return () => {
      window.removeEventListener("pagehide", saveUnloadTime);
      document.removeEventListener("visibilitychange", onVis);
      window.removeEventListener("scroll", onScroll);
      clearInterval(heartbeat);
      clearInterval(statusPollInterval);
      clearTimeout(scrollTimeout);
      stopPollingLogs();
      if (testAllInterval) clearInterval(testAllInterval);
    };
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
          letter-spacing="-1.5">{t("webUiName")}</text
        >
        <text
          x="0"
          y="240"
          fill="var(--md-sys-color-secondary-complement)"
          font-family="system-ui, sans-serif"
          font-size="26"
          font-weight="600"
          opacity="0.95">{t("advancedChargingController")}</text
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
        <span class="card-title">{t("health")}</span><IMaterialSymbolsFavorite
          class="mi-icon"
        />
      </div>
      <div id="bat-health" class="card-value">{health}</div>
    </div>
    <div class="m3-card" style="margin-bottom:0;">
      <div class="card-header">
        <span class="card-title">{t("temperature")}</span><IMaterialSymbolsThermostat
          class="mi-icon"
        />
      </div>
      <div id="bat-temp" class="card-value">{temperature}</div>
    </div>
    <div class="m3-card" style="margin-bottom:0;">
      <div class="card-header">
        <span class="card-title">{t("current")}</span><IMaterialSymbolsSwapCalls
          class="mi-icon"
        />
      </div>
      <div id="bat-current" class="card-value">{current}</div>
    </div>
    <div class="m3-card" style="margin-bottom:0;">
      <div class="card-header">
        <span class="card-title">{t("voltage")}</span><IMaterialSymbolsBolt
          class="mi-icon"
        />
      </div>
      <div id="bat-voltage" class="card-value">{voltage}</div>
    </div>
  </div>

  <!-- Daemon (accd) -->
  <section class="m3-card">
    <div class="header-row section-divider">
      <div class="title-group">
        <IMaterialSymbolsBuild class="mi-icon" />
        <div class="section-title">{t("daemon")}</div>
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
        disabled={!statusReady ||
          isTransitioning ||
          isSectionDisabled ||
          isRunning}>{t("start")}</button
      >
      <button
        id="btn-stop"
        onclick={() => controlDaemon("stop")}
        class="m3-btn btn-danger"
        disabled={!statusReady ||
          isTransitioning ||
          isSectionDisabled ||
          !isRunning}>{t("stop")}</button
      >
      <button
        id="btn-banner-restart"
        onclick={() => controlDaemon("restart")}
        class="m3-btn btn-restart-action"
        disabled={!statusReady ||
          isTransitioning ||
          isSectionDisabled ||
          !isRunning}>{t("restart")}</button
      >
    </div>
  </section>

  <!-- Charging Switch -->
  <section class="m3-card" bind:this={switchCardRef}>
    <div class="header-row section-divider">
      <div class="title-group">
        <IMaterialSymbolsSwitch class="mi-icon" />
        <div class="section-title">{t("chargingSwitchSection")}</div>
      </div>
    </div>

    <!-- Current Switch -->
    <div class="setting-wrapper">
      <div class="setting-row input-row">
        <div class="label-group">
          <div class="label-text">{t("currentSwitch")}</div>
          <button
            type="button"
            class="info-btn"
            onclick={(e) => {
              e.stopPropagation();
              toggleDescription("cs_current");
            }}
            aria-label={t("infoCurrentSwitchLabel")}
          >
            <IMaterialSymbolsInfo class="mi-icon" />
          </button>
        </div>
        <div class="m3-input-display">
          {currentSwitch || "—"}
        </div>
      </div>
      {#if activeDescriptions.cs_current}
        <div
          class="toggle-description"
          transition:slide={{ duration: 250, easing: cubicOut }}
        >
          {@html infoDescriptions.cs_current}
        </div>
      {/if}
    </div>

    <!-- Switch Selector Dropdown Modal Trigger (Input Style) -->
    <div class="setting-wrapper" class:disabled-section={isSectionDisabled}>
      <div class="setting-row input-row">
        <div class="label-group">
          <div class="label-text">{t("workingSwitches")}</div>
          <button
            type="button"
            class="info-btn"
            onclick={(e) => {
              e.stopPropagation();
              toggleDescription("chargingSwitch");
            }}
            aria-label={t("infoChargingSwitchLabel")}
          >
            <IMaterialSymbolsInfo class="mi-icon" />
          </button>
        </div>

        <button
          type="button"
          class="m3-input select-trigger-btn"
          onclick={() =>
            availableSwitches.length > 0 && (showSwitchModal = true)}
          disabled={isSavingSwitch ||
            availableSwitches.length === 0 ||
            isSectionDisabled}
        >
          <span class="select-trigger-text">
            {matchingSwitches
              ? currentSwitch
              : availableSwitches.length === 0
                ? t("switchSelectPrompt")
                : t("selectWorkingSwitchPrompt")}
          </span>
          <IMaterialSymbolsArrowDropDown class="mi-icon" />
        </button>
      </div>

      {#if activeDescriptions.chargingSwitch}
        <div
          class="toggle-description"
          transition:slide={{ duration: 250, easing: cubicOut }}
        >
          {@html infoDescriptions.chargingSwitch}
        </div>
      {/if}
    </div>

    <!-- Manual Override Input -->
    <div class="setting-wrapper" class:disabled-section={isSectionDisabled}>
      <div class="setting-row input-row">
        <div class="label-group">
          <div class="label-text">{t("manualOverride")}</div>
          <button
            type="button"
            class="info-btn"
            onclick={(e) => {
              e.stopPropagation();
              toggleDescription("cs_manual");
            }}
            aria-label={t("infoManualOverrideLabel")}
          >
            <IMaterialSymbolsInfo class="mi-icon" />
          </button>
        </div>
        <input
          type="text"
          class="m3-input"
          placeholder={t("manualSwitchPlaceholder")}
          bind:value={manualSwitchInput}
          disabled={isSectionDisabled}
        />
      </div>
      {#if activeDescriptions.cs_manual}
        <div
          class="toggle-description"
          transition:slide={{ duration: 250, easing: cubicOut }}
        >
          {@html infoDescriptions.cs_manual}
        </div>
      {/if}
    </div>

    <!-- Force Off -->
    <div class="setting-wrapper" class:disabled-section={isSectionDisabled}>
      <div class="setting-row">
        <div class="label-group">
          <div class="label-text">{t("forceOff")}</div>
          <button
            type="button"
            class="info-btn"
            onclick={(e) => {
              e.stopPropagation();
              toggleDescription("fo");
            }}
            aria-label={t("infoForceOffLabel")}
          >
            <IMaterialSymbolsInfo class="mi-icon" />
          </button>
        </div>
        <label class="m3-switch">
          <input
            type="checkbox"
            bind:checked={fo}
            onchange={(e) => toggleSetting("fo", e.target.checked)}
            disabled={isSectionDisabled}
          />
          <span class="slider"></span>
        </label>
      </div>
      {#if activeDescriptions.fo}
        <div
          class="toggle-description"
          transition:slide={{ duration: 250, easing: cubicOut }}
        >
          {@html infoDescriptions.fo}
        </div>
      {/if}
    </div>

    <!-- Action Buttons -->
    <div class="btn-row multi-btn viewer-spacing section-divider-top">
      <button
        onclick={applyManualSwitch}
        class="m3-btn btn-secondary m3-btn-centered"
        disabled={!manualSwitchInput || manualSwitchInput === currentSwitch}
      >
        <span>{t("applyManual")}</span>
      </button>

      <button
        onclick={handleTestAll}
        class="m3-btn btn-primary m3-btn-centered"
        disabled={switchBannerMode === "detecting"}
      >
        {#if testAllState === "running"}
          <span class="btn-leading-icon"><span class="m3-spinner"></span></span>
          <span>{t("cancel")}</span>
        {:else if testAllState === "done"}
          <span>{t("close")}</span>
        {:else}
          <span>{t("testAll")}</span>
        {/if}
      </button>
    </div>

    <!-- Terminal Viewer for Test All -->
    {#if testAllState !== "idle"}
      <div
        class="collapsible-box"
        transition:slide={{ duration: 300, easing: cubicOut }}
      >
        <div
          class="log-box viewer-spacing"
          style="height: 250px;"
          bind:this={testAllContainer}
          use:resizable={"acc_testall_height"}
        >
          {testAllLogs}
        </div>
      </div>
    {/if}
  </section>

  {#snippet noSwitchHint()}
    {#if noSwitch}
      <div
        class="section-hint"
        transition:slideNoFade={{ duration: 250, easing: cubicOut }}
      >
        {t("takesEffectWithSwitch")}
      </div>
    {/if}
  {/snippet}

  <!-- Charging Thresholds -->
  <section class="m3-card" class:disabled-section={isSectionDisabled}>
    <div class="header-row section-divider header-wrap">
      <div class="title-group">
        <IMaterialSymbolsBatteryChargingFull class="mi-icon" />
        <div class="section-title">{t("chargingThresholds")}</div>
      </div>
      {@render noSwitchHint()}
    </div>

    <div class="slider-wrapper">
      <div class="flex justify-between">
        <div class="label-text">{t("resumeAt")}</div>
        <div class="thresh-label">{resumeThresh}%</div>
      </div>
      <div class="slider-container resume" style="--percent: {resumeThresh}%;">
        <input
          type="range"
          min="0"
          max="100"
          step="1"
          disabled={isSectionDisabled}
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
        <div class="label-text">{t("pauseAt")}</div>
        <div class="thresh-label">{pauseThresh}%</div>
      </div>
      <div class="slider-container pause" style="--percent: {pauseThresh}%;">
        <input
          type="range"
          min="0"
          max="100"
          step="1"
          disabled={isSectionDisabled}
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
        <div class="label-text">{t("shutdownAt")}</div>
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
          disabled={isSectionDisabled}
          bind:value={shutdownThresh}
          oninput={() => handleSliderChange("shutdown")}
        />
        <div class="slider-track-visual">
          <div class="slider-track-fill"></div>
        </div>
      </div>
    </div>
  </section>

  <!-- Idle Mode -->
  <section class="m3-card" class:disabled-section={isSectionDisabled}>
    <div class="header-row section-divider header-wrap">
      <div class="title-group">
        <IMaterialSymbolsEnergySavingsLeaf class="mi-icon" />
        <div class="section-title">{t("idleMode")}</div>
      </div>
      {@render noSwitchHint()}
    </div>

    <!-- Allow Idle Above Pause -->
    <div class="setting-wrapper">
      <div class="setting-row">
        <div class="label-group">
          <div class="label-text">{t("allowIdleAbovePause")}</div>
          <button
            type="button"
            class="info-btn"
            onclick={() => toggleDescription("aiapc")}
            aria-label={t("infoAllowIdleAbovePauseLabel")}
          >
            <IMaterialSymbolsInfo class="mi-icon" />
          </button>
        </div>
        <label class="m3-switch">
          <input
            type="checkbox"
            bind:checked={aiapc}
            disabled={isSectionDisabled}
            onchange={(e) => toggleSetting("aiapc", e.target.checked)}
          />
          <span class="slider"></span>
        </label>
      </div>
      {#if activeDescriptions.aiapc}
        <div
          class="toggle-description"
          transition:slide={{ duration: 250, easing: cubicOut }}
        >
          {infoDescriptions.aiapc}
        </div>
      {/if}
    </div>

    <!-- Prioritize Idle Mode -->
    <div class="setting-wrapper">
      <div class="setting-row">
        <div class="label-group">
          <div class="label-text">{t("prioritizeIdleMode")}</div>
          <button
            type="button"
            class="info-btn"
            onclick={() => toggleDescription("pbim")}
            aria-label={t("infoPrioritizeIdleModeLabel")}
          >
            <IMaterialSymbolsInfo class="mi-icon" />
          </button>
        </div>
        <label class="m3-switch">
          <input
            type="checkbox"
            bind:checked={pbim}
            disabled={isSectionDisabled}
            onchange={(e) => toggleSetting("pbim", e.target.checked)}
          />
          <span class="slider"></span>
        </label>
      </div>
      {#if activeDescriptions.pbim}
        <div
          class="toggle-description"
          transition:slide={{ duration: 250, easing: cubicOut }}
        >
          {infoDescriptions.pbim}
        </div>
      {/if}
    </div>

    <!-- Off Mid -->
    <div class="setting-wrapper">
      <div class="setting-row">
        <div class="label-group">
          <div class="label-text">{t("offMid")}</div>
          <button
            type="button"
            class="info-btn"
            onclick={() => toggleDescription("om")}
            aria-label={t("infoOffMidLabel")}
          >
            <IMaterialSymbolsInfo class="mi-icon" />
          </button>
        </div>
        <label class="m3-switch">
          <input
            type="checkbox"
            bind:checked={om}
            disabled={isSectionDisabled}
            onchange={(e) => toggleSetting("om", e.target.checked)}
          />
          <span class="slider"></span>
        </label>
      </div>
      {#if activeDescriptions.om}
        <div
          class="toggle-description"
          transition:slide={{ duration: 250, easing: cubicOut }}
        >
          {infoDescriptions.om}
        </div>
      {/if}
    </div>

    <!-- Idle Apps -->
    <div class="setting-wrapper">
      <div
        class="setting-row interactive"
        onclick={() => !isSectionDisabled && openIdleAppsModal()}
        onkeydown={(e) => {
          if (isSectionDisabled) return;
          if (e.key === "Enter" || e.key === " ") openIdleAppsModal();
        }}
        tabindex={isSectionDisabled ? -1 : 0}
        role="button"
        aria-disabled={isSectionDisabled}
      >
        <div class="label-group">
          <div class="label-text">{t("idleApps")}</div>
          <button
            type="button"
            class="info-btn"
            onclick={(e) => {
              e.stopPropagation();
              toggleDescription("ia");
            }}
            aria-label={t("infoIdleAppsLabel")}
          >
            <IMaterialSymbolsInfo class="mi-icon" />
          </button>
        </div>
        <div class="idle-apps-value">
          <span class="idle-apps-count">{t("idleAppsCount", { count: idleApps.length })}</span>
          <IMaterialSymbolsChevronRight class="mi-icon" />
        </div>
      </div>
      {#if activeDescriptions.ia}
        <div
          class="toggle-description"
          transition:slide={{ duration: 250, easing: cubicOut }}
        >
          {infoDescriptions.ia}
        </div>
      {/if}
    </div>
  </section>

  <!-- Idle Apps Modal -->
  {#if showAppModal}
    <div
      class="modal-backdrop"
      transition:fade={{ duration: 250, easing: cubicOut }}
    >
      <div
        class="m3-modal"
        transition:fly={{ y: 40, duration: 280, easing: cubicOut }}
      >
        <!-- Header -->
        <div class="modal-header">
          <div class="modal-title-group">
            <IMaterialSymbolsApps class="mi-icon" />
            <h3 class="modal-title">{t("selectIdleApps")}</h3>
          </div>
          <button
            class="modal-close-btn"
            onclick={() => (showAppModal = false)}
            aria-label={t("close")}
          >
            <IMaterialSymbolsClose class="mi-icon" />
          </button>
        </div>

        <!-- Top Controls -->
        <div class="modal-top-bar">
          <!-- Clear All -->
          <button
            class="btn-clear-all"
            type="button"
            onclick={clearAllApps}
            disabled={selectedApps.length === 0 || iconsLoading}
          >
            <IMaterialSymbolsClearAll class="mi-icon" />
            <span class="btn-text">{t("clearAll")}</span>
          </button>

          <!-- Search -->
          <div
            class="search-input-wrapper"
            class:expanded={searchExpanded}
            class:disabled-section={iconsLoading}
          >
            <IMaterialSymbolsSearch class="mi-icon search-icon" />

            <input
              type="text"
              class="search-input"
              placeholder={t("searchAppsPlaceholder")}
              bind:value={searchQuery}
              onclick={() => !iconsLoading && (searchExpanded = true)}
              disabled={iconsLoading}
            />

            {#if searchExpanded}
              <button
                type="button"
                class="clear-search-btn"
                onclick={() => {
                  searchQuery = "";
                  searchExpanded = false;
                }}
                aria-label={t("closeSearchLabel")}
              >
                <IMaterialSymbolsClose class="mi-icon" />
              </button>
            {/if}
          </div>

          <!-- System Apps -->
          <label class="sys-toggle-pill" class:disabled-section={iconsLoading}>
            <IMaterialSymbolsAndroid class="mi-icon" />

            <span class="btn-text">{t("systemApps")}</span>

            <span class="m3-switch">
              <input
                type="checkbox"
                bind:checked={showSystemApps}
                disabled={iconsLoading}
              />
              <span class="slider"></span>
            </span>
          </label>
        </div>

        <!-- Scrollable App List -->
        <div class="app-list-wrapper">
          <div class="app-list" class:app-list-hidden={iconsLoading}>
            {#each displayedApps as app (app.pkg)}
              <label
                class="app-item"
                class:selected={selectedApps.includes(app.pkg)}
              >
                <div class="app-avatar">
                  <img
                    class="app-icon-img"
                    src={app.iconUrl}
                    alt=""
                    aria-hidden="true"
                    onload={handleAppIconLoad}
                    onerror={handleAppIconError}
                  />
                  <span class="app-initial">{app.initial}</span>
                </div>

                <div class="app-info">
                  <span class="app-name">{app.name}</span>

                  <div class="app-pkg-ticker" use:checkOverflow>
                    <span class="app-pkg">{app.pkg}</span>
                  </div>
                </div>

                <div class="app-checkbox">
                  <input
                    type="checkbox"
                    checked={selectedApps.includes(app.pkg)}
                    onchange={() => toggleApp(app.pkg)}
                  />
                  <span class="checkmark">
                    <IMaterialSymbolsCheck class="mi-icon" />
                  </span>
                </div>
              </label>
            {/each}

            {#if displayedApps.length === 0}
              <div class="empty-state">
                <IMaterialSymbolsInbox class="mi-icon" />
                <p>{t("noAppsFound")}</p>
              </div>
            {/if}
          </div>

          {#if iconsLoading}
            <div class="app-list-loading">
              <span class="m3-spinner" aria-label={t("loadingApps")}></span>
            </div>
          {/if}
        </div>

        <!-- Footer -->
        <div class="modal-footer">
          <button
            class="m3-btn btn-secondary modal-action-btn"
            onclick={() => (showAppModal = false)}
          >
            {t("cancel")}
          </button>
          <button
            class="m3-btn btn-primary modal-action-btn"
            onclick={saveIdleApps}
          >
            {t("confirm")}
            {#if selectedApps.length > 0 && !iconsLoading}
              <span class="selection-count">{selectedApps.length}</span>
            {/if}
          </button>
        </div>
      </div>
    </div>
  {/if}

  <!-- Reset Battery Stats -->
  <section class="m3-card" class:disabled-section={isSectionDisabled}>
    <div class="header-row section-divider">
      <div class="title-group">
        <IMaterialSymbolsSync class="mi-icon" />
        <div class="section-title">{t("resetBatteryStats")}</div>
      </div>
    </div>

    <!-- On Pause -->
    <div class="setting-wrapper">
      <div class="setting-row">
        <div class="label-group">
          <div class="label-text">{t("onPause")}</div>
          <button
            type="button"
            class="info-btn"
            onclick={() => toggleDescription("rbsp")}
            aria-label={t("infoOnPauseLabel")}
          >
            <IMaterialSymbolsInfo class="mi-icon" />
          </button>
        </div>
        <label class="m3-switch">
          <input
            type="checkbox"
            bind:checked={rbsp}
            disabled={isSectionDisabled}
            onchange={(e) => toggleSetting("rbsp", e.target.checked)}
          />
          <span class="slider"></span>
        </label>
      </div>
      {#if activeDescriptions.rbsp}
        <div
          class="toggle-description"
          transition:slide={{ duration: 250, easing: cubicOut }}
        >
          {infoDescriptions.rbsp}
        </div>
      {/if}
    </div>

    <!-- On Unplug -->
    <div class="setting-wrapper">
      <div class="setting-row">
        <div class="label-group">
          <div class="label-text">{t("onUnplug")}</div>
          <button
            type="button"
            class="info-btn"
            onclick={() => toggleDescription("rbsu")}
            aria-label={t("infoOnUnplugLabel")}
          >
            <IMaterialSymbolsInfo class="mi-icon" />
          </button>
        </div>
        <label class="m3-switch">
          <input
            type="checkbox"
            bind:checked={rbsu}
            disabled={isSectionDisabled}
            onchange={(e) => toggleSetting("rbsu", e.target.checked)}
          />
          <span class="slider"></span>
        </label>
      </div>
      {#if activeDescriptions.rbsu}
        <div
          class="toggle-description"
          transition:slide={{ duration: 250, easing: cubicOut }}
        >
          {infoDescriptions.rbsu}
        </div>
      {/if}
    </div>

    <!-- On Plug -->
    <div class="setting-wrapper">
      <div class="setting-row">
        <div class="label-group">
          <div class="label-text">{t("onPlug")}</div>
          <button
            type="button"
            class="info-btn"
            onclick={() => toggleDescription("rbspl")}
            aria-label={t("infoOnPlugLabel")}
          >
            <IMaterialSymbolsInfo class="mi-icon" />
          </button>
        </div>
        <label class="m3-switch">
          <input
            type="checkbox"
            bind:checked={rbspl}
            disabled={isSectionDisabled}
            onchange={(e) => toggleSetting("rbspl", e.target.checked)}
          />
          <span class="slider"></span>
        </label>
      </div>
      {#if activeDescriptions.rbspl}
        <div
          class="toggle-description"
          transition:slide={{ duration: 250, easing: cubicOut }}
        >
          {infoDescriptions.rbspl}
        </div>
      {/if}
    </div>
  </section>

  <!-- Config File -->
  <section class="m3-card" class:disabled-section={isSectionDisabled}>
    <div class="header-row">
      <div class="title-group">
        <IMaterialSymbolsEditNote class="mi-icon" />
        <div class="section-title">{t("config")}</div>
      </div>
      <div class="config-controls">
        {#if isEditorOpen}
          <button
            class="log-poll-btn"
            class:active={isConfigSearchOpen}
            onclick={() => {
              isConfigSearchOpen = !isConfigSearchOpen;
              if (!isConfigSearchOpen) configSearchQuery = "";
            }}
            title={t("searchConfig")}
            in:fade={{ duration: 180, easing: cubicOut }}
            out:fade={{ duration: 140, easing: cubicOut }}
          >
            <IMaterialSymbolsSearch />
          </button>

          <button
            class="log-poll-btn"
            onclick={undoConfig}
            disabled={!canUndo}
            title={t("undo")}
            in:fade={{ duration: 180, easing: cubicOut }}
            out:fade={{ duration: 140, easing: cubicOut }}
          >
            <IMaterialSymbolsUndo />
          </button>

          <button
            class="log-poll-btn"
            onclick={redoConfig}
            disabled={!canRedo}
            title={t("redo")}
            in:fade={{ duration: 180, easing: cubicOut }}
            out:fade={{ duration: 140, easing: cubicOut }}
          >
            <IMaterialSymbolsRedo />
          </button>

          <button
            class="log-poll-btn"
            onclick={() => jumpEditor(false)}
            title={t("jumpToTop")}
            in:fade={{ duration: 180, easing: cubicOut }}
            out:fade={{ duration: 140, easing: cubicOut }}
          >
            <IMaterialSymbolsVerticalAlignTop />
          </button>

          <button
            class="log-poll-btn"
            onclick={() => jumpEditor(true)}
            title={t("jumpToBottom")}
            in:fade={{ duration: 180, easing: cubicOut }}
            out:fade={{ duration: 140, easing: cubicOut }}
          >
            <IMaterialSymbolsVerticalAlignBottom />
          </button>
        {/if}

        <button
          type="button"
          class="arrow-toggle-btn"
          onclick={toggleEditor}
          aria-label={isEditorOpen
            ? t("collapseConfigFile")
            : t("expandConfigFile")}
          aria-expanded={isEditorOpen}
        >
          <div
            id="arrow-editor"
            class="dropdown-arrow"
            class:open={isEditorOpen}
          >
            ▼
          </div>
        </button>
      </div>
    </div>
    {#if isEditorOpen}
      <div
        id="editor-area"
        class="collapsible-box"
        transition:slideNoFade={{ duration: 300, easing: cubicOut }}
      >
        {#if isConfigSearchOpen}
          <div
            class="inline-search-bar"
            transition:slideNoFade={{ duration: 200, easing: cubicOut }}
          >
            <IMaterialSymbolsSearch class="mi-icon search-icon" />
            <div class="search-input-wrap">
              <input
                type="text"
                class="inline-search-input-field"
                placeholder=""
                aria-label={t("searchConfig")}
                bind:value={configSearchQuery}
              />
              {#if !configSearchQuery}
                <span
                  class="search-placeholder"
                  in:fly={{ y: 6, duration: 180, easing: cubicOut }}
                  out:fly={{ y: -6, duration: 120, easing: cubicOut }}
                >
                  {t("searchConfigPlaceholder")}
                </span>
              {/if}
            </div>
            <div class="search-nav-controls">
              <span style="display:inline-grid; justify-items:end;">
                {#if configCountLabel}
                  {#key configCountLabel}
                    <span
                      class="search-count"
                      style="grid-area:1/1;"
                      in:fly|global={{
                        y: 6,
                        duration: 180,
                        easing: cubicOut,
                      }}
                      out:fly|global={{
                        y: -6,
                        duration: 120,
                        easing: cubicOut,
                      }}
                    >
                      {configCountLabel}
                    </span>
                  {/key}
                {/if}
              </span>

              <span
                style="display:inline-grid; place-items:center; width:24px; height:24px;"
              >
                {#if configSearchQuery}
                  <button
                    type="button"
                    class="clear-search-btn"
                    onclick={(e) => {
                      e.stopPropagation();
                      configSearchQuery = "";
                    }}
                    aria-label={t("clearSearch")}
                    transition:scale={{ duration: 150, easing: cubicOut }}
                  >
                    <IMaterialSymbolsClose class="mi-icon" />
                  </button>
                {/if}
              </span>

              <button
                class="search-nav-btn"
                onclick={() => navigateConfigSearch(-1)}
                title={t("previous")}
                disabled={configMatches().length === 0}
              >
                <IMaterialSymbolsKeyboardArrowUp class="mi-icon" />
              </button>
              <button
                class="search-nav-btn"
                onclick={() => navigateConfigSearch(1)}
                title={t("next")}
                disabled={configMatches().length === 0}
              >
                <IMaterialSymbolsKeyboardArrowDown class="mi-icon" />
              </button>
            </div>
          </div>
        {/if}

        <div
          class="editor-container-wrapper viewer-spacing"
          bind:this={editorScroller}
          onscroll={handleEditorScroll}
          use:resizable={"acc_editor_height"}
        >
          <div class="editor-stack">
            <div class="editor-backdrop">
              {@html highlightedConfigContent}&#8203;
            </div>
            <textarea
              id="config-textarea"
              class="editor-textarea"
              spellcheck="false"
              bind:value={configText}
              bind:this={editorContainer}
              onclick={() => {
                if (editorContainer) editorContainer.readOnly = false;
              }}
              onfocus={() => {
                if (editorContainer && !isConfigSearchOpen)
                  editorContainer.readOnly = false;
              }}
              oninput={recordEdit}></textarea>
          </div>
        </div>
        <div class="btn-row">
          <button
            onclick={resetConfig}
            class="m3-btn btn-danger m3-btn-centered"
            disabled={isSaving || isResetting}
          >
            {#if isResetting && resetButtonText === "Resetting..."}
              <span class="btn-leading-icon">
                <span class="m3-spinner"></span>
              </span>
              <span>{resetButtonText}</span>
            {:else}
              <span>{resetButtonText}</span>
            {/if}
          </button>

          <button
            onclick={saveRawConfig}
            class="m3-btn btn-primary m3-btn-centered"
            disabled={isSaving || isResetting}
          >
            {#if isSaving && saveButtonText === "Saving..."}
              <span class="btn-leading-icon">
                <span class="m3-spinner"></span>
              </span>
              <span>{saveButtonText}</span>
            {:else}
              <span>{saveButtonText}</span>
            {/if}
          </button>
        </div>
      </div>
    {/if}
  </section>

  <!-- Logs -->
  <section class="m3-card">
    <div class="header-row">
      <div class="title-group">
        <IMaterialSymbolsTerminal class="mi-icon" />
        <div class="section-title">{t("logs")}</div>
      </div>

      <div class="logs-controls">
        {#if isLogsOpen}
          <button
            class="log-poll-btn"
            class:active={isLogsSearchOpen}
            onclick={() => {
              isLogsSearchOpen = !isLogsSearchOpen;
              if (!isLogsSearchOpen) logsSearchQuery = "";
            }}
            title={t("searchLogs")}
            in:fade={{ duration: 180, easing: cubicOut }}
            out:fade={{ duration: 140, easing: cubicOut }}
          >
            <IMaterialSymbolsSearch />
          </button>

          <button
            class="log-poll-btn {isLogsPolling ? 'polling' : ''}"
            onclick={() => {
              if (isLogsPolling) {
                stopPollingLogs();
              } else {
                startPollingLogs();
              }
            }}
            aria-label={isLogsPolling
              ? t("pauseLogPolling")
              : t("startLogPolling")}
            title={isLogsPolling ? t("pause") : t("play")}
            in:fade={{ duration: 180, easing: cubicOut }}
            out:fade={{ duration: 140, easing: cubicOut }}
          >
            {#if isLogsPolling}
              <IMaterialSymbolsPause />
            {:else}
              <IMaterialSymbolsPlayArrow />
            {/if}
          </button>
        {/if}

        <!-- Segmented Control Button -->
        <div class="log-type-selector">
          <button
            class="log-tab-btn {isLogsOpen && activeLogType === 'volatile'
              ? 'active'
              : ''}"
            onclick={() => switchLogs("volatile")}
          >
            {t("volatile")}
          </button>
          <button
            class="log-tab-btn {isLogsOpen && activeLogType === 'persistent'
              ? 'active'
              : ''}"
            onclick={() => switchLogs("persistent")}
          >
            {t("persistent")}
          </button>
        </div>
      </div>
    </div>

    {#if isLogsOpen}
      <div
        id="logs-area"
        class="collapsible-box"
        transition:slide={{ duration: 300, easing: cubicOut }}
      >
        {#if isLogsSearchOpen}
          <div
            class="inline-search-bar"
            transition:slideNoFade={{ duration: 200, easing: cubicOut }}
          >
            <IMaterialSymbolsSearch class="mi-icon search-icon" />
            <div class="search-input-wrap">
              <input
                type="text"
                class="inline-search-input-field"
                placeholder=""
                aria-label={t("searchLogs")}
                bind:value={logsSearchQuery}
              />
              {#if !logsSearchQuery}
                <span
                  class="search-placeholder"
                  in:fly={{ y: 6, duration: 180, easing: cubicOut }}
                  out:fly={{ y: -6, duration: 120, easing: cubicOut }}
                >
                  {t("searchLogsPlaceholder")}
                </span>
              {/if}
            </div>
            <div class="search-nav-controls">
              <span style="display:inline-grid; justify-items:end;">
                {#if logsCountLabel}
                  {#key logsCountLabel}
                    <span
                      class="search-count"
                      style="grid-area:1/1;"
                      in:fly|global={{ y: 6, duration: 180, easing: cubicOut }}
                      out:fly|global={{
                        y: -6,
                        duration: 120,
                        easing: cubicOut,
                      }}
                    >
                      {logsCountLabel}
                    </span>
                  {/key}
                {/if}
              </span>

              <span
                style="display:inline-grid; place-items:center; width:24px; height:24px;"
              >
                {#if logsSearchQuery}
                  <button
                    type="button"
                    class="clear-search-btn"
                    onclick={(e) => {
                      e.stopPropagation();
                      logsSearchQuery = "";
                    }}
                    aria-label={t("clearSearch")}
                    transition:scale={{ duration: 150, easing: cubicOut }}
                  >
                    <IMaterialSymbolsClose class="mi-icon" />
                  </button>
                {/if}
              </span>

              <button
                class="search-nav-btn"
                onclick={() => navigateLogsSearch(-1)}
                title={t("previous")}
                disabled={logsMatches().length === 0}
              >
                <IMaterialSymbolsKeyboardArrowUp class="mi-icon" />
              </button>
              <button
                class="search-nav-btn"
                onclick={() => navigateLogsSearch(1)}
                title={t("next")}
                disabled={logsMatches().length === 0}
              >
                <IMaterialSymbolsKeyboardArrowDown class="mi-icon" />
              </button>
            </div>
          </div>
        {/if}

        <div
          class="log-box viewer-spacing"
          bind:this={logContainer}
          onscroll={handleLogScroll}
          use:resizable={"acc_logs_height"}
        >
          {#key activeLogType}
            <div in:fade={{ duration: 250, easing: cubicOut }}>
              {@html highlightedLogsContent}
            </div>
          {/key}
        </div>

        <div class="btn-row">
          <button
            onclick={clearLogs}
            disabled={activeLogType === "persistent"}
            class="m3-btn btn-danger m3-btn-centered"
          >
            <span>{t("clear")}</span>
          </button>
          <button
            onclick={exportLogs}
            disabled={isExportingLogs || isSectionDisabled}
            class="m3-btn btn-primary m3-btn-centered"
          >
            {#if isExportingLogs}
              <span class="btn-leading-icon">
                <span class="m3-spinner"></span>
              </span>
              <span>{t("exporting")}</span>
            {:else}
              <span>{t("export")}</span>
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
    <div class="footer-banner-inner">
      <div class="footer-banner-top">
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
            <div class="repo-action-label">{t("viewOnGitHub")}</div>
          </div>
        </div>
        <div class="footer-right-group">
          <span class="version-tag">v{version}</span>
          <IMaterialSymbolsOpenInNew class="mi-icon open-icon" />
        </div>
      </div>

      <div class="footer-banner-bottom">
        <span class="repo-name">ACC</span>
        <span class="version-tag">{acc_version}</span>
      </div>
    </div>
  </a>
</div>

<DropdownModal
  isOpen={showSwitchModal}
  title={t("selectWorkingSwitch")}
  options={availableSwitches}
  bind:selectedValue={currentSwitch}
  onSelect={handleSelectSwitch}
  onClose={() => (showSwitchModal = false)}
/>

<Toast />

<BannerStack />
