/**
SPDX-FileCopyrightText: 2026 Infiniti151
SPDX-License-Identifier: GPL-3.0-or-later
**/

export const infoDescriptions = {
    cs_current: "Displays the sysfs node currently controlling your battery's charging state. If this field is blank or fails, click <b>Test All</b> to find a compatible switch. Then set a switch with either the dropdown or the manual override input below.",

    chargingSwitch: "Switches that ACC successfully detected and verified as functional on your device. <b>[I]</b> switches support true <i>Battery Idle Mode</i> (powering the phone directly from the wall charger without charging the battery). <b>[D]</b> switches only disable power input. If you only see a single selection, click <b>Test All</b> to populate all working switches.",

    cs_manual: "Set a custom kernel path if your switch is not detected. Appending \" <code>--</code>\" to a valid path locks it and disables ACC's 3-strike fallback cycle. If a switch path is invalid or fails execution completely, ACC will revert to its database to restore charging control.",

    fo: "Aggressively enforces charging switch states to prevent rogue system thermal daemons (e.g., <code>mi_thermald</code>) from overriding ACC's charging switch. Only needed if your switch is being reset constantly by the system.",

    rbsp: "Resets battery statistics whenever charging reaches the pause threshold.",

    rbsu: "Resets battery statistics whenever the charger is unplugged.",

    rbspl: "Resets battery statistics whenever the charger is plugged in.",

    aiapc: "When disabled, ACC avoids idle mode if battery capacity is above the pause threshold to prevent keeping the battery highly charged for extended periods.",

    pbim: "Gives precedence to charging switches that support battery idle mode (powering the device directly off the charger without charging the battery).",

    om: "Turns charging off automatically when ACC starts and the battery capacity is between the resume and pause thresholds.",

    ia: "Matches Android app package names. When a matched app is running in the foreground, ACC automatically enables idle mode. Idle mode is not triggered in split-screen unless both visible apps match the list, and it does not trigger when the app is running in the background."
};