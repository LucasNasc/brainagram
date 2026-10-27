// Botão "Copiar": copia o valor do campo indicado em `data-target` e troca o
// rótulo por um instante (`data-copied`). Sem permissão de área de
// transferência, seleciona o texto para a pessoa copiar à mão.

export const CopyText = {
  mounted() {
    this.el.addEventListener("click", async () => {
      const target = document.getElementById(this.el.dataset.target);
      if (!target) return;
      try {
        await navigator.clipboard.writeText(target.value);
      } catch {
        target.focus();
        target.select();
        return;
      }
      const label = this.el.querySelector("[data-copy-label]");
      if (!label) return;
      this.original ??= label.textContent;
      label.textContent = this.el.dataset.copied;
      clearTimeout(this.timer);
      this.timer = setTimeout(() => (label.textContent = this.original), 1800);
    });
  },

  destroyed() {
    clearTimeout(this.timer);
  },
};
