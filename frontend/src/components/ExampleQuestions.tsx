const EXAMPLES = [
  'How is a minister called to a vacant congregation?',
  'What censures may a Kirk Session impose?',
  'Who is entitled to sit and vote in a Presbytery?',
  'What is the procedure for a dissent and complaint?',
];

export function ExampleQuestions({
  onPick,
}: {
  onPick: (example: string) => void;
}) {
  return (
    <section className='mt-6' aria-label='Example questions'>
      <p className='text-xs font-medium uppercase tracking-wide text-muted-foreground'>
        Try
      </p>
      <ul className='mt-2.5 flex flex-col gap-1.5'>
        {EXAMPLES.map((example) => (
          <li key={example}>
            <button
              type='button'
              onClick={() => onPick(example)}
              className='text-left text-sm text-muted-foreground underline-offset-4 hover:text-foreground hover:underline'
            >
              {example}
            </button>
          </li>
        ))}
      </ul>
    </section>
  );
}
