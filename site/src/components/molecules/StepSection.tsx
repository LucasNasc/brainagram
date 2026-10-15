import { useEffect, useRef, type ReactNode } from "react";
import { timeline } from "../../lib/timeline";

interface Props {
  id: string;
  labelledBy: string;
  className?: string;
  children: ReactNode;
}

/** Uma seção da página, que é um passo do diagrama. */
export function StepSection({ id, labelledBy, className, children }: Props) {
  const ref = useRef<HTMLElement>(null);
  useEffect(() => timeline.addStep(ref.current!, id), [id]);
  return (
    <section ref={ref} id={id} aria-labelledby={labelledBy} className={["lp-step", className].filter(Boolean).join(" ")}>
      {children}
    </section>
  );
}
