import { cleanup, render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it } from "vitest";
import type { AskState } from "@/hooks/useAsk";
import { AnswerPanel } from "./AnswerPanel";

afterEach(cleanup);

function renderState(overrides: Partial<AskState> = {}) {
  const state: AskState = {
    status: "done",
    answer: "",
    sources: [],
    error: null,
    unverifiedCitations: [],
    ...overrides,
  };
  return render(<AnswerPanel state={state} />);
}

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

  it("renders the remaining markdown elements with their mapped tags", () => {
    const article = renderAnswer(
      [
        "# Title",
        "",
        "### Sub",
        "",
        "#### Minor",
        "",
        "> Quoted text",
        "",
        "---",
        "",
        "See [the Act](https://example.org/act).",
      ].join("\n"),
    );

    // h1 and h2 are demoted to h3; h3 and h4 render as h4.
    expect(article.querySelector("h1")).toBeNull();
    expect(article.querySelector("h3")?.textContent).toBe("Title");
    expect([...article.querySelectorAll("h4")].map((h) => h.textContent)).toEqual([
      "Sub",
      "Minor",
    ]);
    expect(article.querySelector("blockquote")?.textContent?.trim()).toBe("Quoted text");
    expect(article.querySelector("hr")).not.toBeNull();

    const link = article.querySelector("a")!;
    expect(link.textContent).toBe("the Act");
    expect(link.getAttribute("href")).toBe("https://example.org/act");
    expect(link.getAttribute("target")).toBe("_blank");
    expect(link.getAttribute("rel")).toBe("noreferrer");
  });

  it("wraps tables in a horizontally scrollable container", () => {
    const article = renderAnswer("| A |\n| --- |\n| 1 |");

    expect(article.querySelector("div.overflow-x-auto > table")).not.toBeNull();
  });

  it("does not add the streaming caret once the answer is done", () => {
    const article = renderAnswer("Finished.");

    expect(article.classList).not.toContain("streaming-caret");
  });

  it("renders nothing while idle", () => {
    const { container } = renderState({ status: "idle", answer: "stale" });

    expect(container.innerHTML).toBe("");
  });

  it("shows the error message as an alert", () => {
    renderState({ status: "error", error: "The server is unavailable." });

    expect(screen.getByRole("alert").textContent).toBe("The server is unavailable.");
    expect(document.querySelector("section")).toBeNull();
    expect(document.querySelector("article")).toBeNull();
  });

  it("shows a lookup message while routing, before any answer arrives", () => {
    const { container } = renderState({ status: "routing" });

    expect(screen.getByText("Looking up the relevant pages…")).toBeTruthy();
    expect(container.querySelector("article")).toBeNull();
    expect(screen.queryByText("Read from")).toBeNull();
    expect(screen.queryByRole("alert")).toBeNull();
    expect(container.querySelector("section")?.getAttribute("aria-busy")).toBe("false");
  });

  it("marks the region busy only while streaming", () => {
    const { container, rerender } = renderState({ status: "streaming", answer: "Partial" });
    const section = container.querySelector("section")!;

    expect(section.getAttribute("aria-live")).toBe("polite");
    expect(section.getAttribute("aria-busy")).toBe("true");
    expect(screen.queryByText("Looking up the relevant pages…")).toBeNull();

    rerender(
      <AnswerPanel
        state={{
          status: "done",
          answer: "Partial",
          sources: [],
          error: null,
          unverifiedCitations: [],
        }}
      />,
    );
    expect(container.querySelector("section")?.getAttribute("aria-busy")).toBe("false");
  });

  it("lists the source pages the answer was read from", () => {
    renderState({
      answer: "Answer.",
      sources: [
        { page: 94, chapter: "Calls", label: "Calling a minister" },
        { page: 112, chapter: "Discipline", label: "Libels" },
      ],
    });

    expect(screen.getByText("Read from")).toBeTruthy();
    const items = screen.getAllByRole("listitem");
    expect(items.map((li) => li.textContent)).toEqual([
      "p.94· Calls",
      "p.112· Discipline",
    ]);
    expect(screen.getByTitle("Calling a minister").textContent).toContain("p.94");
    expect(screen.getByTitle("Libels").textContent).toContain("p.112");
  });

  it("omits the sources block when there are no sources", () => {
    renderState({ answer: "Answer." });

    expect(screen.queryByText("Read from")).toBeNull();
    expect(screen.queryByRole("list")).toBeNull();
  });

  it("warns about a single unverified citation in the singular", () => {
    renderState({ answer: "Answer.", unverifiedCitations: [301] });

    const alert = screen.getByRole("alert");
    expect(alert.querySelector("strong")?.textContent).toBe("p.301");
    expect(alert.textContent).toBe(
      "This answer cited p.301, which was not among the pages it was given. " +
        "Treat that reference as unreliable and verify against the printed book.",
    );
  });

  it("warns about multiple unverified citations in the plural", () => {
    renderState({ status: "streaming", answer: "Answer.", unverifiedCitations: [301, 405] });

    const alert = screen.getByRole("alert");
    expect(alert.querySelector("strong")?.textContent).toBe("p.301, p.405");
    expect(alert.textContent).toContain("which were not among the pages");
    expect(alert.textContent).toContain("Treat those references as unreliable");
  });

  it("shows no warning when every citation was verified", () => {
    renderState({ answer: "Answer." });

    expect(screen.queryByRole("alert")).toBeNull();
  });
});
