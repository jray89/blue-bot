import { useEffect, useRef, useState } from 'react';
import { BookOpen, CornerDownLeft, Loader2 } from 'lucide-react';
import { useAsk } from '@/hooks/useAsk';
import { AnswerPanel } from '@/components/AnswerPanel';
import { cn } from '@/lib/utils';

const MAX_QUESTION_LENGTH = 500;

type Status = {
  remaining: number;
  daily_limit: number;
  edition: string;
  pages: number;
};

const EXAMPLES = [
  'How is a minister called to a vacant congregation?',
  'What censures may a Kirk Session impose?',
  'Who is entitled to sit and vote in a Presbytery?',
  'What is the procedure for a dissent and complaint?',
];

export default function App() {
  const { state, ask, reset } = useAsk();
  const [question, setQuestion] = useState('');
  const [status, setStatus] = useState<Status | null>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  const busy = state.status === 'routing' || state.status === 'streaming';

  // Refresh remaining capacity on load and whenever a question finishes.
  // Depending on `state.status` itself matters: a boolean like
  // `state.status === "done"` latches true after the first answer and never
  // fires again, leaving the footer count stale for the rest of the session.
  useEffect(() => {
    if (
      state.status !== 'idle' &&
      state.status !== 'done' &&
      state.status !== 'error'
    ) {
      return;
    }
    fetch('/api/status')
      .then((r) => (r.ok ? r.json() : null))
      .then(setStatus)
      .catch(() => setStatus(null));
  }, [state.status]);

  const submit = (event?: React.FormEvent) => {
    event?.preventDefault();
    const trimmed = question.trim();
    if (!trimmed || busy) return;
    ask(trimmed);
  };

  const useExample = (example: string) => {
    setQuestion(example);
    reset();
    inputRef.current?.focus();
  };

  return (
    <div className='min-h-dvh flex flex-col'>
      <header className='border-b'>
        <div className='mx-auto w-full max-w-3xl px-5 py-6'>
          <div className='flex items-center gap-2.5'>
            <BookOpen className='size-5 text-[var(--primary)]' aria-hidden />
            <h1 className='font-serif text-2xl font-semibold tracking-tight'>
              The Blue Bot
            </h1>
          </div>
          <p className='mt-1.5 text-sm text-[var(--muted-foreground)]'>
            Questions of polity and practice, answered from{' '}
            <em>The Practice of the Free Church of Scotland</em>, commonly known
            as "The Blue Book".
          </p>
        </div>
      </header>

      <main className='mx-auto w-full max-w-3xl flex-1 px-5 py-7'>
        <form onSubmit={submit}>
          <label htmlFor='question' className='sr-only'>
            Your question
          </label>
          <div className='rounded-xl border bg-[var(--card)] shadow-sm focus-within:ring-2 focus-within:ring-[var(--ring)]'>
            <textarea
              id='question'
              ref={inputRef}
              rows={3}
              value={question}
              maxLength={MAX_QUESTION_LENGTH}
              disabled={busy}
              placeholder='e.g. What is the procedure for moderating in a call?'
              onChange={(e) => setQuestion(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) submit();
              }}
              className='w-full resize-none bg-transparent px-4 py-3 text-[15px] leading-relaxed outline-none placeholder:text-[var(--muted-foreground)] disabled:opacity-60'
            />
            <div className='flex items-center justify-between gap-3 border-t px-3 py-2'>
              <span className='text-xs tabular-nums text-[var(--muted-foreground)]'>
                {question.length}/{MAX_QUESTION_LENGTH}
              </span>
              <button
                type='submit'
                disabled={busy || question.trim().length === 0}
                className={cn(
                  'inline-flex items-center gap-1.5 rounded-lg px-3.5 py-1.5 text-sm font-medium transition',
                  'bg-[var(--primary)] text-[var(--primary-foreground)]',
                  'disabled:cursor-not-allowed disabled:opacity-45',
                  !busy && 'hover:opacity-90',
                )}
              >
                {busy ? (
                  <>
                    <Loader2 className='size-3.5 animate-spin' aria-hidden />
                    {state.status === 'routing' ? 'Finding pages' : 'Answering'}
                  </>
                ) : (
                  <>
                    Ask
                    <CornerDownLeft className='size-3.5' aria-hidden />
                  </>
                )}
              </button>
            </div>
          </div>
        </form>

        {state.status === 'idle' && (
          <section className='mt-6' aria-label='Example questions'>
            <p className='text-xs font-medium uppercase tracking-wide text-[var(--muted-foreground)]'>
              Try
            </p>
            <ul className='mt-2.5 flex flex-col gap-1.5'>
              {EXAMPLES.map((example) => (
                <li key={example}>
                  <button
                    type='button'
                    onClick={() => useExample(example)}
                    className='text-left text-sm text-[var(--muted-foreground)] underline-offset-4 hover:text-[var(--foreground)] hover:underline'
                  >
                    {example}
                  </button>
                </li>
              ))}
            </ul>
          </section>
        )}

        <AnswerPanel state={state} />
      </main>

      <footer className='border-t'>
        <div className='mx-auto w-full max-w-3xl px-5 py-4 text-xs text-[var(--muted-foreground)]'>
          {status ? (
            <>
              {status.pages} pages indexed · {status.remaining} of{' '}
              {status.daily_limit} questions left today
            </>
          ) : (
            <>Not a substitute for the current authorised text.</>
          )}
        </div>
      </footer>
    </div>
  );
}
