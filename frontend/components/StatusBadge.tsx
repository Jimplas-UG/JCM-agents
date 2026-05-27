import { clsx } from "clsx";

export function StatusBadge({
  status,
  label,
}: {
  status: "ok" | "warning" | "error" | "neutral";
  label: string;
}) {
  return (
    <span
      className={clsx(
        "inline-flex items-center gap-1.5 px-2 py-0.5 rounded text-xs font-medium",
        status === "ok" && "bg-terminal-green/10 text-terminal-green",
        status === "warning" && "bg-terminal-amber/10 text-terminal-amber",
        status === "error" && "bg-terminal-red/10 text-terminal-red",
        status === "neutral" && "bg-terminal-border text-terminal-muted"
      )}
    >
      <span
        className={clsx(
          "w-1.5 h-1.5 rounded-full",
          status === "ok" && "bg-terminal-green",
          status === "warning" && "bg-terminal-amber",
          status === "error" && "bg-terminal-red",
          status === "neutral" && "bg-terminal-muted"
        )}
      />
      {label}
    </span>
  );
}
