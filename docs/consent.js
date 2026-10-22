// Cookie consent and Matomo analytics. Matomo always loads, but stays cookieless
// until the visitor allows measurement; the choice lives only in localStorage.
(() => {
  const STORAGE_KEY = "melicum-cookie-consent";
  const MATOMO_URL = "//analytics.debbaweb.it/";
  const MATOMO_SITE_ID = "8";
  const POLICY_URL = "/cookie-policy/";

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
    <p class="consent-text">This site uses cookies for anonymous analytics. <a href="${POLICY_URL}">Read our cookie policy</a> for more details.</p>
    <div class="consent-prefs">
      <div class="consent-row">
        <span>Necessary</span>
        <span class="consent-switch locked" aria-checked="true" role="switch" aria-disabled="true" aria-label="Necessary, always active" title="Necessary storage is always active"></span>
      </div>
      <div class="consent-row">
        <span id="consent-measurement">Measurement</span>
        <button class="consent-switch measurement" type="button" role="switch" aria-checked="false" aria-labelledby="consent-measurement"></button>
      </div>
    </div>
    <div class="consent-actions">
      <button class="consent-btn no" type="button">No</button>
      <button class="consent-btn yes" type="button">Yes</button>
      <button class="consent-btn save" type="button">Save preferences</button>
    </div>
    <button class="consent-link" type="button"></button>`;

  const title = banner.querySelector(".consent-title");
  const toggle = banner.querySelector(".measurement");
  const textButton = banner.querySelector(".consent-link");
  let detailed = false, hasChoice = false, measurement = false;

  function render() {
    banner.classList.toggle("detailed", detailed);
    title.textContent = detailed ? "Customize your preferences" : "Can we use cookies?";
    toggle.setAttribute("aria-checked", measurement);
    textButton.textContent = !detailed ? "Customize" : hasChoice ? "Close" : "Back";
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
