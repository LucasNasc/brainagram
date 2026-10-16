import { REPO_URL } from "../../lib/config";
import { useI18n } from "../../lib/i18n";
import { Icon } from "../atoms/Icon";
import { Message } from "../molecules/Message";
import { RoadmapItem } from "../molecules/RoadmapItem";
import { StepSection } from "../molecules/StepSection";

/** O que vem por aí: mensagens que o diagrama ainda não tocou. */
export function Roadmap() {
  const { copy } = useI18n();
  return (
    <StepSection id="roadmap" labelledBy="roadmap-title">
      <Message from={3} to={4} kind="async">
        {copy.roadmap.message}
      </Message>
      <div className="lp-col">
        <h2 id="roadmap-title" className="lp-title">
          {copy.roadmap.title}
        </h2>
        <p className="lp-lede">{copy.roadmap.lede}</p>
      </div>
      <ol className="lp-pains">
        {copy.roadmap.items.map((entry) => (
          <RoadmapItem key={entry.title} entry={entry} />
        ))}
      </ol>
      <div className="lp-col">
        <p className="lp-hint">
          <a className="lp-link" href={`${REPO_URL}/issues`} rel="noopener">
            {copy.roadmap.discuss}
            <Icon name="external" size={16} />
          </a>
        </p>
      </div>
    </StepSection>
  );
}
