import { useEffect, useRef, useState } from "react";
import { useI18n } from "../../lib/i18n";
import { highlightBrain } from "../../lib/highlight";
import { Icon } from "../atoms/Icon";

interface Props {
  lines: string[];
  /** "brain" realça a sintaxe; "shell" mostra o prompt. */
  language: "brain" | "shell";
  label: string;
  activeLine?: number;
  copyable?: boolean;
}

/** Um bloco de código com cópia. Em shell, o `$` não entra na cópia. */
export function CodeBlock({ lines, language, label, activeLine, copyable = true }: Props) {
  const { copy } = useI18n();
  const [copied, setCopied] = useState(false);
  const timer = useRef(0);
  const body = useRef<HTMLPreElement>(null);

  // Mantém a linha ativa à vista sem rolar a página (só o bloco).
  useEffect(() => {
    const pre = body.current;
    const line = pre?.querySelector<HTMLElement>("[data-active]");
    if (!pre || !line) return;
    const top = line.offsetTop - pre.offsetTop;
    if (top < pre.scrollTop + 20 || top > pre.scrollTop + pre.clientHeight - 40) {
      const row = line.offsetHeight || 20;
      pre.scrollTop = Math.max(0, Math.round((top - pre.clientHeight / 2) / row) * row);
    }
  }, [activeLine]);

  useEffect(() => () => window.clearTimeout(timer.current), []);

  const onCopy = async () => {
    try {
      await navigator.clipboard.writeText(lines.join("\n"));
      setCopied(true);
      window.clearTimeout(timer.current);
      timer.current = window.setTimeout(() => setCopied(false), 1800);
    } catch {
      // sem permissão de área de transferência: o texto continua selecionável
    }
  };

  return (
    <figure className="lp-code" data-language={language}>
      <figcaption className="lp-code__head">
        <span>{label}</span>
        {copyable && (
          <button type="button" className="lp-code__copy" onClick={onCopy}>
            <Icon name={copied ? "check" : "copy"} size={16} />
            <span aria-live="polite">{copied ? copy.player.copied : copy.player.copy}</span>
          </button>
        )}
      </figcaption>
      <pre className="lp-code__body" tabIndex={0} ref={body}>
        <code>
          {lines.map((line, i) => (
            <span key={i} className="lp-code__line" data-active={i === activeLine ? "" : undefined}>
              {language === "brain" ? highlightBrain(line) : line}
              {"\n"}
            </span>
          ))}
        </code>
      </pre>
    </figure>
  );
}
