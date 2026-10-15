import type { Pain as PainCopy } from "../../lib/copy";
import { Message } from "./Message";

/** Uma dor: uma mensagem que falha, e o que ela custa. */
export function Pain({ pain }: { pain: PainCopy }) {
  return (
    <li className="lp-pain">
      <Message from={0} to={1} kind="fail">
        {pain.message}
      </Message>
      <div className="lp-pain__text">
        <h3 className="lp-pain__title">{pain.title}</h3>
        <p>{pain.body}</p>
      </div>
    </li>
  );
}
