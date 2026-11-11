import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

export default defineConfig([
  // Next.js core-web-vitals rules
  ...nextVitals,

  // Next.js TypeScript-specific rules (includes recommended config)
  ...nextTs,

  // Global ignore patterns - array argument as required by ESLint >=9.22
  globalIgnores([
    "node_modules/",
    ".next/",
    "dist/",
  ]),
]);
