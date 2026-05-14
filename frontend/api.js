// Faro API helpers

var API = {};

API.fetchJSON = function (url) {
  return fetch(url).then(function (r) {
    if (!r.ok) throw new Error(r.status + " " + r.statusText);
    return r.json();
  });
};

API.health = function () {
  return API.fetchJSON("/health");
};

API.sensors = function () {
  return API.fetchJSON("/api/sensors");
};

// Full query — returns columnar format { fields, values }
API.query = function (name, minutes) {
  var since = new Date(Date.now() - (minutes || 5) * 60000).toISOString();
  var until = new Date().toISOString();
  return API.fetchJSON(
    "/api/sensors/" +
      encodeURIComponent(name) +
      "?since=" +
      encodeURIComponent(since) +
      "&until=" +
      encodeURIComponent(until),
  );
};

// Latest values only — lightweight, for the polling loop
API.latest = function (name) {
  return API.fetchJSON("/api/sensors/" + encodeURIComponent(name) + "/latest");
};

API.latches = function () {
  return API.fetchJSON("/api/latches");
};
