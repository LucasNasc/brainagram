import type { RoadmapEntry } from "../../lib/copy";
import { Message } from "./Message";

/**
 * Um item do roadmap: uma mensagem que ainda não tocou. A seta fica no estado
 * pendente de propósito, porque é o futuro do diagrama.
 */
export function RoadmapItem({ entry }: { entry: RoadmapEntry }) {
  return (
    <li className="lp-pain lp-pain--plan">
      <Message from={0} to={1} kind="async" hold>
        {entry.status}
      </Message>
      <div className="lp-pain__text">
        <h3 className="lp-pain__title">{entry.title}</h3>
        <p>{entry.body}</p>
      </div>
    </li>
  );
}
