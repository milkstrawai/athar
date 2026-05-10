/* Athar dashboard JS — single self-contained IIFE, no build step.
 *
 * Behavior:
 *   - Partial-link clicks (anchors with `data-athar-partial-link`) intercept
 *     navigation and swap #athar-pre and #athar-post in place via a single
 *     fetch, pushing a new history entry. Modifier-clicks fall through to the
 *     browser's default open-in-new-tab.
 *   - Partial forms (`form[data-athar-partial-form]`) submit on change/input
 *     (input is debounced) the same way. Drops the page param on every submit.
 *     The form itself lives outside the swap regions, so the search input's
 *     focus / value / selection are never disturbed.
 *   - The filter bar's visual state (active segments, selected actor) is
 *     reconciled from the URL after every swap by updateFilterBarFromUrl —
 *     since the bar isn't re-rendered, we keep its highlights in sync from JS.
 *   - Back/forward (popstate) re-fetches the current URL into the regions.
 *   - Copy buttons (`[data-athar-copy="value"]`) write to the clipboard,
 *     flash a check, and announce via the ARIA live region.
 *   - Theme button (`[data-athar-theme-toggle]`) flips data-theme on <html>
 *     and PATCHes /athar/theme to persist.
 *   - Keyboard: `/` focuses the search input; Escape collapses the open row.
 */
(function () {
  "use strict";

  var SWAP_REGION_IDS = ["athar-pre", "athar-post"];
  var FILTER_DEFAULTS = { time: "30d", mode: "all", kind: "all", actor: "all" };

  // ---------- CSRF ----------
  function csrfToken() {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.content : null;
  }

  // ---------- Partial-fetch helpers (CSP-safe, DOM-method swap) ----------
  async function fetchPartial(url, options) {
    options = options || {};
    var headers = Object.assign({
      "Accept": "text/html",
      "X-Requested-With": "XMLHttpRequest",
      "X-Athar-Partial": "true"
    }, options.headers || {});

    var method = (options.method || "GET").toUpperCase();
    if (method !== "GET" && method !== "HEAD") {
      var token = csrfToken();
      if (token) headers["X-CSRF-Token"] = token;
    }

    var response = await fetch(url, Object.assign({}, options, { method: method, headers: headers }));
    if (!response.ok) throw new Error("fetchPartial: " + response.status + " " + response.statusText);
    var html = await response.text();
    return new DOMParser().parseFromString(html, "text/html");
  }

  function replaceElement(target, source) {
    while (target.firstChild) target.removeChild(target.firstChild);
    Array.from(source.childNodes).forEach(function (child) {
      target.appendChild(child.cloneNode(true));
    });
  }

  // ---------- Partial nav: swap #athar-pre + #athar-post (skip filter bar) ----------
  async function partialNav(url, options) {
    options = options || {};

    var regions = SWAP_REGION_IDS.map(function (id) { return document.getElementById(id); });
    if (regions.some(function (el) { return el == null; })) {
      // Required regions missing — fall back to a full navigation.
      window.location.href = url;
      return;
    }

    // Suppress the dimming indicator for form-driven submits — the user is
    // actively typing, and any opacity transition near the cursor reads as a
    // distracting flash on every keystroke.
    var showLoading = !options.silent;
    if (showLoading) regions.forEach(function (r) { r.classList.add("is-loading"); });

    try {
      var doc = await fetchPartial(url, options);

      regions.forEach(function (region) {
        var fresh = doc.getElementById(region.id);
        if (fresh) replaceElement(region, fresh);
      });

      // Push state BEFORE reconciling the filter bar — the reconciliation
      // reads window.location.href to decide which segment is active.
      if (options.replaceState) {
        history.replaceState({}, "", url);
      } else {
        history.pushState({}, "", url);
      }

      // Filter bar isn't re-rendered — reconcile its visual state from the URL.
      updateFilterBarFromUrl();
    } catch (error) {
      console.error("[athar] partial-nav failed, falling back to full navigation:", error);
      window.location.href = url;
    } finally {
      if (showLoading) regions.forEach(function (r) { r.classList.remove("is-loading"); });
    }
  }

  // ---------- Filter bar state reconciliation ----------
  // The filter bar lives outside the swap regions so the search input survives
  // the partial swap. The cost: we have to keep its segment highlights and
  // actor selection in sync with the URL ourselves.
  function updateFilterBarFromUrl() {
    var params = new URL(window.location.href).searchParams;

    ["time", "mode", "kind"].forEach(function (name) {
      var current = params.get(name) || FILTER_DEFAULTS[name];
      document.querySelectorAll('[data-athar-seg="' + name + '"]').forEach(function (link) {
        var matches = link.dataset.atharSegValue === current;
        link.classList.toggle("is-active", matches);
        if (matches) {
          link.setAttribute("aria-current", "page");
        } else {
          link.removeAttribute("aria-current");
        }
      });
    });

    var actorSelect = document.getElementById("athar-actor");
    if (actorSelect) {
      var actor = params.get("actor") || FILTER_DEFAULTS.actor;
      if (actorSelect.value !== actor) actorSelect.value = actor;
    }
  }

  // ---------- Form submit (build URL from current params + form data) ----------
  function buildSubmitUrl(form) {
    var action = form.action || window.location.href;
    var url = new URL(action, window.location.origin);
    // Baseline from the *current* URL, not the form's action — the form has no
    // hidden fields preserving model/time/mode/kind, so without this the only
    // params that would survive a search submit are q + actor.
    var params = new URLSearchParams(window.location.search);
    // Drop params the form is replacing or that should reset.
    params.delete("q"); params.delete("page"); params.delete("expanded");

    var data = new FormData(form);
    var entries = data.entries ? data.entries() : [];
    for (var entry of entries) {
      var key = entry[0];
      var value = entry[1];
      if (value === "" || value == null) continue;
      params.set(key, value);
    }

    url.search = params.toString();
    return url.toString();
  }

  function submitForm(form) {
    partialNav(buildSubmitUrl(form), { silent: true });
  }

  // ---------- Copy button ----------
  var COPY_CHECK_SVG = '<svg viewBox="0 0 16 16" width="11" height="11" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 8l3 3 7-7"/></svg>';

  function announce(message) {
    var region = document.getElementById("athar-aria-live");
    if (!region) return;
    region.textContent = "";
    requestAnimationFrame(function () { region.textContent = message; });
  }

  function flashCopied(button) {
    var label = button.getAttribute("data-athar-copy-label") || "text";
    announce("Copied " + label);

    var original = button.innerHTML;
    button.innerHTML = COPY_CHECK_SVG;

    if (button._atharCopyTimeout) clearTimeout(button._atharCopyTimeout);
    button._atharCopyTimeout = setTimeout(function () {
      if (button.isConnected) button.innerHTML = original;
    }, 1100);
  }

  function doCopy(button) {
    var value = button.getAttribute("data-athar-copy");
    if (!value) return;
    flashCopied(button);
    if (navigator.clipboard) {
      navigator.clipboard.writeText(value).catch(function (error) {
        console.warn("athar: clipboard write failed", error);
      });
    }
  }

  // ---------- Theme toggle (optimistic, revert on failure) ----------
  function toggleTheme(button) {
    var previous = document.documentElement.dataset.theme === "dark" ? "dark" : "light";
    var next = previous === "dark" ? "light" : "dark";
    var previousLabel = button.textContent;

    document.documentElement.dataset.theme = next;
    button.textContent = next === "dark" ? "◐" : "◑";

    var meta = document.querySelector('meta[name="athar-theme-url"]');
    var url = (meta && meta.content) || "/athar/theme";

    fetch(url, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": csrfToken() || "",
        "Accept": "application/json"
      },
      body: JSON.stringify({ theme: next })
    }).then(function (response) {
      if (!response.ok) throw new Error("HTTP " + response.status);
    }).catch(function (error) {
      // Revert optimistic UI so on-screen state stays in sync with the cookie.
      document.documentElement.dataset.theme = previous;
      button.textContent = previousLabel;
      console.warn("athar: theme persistence failed", error);
    });
  }

  // ---------- Click delegation ----------
  document.addEventListener("click", function (event) {
    // Partial-link anchors first — they need preventDefault.
    var partialLink = event.target.closest("a[data-athar-partial-link]");
    if (partialLink) {
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
      if (event.button !== 0) return;
      event.preventDefault();
      partialNav(partialLink.href);
      return;
    }

    var copyBtn = event.target.closest("[data-athar-copy]");
    if (copyBtn) {
      event.preventDefault();
      event.stopPropagation();
      doCopy(copyBtn);
      return;
    }

    var themeBtn = event.target.closest("[data-athar-theme-toggle]");
    if (themeBtn) {
      toggleTheme(themeBtn);
      return;
    }
  });

  // ---------- Form change/input delegation ----------
  var formInputDebounce;
  document.addEventListener("change", function (event) {
    var form = event.target.closest("form[data-athar-partial-form]");
    if (!form) return;
    if (formInputDebounce) { clearTimeout(formInputDebounce); formInputDebounce = null; }
    submitForm(form);
  });
  document.addEventListener("input", function (event) {
    var form = event.target.closest("form[data-athar-partial-form]");
    if (!form) return;
    if (formInputDebounce) clearTimeout(formInputDebounce);
    formInputDebounce = setTimeout(function () { submitForm(form); }, 300);
  });

  // ---------- Keyboard shortcuts ----------
  document.addEventListener("keydown", function (event) {
    // Escape always collapses an open row, even when focus is in an input —
    // otherwise the input's default Escape handling eats the first press.
    if (event.key === "Escape") {
      var collapse = document.querySelector("[data-collapse-expand]");
      if (collapse) {
        event.preventDefault();
        collapse.click();
      }
      return;
    }

    if (event.target.matches("input, textarea, select") || event.target.isContentEditable) return;

    if (event.key === "/") {
      event.preventDefault();
      var search = document.querySelector(".filter-search input[type=search]");
      if (search) search.focus();
    }
  });

  // ---------- Browser back/forward ----------
  window.addEventListener("popstate", function () {
    partialNav(window.location.href, { silent: true, replaceState: true });
  });
})();
