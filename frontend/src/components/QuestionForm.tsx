import type { Ref } from 'react';
import { CornerDownLeft, Loader2 } from 'lucide-react';
import type { AskStatus } from '@/hooks/useAsk';
import { cn } from '@/lib/utils';

const MAX_QUESTION_LENGTH = 500;

type QuestionFormProps = {
  question: string;
  onQuestionChange: (question: string) => void;
  onSubmit: () => void;
  status: AskStatus;
  inputRef?: Ref<HTMLTextAreaElement>;
};

export function QuestionForm({
  question,
  onQuestionChange,
  onSubmit,
  status,
  inputRef,
}: QuestionFormProps) {
  const busy = status === 'routing' || status === 'streaming';

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        onSubmit();
      }}
    >
      <label htmlFor='question' className='sr-only'>
        Your question
      </label>
      <div className='rounded-xl border bg-card shadow-sm focus-within:ring-2 focus-within:ring-ring'>
        <textarea
          id='question'
          ref={inputRef}
          rows={3}
          value={question}
          maxLength={MAX_QUESTION_LENGTH}
          disabled={busy}
          placeholder='e.g. What is the procedure for moderating in a call?'
          onChange={(e) => onQuestionChange(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) onSubmit();
          }}
          className='w-full resize-none bg-transparent px-4 py-3 text-[15px] leading-relaxed outline-none placeholder:text-muted-foreground disabled:opacity-60'
        />
        <div className='flex items-center justify-between gap-3 border-t px-3 py-2'>
          <span className='text-xs tabular-nums text-muted-foreground'>
            {question.length}/{MAX_QUESTION_LENGTH}
          </span>
          <button
            type='submit'
            disabled={busy || question.trim().length === 0}
            className={cn(
              'inline-flex items-center gap-1.5 rounded-lg px-3.5 py-1.5 text-sm font-medium transition',
              'bg-primary text-primary-foreground',
              'disabled:cursor-not-allowed disabled:opacity-45',
              !busy && 'hover:opacity-90',
            )}
          >
            {busy ? (
              <>
                <Loader2 className='size-3.5 animate-spin' aria-hidden />
                {status === 'routing' ? 'Finding pages' : 'Answering'}
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
  );
}
