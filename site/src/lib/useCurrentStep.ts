import { useSyncExternalStore } from "react";
import { timeline } from "./timeline";

/** Índice do passo (seção) que está sob a linha de leitura. */
export function useCurrentStep(): number {
  return useSyncExternalStore(timeline.subscribeStep, timeline.getCurrent, () => 0);
}
