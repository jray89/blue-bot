import { BookOpen } from 'lucide-react';

export function SiteHeader() {
  return (
    <header className='border-b'>
      <div className='mx-auto w-full max-w-3xl px-5 py-6'>
        <div className='flex items-center gap-2.5'>
          <BookOpen className='size-5 text-primary' aria-hidden />
          <h1 className='font-serif text-2xl font-semibold tracking-tight'>
            The Blue Bot
          </h1>
        </div>
        <p className='mt-1.5 text-sm text-muted-foreground'>
          Questions of polity and practice, answered from{' '}
          <em>The Practice of the Free Church of Scotland</em>, commonly known
          as "The Blue Book".
        </p>
      </div>
    </header>
  );
}
