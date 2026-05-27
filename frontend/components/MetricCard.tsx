import { clsx } from "clsx";

interface MetricCardProps {
  label: string;
  value: string | number;
  sub?: string;
  variant?: "default" | "positive" | "negative" | "warning";
}

export function MetricCard({ label, value, sub, variant = "default" }: MetricCardProps) {
  return (
    <div className="bg-terminal-panel border border-terminal-border rounded-lg p-4">
      <p className="text-xs text-terminal-muted uppercase tracking-wider">{label}</p>
      <p
        className={clsx(
          "text-2xl font-mono font-semibold mt-1",
          variant === "positive" && "text-terminal-green",
          variant === "negative" && "text-terminal-red",
          variant === "warning" && "text-terminal-amber"
        )}
      >
        {value}
      </p>
      {sub && <p className="text-xs text-terminal-muted mt-1">{sub}</p>}
    </div>
  );
}
