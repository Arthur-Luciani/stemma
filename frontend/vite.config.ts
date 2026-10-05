/// <reference types="vitest/config" />
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

const BACKEND = 'http://127.0.0.1:8010';

export default defineConfig({
  plugins: [react()],
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
    css: { modules: { classNameStrategy: 'non-scoped' } },
  },
});
