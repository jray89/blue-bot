import { cleanup, render } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import type { AskState } from "@/hooks/useAsk";
import { AnswerPanel } from "./AnswerPanel";

afterEach(cleanup);

function renderAnswer(answer: string, status: AskState["status"] = "done") {
  const state: AskState = {
    status,
    answer,
    sources: [],
    error: null,
    unverifiedCitations: [],
  };
  return render(<AnswerPanel state={state} />).container.querySelector("article")!;
}

describe("AnswerPanel", () => {
  it("renders the model's markdown as HTML rather than literal syntax", () => {
    const article = renderAnswer(
      [
        "## Calling a minister",
        "",
        "The **Kirk Session** petitions Presbytery (p. 94).",
        "",
        "1. Moderation in a call",
        "2. Signing the call",
        "",
        "- *apud acta*",
        "- libel",
      ].join("\n"),
    );

    expect(article.querySelector("h3")?.textContent).toBe("Calling a minister");
    expect(article.querySelector("strong")?.textContent).toBe("Kirk Session");
    expect(article.querySelector("em")?.textContent).toBe("apud acta");
    expect([...article.querySelectorAll("ol > li")].map((li) => li.textContent)).toEqual([
      "Moderation in a call",
      "Signing the call",
    ]);
    expect(article.querySelectorAll("ul > li")).toHaveLength(2);
    expect(article.textContent).not.toMatch(/##|\*\*|^\d+\.|^- /m);
  });

  it("renders GFM tables", () => {
    const article = renderAnswer("| Court | Body |\n| --- | --- |\n| Lowest | Kirk Session |");

    expect(article.querySelector("th")?.textContent).toBe("Court");
    expect(article.querySelector("td:last-child")?.textContent).toBe("Kirk Session");
  });

  it("does not render raw HTML from the model", () => {
    const article = renderAnswer('Hello <img src=x onerror="alert(1)"> <script>bad()</script>');

    expect(article.querySelector("img")).toBeNull();
    expect(article.querySelector("script")).toBeNull();
  });

  it("leaves unterminated emphasis literal while streaming", () => {
    const article = renderAnswer("The **Kirk Ses", "streaming");

    expect(article.querySelector("strong")).toBeNull();
    expect(article.textContent).toContain("**Kirk Ses");
    expect(article.classList).toContain("streaming-caret");
  });
});
