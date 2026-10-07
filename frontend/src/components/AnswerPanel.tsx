import { CircleAlert } from "lucide-react";
import type { AskState } from "@/hooks/useAsk";
import { cn } from "@/lib/utils";
import { AnswerMarkdown } from "./AnswerMarkdown";
import { Sources } from "./Sources";
import { UnverifiedWarning } from "./UnverifiedWarning";

export function AnswerPanel({ state }: { state: AskState }) {
  if (state.status === "idle") return null;

  if (state.status === "error") {
    return (
      <div
        role="alert"
        className="mt-6 flex items-start gap-2.5 rounded-xl border px-4 py-3"
      >
        <CircleAlert
          className="mt-0.5 size-4 shrink-0 text-destructive"
          aria-hidden
        />
        <p className="text-sm text-foreground">{state.error}</p>
      </div>
    );
  }

  return (
    <section className="mt-6" aria-live="polite" aria-busy={state.status === "streaming"}>
      {state.sources.length > 0 && <Sources sources={state.sources} />}

      {state.answer && (
        <article
          className={cn(
            "answer mt-4 font-serif text-[17px] leading-[1.65] text-foreground",
            // Trailing caret on the final block while streaming (see index.css).
            state.status === "streaming" && "streaming-caret",
          )}
        >
          <AnswerMarkdown>{state.answer}</AnswerMarkdown>
        </article>
      )}

      {state.status === "routing" && (
        <p className="text-sm text-muted-foreground">
          Looking up the relevant pages…
        </p>
      )}

      {state.unverifiedCitations.length > 0 && (
        <UnverifiedWarning pages={state.unverifiedCitations} />
      )}
    </section>
  );
}
