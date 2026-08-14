import { useState, useRef, useEffect } from "preact/hooks";

const PLACEHOLDERS = [
  "/team go",
  "/discuss permission flow",
  "/learn vibe-island patterns",
  "/spec atlas-viewer-phase-2",
];

export function Composer({
  scopeLabel,
  prefill = "",
  contextLabel,
}: {
  scopeLabel: string;
  prefill?: string;
  contextLabel: string;
}) {
  const [value, setValue] = useState(prefill);
  const [placeholder, setPlaceholder] = useState(PLACEHOLDERS[0]!);
  const ref = useRef<HTMLTextAreaElement | null>(null);

  useEffect(() => {
    setValue(prefill);
  }, [prefill]);

  useEffect(() => {
    const i = Math.floor(Math.random() * PLACEHOLDERS.length);
    setPlaceholder(PLACEHOLDERS[i]!);
  }, [scopeLabel]);

  function send() {
    if (!value.trim()) return;
    setValue("");
    ref.current?.focus();
  }

  return (
    <div class="composer" role="region" aria-label="Composer">
      <div class="composer__title">💬 Discuss with {scopeLabel}</div>
      <div class="composer__row">
        <textarea
          ref={ref}
          class="composer__input"
          rows={1}
          placeholder={placeholder}
          value={value}
          onInput={(e) =>
            setValue((e.currentTarget as HTMLTextAreaElement).value)
          }
          onKeyDown={(e) => {
            if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
              e.preventDefault();
              send();
            }
          }}
        />
        <button
          type="button"
          class="composer__send"
          onClick={send}
          aria-label="Send"
        >
          ▶
        </button>
      </div>
      <div class="composer__context">Context: {contextLabel}</div>
    </div>
  );
}
