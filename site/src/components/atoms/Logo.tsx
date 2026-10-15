/** A marca do Brainagram; o ponto violeta é o impulso. */
export function Logo({ wordmark = true }: { wordmark?: boolean }) {
  return (
    <span className="lp-logo">
      <svg width="24" height="24" viewBox="0 0 28 30" aria-hidden="true" focusable="false">
        <circle cx="9" cy="6" r="3.5" fill="currentColor" />
        <path d="M9 9.5V21" stroke="currentColor" strokeWidth="3" strokeLinecap="round" fill="none" />
        <circle cx="16.5" cy="21" r="7.5" stroke="currentColor" strokeWidth="3" fill="none" />
        <circle className="lp-logo__impulse" cx="21.8" cy="15.7" r="3.4" />
      </svg>
      <span className={wordmark ? "lp-logo__word" : "lp-sr"}>brainagram</span>
    </span>
  );
}
