/// <reference types="vitest/config" />
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';
import { VitePWA } from 'vite-plugin-pwa';

const BACKEND = 'http://127.0.0.1:8010';
// Igual ao --bg-base: fundo da splash do Android e cor da barra de status.
const BG_BASE = '#121416';

export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      // O SW novo espera o usuário tocar em "Recarregar" (UpdatePrompt).
      registerType: 'prompt',
      injectRegister: false,
      includeAssets: [
        'favicon.svg',
        'favicon-32x32.png',
        'favicon-16x16.png',
        'apple-touch-icon-180x180.png',
      ],
      manifest: {
        id: '/',
        name: 'Stemma',
        short_name: 'Stemma',
        description: 'Separe músicas em voz, bateria, baixo e outros, e mixe cada parte.',
        lang: 'pt-BR',
        start_url: '/',
        scope: '/',
        display: 'standalone',
        background_color: BG_BASE,
        theme_color: BG_BASE,
        icons: [
          { src: 'pwa-192x192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
          { src: 'pwa-512x512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
          {
            src: 'maskable-icon-512x512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'maskable',
          },
        ],
      },
      workbox: {
        // Só o app shell. Stems, peaks, exports e API nunca passam pelo cache do SW.
        globPatterns: ['**/*.{js,css,html,svg,png,webmanifest}'],
        navigateFallback: '/index.html',
        navigateFallbackDenylist: [/^\/api\//, /^\/ws/, /^\/health/],
        runtimeCaching: [],
        cleanupOutdatedCaches: true,
      },
    }),
  ],
  server: {
    port: 5183,
    strictPort: true,
    // IPv4 explícito: no Windows `localhost` vira só ::1 e o `tailscale serve` aponta para 127.0.0.1.
    host: '127.0.0.1',
    // Acesso pelo celular via `tailscale serve` (*.ts.net).
    allowedHosts: ['.ts.net'],
    proxy: {
      '/api': BACKEND,
      '/health': BACKEND,
      '/ws': { target: BACKEND, ws: true },
    },
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
    // O módulo virtual do vite-plugin-pwa não existe no Vitest; o fake simula versão nova.
    alias: { 'virtual:pwa-register/react': '/src/test/pwaRegister.ts' },
    css: { modules: { classNameStrategy: 'non-scoped' } },
  },
});
