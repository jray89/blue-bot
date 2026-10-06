import { CircleAlert, FileText, TriangleAlert } from "lucide-react";
import Markdown, { type Components } from "react-markdown";
import remarkGfm from "remark-gfm";
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
        <article
          className={cn(
            "answer mt-4 font-serif text-[17px] leading-[1.65] text-[var(--foreground)]",
            // Trailing caret on the final block while streaming (see index.css).
            state.status === "streaming" && "streaming-caret",
          )}
        >
          <Markdown remarkPlugins={[remarkGfm]} components={components}>
            {state.answer}
          </Markdown>
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
 * The model answers in markdown — headings, numbered procedures, bold terms —
 * so render it as such rather than leaking `##` and `1.` into the prose.
 * react-markdown builds React elements and ignores raw HTML in the source, so
 * model output can't inject markup. Unterminated syntax mid-stream stays
 * literal until its closing half arrives.
 */
const components: Components = {
  h1: ({ node: _, ...props }) => <h3 className="text-lg font-semibold" {...props} />,
  h2: ({ node: _, ...props }) => <h3 className="text-lg font-semibold" {...props} />,
  h3: ({ node: _, ...props }) => <h4 className="font-semibold" {...props} />,
  h4: ({ node: _, ...props }) => <h4 className="font-semibold" {...props} />,
  strong: ({ node: _, ...props }) => <strong className="font-semibold" {...props} />,
  ul: ({ node: _, ...props }) => <ul className="list-disc space-y-1.5 pl-6" {...props} />,
  ol: ({ node: _, ...props }) => <ol className="list-decimal space-y-1.5 pl-6" {...props} />,
  blockquote: ({ node: _, ...props }) => (
    <blockquote
      className="border-l-2 pl-4 italic text-[var(--muted-foreground)]"
      {...props}
    />
  ),
  table: ({ node: _, ...props }) => (
    <div className="overflow-x-auto">
      <table className="w-full border-collapse text-[15px]" {...props} />
    </div>
  ),
  th: ({ node: _, ...props }) => (
    <th className="border-b px-2 py-1 text-left font-semibold" {...props} />
  ),
  td: ({ node: _, ...props }) => <td className="border-b px-2 py-1 align-top" {...props} />,
  a: ({ node: _, ...props }) => (
    <a className="underline underline-offset-2" target="_blank" rel="noreferrer" {...props} />
  ),
  hr: () => <hr className="border-[var(--border)]" />,
};

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
