import { clsx } from "clsx";

interface PanelProps {
  title: string;
  children: React.ReactNode;
  className?: string;
  action?: React.ReactNode;
}

export function Panel({ title, children, className, action }: PanelProps) {
  return (
    <div
      className={clsx(
        "bg-terminal-panel border border-terminal-border rounded-lg overflow-hidden",
        className
      )}
    >
      <div className="flex items-center justify-between px-4 py-2 border-b border-terminal-border">
        <h3 className="text-xs font-semibold uppercase tracking-wider text-terminal-muted">
          {title}
        </h3>
        {action}
      </div>
      <div className="p-4">{children}</div>
    </div>
  );
}
