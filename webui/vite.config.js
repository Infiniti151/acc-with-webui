/**
SPDX-FileCopyrightText: 2026 Infiniti151
SPDX-License-Identifier: GPL-3.0-or-later
**/

import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import { viteSingleFile } from 'vite-plugin-singlefile';
import Icons from 'unplugin-icons/vite';
import IconsResolver from 'unplugin-icons/resolver';
import AutoImport from 'unplugin-auto-import/vite';
import { resolve } from 'node:path';
import { execSync } from 'node:child_process';

export default defineConfig(({ command, mode }) => {
    const autoDeploy = process.env.AUTO_DEPLOY === 'true';

    return {
        plugins: [
            svelte(),
            viteSingleFile(),
            AutoImport({
                resolvers: [
                    IconsResolver({
                        prefix: 'i',
                        enabledCollections: ['material-symbols']
                    })
                ]
            }),
            Icons({
                compiler: 'svelte',
                autoInstall: false
            }),
            ...(autoDeploy ? [{
                name: 'deploy-to-acc',
                closeBundle() {
                    const MODULE_DIR = '/data/adb/modules/acc';
                    const MODULE_WEBROOT = `${MODULE_DIR}/webroot`;
                    const LOCAL_WEBROOT = '../install/webroot';
                    const REMOTE_TMP = '/data/local/tmp';
                    const FONT_FILENAME = 'JetBrainsMono-VariableFont_wght.woff2';

                    const REMOTE_FONT_PATH = `${MODULE_WEBROOT}/fonts/${FONT_FILENAME}`;
                    const LOCAL_FONT_PATH = `${LOCAL_WEBROOT}/fonts/${FONT_FILENAME}`;
                    const REMOTE_TMP_INDEX = `${REMOTE_TMP}/index.html`;
                    const REMOTE_TMP_FONT = `${REMOTE_TMP}/${FONT_FILENAME}`;

                    try {
                        function getPreferredDevice() {
                            const output = execSync('adb devices', { stdio: 'pipe' }).toString();
                            const lines = output.split('\n').slice(1);

                            let usb = null;
                            let wireless = null;

                            for (const line of lines) {
                                const [serial, status] = line.trim().split(/\s+/);
                                if (!serial || status !== 'device') continue;

                                if (serial.includes(':')) wireless = serial;
                                else usb = serial;
                            }

                            return usb || wireless;
                        }

                        const device = getPreferredDevice();

                        if (!device) {
                            throw new Error('NO_DEVICE_CONNECTED');
                        }

                        // Pre-flight check: Verify if the ACC module is installed on the device
                        const moduleExists = execSync(`adb -s ${device} shell "su -c '[ -d ${MODULE_DIR} ] && echo 1 || echo 0'"`, { stdio: 'pipe' }).toString().trim();

                        if (moduleExists !== '1') {
                            throw new Error('MODULE_NOT_INSTALLED');
                        }

                        console.log(`🚀 Pushing WebUI to device (${device}) via ADB...`);

                        // 1. Always push index.html (since it updates on every build)
                        execSync(`adb -s ${device} push ${LOCAL_WEBROOT}/index.html ${REMOTE_TMP_INDEX}`, { stdio: 'inherit' });
                        execSync(`adb -s ${device} shell "su -c 'mv ${REMOTE_TMP_INDEX} ${MODULE_WEBROOT}/index.html'"`, { stdio: 'pipe' });

                        // 2. Check if the font file already exists on the device
                        const fontExists = execSync(`adb -s ${device} shell "su -c '[ -f ${REMOTE_FONT_PATH} ] && echo 1 || echo 0'"`, { stdio: 'pipe' }).toString().trim();

                        if (fontExists === '0') {
                            console.log('📦 Font not found on device. Pushing JetBrains Mono font file...');
                            execSync(`adb -s ${device} push ${LOCAL_FONT_PATH} ${REMOTE_TMP_FONT}`, { stdio: 'inherit' });
                            execSync(`adb -s ${device} shell "su -c 'mkdir -p ${MODULE_WEBROOT}/fonts && mv ${REMOTE_TMP_FONT} ${REMOTE_FONT_PATH}'"`, { stdio: 'pipe' });
                        } else {
                            console.log('⚡ Font already exists on device. Skipping font push.');
                        }

                        console.log('✨ Successfully deployed to ACC module!');

                    } catch (e) {
                        const errorMessage = e.message || '';
                        const stderr = e.stderr ? e.stderr.toString() : '';
                        const fullErrorText = `${errorMessage} ${stderr}`;

                        // 1. Root Check: Look for phone-side su errors captured by our 'pipe' configuration
                        const isRootMissing =
                            fullErrorText.includes('su: not found') ||
                            fullErrorText.includes('su: inaccessible') ||
                            fullErrorText.includes('permission denied');

                        // 2. ADB Check: Only assume ADB is missing if root didn't fail and it matches system patterns
                        const isADBNotInstalled = !isRootMissing && (
                            e.code === 'ENOENT' ||
                            (e.status === 127 && (fullErrorText.includes('adb') || fullErrorText.includes('command not found'))) ||
                            fullErrorText.includes('adb\' is not recognized')
                        );

                        if (isRootMissing) {
                            console.error('❌ Root access denied. Please grant root (su) access to Android Shell in your root manager app.');
                        }
                        else if (isADBNotInstalled) {
                            console.error('❌ ADB is not installed or not added to your system PATH.');
                        }
                        else if (e.message === 'NO_DEVICE_CONNECTED') {
                            console.error('❌ No Android device found. Please connect your phone via USB or Wireless ADB.');
                        }
                        else if (e.message === 'MODULE_NOT_INSTALLED') {
                            console.error(`❌ ACC module is not installed on the device (${MODULE_DIR} not found). Please flash the module first.`);
                        }
                        else {
                            console.error('⚠️ Deployment failed due to an ADB error:', errorMessage);
                        }
                    }
                }
            }] : [])
        ],
        root: resolve(import.meta.dirname),
        build: {
            outDir: resolve(import.meta.dirname, '../install/webroot'),
            emptyOutDir: true,
            minify: 'terser',
            terserOptions: {
                compress: {
                    drop_console: ['log', 'info', 'warn', 'debug', 'trace']
                },
                format: {
                    comments: false
                },
            }
        }
    };
});