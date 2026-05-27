import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{js,ts,jsx,tsx}", "./components/**/*.{js,ts,jsx,tsx}"],
  theme: {
    extend: {
      colors: {
        terminal: {
          bg: "#0a0e17",
          panel: "#111827",
          border: "#1f2937",
          accent: "#3b82f6",
          green: "#10b981",
          red: "#ef4444",
          amber: "#f59e0b",
          muted: "#6b7280",
        },
      },
      fontFamily: {
        mono: ["JetBrains Mono", "Consolas", "monospace"],
        sans: ["Inter", "system-ui", "sans-serif"],
      },
    },
  },
  plugins: [],
};

export default config;
