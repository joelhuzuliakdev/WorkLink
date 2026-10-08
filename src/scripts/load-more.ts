/**
 * "Cargar más" sin recargar: pide el fragmento HTML de la página siguiente y
 * lo agrega a la lista. Si algo falla, sigue el enlace normal (funciona sin JS).
 */
document.addEventListener("click", async (event) => {
  const link = (event.target as HTMLElement).closest<HTMLAnchorElement>("a[data-load-more]");
  if (!link || event.metaKey || event.ctrlKey || event.shiftKey) return;
  event.preventDefault();
  if (link.getAttribute("aria-busy") === "true") return;
  const wrapper = link.closest("[data-load-more-wrapper]");
  link.textContent = "Cargando…";
  link.setAttribute("aria-busy", "true");
  try {
    const res = await fetch(link.dataset.loadMore!, { headers: { Accept: "text/html" } });
    if (!res.ok) throw new Error(String(res.status));
    const html = await res.text();
    wrapper?.insertAdjacentHTML("afterend", html);
    wrapper?.remove();
  } catch {
    window.location.href = link.href;
  }
});
