import { act, cleanup, fireEvent, render, screen, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { AskState } from "@/hooks/useAsk";
import App from "./App";

const ask = vi.fn();
const reset = vi.fn();
const cancel = vi.fn();
let state: AskState;

vi.mock("@/hooks/useAsk", () => ({
  useAsk: () => ({ state, ask, reset, cancel }),
}));

const fetchMock = vi.fn();

function askState(overrides: Partial<AskState> = {}): AskState {
  return {
    status: "idle",
    answer: "",
    sources: [],
    error: null,
    unverifiedCitations: [],
    ...overrides,
  };
}

function statusResponse(body: unknown, ok = true) {
  return Promise.resolve({ ok, json: () => Promise.resolve(body) });
}

const STATUS = {
  remaining: 42,
  daily_limit: 50,
  edition: "2024",
  pages: 312,
  per_visitor: { per_hour: 3, per_day: 9 },
};

function textarea() {
  return screen.getByLabelText("Your question") as HTMLTextAreaElement;
}

function submitButton() {
  return screen.getByRole("button", { name: /ask|finding pages|answering/i }) as HTMLButtonElement;
}

function footer() {
  return screen.getByRole("contentinfo");
}

function type(value: string) {
  fireEvent.change(textarea(), { target: { value } });
}

beforeEach(() => {
  state = askState();
  fetchMock.mockImplementation(() => statusResponse(STATUS));
  vi.stubGlobal("fetch", fetchMock);
});

afterEach(() => {
  cleanup();
  vi.clearAllMocks();
  vi.unstubAllGlobals();
});

describe("App", () => {
  describe("asking", () => {
    it("disables Ask until the question has non-whitespace content", async () => {
      render(<App />);

      expect(submitButton().disabled).toBe(true);
      type("   ");
      expect(submitButton().disabled).toBe(true);
      type("What is a Presbytery?");
      expect(submitButton().disabled).toBe(false);
      await screen.findByText(/pages indexed/);
    });

    it("submits the trimmed question", async () => {
      render(<App />);

      type("  What is a Presbytery?  ");
      fireEvent.click(submitButton());

      expect(ask).toHaveBeenCalledExactlyOnceWith("What is a Presbytery?");
      await screen.findByText(/pages indexed/);
    });

    it("does not submit a blank question", async () => {
      render(<App />);

      type("   ");
      fireEvent.submit(textarea().closest("form")!);

      expect(ask).not.toHaveBeenCalled();
      await screen.findByText(/pages indexed/);
    });

    it("submits on Enter, including Cmd+Enter and Ctrl+Enter", async () => {
      render(<App />);
      type("What is a Presbytery?");

      expect(fireEvent.keyDown(textarea(), { key: "Enter" })).toBe(false); // default prevented: no newline
      fireEvent.keyDown(textarea(), { key: "Enter", metaKey: true });
      fireEvent.keyDown(textarea(), { key: "Enter", ctrlKey: true });
      expect(ask).toHaveBeenCalledTimes(3);
      expect(ask).toHaveBeenCalledWith("What is a Presbytery?");

      fireEvent.keyDown(textarea(), { key: "a", metaKey: true });
      expect(ask).toHaveBeenCalledTimes(3);
      await screen.findByText(/pages indexed/);
    });

    it("inserts a newline on Shift+Enter instead of submitting", async () => {
      render(<App />);
      type("What is a Presbytery?");

      expect(fireEvent.keyDown(textarea(), { key: "Enter", shiftKey: true })).toBe(true);
      expect(ask).not.toHaveBeenCalled();
      await screen.findByText(/pages indexed/);
    });

    it("shows a character counter capped at the max length", async () => {
      render(<App />);

      expect(screen.getByText("0/500")).toBeTruthy();
      expect(textarea().maxLength).toBe(500);
      type("Hello");
      expect(screen.getByText("5/500")).toBeTruthy();
      await screen.findByText(/pages indexed/);
    });
  });

  describe("while busy", () => {
    it.each([
      ["routing", "Finding pages"],
      ["streaming", "Answering"],
    ] as const)("locks the form while %s and labels the button %j", async (status, label) => {
      state = askState({ status });
      render(<App />);

      const button = screen.getByRole("button", { name: label }) as HTMLButtonElement;
      expect(button.disabled).toBe(true);
      expect(textarea().disabled).toBe(true);

      // Even if a submit sneaks through (e.g. a keyboard shortcut), it's ignored.
      fireEvent.submit(textarea().closest("form")!);
      fireEvent.keyDown(textarea(), { key: "Enter", metaKey: true });
      expect(ask).not.toHaveBeenCalled();

      expect(screen.queryByRole("region", { name: "Example questions" })).toBeNull();
    });

    it("ignores a submit while busy even with a question typed", async () => {
      const { rerender } = render(<App />);
      type("What is a Presbytery?");
      await screen.findByText(/pages indexed/);

      state = askState({ status: "streaming", answer: "Partial" });
      rerender(<App />);

      fireEvent.submit(textarea().closest("form")!);
      expect(ask).not.toHaveBeenCalled();
    });
  });

  describe("example questions", () => {
    it("lists examples when idle", async () => {
      render(<App />);

      const region = screen.getByRole("region", { name: "Example questions" });
      expect(region.querySelectorAll("button")).toHaveLength(4);
      await screen.findByText(/pages indexed/);
    });

    it("fills the question, resets the answer and focuses the input when an example is clicked", async () => {
      render(<App />);
      const example = "What censures may a Kirk Session impose?";

      fireEvent.click(screen.getByRole("button", { name: example }));

      expect(textarea().value).toBe(example);
      expect(reset).toHaveBeenCalledTimes(1);
      expect(document.activeElement).toBe(textarea());
      expect(ask).not.toHaveBeenCalled();
      expect(submitButton().disabled).toBe(false);
      await screen.findByText(/pages indexed/);
    });

    it.each(["done", "error"] as const)("hides examples once %s", async (status) => {
      state = askState({ status, answer: "An answer", error: "Boom" });
      render(<App />);

      expect(screen.queryByRole("region", { name: "Example questions" })).toBeNull();
      await screen.findByText(/pages indexed/);
    });
  });

  describe("answer panel", () => {
    it("renders the answer", async () => {
      state = askState({ status: "done", answer: "The **Kirk Session** decides." });
      render(<App />);

      expect(screen.getByText("Kirk Session").tagName).toBe("STRONG");
      await screen.findByText(/pages indexed/);
    });

    it("renders errors as an alert", async () => {
      state = askState({ status: "error", error: "Daily limit reached." });
      render(<App />);

      expect(screen.getByRole("alert").textContent).toContain("Daily limit reached.");
      await screen.findByText(/pages indexed/);
    });
  });

  describe("status footer", () => {
    it("stays empty until status loads, then shows the remaining capacity", async () => {
      render(<App />);

      expect(footer().textContent).toBe("");
      expect(
        (await screen.findByText(/pages indexed/)).textContent,
      ).toBe(
        "312 pages indexed · 42 of 50 questions left today · limit 3 per hour, 9 per day per visitor",
      );
      expect(fetchMock).toHaveBeenCalledExactlyOnceWith("/api/status");
    });

    it("stays empty when the status endpoint returns an error", async () => {
      fetchMock.mockImplementation(() => statusResponse({ error: "nope" }, false));
      render(<App />);

      await waitFor(() => expect(fetchMock).toHaveBeenCalled());
      await act(async () => {});
      expect(footer().textContent).toBe("");
    });

    it("stays empty when the status request fails", async () => {
      fetchMock.mockImplementation(() => Promise.reject(new Error("offline")));
      render(<App />);

      await waitFor(() => expect(fetchMock).toHaveBeenCalled());
      await act(async () => {});
      expect(footer().textContent).toBe("");
    });

    it("refreshes after every finished question, not just the first", async () => {
      const { rerender } = render(<App />);
      await screen.findByText(/42 of 50/);
      expect(fetchMock).toHaveBeenCalledTimes(1);

      const cycle = async (remaining: number, end: AskState["status"]) => {
        fetchMock.mockImplementation(() => statusResponse({ ...STATUS, remaining }));
        for (const status of ["routing", "streaming"] as const) {
          state = askState({ status });
          rerender(<App />);
        }
        state = askState({ status: end, answer: "x", error: "x" });
        rerender(<App />);
        await screen.findByText(new RegExp(`${remaining} of 50`));
      };

      await cycle(41, "done");
      expect(fetchMock).toHaveBeenCalledTimes(2);
      await cycle(40, "done");
      expect(fetchMock).toHaveBeenCalledTimes(3);
      await cycle(39, "error");
      expect(fetchMock).toHaveBeenCalledTimes(4);
    });

    it("does not poll while a question is in flight", () => {
      state = askState({ status: "routing" });
      const { rerender } = render(<App />);
      state = askState({ status: "streaming" });
      rerender(<App />);

      expect(fetchMock).not.toHaveBeenCalled();
    });
  });
});
