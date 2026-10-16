import { useI18n } from "../../lib/i18n";
import { useCurrentStep } from "../../lib/useCurrentStep";
import { useDemoLink } from "../../lib/useDemoLink";
import { Icon } from "../atoms/Icon";
import { Logo } from "../atoms/Logo";
import { LaneHeader } from "../molecules/LaneHeader";
import { LangSwitch } from "../molecules/LangSwitch";

export const STEP_IDS = ["inicio", "dores", "como-funciona", "como-usar", "roadmap", "demo"] as const;

/** O topo da página: os participantes do diagrama, que são a navegação. */
export function LaneNav() {
  const { copy } = useI18n();
  const current = useCurrentStep();
  const demo = useDemoLink();
  return (
    <header className="lp-nav">
      <a className="lp-nav__brand" href="#inicio">
        <Logo />
      </a>
      <nav className="lp-nav__lanes" aria-label={copy.navLabel}>
        <LaneHeader lane={0} href="#inicio" current={current === 0}>
          <Icon name="actor" size={16} />
          <span className="lp-lane__name">{copy.lanes[0]}</span>
        </LaneHeader>
        {[1, 2, 3].map((lane) => (
          <LaneHeader key={lane} lane={lane} href={`#${STEP_IDS[lane]}`} current={current === lane}>
            {copy.lanes[lane]}
          </LaneHeader>
        ))}
        <LaneHeader lane={4} href={demo.href} primary>
          <span className="lp-lane__name">{demo.short}</span>
          <Icon name="arrow" size={16} />
        </LaneHeader>
      </nav>
      <div className="lp-nav__tools">
        <LangSwitch />
      </div>
    </header>
  );
}
