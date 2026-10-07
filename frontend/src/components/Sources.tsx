import { FileText } from "lucide-react";
import type { Source } from "@/hooks/useAsk";

export function Sources({ sources }: { sources: Source[] }) {
  return (
    <div>
      <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
        Read from
      </p>
      <ul className="mt-2 flex flex-wrap gap-1.5">
        {sources.map((source) => (
          <li key={source.page}>
            <span
              title={source.label}
              className="inline-flex items-center gap-1.5 rounded-md border bg-muted px-2 py-1 text-xs text-muted-foreground"
            >
              <FileText className="size-3" aria-hidden />
              p.{source.page}
              <span className="hidden sm:inline text-muted-foreground/70">
                · {source.chapter}
              </span>
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}
