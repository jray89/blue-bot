import { TriangleAlert } from "lucide-react";

/**
 * The answer cited a page it was never given. That is a fabricated reference,
 * and the reader needs to know before they go looking for it.
 */
export function UnverifiedWarning({ pages }: { pages: number[] }) {
  return (
    <div
      role="alert"
      className="mt-5 flex items-start gap-2.5 rounded-xl border px-4 py-3"
    >
      <TriangleAlert
        className="mt-0.5 size-4 shrink-0 text-warning"
        aria-hidden
      />
      <p className="text-sm text-muted-foreground">
        This answer cited{" "}
        <strong className="font-medium text-foreground">
          {pages.map((page) => `p.${page}`).join(", ")}
        </strong>
        , which {pages.length === 1 ? "was" : "were"} not among the pages it was
        given. Treat {pages.length === 1 ? "that reference" : "those references"}{" "}
        as unreliable and verify against the printed book.
      </p>
    </div>
  );
}
