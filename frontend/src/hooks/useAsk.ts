import { useCallback, useRef, useState } from "react";

export type Source = {
  page: number;
  chapter: string;
  label: string;
};

export type AskStatus = "idle" | "routing" | "streaming" | "done" | "error";

export type AskState = {
  status: AskStatus;
  answer: string;
  sources: Source[];
  error: string | null;
  /** Pages the answer cited that were never supplied to it — i.e. fabricated. */
  unverifiedCitations: number[];
};

const INITIAL: AskState = {
  status: "idle",
  answer: "",
  sources: [],
  error: null,
  unverifiedCitations: [],
};

/**
 * Consumes the /api/ask Server-Sent Events stream.
 *
 * EventSource is not an option here: it only issues GET requests, and the
 * question goes up in a POST body. So we read the response stream by hand and
 * parse SSE frames off it.
 */
export function useAsk() {
  const [state, setState] = useState<AskState>(INITIAL);
  const abortRef = useRef<AbortController | null>(null);

  const cancel = useCallback(() => {
    abortRef.current?.abort();
    abortRef.current = null;
  }, []);

  const reset = useCallback(() => {
    cancel();
    setState(INITIAL);
  }, [cancel]);

  const ask = useCallback(
    async (question: string) => {
      cancel();
      const controller = new AbortController();
      abortRef.current = controller;

      setState({ ...INITIAL, status: "routing" });

      try {
        const response = await fetch("/api/ask", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ question }),
          signal: controller.signal,
        });

        // Failures that happen before streaming starts (validation, per-IP
        // throttle, daily cap) come back as ordinary JSON with a 4xx status.
        if (!response.ok || !response.body) {
          const message = await readJsonError(response);
          setState({ ...INITIAL, status: "error", error: message });
          return;
        }

        await consume(response.body, setState);
      } catch (error) {
        if (controller.signal.aborted) return; // deliberate cancel; not an error
        setState({
          ...INITIAL,
          status: "error",
          error: "Couldn't reach the service. Check your connection and try again.",
        });
      } finally {
        if (abortRef.current === controller) abortRef.current = null;
      }
    },
    [cancel],
  );

  return { state, ask, reset, cancel };
}

async function readJsonError(response: Response): Promise<string> {
  try {
    const body = await response.json();
    if (typeof body?.error === "string") return body.error;
  } catch {
    /* fall through to the generic message */
  }
  return `Request failed (${response.status}).`;
}

async function consume(
  body: ReadableStream<Uint8Array>,
  setState: React.Dispatch<React.SetStateAction<AskState>>,
) {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });

    // Frames are separated by a blank line. A frame may be split across
    // network chunks, so only consume complete ones and keep the remainder.
    let boundary = buffer.indexOf("\n\n");
    while (boundary !== -1) {
      apply(buffer.slice(0, boundary), setState);
      buffer = buffer.slice(boundary + 2);
      boundary = buffer.indexOf("\n\n");
    }
  }

  // If the connection closed without a `done` frame, don't leave the UI
  // spinning forever.
  setState((prev) => (prev.status === "streaming" || prev.status === "routing"
    ? { ...prev, status: "done" }
    : prev));
}

function apply(
  frame: string,
  setState: React.Dispatch<React.SetStateAction<AskState>>,
) {
  let event = "message";
  const dataLines: string[] = [];

  for (const line of frame.split("\n")) {
    if (line.startsWith("event:")) event = line.slice(6).trim();
    else if (line.startsWith("data:")) dataLines.push(line.slice(5).trim());
  }
  if (dataLines.length === 0) return;

  let payload: any;
  try {
    payload = JSON.parse(dataLines.join("\n"));
  } catch {
    return; // malformed frame; skip rather than tear the whole answer down
  }

  switch (event) {
    case "sources":
      setState((prev) => ({
        ...prev,
        status: "streaming",
        sources: payload.sources ?? [],
      }));
      break;

    case "token":
      setState((prev) => ({
        ...prev,
        status: "streaming",
        answer: prev.answer + (payload.text ?? ""),
      }));
      break;

    case "no_answer":
      setState((prev) => ({
        ...prev,
        status: "done",
        answer: payload.message ?? "",
      }));
      break;

    case "done":
      setState((prev) => ({
        ...prev,
        status: "done",
        unverifiedCitations: payload.unverified_citations ?? [],
      }));
      break;

    case "error":
      setState((prev) => ({
        ...prev,
        status: "error",
        error: payload.message ?? "Something went wrong.",
      }));
      break;
  }
}
