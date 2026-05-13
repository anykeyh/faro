// Faro Dashboard — Mithril application

// ── API helpers ───────────────────────────────────────────

async function fetchJSON(url) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(r.status + " " + r.statusText);
  return r.json();
}

function friendly(n, decimals) {
  decimals = decimals || 1;
  if (n === null || n === undefined) return "\u2014";
  return Number(n).toFixed(decimals);
}

function colorClass(value, warn, crit) {
  warn = warn || 70;
  crit = crit || 90;
  if (value >= crit) return "crit";
  if (value >= warn) return "warn";
  return "good";
}

function timeAgo(iso) {
  if (!iso) return "";
  var sec = Math.floor((Date.now() - new Date(iso).getTime()) / 1000);
  if (sec < 5) return "just now";
  if (sec < 60) return sec + "s ago";
  return Math.floor(sec / 60) + "m ago";
}

function latestBucket(buckets) {
  if (!buckets || buckets.length === 0) return null;
  return buckets[buckets.length - 1];
}

// ── Card config ───────────────────────────────────────────

var CARD_CONFIG = {};

CARD_CONFIG.cpu = {
  label: "CPU Usage",
  primary: "usage_pct",
  unit: "%",
  stats: [
    { label: "User", metric: "user_pct" },
    { label: "System", metric: "system_pct" },
    { label: "IOWait", metric: "iowait_pct" },
    { label: "Idle", metric: "idle_pct" },
  ],
};

CARD_CONFIG.memory = {
  label: "Memory",
  primary: "usage_pct",
  unit: "%",
  stats: [
    { label: "Used", metric: "used_kb" },
    { label: "Free", metric: "free_kb" },
    { label: "Available", metric: "available_kb" },
    { label: "Swap", metric: "swap_used_kb" },
  ],
};

CARD_CONFIG.disk = {};

// ── Store ─────────────────────────────────────────────────

var store = {
  online: false,
  clock: new Date().toLocaleTimeString(),
  adapters: [],
};

setInterval(function () {
  store.clock = new Date().toLocaleTimeString();
}, 1000);

// ── Poller ────────────────────────────────────────────────

function poll() {
  fetchJSON("/health")
    .then(function () {
      if (store.adapters.length > 0) {
        return refreshAdapters();
      }
    })
    .then(function () {
      return fetchJSON("/api/sensors");
    })
    .then(function (sensors) {
      var names = {};
      sensors.forEach(function (s) {
        names[s.name] = true;
      });
      var promises = [];
      for (var name in names) {
        if (
          store.adapters.find(function (a) {
            return a.name === name;
          })
        )
          continue;
        promises.push(
          fetchJSON(
            "/api/sensors/" +
              encodeURIComponent(name) +
              "?since=" +
              encodeURIComponent(new Date(Date.now() - 60000).toISOString()) +
              "&until=" +
              encodeURIComponent(new Date().toISOString()),
          ).then(function (data) {
            store.adapters.push({ name: data.name, series: data.series });
          }),
        );
      }
      return Promise.all(promises);
    })
    .then(function () {
      store.online = true;
      m.redraw();
    })
    .catch(function () {
      store.online = false;
      m.redraw();
    });
}

function refreshAdapters() {
  var promises = store.adapters.map(function (a) {
    return fetchJSON(
      "/api/sensors/" +
        encodeURIComponent(a.name) +
        "?since=" +
        encodeURIComponent(new Date(Date.now() - 60000).toISOString()) +
        "&until=" +
        encodeURIComponent(new Date().toISOString()),
    ).then(function (data) {
      a.series = data.series;
    });
  });
  return Promise.all(promises);
}

// Initial poll
poll();

// Recurring poll every 5 seconds
setInterval(poll, 5000);

// ── Components ────────────────────────────────────────────

var Header = {
  view: function () {
    return m("header", [
      m("h1", "Faro"),
      m(
        "span",
        {
          class: "status " + (store.online ? "online" : "offline"),
        },
        store.online ? "Online" : "Offline",
      ),
      m("span", { id: "clock" }, store.clock),
    ]);
  },
};

function getVal(series, key) {
  var bucket = latestBucket(series[key]);
  return bucket ? bucket.value : null;
}

var SensorCard = {
  view: function (vnode) {
    var name = vnode.attrs.name;
    var series = vnode.attrs.series;
    var config = CARD_CONFIG[name];

    // Generic fallback for unknown probe types
    if (!config) {
      var keys = Object.keys(series);
      var v = keys.length > 0 ? getVal(series, keys[0]) : null;
      return m(".card", [
        m("h2", name),
        m(".primary", v !== null ? friendly(v, 1) : "\u2014"),
        m(
          ".sublabel",
          "last " +
            timeAgo(
              latestBucket(series[keys[0]])
                ? latestBucket(series[keys[0]]).resolved_at
                : null,
            ),
        ),
      ]);
    }

    // Disk — dynamic per-mount
    if (name === "disk") {
      var mounts = [];
      for (var key in series) {
        if (key.indexOf("_usage_pct") === -1) continue;
        var bucket = latestBucket(series[key]);
        mounts.push({
          mount: key
            .replace(/_slash_/g, "/")
            .replace(/_dash_/g, "-")
            .replace(/_usage_pct$/, ""),
          value: bucket ? bucket.value : null,
        });
      }
      return m(".card", [
        m("h2", "Disk"),
        mounts.length > 0
          ? m(
              ".stats",
              mounts.map(function (mnt) {
                return m(".stat", [
                  m(".label", mnt.mount),
                  m(
                    ".value",
                    { class: colorClass(mnt.value, 80, 95) },
                    mnt.value !== null ? friendly(mnt.value, 1) : "\u2014",
                    m(
                      "span",
                      { style: "font-size:12px;color:var(--text-dim)" },
                      "%",
                    ),
                  ),
                ]);
              }),
            )
          : m(".sublabel", "No data"),
      ]);
    }

    // Standard card with config
    var bucket = latestBucket(series[config.primary]);
    var val = bucket ? bucket.value : null;

    return m(".card", [
      m("h2", config.label),
      m(".primary." + colorClass(val), [
        val !== null ? val.toFixed(1) : "\u2014",
        m(
          "span",
          {
            style:
              "font-size:16px;font-weight:400;color:var(--text-dim);margin-left:4px",
          },
          config.unit,
        ),
      ]),
      m(
        ".sublabel",
        config.label +
          " \u2022 last " +
          timeAgo(bucket ? bucket.resolved_at : null),
      ),
      m(
        ".stats",
        (config.stats || []).map(function (s) {
          var v = getVal(series, s.metric);
          return m(".stat", [
            m(".label", s.label),
            m(".value", v !== null ? friendly(v, 0) : "\u2014"),
          ]);
        }),
      ),
    ]);
  },
};

var Dashboard = {
  view: function () {
    if (store.adapters.length === 0) {
      return m(".dashboard", [
        m(".empty", [
          m("h2", "Waiting for data\u2026"),
          m("p", "Sensors will appear here once probes start reporting."),
        ]),
      ]);
    }
    return m(
      ".dashboard",
      store.adapters.map(function (a) {
        return m(SensorCard, { name: a.name, series: a.series });
      }),
    );
  },
};

var App = {
  view: function () {
    return [m(Header), m("main", m(Dashboard))];
  },
};

// ── Mount ─────────────────────────────────────────────────

m.mount(document.getElementById("app"), App);
