// Mobile navigation: the section links collapse behind a disclosure button.
const nav = document.querySelector("nav");
const menu = nav.querySelector(".menu-toggle");
const setMenu = open => { nav.classList.toggle("open", open); menu.setAttribute("aria-expanded", open); };
menu.addEventListener("click", () => setMenu(!nav.classList.contains("open")));
nav.querySelector("ul").addEventListener("click", event => { if (event.target.closest("a")) setMenu(false); });
document.addEventListener("click", event => { if (!nav.contains(event.target)) setMenu(false); });
document.addEventListener("keydown", event => {
  if (event.key === "Escape" && nav.classList.contains("open")) { setMenu(false); menu.focus(); }
});
matchMedia("(max-width: 860px)").addEventListener("change", () => setMenu(false));

// Screenshot lightbox: grows from the thumbnail, browses with buttons, arrow keys and swipes, and zooms on tap.
const box = document.querySelector(".lightbox");
const stage = box.querySelector(".lb-stage");
const view = box.querySelector(".lb-img");
const zoomButton = box.querySelector(".lb-zoom");
const backdrop = box.querySelector(".lb-bg");
const chrome = [...box.querySelectorAll(".lb-ui")];
const calm = matchMedia("(prefers-reduced-motion: reduce)");
const ease = "cubic-bezier(.2, .8, .2, 1)";
const slides = [...document.querySelectorAll(".gallery figure")].map(figure => {
  const link = figure.querySelector("a"), thumb = figure.querySelector("img"), caption = figure.querySelector("figcaption");
  return {
    link, thumb, src: link.href, alt: thumb.alt,
    width: +thumb.getAttribute("width"), height: +thumb.getAttribute("height"),
    title: caption.querySelector("b").textContent, text: caption.lastChild.textContent.trim(),
  };
});
let index = 0, busy = false, zoomed = false, swipedAt = 0, running = [];

const wrap = i => (i + slides.length) % slides.length;
const preload = i => {
  const slide = slides[wrap(i)];
  if (!slide.ready) { const image = new Image(); image.src = slide.src; slide.ready = image.decode().catch(() => {}); }
  return slide.ready;
};
const play = (element, frames, options) => { const animation = element.animate(frames, options); running.push(animation); return animation.finished.catch(() => {}); };
const fade = (to, duration, delay = 0) => Promise.all([
  play(backdrop, [{ opacity: 1 - to }, { opacity: to }], { duration, easing: "ease", fill: "both" }),
  ...chrome.map(element => play(element, [{ opacity: 1 - to }, { opacity: to }], { duration: duration * .6, delay, easing: "ease", fill: "both" })),
]);
// Transform that maps rectangle b onto rectangle a; both share the image's aspect ratio.
const across = (a, b) => `translate(${a.left + a.width / 2 - b.left - b.width / 2}px, ${a.top + a.height / 2 - b.top - b.height / 2}px) scale(${a.width / b.width})`;
const onScreen = rect => rect.width > 0 && rect.bottom > 0 && rect.top < innerHeight && rect.right > 0 && rect.left < innerWidth;

function fill(i) {
  index = wrap(i);
  const slide = slides[index];
  setZoom(false);
  view.src = slide.src;
  view.alt = slide.alt;
  view.style.setProperty("--ar", slide.width / slide.height);
  view.style.setProperty("--w", `${slide.width * 2}px`);
  box.querySelector(".lb-count").textContent = `${index + 1} / ${slides.length}`;
  box.querySelector("#lb-title").textContent = slide.title;
  box.querySelector(".lb-text").textContent = slide.text;
  box.classList.toggle("loading", !view.complete);
  preload(index + 1);
  preload(index - 1);
}
view.addEventListener("load", () => box.classList.remove("loading"));
view.addEventListener("error", () => box.classList.remove("loading"));

async function open(i) {
  fill(i);
  box.showModal();
  if (calm.matches) return;
  busy = true;
  const thumb = slides[index].thumb;
  thumb.style.visibility = "hidden";
  await Promise.all([
    play(view, [{ transform: across(thumb.getBoundingClientRect(), view.getBoundingClientRect()) }, { transform: "none" }], { duration: 420, easing: ease }),
    fade(1, 320, 120),
  ]);
  thumb.style.visibility = "";
  busy = false;
}

async function close() {
  if (busy || !box.open) return;
  setZoom(false);
  const { thumb } = slides[index];
  // Return to the current screenshot's thumbnail, sliding the mobile strip to it without moving the page.
  const gallery = thumb.closest(".gallery");
  const offset = thumb.getBoundingClientRect().left - gallery.getBoundingClientRect().left - parseFloat(getComputedStyle(gallery).scrollPaddingLeft || 0);
  gallery.scrollLeft += offset;
  if (!calm.matches) {
    busy = true;
    const target = thumb.getBoundingClientRect();
    const home = onScreen(target);
    if (home) thumb.style.visibility = "hidden";
    await Promise.all([
      home
        ? play(view, [{ transform: "none" }, { transform: across(target, view.getBoundingClientRect()) }], { duration: 360, easing: ease, fill: "forwards" })
        : play(view, [{ opacity: 1 }, { opacity: 0, transform: "scale(.96)" }], { duration: 220, easing: "ease-in", fill: "forwards" }),
      fade(0, 300),
    ]);
  }
  box.close();
}

async function go(step, from = 0) {
  if (busy) return;
  busy = true;
  setZoom(false);
  const late = setTimeout(() => box.classList.add("loading"), 150);
  await preload(index + step);
  clearTimeout(late);
  const shift = Math.min(innerWidth * .25, 120);
  if (!calm.matches) await play(view, [{ transform: `translateX(${from}px)`, opacity: 1 }, { transform: `translateX(${-step * shift}px)`, opacity: 0 }], { duration: 140, easing: "ease-in" });
  fill(index + step);
  if (!calm.matches) await play(view, [{ transform: `translateX(${step * shift}px)`, opacity: 0 }, { transform: "none", opacity: 1 }], { duration: 260, easing: ease });
  busy = false;
}

function setZoom(on, point) {
  if (on === zoomed) return;
  const fit = view.getBoundingClientRect();
  zoomed = on;
  stage.classList.toggle("zoomed", on);
  zoomButton.setAttribute("aria-pressed", on);
  if (!on) return;
  // Enlarge up to the screenshot's own resolution, keeping the selected point in place.
  const width = Math.min(fit.width * 2.5, Math.max(slides[index].width * 2, fit.width * 1.5));
  const scale = width / fit.width, area = stage.getBoundingClientRect();
  const x = point ? point.x : area.left + area.width / 2, y = point ? point.y : area.top + area.height / 2;
  view.style.setProperty("--zw", `${width}px`);
  stage.scrollLeft = (x - fit.left) * scale - (x - area.left);
  stage.scrollTop = (y - fit.top) * scale - (y - area.top);
}

// Clear animations and hidden thumbnails however the dialog closes, including a forced Escape.
box.addEventListener("close", () => {
  running.forEach(animation => animation.cancel());
  running = [];
  slides.forEach(slide => slide.thumb.style.visibility = "");
  setZoom(false);
  busy = false;
});
box.addEventListener("cancel", event => { event.preventDefault(); close(); });
box.addEventListener("keydown", event => {
  if (event.key === "ArrowRight") go(1);
  else if (event.key === "ArrowLeft") go(-1);
});
box.querySelector(".lb-close").addEventListener("click", close);
box.querySelector(".lb-prev").addEventListener("click", () => go(-1));
box.querySelector(".lb-next").addEventListener("click", () => go(1));
zoomButton.addEventListener("click", () => setZoom(!zoomed));
stage.addEventListener("click", event => {
  if (busy || performance.now() - swipedAt < 400) return;
  if (event.target === view) setZoom(!zoomed, { x: event.clientX, y: event.clientY });
  else close();
});

// Horizontal swipes on touch screens; vertical pans and pinch zoom stay with the browser.
let drag = null;
stage.addEventListener("pointerdown", event => {
  if (busy || zoomed || !event.isPrimary || event.pointerType === "mouse") return;
  drag = { id: event.pointerId, x: event.clientX, y: event.clientY, dx: 0, active: false };
});
stage.addEventListener("pointermove", event => {
  if (drag?.id !== event.pointerId) return;
  drag.dx = event.clientX - drag.x;
  if (!drag.active && Math.abs(drag.dx) > 10 && Math.abs(drag.dx) > Math.abs(event.clientY - drag.y)) {
    drag.active = true;
    stage.setPointerCapture(event.pointerId);
  }
  if (drag.active) view.style.transform = `translateX(${drag.dx}px)`;
});
const release = event => {
  if (drag?.id !== event.pointerId) return;
  const { dx, active } = drag;
  drag = null;
  if (!active) return;
  swipedAt = performance.now();
  view.style.transform = "";
  if (event.type === "pointerup" && Math.abs(dx) > 60) go(dx < 0 ? 1 : -1, dx);
  else play(view, [{ transform: `translateX(${dx}px)` }, { transform: "none" }], { duration: 200, easing: ease });
};
stage.addEventListener("pointerup", release);
stage.addEventListener("pointercancel", release);

slides.forEach((slide, i) => slide.link.addEventListener("click", event => {
  if (event.button || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
  event.preventDefault();
  open(i);
}));
