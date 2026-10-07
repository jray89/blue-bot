import { useRef, useState } from 'react';
import { useAsk } from '@/hooks/useAsk';
import { useStatus } from '@/hooks/useStatus';
import { AnswerPanel } from '@/components/AnswerPanel';
import { ExampleQuestions } from '@/components/ExampleQuestions';
import { QuestionForm } from '@/components/QuestionForm';
import { SiteHeader } from '@/components/SiteHeader';
import { StatusFooter } from '@/components/StatusFooter';

export default function App() {
  const { state, ask, reset } = useAsk();
  const status = useStatus(state.status);
  const [question, setQuestion] = useState('');
  const inputRef = useRef<HTMLTextAreaElement>(null);

  const busy = state.status === 'routing' || state.status === 'streaming';

  const submit = () => {
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
      <SiteHeader />

      <main className='mx-auto w-full max-w-3xl flex-1 px-5 py-7'>
        <QuestionForm
          question={question}
          onQuestionChange={setQuestion}
          onSubmit={submit}
          status={state.status}
          inputRef={inputRef}
        />

        {state.status === 'idle' && <ExampleQuestions onPick={useExample} />}

        <AnswerPanel state={state} />
      </main>

      <StatusFooter status={status} />
    </div>
  );
}
