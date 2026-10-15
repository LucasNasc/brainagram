import { REPO_URL } from "../../lib/config";
import { checkoutSource } from "../../lib/copy";
import { useI18n } from "../../lib/i18n";
import { CodeBlock } from "../molecules/CodeBlock";
import { Message } from "../molecules/Message";
import { StepSection } from "../molecules/StepSection";

const INSTALL = [`git clone ${REPO_URL}.git`, "cd brainagram", "cp .env.example .env", "docker compose up -d"];

export function HowToUse() {
  const { copy, lang } = useI18n();
  const [up, write, share] = copy.use.steps;
  // Os participantes e o primeiro passo do exemplo: o bastante para começar.
  const source = checkoutSource(copy);
  const snippet = [...source.slice(2, 5), "", ...source.slice(8, 12)];
  const gif = lang === "pt" ? "./media/checkout.pt-BR.gif" : "./media/checkout.en.gif";
  return (
    <StepSection id="como-usar" labelledBy="use-title">
      <Message from={2} to={3} kind="async">
        {copy.use.message}
      </Message>
      <div className="lp-col">
        <h2 id="use-title" className="lp-title">
          {copy.use.title}
        </h2>
      </div>
      <ol className="lp-use">
        <li className="lp-use__step">
          <div className="lp-use__text">
            <h3>{up.title}</h3>
            <p>{up.body}</p>
          </div>
          <CodeBlock lines={INSTALL} language="shell" label="shell" />
        </li>
        <li className="lp-use__step">
          <div className="lp-use__text">
            <h3>{write.title}</h3>
            <p>{write.body}</p>
          </div>
          <CodeBlock lines={snippet} language="brain" label={copy.how.source} />
        </li>
        <li className="lp-use__step lp-use__step--wide">
          <div className="lp-use__text">
            <h3>{share.title}</h3>
            <p>{share.body}</p>
          </div>
          <img className="lp-use__gif" src={gif} alt={copy.use.gifAlt} width={2364} height={1777} loading="lazy" decoding="async" />
        </li>
      </ol>
    </StepSection>
  );
}
