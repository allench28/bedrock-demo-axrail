import react from "@vitejs/plugin-react";
import path from "path";
import { resolve } from "path";
import { defineConfig } from "vite";

import { compilerOptions } from "./tsconfig.paths.json";
const alias = Object.entries(compilerOptions.paths).reduce(
  (acc, [key, [value]]) => {
    const aliasKey = key.substring(0, key.length - 2);
    const path = value.substring(0, value.length - 2);
    return {
      ...acc,
      [aliasKey]: resolve(__dirname, path),
    };
  },
  {}
);

// https://vitejs.dev/config/
export default defineConfig({
  define: { global: "window" },
  plugins: [react()],
  resolve: {
    alias: {
      ...alias,
      "@": path.resolve(__dirname, "./src"),
      "./runtimeConfig": "./runtimeConfig.browser",
    },
  },
});
