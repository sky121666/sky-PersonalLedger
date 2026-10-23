import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import tailwindcss from '@tailwindcss/vite'
import { fileURLToPath, URL } from 'node:url'

export default defineConfig({
  // Support custom base path via environment variable
  base: process.env.VITE_BASE_PATH || '/',
  plugins: [
    vue(),
    tailwindcss()
  ],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url))
    }
  },
  build: {
    target: ['chrome111', 'firefox128', 'safari16.4']
  },
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        // Keep the browser Host aligned with Origin for cookie-session CSRF checks.
        changeOrigin: false
      }
    }
  }
})
