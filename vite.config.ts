import { svelte } from '@sveltejs/vite-plugin-svelte'
import tailwindcss from '@tailwindcss/vite'
import { defineConfig } from 'vite'
import RubyPlugin from 'vite-plugin-ruby'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'

const rootDir = dirname(fileURLToPath(import.meta.url))

export default defineConfig({
  resolve: {
    alias: {
      '@inertiajs/svelte': resolve(rootDir, 'vendor/inertia/packages/svelte/dist/index.js'),
      '@inertiajs/svelte/server': resolve(rootDir, 'vendor/inertia/packages/svelte/dist/server.js'),
      '@inertiajs/core': resolve(rootDir, 'vendor/inertia/packages/core/dist/index.js'),
      '@inertiajs/core/server': resolve(rootDir, 'vendor/inertia/packages/core/dist/server.js'),
    },
    conditions: [
      'svelte',
      'browser',
      'module',
      'import',
      'default',
      'development',
      'production',
    ],
  },
  plugins: [
    svelte(),
    tailwindcss(),
    RubyPlugin(),
  ],
})
