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
  stats: [], // [{name, metric}] — flat list of available metrics
  cards: [], // [{id, type, title, adapter, metrics, w, h}]
  nextCardId: 1,
  editCard: null, // card being edited, or null
};

function latestBucket(buckets) {
  if (!buckets || buckets.length === 0) return null;
  return buckets[buckets.length - 1];
}

store.getVal = function (adapterName, metric) {
  var a = store.adapters[adapterName];
  if (!a) return null;
  var bucket = latestBucket(a.series[metric]);
  return bucket ? bucket.value : null;
};

store.getSeries = function (adapterName, metric) {
  var a = store.adapters[adapterName];
  if (!a) return null;
  return a.series[metric] || null;
};

store.cardLabel = function (card) {
  if (card.title) return card.title;
  return card.adapter;
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

store.addCard = function (type, adapter, metrics, w, slotCol, slotRow) {
  var card = {
    id: store.nextCardId++,
    type: type,
    adapter: adapter,
    metrics: metrics,
    w: w || 1,
    h: 1, // default height
    title: store.cardLabel({ adapter: adapter, metrics: metrics }),
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

store.saveLayout = function () {
  var data = store.cards.map(function (c) {
    return {
      id: c.id,
      type: c.type,
      adapter: c.adapter,
      metrics: c.metrics,
      w: c.w,
      h: c.h,
      x: c.x,
      y: c.y,
      title: c.title,
      range: c.range,
    };
  });
  try {
    localStorage.setItem("faro_layout", JSON.stringify(data));
  } catch (_) {}
};

store.loadLayout = function () {
  try {
    var raw = localStorage.getItem("faro_layout");
    if (!raw) return;
    var data = JSON.parse(raw);
    store.nextCardId =
      (data.reduce(function (m, c) {
        return Math.max(m, c.id);
      }, 0) || 0) + 1;
    data.forEach(function (c) {
      // default h for legacy cards
      if (c.h === undefined) c.h = 1;
      store.cards.push(c);
    });
  } catch (_) {}
};
