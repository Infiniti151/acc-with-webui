/**
SPDX-FileCopyrightText: 2026 Infiniti151
SPDX-License-Identifier: GPL-3.0-or-later
**/

import { exec as ksuExec } from "kernelsu";

/**
   * Custom exec wrapper for KernelSU shell calls.
   * Catches bridge exceptions, handles timeouts, and normalizes stdout/stderr output.
   *
   * @param {string} cmd - Command to execute
   * @param {number|object} [optionsOrTimeout=15000] - Timeout in ms or KernelSU options object
   * @returns {Promise<{errno: number, stdout: string, stderr: string}>}
   */
export async function exec(cmd, optionsOrTimeout = 15000) {
    let options = {};
    let timeoutMs = 15000;

    if (typeof optionsOrTimeout === "number") {
        timeoutMs = optionsOrTimeout;
    } else if (typeof optionsOrTimeout === "object" && optionsOrTimeout !== null) {
        options = optionsOrTimeout;
    }

    try {
        const execPromise = ksuExec(cmd, options);
        const timeoutPromise = new Promise((resolve) =>
            setTimeout(
                () => resolve({ errno: -3, stdout: "", stderr: "Command timed out" }),
                timeoutMs
            )
        );

        const res = await Promise.race([execPromise, timeoutPromise]);
        return {
            errno: typeof res?.errno === "number" ? res.errno : -1,
            stdout: typeof res?.stdout === "string" ? res.stdout.trim() : "",
            stderr: typeof res?.stderr === "string" ? res.stderr.trim() : "",
        };
    } catch (e) {
        return {
            errno: -2,
            stdout: "",
            stderr: e?.message || "Execution exception",
        };
    }
}
