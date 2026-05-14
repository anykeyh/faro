// Global state

var store = {
  online: false,
  clock: new Date().toLocaleTimeString(),
  adapters: {}, // name -> { name, series }
  stats: [], // [{name, metric}] — flat list of available metrics
  cards: [], // [{id, type, title, adapter, metrics, w}]
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

store.LAYOUT_COLS = 4;

// (row, col) positions for each card. Recalculated after adds/removes.
// We store x/y on each card: x = column (0..3), w = width in cols (1..4)
store.autoPlace = function (card) {
  // Place at the first available spot
  var taken = {};
  store.cards.forEach(function (c) {
    if (c.id === card.id) return;
    if (c.x === undefined) return;
    for (var i = 0; i < c.w; i++) {
      taken[c.y + "-" + (c.x + i)] = true;
    }
  });
  for (var row = 0; ; row++) {
    for (var col = 0; col <= store.LAYOUT_COLS - card.w; col++) {
      var free = true;
      for (var i = 0; i < card.w; i++) {
        if (taken[row + "-" + (col + i)]) {
          free = false;
          break;
        }
      }
      if (free) {
        card.x = col;
        card.y = row;
        return;
      }
    }
  }
};

store.addCard = function (type, adapter, metrics, w) {
  var card = {
    id: store.nextCardId++,
    type: type, // "indicator" or "graph"
    adapter: adapter,
    metrics: metrics,
    w: w || 1,
    title: store.cardLabel({ adapter: adapter, metrics: metrics }),
    range: 60, // default 60 minutes; only used for graph cards
  };
  store.autoPlace(card);
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

// Persist layout to localStorage
store.saveLayout = function () {
  var data = store.cards.map(function (c) {
    return {
      id: c.id,
      type: c.type,
      adapter: c.adapter,
      metrics: c.metrics,
      w: c.w,
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
      store.cards.push(c);
    });
  } catch (_) {}
};
