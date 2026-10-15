import type { ButtonHTMLAttributes } from "react";
import { Icon, type IconName } from "./Icon";

interface Props extends ButtonHTMLAttributes<HTMLButtonElement> {
  icon: IconName;
  label: string;
  tone?: "plain" | "brand";
}

/** Botão só com ícone; o rótulo vai em aria-label e na dica. */
export function IconButton({ icon, label, tone = "plain", className, ...rest }: Props) {
  const cls = ["lp-iconbtn", `lp-iconbtn--${tone}`, className].filter(Boolean).join(" ");
  return (
    <button type="button" className={cls} aria-label={label} title={label} {...rest}>
      <Icon name={icon} />
    </button>
  );
}
