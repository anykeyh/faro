// Faro Dashboard — entry point

// ── Poller ────────────────────────────────────────────────

function updateClock() {
  store.clock = new Date().toLocaleTimeString();
}

function refreshAdapters() {
  // Only refresh adapters that have at least one card referencing them.
  var needed = {};
  store.cards.forEach(function (c) {
    if (c.probes) {
      c.probes.forEach(function (p) {
        if (p.adapter !== "meta") needed[p.adapter] = true;
      });
    } else if (c.adapter && c.adapter !== "meta") {
      // fallback for old format
      needed[c.adapter] = true;
    }
  });
  // Always refresh "meta" healthy probe regardless
  if (store.adapters["meta"]) needed["meta"] = true;

  var promises = [];
  for (var name in needed) {
    (function (adapterName) {
      promises.push(
        API.latest(adapterName).then(function (data) {
          var a = store.adapters[data.name];
          a.values = data.values;
          // Append new values to series for live-updating graph cards
          var series = a.series;
          if (series && data.values) {
            var now = new Date().toISOString();
            for (var metric in data.values) {
              if (!series[metric]) series[metric] = [];
              // Replace the last point if it has the same timestamp (skip dupes)
              var pts = series[metric];
              var last = pts.length > 0 ? pts[pts.length - 1] : null;
              var val = data.values[metric];
              if (last && last.resolved_at === now) {
                last.value = val;
                last.avg = val;
              } else {
                pts.push({
                  metric: metric,
                  value: val,
                  avg: val,
                  k: 1,
                  dev: 0,
                  min: val,
                  max: val,
                  from_ts: now,
                  to_ts: now,
                  resolved_at: now,
                });
              }
            }
          }
        }),
      );
    })(name);
  }
  return Promise.all(promises);
}

function discoverAdapters() {
  return API.sensors().then(function (sensors) {
    var names = {};
    sensors.forEach(function (s) {
      names[s.name] = true;
    });
    var promises = [];
    for (var name in names) {
      if (store.adapters[name]) continue;
      (function (adapterName) {
        promises.push(
          API.latest(adapterName).then(function (data) {
            store.adapters[data.name] = {
              name: data.name,
              values: data.values,
            };
          }),
        );
      })(name);
    }
    return Promise.all(promises);
  });
}

function refreshLatches() {
  return API.latches().then(function (data) {
    store.latches = data;
  });
}

function poll() {
  API.health()
    .then(function () {
      store.online = true;
    })
    .catch(function () {
      store.online = false;
    })
    .then(discoverAdapters)
    .then(refreshAdapters)
    .then(refreshLatches)
    .then(function () {
      m.redraw();
    })
    .catch(function () {
      m.redraw();
    });
}

// ── Init ──────────────────────────────────────────────────

store.loadLayout();
updateClock();
poll();

setInterval(updateClock, 1000);
setInterval(poll, 5000);

// ── App component ─────────────────────────────────────────

var App = {
  view: function () {
    return [m(Header), m("main", m(Dashboard))];
  },
};

// ── Mount ─────────────────────────────────────────────────

m.mount(document.getElementById("app"), App);
