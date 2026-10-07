import { useEffect, useState } from 'react';
import type { AskStatus } from '@/hooks/useAsk';

export type Status = {
  remaining: number;
  daily_limit: number;
  edition: string;
  pages: number;
  per_visitor: { per_hour: number; per_day: number };
};

/**
 * Remaining capacity from /api/status, refreshed on load and whenever a
 * question finishes.
 */
export function useStatus(askStatus: AskStatus) {
  const [status, setStatus] = useState<Status | null>(null);

  // Depending on `askStatus` itself matters: a boolean like
  // `askStatus === "done"` latches true after the first answer and never
  // fires again, leaving the footer count stale for the rest of the session.
  useEffect(() => {
    if (askStatus !== 'idle' && askStatus !== 'done' && askStatus !== 'error') {
      return;
    }
    fetch('/api/status')
      .then((r) => (r.ok ? r.json() : null))
      .then(setStatus)
      .catch(() => setStatus(null));
  }, [askStatus]);

  return status;
}
