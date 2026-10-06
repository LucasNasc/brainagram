// Escolher um arquivo no diálogo de importar: o texto dele vai para o campo
// (o mesmo que colar). Quem converte continua sendo o servidor.

export const ReadFileInto = {
  mounted() {
    this.el.addEventListener("change", async () => {
      const file = this.el.files && this.el.files[0];
      if (!file) return;
      const target = document.getElementById(this.el.dataset.target);
      if (!target) return;
      target.value = await file.text();
      target.dispatchEvent(new Event("input", { bubbles: true }));
      const label = this.el.closest(".ba-field")?.querySelector("[data-file-name]");
      if (label) label.textContent = file.name;
      // `.brain` já diz o formato
      if (/\.brain$/i.test(file.name)) {
        const format = document.getElementById("import-format");
        if (format) format.value = "brainagram";
      }
    });
  },
};
