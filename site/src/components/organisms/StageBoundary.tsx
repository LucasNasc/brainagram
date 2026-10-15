import { Component, type ReactNode } from "react";

/**
 * Se o WebGL não estiver disponível, a página continua inteira: o texto, os
 * rótulos e os links não dependem do canvas.
 */
export class StageBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false };

  static getDerivedStateFromError() {
    return { failed: true };
  }

  render() {
    return this.state.failed ? null : this.props.children;
  }
}
