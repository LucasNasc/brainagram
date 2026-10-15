import { useI18n } from "../../lib/i18n";
import { Pain } from "../molecules/Pain";
import { StepSection } from "../molecules/StepSection";

/** As dores: quatro mensagens que falham antes de chegar a quem precisa. */
export function Pains() {
  const { copy } = useI18n();
  return (
    <StepSection id="dores" labelledBy="pains-title">
      <div className="lp-col">
        <h2 id="pains-title" className="lp-title">
          {copy.pains.title}
        </h2>
      </div>
      <ol className="lp-pains">
        {copy.pains.items.map((pain) => (
          <Pain key={pain.message} pain={pain} />
        ))}
      </ol>
    </StepSection>
  );
}
