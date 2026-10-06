import { act, cleanup, renderHook, waitFor } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useAsk } from "./useAsk";

afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

const encoder = new TextEncoder();

function frame(event: string, data: unknown) {
  return `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`;
}

/**
 * A streamed response the test pushes chunks into by hand. Like a real fetch,
 * aborting the request's signal errors the body mid-stream.
 */
function controlledStream() {
  let controller!: ReadableStreamDefaultController<Uint8Array>;
  const body = new ReadableStream<Uint8Array>({
    start(c) {
      controller = c;
    },
  });
  return {
    body,
    push: (text: string) => controller.enqueue(encoder.encode(text)),
    pushBytes: (bytes: Uint8Array) => controller.enqueue(bytes),
    close: () => controller.close(),
    abortWith: (signal: AbortSignal) =>
      signal.addEventListener("abort", () =>
        controller.error(new DOMException("The operation was aborted.", "AbortError")),
      ),
  };
}

/** Stubs fetch with a single streamed response; returns the stream handle. */
function stubStream() {
  const stream = controlledStream();
  const fetchMock = vi.fn(async (_url: string, init: RequestInit) => {
    stream.abortWith(init.signal!);
    return new Response(stream.body, {
      status: 200,
      headers: { "Content-Type": "text/event-stream" },
    });
  });
  vi.stubGlobal("fetch", fetchMock);
  return { ...stream, fetchMock };
}

/** Stubs fetch with a complete SSE body delivered in the given chunks. */
function stubChunks(chunks: string[]) {
  const body = new ReadableStream<Uint8Array>({
    start(c) {
      for (const chunk of chunks) c.enqueue(encoder.encode(chunk));
      c.close();
    },
  });
  vi.stubGlobal("fetch", vi.fn(async () => new Response(body, { status: 200 })));
}

async function askAndSettle(result: { current: ReturnType<typeof useAsk> }, question = "Q?") {
  await act(() => result.current.ask(question));
}

describe("useAsk", () => {
  it("starts idle", () => {
    const { result } = renderHook(() => useAsk());

    expect(result.current.state).toEqual({
      status: "idle",
      answer: "",
      sources: [],
      error: null,
      unverifiedCitations: [],
    });
  });

  it("POSTs the question as JSON", async () => {
    stubChunks([frame("done", {})]);
    const { result } = renderHook(() => useAsk());

    await askAndSettle(result, "Who moderates the Kirk Session?");

    const [url, init] = vi.mocked(fetch).mock.calls[0];
    expect(url).toBe("/api/ask");
    expect(init).toMatchObject({
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ question: "Who moderates the Kirk Session?" }),
    });
    expect(init?.signal).toBeInstanceOf(AbortSignal);
  });

  it("moves from routing to streaming to done as events arrive", async () => {
    const stream = stubStream();
    const { result } = renderHook(() => useAsk());

    let pending!: Promise<void>;
    act(() => {
      pending = result.current.ask("Q?");
    });
    expect(result.current.state.status).toBe("routing");

    const sources = [{ page: 94, chapter: "Calls", label: "p. 94" }];
    await act(async () => stream.push(frame("sources", { sources })));
    await waitFor(() => expect(result.current.state.status).toBe("streaming"));
    expect(result.current.state.sources).toEqual(sources);

    await act(async () => stream.push(frame("token", { text: "The Kirk " })));
    await act(async () => stream.push(frame("token", { text: "Session." })));
    await waitFor(() => expect(result.current.state.answer).toBe("The Kirk Session."));
    expect(result.current.state.status).toBe("streaming");

    await act(async () => {
      stream.push(frame("done", { unverified_citations: [12, 40] }));
      stream.close();
      await pending;
    });

    expect(result.current.state).toEqual({
      status: "done",
      answer: "The Kirk Session.",
      sources,
      error: null,
      unverifiedCitations: [12, 40],
    });
  });

  it("reassembles frames split across chunk boundaries", async () => {
    const whole =
      frame("sources", { sources: [{ page: 1, chapter: "A", label: "p. 1" }] }) +
      frame("token", { text: "Hello" }) +
      frame("token", { text: ", world" }) +
      frame("done", {});
    // Split mid-field, mid-JSON, and between the two newlines of a separator.
    const cuts = [5, 31, whole.indexOf("\n\n") + 1, whole.indexOf("Hello") + 2, whole.length - 3];
    const chunks = [0, ...cuts].map((start, i) => whole.slice(start, [...cuts, whole.length][i]));
    expect(chunks.join("")).toBe(whole);
    stubChunks(chunks);
    const { result } = renderHook(() => useAsk());

    await askAndSettle(result);

    expect(result.current.state.status).toBe("done");
    expect(result.current.state.answer).toBe("Hello, world");
    expect(result.current.state.sources).toHaveLength(1);
  });

  it("decodes multi-byte UTF-8 characters split across chunks", async () => {
    const stream = stubStream();
    const { result } = renderHook(() => useAsk());

    let pending!: Promise<void>;
    act(() => {
      pending = result.current.ask("Q?");
    });
    const bytes = encoder.encode(frame("token", { text: "Précis — done" }));
    const split = bytes.indexOf(0xe2) + 1; // inside the 3-byte em dash
    await act(async () => {
      stream.pushBytes(bytes.slice(0, split));
      stream.pushBytes(bytes.slice(split));
      stream.close();
      await pending;
    });

    expect(result.current.state.answer).toBe("Précis — done");
  });

  it("handles several frames in one chunk", async () => {
    stubChunks([frame("token", { text: "a" }) + frame("token", { text: "b" }) + frame("done", {})]);
    const { result } = renderHook(() => useAsk());

    await askAndSettle(result);

    expect(result.current.state.answer).toBe("ab");
    expect(result.current.state.status).toBe("done");
  });

  it("joins multi-line data fields before parsing", async () => {
    stubChunks(['event: token\ndata: {"text":\ndata: "joined"}\n\n']);
    const { result } = renderHook(() => useAsk());

    await askAndSettle(result);

    expect(result.current.state.answer).toBe("joined");
  });

  it("skips malformed, data-less, comment-only and unknown frames", async () => {
    stubChunks([
      "event: token\ndata: {not json\n\n",
      "event: token\n\n",
      ": keep-alive\n\n",
      frame("mystery", { text: "ignored" }),
      frame("token", { text: "kept" }),
    ]);
    const { result } = renderHook(() => useAsk());

    await askAndSettle(result);

    expect(result.current.state.answer).toBe("kept");
    expect(result.current.state.error).toBeNull();
  });

  it("treats frames without an event field as plain messages and ignores them", async () => {
    stubChunks([`data: ${JSON.stringify({ text: "nope" })}\n\n`]);
    const { result } = renderHook(() => useAsk());

    await askAndSettle(result);

    expect(result.current.state.answer).toBe("");
  });

  it("tolerates events with missing payload fields", async () => {
    stubChunks([frame("sources", {}), frame("token", {}), frame("done", {})]);
    const { result } = renderHook(() => useAsk());

    await askAndSettle(result);

    expect(result.current.state).toMatchObject({
      status: "done",
      answer: "",
      sources: [],
      unverifiedCitations: [],
    });
  });

  it("shows the refusal message for no_answer", async () => {
    stubChunks([frame("no_answer", { message: "The book doesn't cover that." })]);
    const { result } = renderHook(() => useAsk());

    await askAndSettle(result);

    expect(result.current.state.status).toBe("done");
    expect(result.current.state.answer).toBe("The book doesn't cover that.");
  });

  it("falls back to an empty answer when no_answer has no message", async () => {
    stubChunks([frame("token", { text: "partial" }), frame("no_answer", {})]);
    const { result } = renderHook(() => useAsk());

    await askAndSettle(result);

    expect(result.current.state).toMatchObject({ status: "done", answer: "" });
  });

  it("surfaces a mid-stream error event and keeps it after the stream closes", async () => {
    stubChunks([frame("token", { text: "Half an ans" }), frame("error", { message: "Model overloaded." })]);
    const { result } = renderHook(() => useAsk());

    await askAndSettle(result);

    expect(result.current.state).toMatchObject({
      status: "error",
      error: "Model overloaded.",
      answer: "Half an ans",
    });
  });

  it("uses a generic message for an error event without one", async () => {
    stubChunks([frame("error", {})]);
    const { result } = renderHook(() => useAsk());

    await askAndSettle(result);

    expect(result.current.state).toMatchObject({ status: "error", error: "Something went wrong." });
  });

  it("finishes rather than spinning forever when the stream closes without a done frame", async () => {
    stubChunks([frame("token", { text: "Cut off" })]);
    const { result } = renderHook(() => useAsk());

    await askAndSettle(result);

    expect(result.current.state).toMatchObject({ status: "done", answer: "Cut off" });
  });

  it("finishes when the stream closes before any event", async () => {
    stubChunks([]);
    const { result } = renderHook(() => useAsk());

    await askAndSettle(result);

    expect(result.current.state.status).toBe("done");
  });

  it("discards a trailing frame that never gets its blank-line terminator", async () => {
    stubChunks([frame("token", { text: "a" }), 'event: token\ndata: {"text":"b"}\n']);
    const { result } = renderHook(() => useAsk());

    await askAndSettle(result);

    expect(result.current.state.answer).toBe("a");
  });

  describe("failures before streaming", () => {
    it("shows the server's JSON error for a non-OK response", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(async () => Response.json({ error: "Daily limit reached." }, { status: 429 })),
      );
      const { result } = renderHook(() => useAsk());

      await askAndSettle(result);

      expect(result.current.state).toEqual({
        status: "error",
        answer: "",
        sources: [],
        error: "Daily limit reached.",
        unverifiedCitations: [],
      });
    });

    it("falls back to the status code when the error body has no message", async () => {
      vi.stubGlobal("fetch", vi.fn(async () => Response.json({ detail: "nope" }, { status: 422 })));
      const { result } = renderHook(() => useAsk());

      await askAndSettle(result);

      expect(result.current.state).toMatchObject({ status: "error", error: "Request failed (422)." });
    });

    it("falls back to the status code when the error body isn't JSON", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(async () => new Response("<html>Bad Gateway</html>", { status: 502 })),
      );
      const { result } = renderHook(() => useAsk());

      await askAndSettle(result);

      expect(result.current.state).toMatchObject({ status: "error", error: "Request failed (502)." });
    });

    it("treats an OK response with no body as an error", async () => {
      vi.stubGlobal("fetch", vi.fn(async () => new Response(null, { status: 200 })));
      const { result } = renderHook(() => useAsk());

      await askAndSettle(result);

      expect(result.current.state).toMatchObject({ status: "error", error: "Request failed (200)." });
    });

    it("reports a network failure", async () => {
      vi.stubGlobal("fetch", vi.fn(async () => Promise.reject(new TypeError("Failed to fetch"))));
      const { result } = renderHook(() => useAsk());

      await askAndSettle(result);

      expect(result.current.state).toMatchObject({
        status: "error",
        error: "Couldn't reach the service. Check your connection and try again.",
      });
    });

    it("reports a connection dropped mid-stream", async () => {
      const body = new ReadableStream<Uint8Array>({
        start(c) {
          c.enqueue(encoder.encode(frame("token", { text: "par" })));
          c.error(new TypeError("network error"));
        },
      });
      vi.stubGlobal("fetch", vi.fn(async () => new Response(body)));
      const { result } = renderHook(() => useAsk());

      await askAndSettle(result);

      expect(result.current.state).toMatchObject({
        status: "error",
        error: "Couldn't reach the service. Check your connection and try again.",
      });
    });
  });

  describe("cancellation", () => {
    it("cancel() aborts the in-flight request without reporting an error", async () => {
      const stream = stubStream();
      const { result } = renderHook(() => useAsk());

      let pending!: Promise<void>;
      act(() => {
        pending = result.current.ask("Q?");
      });
      await act(async () => stream.push(frame("token", { text: "Some" })));
      await waitFor(() => expect(result.current.state.answer).toBe("Some"));

      const signal = stream.fetchMock.mock.calls[0][1].signal!;
      await act(async () => {
        result.current.cancel();
        await pending;
      });

      expect(signal.aborted).toBe(true);
      expect(result.current.state.error).toBeNull();
      expect(result.current.state.answer).toBe("Some");
    });

    it("cancel() is a no-op when nothing is in flight", () => {
      const { result } = renderHook(() => useAsk());

      expect(() => act(() => result.current.cancel())).not.toThrow();
      expect(result.current.state.status).toBe("idle");
    });

    it("reset() aborts the request and returns to idle", async () => {
      const stream = stubStream();
      const { result } = renderHook(() => useAsk());

      let pending!: Promise<void>;
      act(() => {
        pending = result.current.ask("Q?");
      });
      await act(async () => stream.push(frame("token", { text: "Some" })));
      await waitFor(() => expect(result.current.state.answer).toBe("Some"));

      await act(async () => {
        result.current.reset();
        await pending;
      });

      expect(stream.fetchMock.mock.calls[0][1].signal!.aborted).toBe(true);
      expect(result.current.state).toEqual({
        status: "idle",
        answer: "",
        sources: [],
        error: null,
        unverifiedCitations: [],
      });
    });

    it("reset() after a finished answer clears it", async () => {
      stubChunks([frame("token", { text: "Old" }), frame("done", {})]);
      const { result } = renderHook(() => useAsk());
      await askAndSettle(result);

      act(() => result.current.reset());

      expect(result.current.state.status).toBe("idle");
      expect(result.current.state.answer).toBe("");
    });

    it("aborts a request before its response arrives without reporting an error", async () => {
      vi.stubGlobal(
        "fetch",
        vi.fn(
          (_url: string, init: RequestInit) =>
            new Promise<Response>((_resolve, reject) => {
              init.signal!.addEventListener("abort", () =>
                reject(new DOMException("Aborted", "AbortError")),
              );
            }),
        ),
      );
      const { result } = renderHook(() => useAsk());

      let pending!: Promise<void>;
      act(() => {
        pending = result.current.ask("Q?");
      });
      await act(async () => {
        result.current.cancel();
        await pending;
      });

      expect(result.current.state.error).toBeNull();
    });

    it("a new question supersedes the one in flight", async () => {
      const first = controlledStream();
      const second = controlledStream();
      const streams = [first, second];
      const fetchMock = vi.fn(async (_url: string, init: RequestInit) => {
        const stream = streams.shift()!;
        stream.abortWith(init.signal!);
        return new Response(stream.body);
      });
      vi.stubGlobal("fetch", fetchMock);
      const { result } = renderHook(() => useAsk());

      let firstPending!: Promise<void>;
      act(() => {
        firstPending = result.current.ask("First?");
      });
      await act(async () => first.push(frame("token", { text: "first answer" })));
      await waitFor(() => expect(result.current.state.answer).toBe("first answer"));

      let secondPending!: Promise<void>;
      await act(async () => {
        secondPending = result.current.ask("Second?");
        await firstPending;
      });
      expect(fetchMock.mock.calls[0][1].signal!.aborted).toBe(true);
      expect(result.current.state).toMatchObject({ status: "routing", answer: "", error: null });

      await act(async () => {
        second.push(frame("token", { text: "second answer" }) + frame("done", {}));
        second.close();
        await secondPending;
      });

      expect(result.current.state).toMatchObject({ status: "done", answer: "second answer" });
      expect(fetchMock.mock.calls[1][1].signal!.aborted).toBe(false);
    });
  });
});
