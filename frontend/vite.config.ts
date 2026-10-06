import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) },
  },
  server: {
    port: 5175,
    proxy: {
      // The ask endpoint is a Server-Sent Events stream. Vite's proxy passes
      // streamed responses through without buffering or compressing them, so no
      // extra configuration is needed here — but don't add compression to this
      // route, or answers will arrive in one lump at the end.
      "/api": {
        target: "http://localhost:3000",
        changeOrigin: true,
      },
    },
  },
  test: {
    environment: "jsdom",
  },
});
