import { defineConfig } from "vite";
import preact from "@preact/preset-vite";
import { fileURLToPath } from "node:url";

export default defineConfig({
  plugins: [preact()],
  resolve: {
    alias: {
      "@": fileURLToPath(new URL("./src", import.meta.url)),
    },
  },
  server: {
    port: 7878,
    strictPort: false,
    proxy: {
      "/index.jsonl": "http://localhost:4848",
      "/notes": "http://localhost:4848",
      "/token": "http://localhost:4848",
    },
  },
});
