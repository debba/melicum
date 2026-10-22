// Language selector: a native <details> disclosure that also closes on Escape,
// an outside click, or focus moving elsewhere.
for (const picker of document.querySelectorAll(".lang")) {
  const summary = picker.querySelector("summary");
  const close = refocus => {
    if (!picker.open) return;
    picker.open = false;
    if (refocus) summary.focus();
  };
  document.addEventListener("click", event => { if (!picker.contains(event.target)) close(false); });
  picker.addEventListener("keydown", event => {
    if (event.key === "Escape" && picker.open) { event.stopPropagation(); close(true); }
  });
  picker.addEventListener("focusout", event => {
    if (event.relatedTarget && !picker.contains(event.relatedTarget)) close(false);
  });
}
