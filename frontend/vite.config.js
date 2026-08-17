import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Dev server pinned to port 3000 to match the Cognito app client's
// callback_urls and the API Gateway's CORS allow-list
// (terraform/environments/dev/main.tf), both of which include
// http://localhost:3000 — change all three together if this ever moves.
export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
  },
});
