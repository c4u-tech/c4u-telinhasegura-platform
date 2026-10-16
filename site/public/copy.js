// The Pix key's copy button. The button
// starts hidden and appears only where the clipboard works; without it the
// key stays selectable text. No inline script: the CSP is default-src 'self'.
"use strict";

document.querySelectorAll("button[data-copy]").forEach((button) => {
  if (!navigator.clipboard || !window.isSecureContext) return;
  const status = document.getElementById(button.dataset.copied);
  button.hidden = false;
  button.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(button.dataset.copy);
      status.textContent = "Chave copiada. Cole no app do seu banco.";
    } catch {
      status.textContent = "Não deu para copiar. Selecione a chave acima e copie.";
    }
  });
});
