import { Closing } from "../organisms/Closing";
import { Hero } from "../organisms/Hero";
import { HowItWorks } from "../organisms/HowItWorks";
import { HowToUse } from "../organisms/HowToUse";
import { Pains } from "../organisms/Pains";
import { Roadmap } from "../organisms/Roadmap";
import { SequencePage } from "../templates/SequencePage";

/** A landing: seis passos de um diagrama de sequência. */
export function Landing() {
  return (
    <SequencePage>
      <Hero />
      <Pains />
      <HowItWorks />
      <HowToUse />
      <Roadmap />
      <Closing />
    </SequencePage>
  );
}
