// Cookie consent and Matomo analytics. Matomo always loads, but stays cookieless
// until the visitor allows measurement; the choice lives only in localStorage.
(() => {
  const STORAGE_KEY = "melicum-cookie-consent";
  const MATOMO_URL = "//analytics.debbaweb.it/";
  const MATOMO_SITE_ID = "8";

  // Banner copy follows the page language; English is the default.
  const STRINGS = {
    en: {
      policy: "/cookie-policy/",
      question: "Can we use cookies?",
      customizeTitle: "Customize your preferences",
      text: "This site uses cookies for anonymous analytics.",
      readPolicy: "Read our cookie policy",
      moreDetails: "for more details.",
      necessary: "Necessary",
      necessaryLabel: "Necessary, always active",
      necessaryTitle: "Necessary storage is always active",
      measurement: "Measurement",
      no: "No",
      yes: "Yes",
      save: "Save preferences",
      customize: "Customize",
      close: "Close",
      back: "Back",
    },
    it: {
      policy: "/it/cookie-policy/",
      question: "Possiamo usare i cookie?",
      customizeTitle: "Personalizza le tue preferenze",
      text: "Questo sito usa i cookie per statistiche anonime.",
      readPolicy: "Leggi la cookie policy",
      moreDetails: "per saperne di più.",
      necessary: "Necessari",
      necessaryLabel: "Necessari, sempre attivi",
      necessaryTitle: "I dati necessari sono sempre attivi",
      measurement: "Statistiche",
      no: "No",
      yes: "Sì",
      save: "Salva preferenze",
      customize: "Personalizza",
      close: "Chiudi",
      back: "Indietro",
    },
  };
  const t = STRINGS[document.documentElement.lang.slice(0, 2)] || STRINGS.en;

  const readPrefs = () => {
    try {
      const prefs = JSON.parse(localStorage.getItem(STORAGE_KEY));
      return prefs && typeof prefs.measurement === "boolean" ? prefs : null;
    } catch {
      return null;
    }
  };
  const writePrefs = prefs => {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify(prefs)); } catch {}
  };

  let matomoLoaded = false;
  function initMatomo(cookieConsent) {
    const _paq = (window._paq = window._paq || []);
    if (matomoLoaded) {
      if (cookieConsent) _paq.push(["setCookieConsentGiven"]);
      else { _paq.push(["forgetCookieConsentGiven"]); _paq.push(["disableCookies"]); }
      return;
    }
    matomoLoaded = true;
    _paq.push([cookieConsent ? "setCookieConsentGiven" : "disableCookies"]);
    _paq.push(["setTrackerUrl", MATOMO_URL + "matomo.php"]);
    _paq.push(["setSiteId", MATOMO_SITE_ID]);
    _paq.push(["trackPageView"]);
    _paq.push(["enableLinkTracking"]);
    const script = document.createElement("script");
    script.async = true;
    script.src = MATOMO_URL + "matomo.js";
    document.head.append(script);
  }

  // Banner: a short question first, then per-category preferences on request.
  const banner = document.createElement("div");
  banner.className = "consent";
  banner.setAttribute("role", "dialog");
  banner.setAttribute("aria-labelledby", "consent-title");
  banner.hidden = true;
  banner.innerHTML = `
    <h2 class="consent-title" id="consent-title"></h2>
    <p class="consent-text">${t.text} <a href="${t.policy}">${t.readPolicy}</a> ${t.moreDetails}</p>
    <div class="consent-prefs">
      <div class="consent-row">
        <span>${t.necessary}</span>
        <span class="consent-switch locked" aria-checked="true" role="switch" aria-disabled="true" aria-label="${t.necessaryLabel}" title="${t.necessaryTitle}"></span>
      </div>
      <div class="consent-row">
        <span id="consent-measurement">${t.measurement}</span>
        <button class="consent-switch measurement" type="button" role="switch" aria-checked="false" aria-labelledby="consent-measurement"></button>
      </div>
    </div>
    <div class="consent-actions">
      <button class="consent-btn no" type="button">${t.no}</button>
      <button class="consent-btn yes" type="button">${t.yes}</button>
      <button class="consent-btn save" type="button">${t.save}</button>
    </div>
    <button class="consent-link" type="button"></button>`;

  const title = banner.querySelector(".consent-title");
  const toggle = banner.querySelector(".measurement");
  const textButton = banner.querySelector(".consent-link");
  let detailed = false, hasChoice = false, measurement = false;

  function render() {
    banner.classList.toggle("detailed", detailed);
    title.textContent = detailed ? t.customizeTitle : t.question;
    toggle.setAttribute("aria-checked", measurement);
    textButton.textContent = !detailed ? t.customize : hasChoice ? t.close : t.back;
  }

  function show() {
    const prefs = readPrefs();
    hasChoice = detailed = !!prefs;
    if (prefs) measurement = prefs.measurement;
    render();
    banner.hidden = false;
  }

  function save(value) {
    measurement = value;
    hasChoice = true;
    writePrefs({ necessary: true, measurement: value });
    banner.hidden = true;
    initMatomo(value);
  }

  toggle.addEventListener("click", () => { measurement = !measurement; render(); });
  banner.querySelector(".no").addEventListener("click", () => save(false));
  banner.querySelector(".yes").addEventListener("click", () => save(true));
  banner.querySelector(".save").addEventListener("click", () => save(measurement));
  textButton.addEventListener("click", () => {
    if (!detailed) detailed = true;
    else if (hasChoice) { banner.hidden = true; return; }
    else detailed = false;
    render();
  });
  document.addEventListener("click", event => {
    if (event.target.closest("[data-manage-cookies]")) show();
  });

  document.body.append(banner);
  const prefs = readPrefs();
  initMatomo(prefs?.measurement === true);
  if (prefs) measurement = prefs.measurement;
  else show();
})();
