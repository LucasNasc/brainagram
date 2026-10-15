import { useI18n } from "../../lib/i18n";
import { Message } from "../molecules/Message";
import { StepSection } from "../molecules/StepSection";
import { MiniPlayer } from "./MiniPlayer";

export function HowItWorks() {
  const { copy } = useI18n();
  return (
    <StepSection id="como-funciona" labelledBy="how-title">
      <Message from={1} to={2}>
        {copy.how.message}
      </Message>
      <div className="lp-col">
        <h2 id="how-title" className="lp-title">
          {copy.how.title}
        </h2>
        <p className="lp-lede">{copy.how.lede}</p>
      </div>
      <div className="lp-wide">
        <MiniPlayer />
        <dl className="lp-facts">
          {copy.how.features.map((feature) => (
            <div key={feature.term} className="lp-facts__item">
              <dt>{feature.term}</dt>
              <dd>{feature.body}</dd>
            </div>
          ))}
        </dl>
      </div>
    </StepSection>
  );
}
