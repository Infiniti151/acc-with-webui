/**
SPDX-FileCopyrightText: 2026 Infiniti151
SPDX-License-Identifier: GPL-3.0-or-later
**/

// This file exists only to quiet the IDE language server for the root workspace
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';

export default {
  preprocess: vitePreprocess()
};