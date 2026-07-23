import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import { viteSingleFile } from 'vite-plugin-singlefile';
import { resolve } from 'path';

export default defineConfig({
    plugins: [svelte(), viteSingleFile()],
    root: resolve(__dirname),
    build: {
        outDir: resolve(__dirname, '../install/webroot'),
        emptyOutDir: true,
        minify: 'terser',
        terserOptions: {
            compress: {
                drop_console: true,
            }
        }
    }
});