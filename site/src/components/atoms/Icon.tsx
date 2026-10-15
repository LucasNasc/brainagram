import type { ReactNode } from "react";

/** Ícones desenhados para a página: traço de 1,5 em uma grade de 20. */
const PATHS: Record<string, ReactNode> = {
  play: <path d="M6.5 4.2v11.6a.6.6 0 0 0 .92.5l9-5.8a.6.6 0 0 0 0-1l-9-5.8a.6.6 0 0 0-.92.5Z" fill="currentColor" stroke="none" />,
  pause: <path d="M6 4.5h2.6v11H6zM11.4 4.5H14v11h-2.6z" fill="currentColor" stroke="none" />,
  prev: <path d="M15 5l-6 5 6 5M6 5v10" />,
  next: <path d="M5 5l6 5-6 5M14 5v10" />,
  arrow: <path d="M4 10h12M11.5 5.5 16 10l-4.5 4.5" />,
  external: <path d="M8 5H5v10h10v-3M11 5h4v4M15 5l-6 6" />,
  copy: <path d="M7.5 7.5h8v8h-8zM12.5 7.5v-3h-8v8h3" />,
  check: <path d="m4.5 10.5 3.5 3.5 7.5-8" />,
  scroll: <path d="M10 3.5v11M5.5 10.5 10 15l4.5-4.5" />,
  participant: <path d="M4.5 5.5h11v9h-11zM4.5 8.5h11" />,
  service: <path d="M10 3.5 15.6 6.75v6.5L10 16.5l-5.6-3.25v-6.5z" />,
  database: (
    <>
      <ellipse cx="10" cy="5.5" rx="5.5" ry="2.25" />
      <path d="M4.5 5.5v9c0 1.24 2.46 2.25 5.5 2.25s5.5-1.01 5.5-2.25v-9M4.5 10c0 1.24 2.46 2.25 5.5 2.25s5.5-1.01 5.5-2.25" />
    </>
  ),
  queue: <path d="M3.5 6.5h13v7h-13zM7.5 6.5v7M11.5 6.5v7" />,
  actor: (
    <>
      <circle cx="10" cy="6.5" r="2.75" />
      <path d="M4.5 16.5c.6-3 2.7-4.5 5.5-4.5s4.9 1.5 5.5 4.5" />
    </>
  ),
  github: (
    <path
      d="M10 2.5a7.5 7.5 0 0 0-2.37 14.62c.37.07.5-.16.5-.36v-1.4c-2.08.45-2.52-.9-2.52-.9-.34-.86-.83-1.1-.83-1.1-.68-.46.05-.45.05-.45.75.05 1.15.77 1.15.77.67 1.15 1.75.82 2.18.62.07-.48.26-.82.47-1-1.66-.2-3.4-.83-3.4-3.7 0-.82.29-1.49.77-2.01-.08-.19-.33-.95.07-1.98 0 0 .63-.2 2.06.77a7.1 7.1 0 0 1 3.75 0c1.43-.97 2.06-.77 2.06-.77.4 1.03.15 1.79.07 1.98.48.52.77 1.19.77 2.01 0 2.88-1.75 3.5-3.42 3.69.27.23.51.69.51 1.39v2.06c0 .2.13.44.51.36A7.5 7.5 0 0 0 10 2.5Z"
      fill="currentColor"
      stroke="none"
    />
  ),
};

export type IconName = keyof typeof PATHS;

export function Icon({ name, size = 20 }: { name: IconName; size?: number }) {
  return (
    <svg
      className="lp-icon"
      width={size}
      height={size}
      viewBox="0 0 20 20"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      {PATHS[name]}
    </svg>
  );
}
