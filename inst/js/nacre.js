(function() {
  var defined = new Set();
  var PROP_ATTRS = { value: true, disabled: true, checked: true, selected: true };

  Shiny.addCustomMessageHandler('nacre-attr', function(msg) {
    var el = document.getElementById(msg.id);
    if (!el) return;
    if (document.activeElement === el && msg.attr === 'value') return;
    if (PROP_ATTRS[msg.attr]) {
      el[msg.attr] = msg.value;
    } else if (msg.value === false || msg.value === null) {
      el.removeAttribute(msg.attr);
    } else {
      if (msg.attr === 'textContent') {
        el.textContent = msg.value;
      } else {
        el.setAttribute(msg.attr, msg.value);
      }
    }
  });

  Shiny.addCustomMessageHandler('nacre-swap', function(msg) {
    var el = document.getElementById(msg.id);
    if (!el) return;
    Shiny.unbindAll(el);
    el.innerHTML = msg.html;
    // Defer bindAll so Shiny finishes processing all messages in the
    // current flush before we ask it to discover new output bindings
    setTimeout(function() { Shiny.bindAll(el); }, 0);
  });

  // --- Rate limiting (throttle / debounce with optional coalesce) ---
  // NOTE: Shiny dispatches shiny:idle as a jQuery event, NOT a native DOM
  // event. All listeners must use $(document).one(), not addEventListener.

  var managed = {};  // inputId -> state object
  var idleListenerActive = false;

  function sendEvent(inputId, value, id) {
    Shiny.setInputValue(inputId, {
      value: value, id: id, nonce: Math.random()
    }, { priority: 'event' });
  }

  function onShinyIdle() {
    idleListenerActive = false;
    var anySent = false;
    for (var inputId in managed) {
      var s = managed[inputId];
      if (s.serverBusy) {
        s.serverBusy = false;
        if (s.maybeSend) s.maybeSend();
        if (s.serverBusy) anySent = true;
      }
    }
    if (anySent) {
      $(document).one('shiny:idle', onShinyIdle);
      idleListenerActive = true;
    }
  }

  function ensureIdleListener() {
    if (!idleListenerActive) {
      $(document).one('shiny:idle', onShinyIdle);
      idleListenerActive = true;
    }
  }

  function setupThrottle(el, msg) {
    var s = {
      value: null, id: null,
      timerRunning: false, timerReady: false,
      serverBusy: false,
      coalesce: msg.coalesce,
      leading: msg.leading,
      maybeSend: null
    };

    s.maybeSend = function() {
      if (s.coalesce && s.serverBusy) return;
      if (!s.timerReady) return;
      if (s.value === null) return;
      var val = s.value; var id = s.id;
      s.value = null; s.id = null;
      s.timerReady = false;
      s.serverBusy = true;
      sendEvent(msg.inputId, val, id);
      s.timerRunning = true;
      setTimeout(function() {
        s.timerRunning = false;
        s.timerReady = true;
        s.maybeSend();
      }, msg.ms);
      if (s.coalesce) ensureIdleListener();
    };

    managed[msg.inputId] = s;

    el.addEventListener(msg.event, function(e) {
      s.value = el.value;
      s.id = msg.id;
      if (!s.timerRunning) {
        if (s.leading) {
          // Fire immediately, start cooldown timer
          var val = s.value; var id = s.id;
          s.value = null; s.id = null;
          s.serverBusy = true;
          sendEvent(msg.inputId, val, id);
          s.timerRunning = true;
          setTimeout(function() {
            s.timerRunning = false;
            s.timerReady = true;
            s.maybeSend();
          }, msg.ms);
          if (s.coalesce) ensureIdleListener();
        } else {
          // Start timer, send when it fires
          s.timerRunning = true;
          setTimeout(function() {
            s.timerRunning = false;
            s.timerReady = true;
            s.maybeSend();
          }, msg.ms);
        }
      }
    });
  }

  function setupDebounce(el, msg) {
    var s = {
      value: null, id: null,
      timerId: null, timerReady: false,
      serverBusy: false,
      coalesce: msg.coalesce,
      maybeSend: null
    };

    s.maybeSend = function() {
      if (s.coalesce && s.serverBusy) return;
      if (!s.timerReady) return;
      if (s.value === null) return;
      var val = s.value; var id = s.id;
      s.value = null; s.id = null;
      s.timerReady = false;
      s.serverBusy = true;
      sendEvent(msg.inputId, val, id);
      if (s.coalesce) ensureIdleListener();
    };

    managed[msg.inputId] = s;

    el.addEventListener(msg.event, function(e) {
      s.value = el.value;
      s.id = msg.id;
      s.timerReady = false;
      if (s.timerId !== null) clearTimeout(s.timerId);
      s.timerId = setTimeout(function() {
        s.timerId = null;
        s.timerReady = true;
        s.maybeSend();
      }, msg.ms);
    });
  }

  Shiny.addCustomMessageHandler('nacre-events', function(msgs) {
    msgs.forEach(function(msg) {
      var el = document.getElementById(msg.id);
      if (!el) return;
      var key = msg.id + ':' + msg.event;
      if (defined.has(key)) return;
      defined.add(key);
      if (msg.mode === 'throttle') {
        setupThrottle(el, msg);
      } else if (msg.mode === 'debounce') {
        setupDebounce(el, msg);
      } else {
        el.addEventListener(msg.event, function(e) {
          sendEvent(msg.inputId, el.value, msg.id);
        });
      }
    });
  });
})();
