// Faro Dashboard — entry point

// ── Poller ────────────────────────────────────────────────

function updateClock() {
  store.clock = new Date().toLocaleTimeString();
}

function refreshAdapters() {
  var promises = [];
  for (var name in store.adapters) {
    promises.push(
      API.latest(name).then(function (data) {
        store.adapters[data.name].series = data.series;
      }),
    );
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
      promises.push(
        API.latest(name).then(function (data) {
          store.adapters[data.name] = { name: data.name, series: data.series };
        }),
      );
    }
    return Promise.all(promises);
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
