import { REPO_URL } from "../../lib/config";
import { useI18n } from "../../lib/i18n";
import { useDemoLink } from "../../lib/useDemoLink";
import { Button } from "../atoms/Button";
import { Icon } from "../atoms/Icon";
import { Message } from "../molecules/Message";
import { StepSection } from "../molecules/StepSection";

/** O último passo: a seta chega na demo, e a resposta volta para o visitante. */
export function Closing() {
  const { copy } = useI18n();
  const demo = useDemoLink();
  return (
    <StepSection id="demo" labelledBy="closing-title" className="lp-closing">
      <Message from={3} to={4}>
        {copy.closing.message}
      </Message>
      <div className="lp-col">
        <h2 id="closing-title" className="lp-display lp-display--closing">
          {copy.closing.title}
        </h2>
        <p className="lp-lede">{copy.closing.body}</p>
        <div className="lp-actions">
          <Button variant="primary" size="lg" href={demo.href}>
            {demo.label}
            <Icon name="arrow" />
          </Button>
          <Button size="lg" href={REPO_URL}>
            <Icon name="github" />
            {copy.cta.github}
          </Button>
        </div>
      </div>
      <Message from={4} to={0} kind="return">
        {copy.closing.reply}
      </Message>
      <footer className="lp-footer">
        <p>{copy.footer.license}</p>
        <ul>
          <li>
            <a href={`${REPO_URL}#readme`} rel="noopener">
              {copy.footer.docs}
            </a>
          </li>
          <li>
            <a href={`${REPO_URL}/blob/main/CONTRIBUTING.md`} rel="noopener">
              {copy.footer.contribute}
            </a>
          </li>
          <li>
            <a href={REPO_URL} rel="noopener">
              GitHub
            </a>
          </li>
        </ul>
      </footer>
    </StepSection>
  );
}
