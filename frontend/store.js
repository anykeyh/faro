// Grid layout constants
var COLS = 4;
var GAP = 10;

// ── Fluid grid helpers ────────────────────────────────────
// dragState is defined in dashboard.js and has ._cell (column width in px)
// Row height = _cell / 2  (2:1 width:height ratio)

function cellW(n) {
  return (dragState._cell || 140) * n;
}

function cellH(n) {
  return ((dragState._cell || 140) / 2) * n;
}

function posX(n) {
  return n * ((dragState._cell || 140) + GAP);
}

function posY(n) {
  return n * ((dragState._cell || 140) / 2 + GAP);
}

// A card spanning w columns / h rows should fill w cells + (w-1) gaps
function spanW(w) {
  return w * (dragState._cell || 140) + (w - 1) * GAP;
}

function spanH(h) {
  return h * ((dragState._cell || 140) / 2) + (h - 1) * GAP;
}

// ── Global state ─────────────────────────────────────────

var store = {
  online: false,
  clock: new Date().toLocaleTimeString(),
  adapters: {}, // name -> { name, series }
  latches: [], // [{ adapter, metric, latches: [{name, set, release, sustain, open}] }]
  stats: [], // [{name, metric}] — flat list of available metrics
  cards: [], // [{id, type, title, probes, w, h}]
  nextCardId: 1,
  editCard: null, // card being edited, or null
};

store.getVal = function (adapterName, metric) {
  var a = store.adapters[adapterName];
  if (!a) return null;
  // `values` is populated by the /latest endpoint (fast poll)
  if (a.values) return a.values[metric] !== undefined ? a.values[metric] : null;
  // `series` is populated by the full /query endpoint (graph cards)
  var bucket = a.series && a.series[metric];
  return bucket && bucket.length > 0 ? bucket[bucket.length - 1].value : null;
};

store.getSeries = function (adapterName, metric) {
  var a = store.adapters[adapterName];
  if (!a) return null;
  return a.series ? a.series[metric] || null : null;
};

store.cardLabel = function (card) {
  if (card.title) return card.title;
  if (card.probes && card.probes.length > 0) {
    var names = {};
    card.probes.forEach(function (p) {
      names[p.adapter] = true;
    });
    var keys = Object.keys(names);
    return keys.length === 1 ? keys[0] : keys.join(" + ");
  }
  return "Card";
};

// ── Layout helpers ────────────────────────────────────────

function intersects(a, b) {
  return (
    a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y
  );
}

function canPlace(cardId, x, y, w, h) {
  h = h || 1;
  if (x < 0 || y < 0) return false;
  if (x + w > COLS) return false;
  return !store.cards.some(function (c) {
    return (
      c.id !== cardId &&
      intersects(
        { x: x, y: y, w: w, h: h },
        { x: c.x, y: c.y, w: c.w, h: c.h || 1 },
      )
    );
  });
}

store.autoPlace = function (card) {
  var h = card.h || 1;
  var taken = {};
  store.cards.forEach(function (c) {
    if (c.id === card.id) return;
    if (c.x === undefined) return;
    for (var r = 0; r < (c.h || 1); r++) {
      for (var i = 0; i < c.w; i++) {
        taken[c.y + r + "-" + (c.x + i)] = true;
      }
    }
  });
  for (var row = 0; ; row++) {
    for (var col = 0; col <= COLS - card.w; col++) {
      var free = true;
      for (var r = 0; r < h; r++) {
        for (var i = 0; i < card.w; i++) {
          if (taken[row + r + "-" + (col + i)]) {
            free = false;
            break;
          }
        }
        if (!free) break;
      }
      if (free) {
        card.x = col;
        card.y = row;
        return;
      }
    }
  }
};

store.addCard = function (type, probes, w, slotCol, slotRow) {
  var card = {
    id: store.nextCardId++,
    type: type,
    probes: probes,
    w: w || 1,
    h: 1,
    title: null,
    range: 60,
  };
  if (
    slotCol !== undefined &&
    slotCol !== null &&
    slotRow !== undefined &&
    slotRow !== null
  ) {
    if (canPlace(card.id, slotCol, slotRow, card.w, card.h)) {
      card.x = slotCol;
      card.y = slotRow;
    } else {
      store.autoPlace(card);
    }
  } else {
    store.autoPlace(card);
  }
  store.cards.push(card);
  store.saveLayout();
};

store.removeCard = function (card) {
  var idx = store.cards.indexOf(card);
  if (idx >= 0) store.cards.splice(idx, 1);
  store.saveLayout();
};

store.updateCard = function (card, opts) {
  for (var k in opts) card[k] = opts[k];
  store.autoPlace(card);
  store.saveLayout();
};

// Ensure backward compatibility: migrate old format to new probes-based format
function migrateCard(c) {
  if (c.adapter && c.metrics && !c.probes) {
    c.probes = c.metrics.map(function (m) {
      return { adapter: c.adapter, metric: m };
    });
    delete c.adapter;
    delete c.metrics;
  }
  if (!c.probes) c.probes = [];
  if (c.h === undefined || c.h < 1) c.h = 1;
  if (c.type === "alert" && !c.alertNames) c.alertNames = [];
  return c;
}

store.saveLayout = function () {
  var data = store.cards.map(function (c) {
    var out = {
      id: c.id,
      type: c.type,
      probes: c.probes,
      w: c.w,
      h: c.h,
      x: c.x,
      y: c.y,
      title: c.title,
      range: c.range,
    };
    if (c.type === "alert") out.alertNames = c.alertNames;
    return out;
  });
  var xhr = new XMLHttpRequest();
  xhr.open("POST", "/api/layout", true);
  xhr.setRequestHeader("Content-Type", "application/json");
  xhr.send(JSON.stringify(data));
};

store.loadLayout = function () {
  var xhr = new XMLHttpRequest();
  xhr.open("GET", "/api/layout", true);
  xhr.onload = function () {
    if (xhr.status === 200) {
      try {
        var data = JSON.parse(xhr.responseText);
        if (data && data.length > 0) {
          store.nextCardId =
            (data.reduce(function (m, c) {
              return Math.max(m, c.id);
            }, 0) || 0) + 1;
          data.forEach(function (c) {
            store.cards.push(migrateCard(c));
          });
        }
      } catch (_) {}
    }
  };
  xhr.send();
};
