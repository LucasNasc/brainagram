import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { Landing } from "./components/pages/Landing";
import { I18nProvider } from "./lib/i18n";
import "./styles/tokens.css";
import "./styles/base.css";
import "./styles/atoms.css";
import "./styles/molecules.css";
import "./styles/organisms.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <I18nProvider>
      <Landing />
    </I18nProvider>
  </StrictMode>,
);
