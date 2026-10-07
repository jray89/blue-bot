import Markdown, { type Components } from "react-markdown";
import remarkGfm from "remark-gfm";

export function AnswerMarkdown({ children }: { children: string }) {
  return (
    <Markdown remarkPlugins={[remarkGfm]} components={components}>
      {children}
    </Markdown>
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
      className="border-l-2 pl-4 italic text-muted-foreground"
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
  hr: () => <hr className="border-border" />,
};
