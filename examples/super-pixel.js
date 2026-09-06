/*
 * Super Pixel
 * ------------------------------------------------------------------
 * One embeddable pixel that:
 *
 * 1. Creates a capture session when the page loads.
 * 2. Tracks form interactions.
 * 3. Sends the submitted lead to the Rails backend.
 * 4. Polls the Rails backend for REAL verification activity.
 *
 * Real mode:
 *
 *   <script
 *     async
 *     src="/super-pixel.js"
 *     data-pixel-id="px_demo"
 *     data-endpoint="http://localhost:3000"
 *   ></script>
 *
 * Simulation mode:
 *
 *   Remove data-endpoint and the local demo simulation will run.
 */

(function () {
  "use strict";

  var script =
    document.currentScript ||
    (function () {
      var scripts = document.getElementsByTagName("script");

      return scripts[scripts.length - 1];
    })();

  var CONFIG = {
    pixelId: (script && script.getAttribute("data-pixel-id")) || "px_demo",

    endpoint: (script && script.getAttribute("data-endpoint")) || null,

    pollingIntervalMs: 750,

    layers: [
      "vpn_proxy",
      "anura",
      "trustedform",
      "blacklist_alliance",
      "dnc",
      "phone_validation",
      "email_validation",
      "enrichment",
      "duplicate_detection",
      "voice",
      "consensus",
    ],
  };

  /*
   * ---------------------------------------------------------------
   * Event bus
   * ---------------------------------------------------------------
   *
   * The host landing page subscribes through:
   *
   *   SuperPixel.onActivity(...)
   *
   * We use emit() internally so the pixel itself does not need to
   * know anything about the landing page UI.
   */

  var listeners = [];

  function emit(event) {
    for (var i = 0; i < listeners.length; i++) {
      try {
        listeners[i](event);
      } catch (error) {
        /*
         * A bug inside the host page must never break
         * lead capture or verification.
         */
      }
    }
  }

  /*
   * ---------------------------------------------------------------
   * Session
   * ---------------------------------------------------------------
   */

  function sessionId() {
    return (
      "sess_" +
      Date.now().toString(36) +
      "_" +
      Math.random().toString(36).slice(2, 8)
    );
  }

  var SESSION = {
    session_id: sessionId(),
    pixel_id: CONFIG.pixelId,
    page_url: window.location.href,
    referrer: document.referrer || null,
    user_agent: navigator.userAgent,
    started_at: new Date().toISOString(),
    interactions: [],
  };

  /*
   * ---------------------------------------------------------------
   * HTTP helpers
   * ---------------------------------------------------------------
   */

  function buildUrl(path) {
    if (!CONFIG.endpoint) {
      return null;
    }

    return CONFIG.endpoint.replace(/\/$/, "") + path;
  }

  function post(path, body) {
    if (!CONFIG.endpoint) {
      return Promise.resolve(null);
    }

    return fetch(buildUrl(path), {
      method: "POST",

      headers: {
        "Content-Type": "application/json",
      },

      body: JSON.stringify(body),

      keepalive: true,
    })
      .then(function (response) {
        if (!response.ok) {
          return response
            .json()
            .catch(function () {
              return {};
            })
            .then(function (body) {
              var message =
                body.error || "Request failed with status " + response.status;

              throw new Error(message);
            });
        }

        return response.json();
      })
      .catch(function (error) {
        emit({
          type: "info",
          message: "Super Pixel request failed: " + error.message,
        });

        return null;
      });
  }

  function get(path) {
    if (!CONFIG.endpoint) {
      return Promise.resolve(null);
    }

    return fetch(buildUrl(path), {
      method: "GET",

      headers: {
        Accept: "application/json",
      },

      cache: "no-store",
    })
      .then(function (response) {
        if (!response.ok) {
          throw new Error("Request failed with status " + response.status);
        }

        return response.json();
      })
      .catch(function (error) {
        /*
         * Polling errors are intentionally non-fatal.
         *
         * A temporary network failure should not destroy the
         * subscription. The next polling cycle can retry.
         */

        console.warn("Super Pixel activity polling failed:", error.message);

        return null;
      });
  }

  /*
   * ---------------------------------------------------------------
   * Capture visit
   * ---------------------------------------------------------------
   *
   * Rails records request.remote_ip when this request arrives.
   * Later, the lead submit IP can be compared against this visit IP.
   */

  post("/visit", {
    session_id: SESSION.session_id,
    pixel_id: SESSION.pixel_id,
    page_url: SESSION.page_url,
    referrer: SESSION.referrer,
    user_agent: SESSION.user_agent,
    started_at: SESSION.started_at,
  });

  emit({
    type: "session_started",
    session: SESSION,
  });

  /*
   * ---------------------------------------------------------------
   * Form instrumentation
   * ---------------------------------------------------------------
   */

  function trackForm(form) {
    /*
     * Prevent accidental double attachment.
     *
     * This matters if SuperPixel.attach(form) is called manually
     * after our automatic boot logic already attached the form.
     */

    if (form.__superPixelAttached) {
      return;
    }

    form.__superPixelAttached = true;

    var fields = form.querySelectorAll("input, select, textarea");

    Array.prototype.forEach.call(fields, function (element) {
      ["focus", "blur", "change"].forEach(function (eventType) {
        element.addEventListener(eventType, function () {
          var interaction = {
            name: element.name || element.id || "(unnamed)",

            action: eventType,

            at: new Date().toISOString(),
          };

          SESSION.interactions.push(interaction);

          emit({
            type: "field",
            interaction: interaction,
          });
        });
      });
    });

    form.addEventListener("submit", function (event) {
      /*
       * The supplied demo form stays on the page so the
       * verification activity can be displayed.
       *
       * A production integration can allow its normal form
       * submission to continue.
       */

      if (form.hasAttribute("data-pixel-demo")) {
        event.preventDefault();
      }

      var data = {};

      Array.prototype.forEach.call(fields, function (element) {
        if (!element.name) {
          return;
        }

        /*
         * Handle checkboxes more usefully than simply
         * reading .value.
         */

        if (element.type === "checkbox") {
          data[element.name] = element.checked;

          return;
        }

        data[element.name] = element.value;
      });

      var fixtureKey = data.fixture_key || null;

      delete data.fixture_key;

      var lead = {
        session_id: SESSION.session_id,
        pixel_id: SESSION.pixel_id,

        fixture_key: fixtureKey,
        submitted_at: new Date().toISOString(),

        form_dwell_ms: Date.now() - new Date(SESSION.started_at).getTime(),

        fields: data,

        /*
         * We retain interaction evidence with the submission
         * even though our first Rails endpoint does not yet
         * persist all interaction details.
         */
        interactions: SESSION.interactions.slice(),
      };

      emit({
        type: "submitted",
        lead: lead,
      });

      /*
       * REAL MODE
       *
       * Rails:
       *
       * POST /leads
       *   ↓
       * VerificationRunner
       *   ↓
       * ActivityEvent rows
       *   ↓
       * subscribeToActivity()
       */

      if (CONFIG.endpoint) {
        post("/leads", lead).then(function (response) {
          if (!response || !response.lead_id) {
            emit({
              type: "info",
              message: "Lead submission did not return a lead ID.",
            });

            return;
          }

          subscribeToActivity(response.lead_id);
        });

        return;
      }

      /*
       * No endpoint configured:
       * preserve the original standalone demo behavior.
       */

      simulateVerification(lead);
    });
  }

  /*
   * ---------------------------------------------------------------
   * Real verification activity polling
   * ---------------------------------------------------------------
   *
   * Backend contract:
   *
   * GET /leads/:lead_id/activity?after_id=123
   *
   * Response:
   *
   * {
   *   "lead_id": "L-1001",
   *   "events": [
   *     {
   *       "id": 124,
   *       "event_type": "layer_result",
   *       "payload": {...},
   *       "created_at": "..."
   *     }
   *   ]
   * }
   *
   * We remember the newest event ID so every request only asks
   * Rails for events we have not already processed.
   */

  function subscribeToActivity(leadId) {
    var lastEventId = 0;
    var stopped = false;
    var timer = null;

    emit({
      type: "info",
      message: "Subscribed to verification activity for " + leadId,
    });

    function stopPolling() {
      stopped = true;

      if (timer) {
        clearTimeout(timer);
        timer = null;
      }
    }

    function scheduleNextPoll() {
      if (stopped) {
        return;
      }

      timer = setTimeout(poll, CONFIG.pollingIntervalMs);
    }

    function poll() {
      if (stopped) {
        return;
      }

      var path =
        "/leads/" +
        encodeURIComponent(leadId) +
        "/activity?after_id=" +
        encodeURIComponent(lastEventId);

      get(path).then(function (response) {
        if (stopped) {
          return;
        }

        if (!response || !Array.isArray(response.events)) {
          scheduleNextPoll();
          return;
        }

        var finalVerdictReceived = false;

        response.events.forEach(function (activityEvent) {
          if (activityEvent.id > lastEventId) {
            lastEventId = activityEvent.id;
          }

          var isFinal = handleActivityEvent(activityEvent);

          if (isFinal) {
            finalVerdictReceived = true;
          }
        });

        if (finalVerdictReceived) {
          stopPolling();
          return;
        }

        scheduleNextPoll();
      });
    }

    /*
     * Poll immediately.
     *
     * Our current Rails VerificationRunner is synchronous, which
     * means verification may have already finished by the time
     * POST /leads returns.
     *
     * Starting with after_id=0 is therefore important: the first
     * request retrieves the persisted events that already exist.
     */

    poll();

    return {
      stop: stopPolling,
    };
  }

  /*
   * ---------------------------------------------------------------
   * Translate Rails ActivityEvent → landing page event shape
   * ---------------------------------------------------------------
   */

  function handleActivityEvent(activityEvent) {
    var payload = activityEvent.payload || {};

    switch (activityEvent.event_type) {
      case "verification_started":
        emit({
          type: "info",
          message:
            "Verification started using policy " +
            (payload.policy_version || "unknown"),
        });

        return false;

      case "layer_result":
        emit({
          type: "layer_result",

          layer: payload.layer_name,

          verdict: displayLayerVerdict(payload),

          detail: layerDetail(payload),

          execution_status: payload.execution_status,

          risk_score: payload.risk_score,

          credit_cost: payload.credit_cost,

          raw_response: payload.raw_response,
        });

        return false;

      case "final_verdict":
        emit({
          type: "final_verdict",

          verdict: payload.decision,

          score: payload.risk_score,

          hard_stop: payload.hard_stop,

          reasons: payload.reasons || [],
        });

        return true;

      case "info":
        emit({
          type: "info",
          message: payload.message || "Verification activity",
        });

        return false;

      default:
        /*
         * Unknown activity types are safely ignored so backend
         * additions remain backward compatible with older pixels.
         */

        return false;
    }
  }

  function displayLayerVerdict(payload) {
    if (payload.execution_status === "not_applicable") {
      return "skip";
    }

    if (payload.execution_status === "not_enabled") {
      return "skip";
    }

    if (payload.execution_status === "insufficient_credits") {
      return "warn";
    }

    if (payload.execution_status === "failed") {
      return "warn";
    }

    return payload.verdict || "unknown";
  }

  function layerDetail(payload) {
    if (payload.reason) {
      return payload.reason;
    }

    if (payload.execution_status === "not_applicable") {
      return "Layer was not applicable to this lead.";
    }

    if (payload.execution_status === "not_enabled") {
      return "Layer is not enabled for this pixel.";
    }

    var raw = payload.raw_response || {};

    /*
     * Give the supplied landing page a short readable detail.
     * The complete normalized response is still available through
     * raw_response if a richer UI wants it.
     */

    if (raw.status) {
      return "status: " + raw.status;
    }

    if (raw.risk) {
      return "risk: " + raw.risk;
    }

    if (raw.verdict) {
      return "result: " + raw.verdict;
    }

    return payload.execution_status || "completed";
  }

  /*
   * ---------------------------------------------------------------
   * SIMULATION ONLY
   * ---------------------------------------------------------------
   *
   * This remains available when data-endpoint is not supplied.
   *
   * When data-endpoint IS supplied, none of these simulated
   * verification results are used.
   */

  function simulateVerification(lead) {
    var demo = {
      vpn_proxy: {
        verdict: "pass",
        detail: "residential IP, submit matches visit",
      },

      anura: {
        verdict: "pass",
        detail: "result: good",
      },

      trustedform: {
        verdict: "pass",
        detail: "cert verified, phone+email match",
      },

      blacklist_alliance: {
        verdict: "pass",
        detail: "no litigator match",
      },

      dnc: {
        verdict: "pass",
        detail: "callable, window open",
      },

      phone_validation: {
        verdict: "pass",
        detail: "3/3 providers valid mobile",
      },

      email_validation: {
        verdict: "pass",
        detail: "2/2 deliverable",
      },

      enrichment: {
        verdict: "pass",
        detail: "2 sources agree, identity matches",
      },

      duplicate_detection: {
        verdict: "pass",
        detail: "no CRM match for account",
      },

      voice: {
        verdict: "skip",
        detail: "no voice sample",
      },
    };

    var order = CONFIG.layers.filter(function (layer) {
      return layer !== "consensus";
    });

    var index = 0;

    (function step() {
      if (index >= order.length) {
        emit({
          type: "final_verdict",
          verdict: "ACCEPT",
          score: 0,
          reasons: ["Simulation mode", "All demo layers passed"],
        });

        return;
      }

      var layer = order[index++];

      var result = demo[layer] || {
        verdict: "pass",
        detail: "",
      };

      emit({
        type: "layer_result",
        layer: layer,
        verdict: result.verdict,
        detail: result.detail,
      });

      setTimeout(step, 420 + Math.random() * 380);
    })();
  }

  /*
   * ---------------------------------------------------------------
   * Public API
   * ---------------------------------------------------------------
   */

  window.SuperPixel = {
    config: CONFIG,

    session: SESSION,

    onActivity: function (callback) {
      listeners.push(callback);
    },

    attach: trackForm,

    subscribeToActivity: subscribeToActivity,
  };

  /*
   * Automatically attach to:
   *
   * <form data-pixel-form>
   */

  function boot() {
    var forms = document.querySelectorAll("form[data-pixel-form]");

    Array.prototype.forEach.call(forms, trackForm);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
