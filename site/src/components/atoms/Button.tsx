import type { AnchorHTMLAttributes, ButtonHTMLAttributes, ReactNode } from "react";

type Variant = "primary" | "secondary" | "ghost";
type Size = "md" | "lg";

interface Common {
  variant?: Variant;
  size?: Size;
  children: ReactNode;
}

type LinkProps = Common & AnchorHTMLAttributes<HTMLAnchorElement> & { href: string };
type ActionProps = Common & ButtonHTMLAttributes<HTMLButtonElement> & { href?: undefined };

/** Botão ou link com a mesma aparência. Com `href`, é um link de verdade. */
export function Button(props: LinkProps | ActionProps) {
  const { variant = "secondary", size = "md", children, className, ...rest } = props;
  const cls = ["lp-btn", `lp-btn--${variant}`, `lp-btn--${size}`, className].filter(Boolean).join(" ");
  if (typeof props.href === "string") {
    const external = /^https?:/.test(props.href);
    return (
      <a className={cls} {...(external ? { rel: "noopener" } : {})} {...(rest as AnchorHTMLAttributes<HTMLAnchorElement>)}>
        {children}
      </a>
    );
  }
  return (
    <button type="button" className={cls} {...(rest as ButtonHTMLAttributes<HTMLButtonElement>)}>
      {children}
    </button>
  );
}
