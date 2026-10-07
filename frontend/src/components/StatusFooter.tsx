import type { Status } from '@/hooks/useStatus';

export function StatusFooter({ status }: { status: Status | null }) {
  return (
    <footer className='border-t'>
      <div className='mx-auto w-full max-w-3xl px-5 py-4 text-xs text-muted-foreground'>
        {status ? (
          <>
            {status.pages} pages indexed · {status.remaining} of{' '}
            {status.daily_limit} questions left today · limit{' '}
            {status.per_visitor.per_hour} per hour,{' '}
            {status.per_visitor.per_day} per day per visitor
          </>
        ) : null}
      </div>
    </footer>
  );
}
