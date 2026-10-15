import { useI18n } from "../../lib/i18n";
import { useDemoLink } from "../../lib/useDemoLink";
import { Button } from "../atoms/Button";
import { Icon } from "../atoms/Icon";
import { Message } from "../molecules/Message";
import { StepSection } from "../molecules/StepSection";

export function Hero() {
  const { copy } = useI18n();
  const demo = useDemoLink();
  return (
    <StepSection id="inicio" labelledBy="hero-title" className="lp-hero">
      <Message from={0} to={4} href={demo.href}>
        {demo.message}
      </Message>
      <div className="lp-col">
        <h1 id="hero-title" className="lp-display">
          {copy.hero.title}
        </h1>
        <p className="lp-lede">{copy.hero.lede}</p>
        <div className="lp-actions">
          <Button variant="primary" size="lg" href={demo.href}>
            {demo.label}
            <Icon name="arrow" />
          </Button>
          <Button size="lg" href="#como-usar">
            {copy.cta.install}
          </Button>
        </div>
        <p className="lp-hint">
          <Icon name="scroll" size={16} />
          {copy.hero.hint}
        </p>
      </div>
    </StepSection>
  );
}
