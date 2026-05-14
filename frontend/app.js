// Faro Dashboard — entry point

// ── Poller ────────────────────────────────────────────────

function updateClock() {
  store.clock = new Date().toLocaleTimeString();
}

function refreshAdapters() {
  var promises = [];
  for (var name in store.adapters) {
    (function (adapterName) {
      promises.push(
        API.latest(adapterName).then(function (data) {
          store.adapters[data.name].series = data.series;
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
              series: data.series,
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
