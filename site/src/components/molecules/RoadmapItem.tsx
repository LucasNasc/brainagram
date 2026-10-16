import type { RoadmapEntry, RoadmapStage } from "../../lib/copy";
import { Message } from "./Message";

/** Quanto da seta cada estágio já percorreu. */
const REACH: Record<RoadmapStage, number> = { specified: 0.66, planned: 0.4, exploring: 0.16 };

/**
 * Um item do roadmap: uma mensagem que ainda não chegou. A seta anda só até
 * onde a ideia já foi, e o impulso fica ali, esperando.
 */
export function RoadmapItem({ entry }: { entry: RoadmapEntry }) {
  return (
    <li className="lp-pain lp-pain--plan">
      <Message from={0} to={1} kind="async" cap={REACH[entry.stage]}>
        {entry.status}
      </Message>
      <div className="lp-pain__text">
        <h3 className="lp-pain__title">{entry.title}</h3>
        <p>{entry.body}</p>
      </div>
    </li>
  );
}
