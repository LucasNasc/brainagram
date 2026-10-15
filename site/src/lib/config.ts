export const REPO_URL = "https://github.com/LucasNasc/brainagram";

const demo = (import.meta.env.VITE_DEMO_URL as string | undefined)?.trim();

/** A demo pública, quando existe. Defina VITE_DEMO_URL no build. */
export const DEMO_URL: string | null = demo ? demo : null;
