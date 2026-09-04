import { CircleAlert, FileText, TriangleAlert } from "lucide-react";
import type { AskState } from "@/hooks/useAsk";
import { cn } from "@/lib/utils";

export function AnswerPanel({ state }: { state: AskState }) {
  if (state.status === "idle") return null;

  if (state.status === "error") {
    return (
      <div
        role="alert"
        className="mt-6 flex items-start gap-2.5 rounded-xl border px-4 py-3"
      >
        <CircleAlert
          className="mt-0.5 size-4 shrink-0 text-[var(--destructive)]"
          aria-hidden
        />
        <p className="text-sm text-[var(--foreground)]">{state.error}</p>
      </div>
    );
  }

  return (
    <section className="mt-6" aria-live="polite" aria-busy={state.status === "streaming"}>
      {state.sources.length > 0 && <Sources sources={state.sources} />}

      {state.answer && (
        <article className="mt-4 font-serif text-[17px] leading-[1.65] text-[var(--foreground)]">
          {state.answer.split(/\n{2,}/).map((paragraph, index, all) => (
            <p
              key={index}
              className={cn(
                index > 0 && "mt-3.5",
                // Trailing caret only on the final paragraph while streaming.
                state.status === "streaming" &&
                  index === all.length - 1 &&
                  "streaming-caret",
              )}
            >
              {renderEmphasis(paragraph)}
            </p>
          ))}
        </article>
      )}

      {state.status === "routing" && (
        <p className="text-sm text-[var(--muted-foreground)]">
          Looking up the relevant pages…
        </p>
      )}

      {state.unverifiedCitations.length > 0 && (
        <UnverifiedWarning pages={state.unverifiedCitations} />
      )}
    </section>
  );
}

/**
 * The model writes **bold** for the term being defined, which reads well for
 * procedural lists. Render just that — a full markdown parser would be a
 * dependency and an injection surface for very little gain.
 *
 * Splitting on a capturing group keeps the delimiters, so odd indices are the
 * emphasised runs. An unterminated `**` mid-stream simply stays literal until
 * its closing pair arrives.
 */
function renderEmphasis(text: string) {
  return text.split(/\*\*(.+?)\*\*/g).map((part, index) =>
    index % 2 === 1 ? (
      <strong key={index} className="font-semibold">
        {part}
      </strong>
    ) : (
      part
    ),
  );
}

function Sources({ sources }: { sources: AskState["sources"] }) {
  return (
    <div>
      <p className="text-xs font-medium uppercase tracking-wide text-[var(--muted-foreground)]">
        Read from
      </p>
      <ul className="mt-2 flex flex-wrap gap-1.5">
        {sources.map((source) => (
          <li key={source.page}>
            <span
              title={source.label}
              className="inline-flex items-center gap-1.5 rounded-md border bg-[var(--muted)] px-2 py-1 text-xs text-[var(--muted-foreground)]"
            >
              <FileText className="size-3" aria-hidden />
              p.{source.page}
              <span className="hidden sm:inline text-[var(--muted-foreground)]/70">
                · {source.chapter}
              </span>
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}

/**
 * The answer cited a page it was never given. That is a fabricated reference,
 * and the reader needs to know before they go looking for it.
 */
function UnverifiedWarning({ pages }: { pages: number[] }) {
  return (
    <div
      role="alert"
      className="mt-5 flex items-start gap-2.5 rounded-xl border px-4 py-3"
    >
      <TriangleAlert
        className="mt-0.5 size-4 shrink-0 text-[var(--warning)]"
        aria-hidden
      />
      <p className="text-sm text-[var(--muted-foreground)]">
        This answer cited{" "}
        <strong className="font-medium text-[var(--foreground)]">
          {pages.map((page) => `p.${page}`).join(", ")}
        </strong>
        , which {pages.length === 1 ? "was" : "were"} not among the pages it was
        given. Treat {pages.length === 1 ? "that reference" : "those references"}{" "}
        as unreliable and verify against the printed book.
      </p>
    </div>
  );
}
