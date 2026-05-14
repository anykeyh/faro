// Dashboard — the grid layout with pixel-based drag & drop

var cardComponents = {
  indicator: IndicatorCard,
  graph: GraphCard,
  alert: LatchCard,
};

// ── Drag state ────────────────────────────────────────────

var dragState = {
  drag: null,
  resize: null,
  editCard: null, // card being edited, or null
  _cell: 0,
  _addRow: -1,
};

// ── Grid measurement ──────────────────────────────────────

function measureGrid() {
  var dash = document.querySelector(".dashboard");
  if (!dash) {
    dragState._cell = 140;
    return;
  }
  // .dashboard has 20px padding on each side.
  // The .grid sits inside padding, so usable width = clientWidth - 40.
  // But on first render .grid doesn't exist yet, so we estimate from .dashboard.
  var w = dash.clientWidth - 40;
  if (w < 100) w = 600;
  dragState._cell = (w - GAP * (COLS - 1)) / COLS;
}

function stepX() {
  return dragState._cell + GAP;
}
function stepY() {
  return dragState._cell / 2 + GAP;
}

// ── Helpers ───────────────────────────────────────────────

function findCard(id) {
  for (var i = 0; i < store.cards.length; i++) {
    if (store.cards[i].id === id) return store.cards[i];
  }
  return null;
}

// ── Global mouse handlers ──────────────────────────────────

function onMouseMove(e) {
  if (dragState.drag) {
    var gridEl = document.querySelector(".grid");
    if (!gridEl) return;
    var r = gridEl.getBoundingClientRect();
    var localX = e.clientX - r.left - dragState.drag.offsetX;
    var localY = e.clientY - r.top - dragState.drag.offsetY;
    var card = findCard(dragState.drag.id);

    var tx = Math.round(localX / stepX());
    var ty = Math.round(localY / stepY());
    tx = Math.max(0, Math.min(COLS - card.w, tx));
    ty = Math.max(0, ty);

    dragState.drag.targetX = tx;
    dragState.drag.targetY = ty;
    dragState.drag.canDrop = canPlace(card.id, tx, ty, card.w, card.h || 1);
    m.redraw();
  } else if (dragState.resize) {
    var card = findCard(dragState.resize.id);
    var dx = e.clientX - dragState.resize.startMouseX;
    var dy = e.clientY - dragState.resize.startMouseY;

    var w = Math.max(
      1,
      Math.round(
        (dragState.resize.startW * dragState._cell + dx) / dragState._cell,
      ),
    );
    w = Math.min(COLS - card.x, w);

    var h = Math.max(
      1,
      Math.round(
        (dragState.resize.startH * (dragState._cell / 2) + dy) /
          (dragState._cell / 2),
      ),
    );

    dragState.resize.targetW = w;
    dragState.resize.targetH = h;
    dragState.resize.canResize = canPlace(card.id, card.x, card.y, w, h);
    m.redraw();
  }
}

function onMouseUp() {
  if (dragState.drag) {
    if (dragState.drag.canDrop) {
      var card = findCard(dragState.drag.id);
      card.x = dragState.drag.targetX;
      card.y = dragState.drag.targetY;
      store.saveLayout();
    }
    dragState.drag = null;
    m.redraw();
  } else if (dragState.resize) {
    if (dragState.resize.canResize) {
      var card = findCard(dragState.resize.id);
      card.w = dragState.resize.targetW;
      card.h = dragState.resize.targetH;
      store.saveLayout();
    }
    dragState.resize = null;
    m.redraw();
  }
}

document.addEventListener("mousemove", onMouseMove);
document.addEventListener("mouseup", onMouseUp);

// ── Dashboard component ───────────────────────────────────

var Dashboard = {
  oncreate: measureGrid,
  view: function () {
    measureGrid();

    if (Object.keys(store.adapters).length === 0) {
      return m(".dashboard", [
        m(".empty", [
          m("h2", "Waiting for data\u2026"),
          m("p", "Sensors will appear here once probes start reporting."),
        ]),
      ]);
    }

    var maxRow = 0;
    store.cards.forEach(function (c) {
      if (c.x === undefined || c.y === undefined) store.autoPlace(c);
      var bottom = (c.y || 0) + (c.h || 1);
      if (bottom > maxRow) maxRow = bottom;
    });

    // Slot row is one below the last card, or at row 0 if no cards exist yet.
    var addRow = maxRow;
    dragState._addRow = addRow;
    var rows = addRow + 1;

    // During drag/resize extend the grid height for the preview
    var dragH = 0;
    if (dragState.drag) {
      var dc = findCard(dragState.drag.id);
      dragH = dragState.drag.targetY + (dc ? dc.h || 1 : 1) || 1;
    }
    if (dragState.resize) {
      var rc = findCard(dragState.resize.id);
      if (rc) {
        var rh = rc.y + (dragState.resize.targetH || 1);
        if (rh > dragH) dragH = rh;
      }
    }
    rows = Math.max(rows, dragH + 1);

    // Background cells + clickable empty slot row
    var cells = [];
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < COLS; x++) {
        var isAddRow = y === addRow;
        cells.push(
          m(isAddRow ? ".slot" : ".cell", {
            style: {
              left: posX(x) + "px",
              top: posY(y) + "px",
              width: cellW(1) + "px",
              height: cellH(1) + "px",
            },
            onclick: isAddRow
              ? (function (col) {
                  return function () {
                    openAddAt(col, addRow);
                  };
                })(x)
              : null,
          }),
        );
      }
    }

    // Drop/resize preview
    var preview = null;
    if (dragState.drag) {
      var c = findCard(dragState.drag.id);
      preview = m(".preview", {
        class: dragState.drag.canDrop ? "valid" : "invalid",
        style: {
          left: posX(dragState.drag.targetX) + "px",
          top: posY(dragState.drag.targetY) + "px",
          width: spanW(c.w) + "px",
          height: spanH(c.h || 1) + "px",
        },
      });
    } else if (dragState.resize) {
      var cr = findCard(dragState.resize.id);
      preview = m(".preview", {
        class: dragState.resize.canResize ? "valid" : "invalid",
        style: {
          left: posX(cr.x) + "px",
          top: posY(cr.y) + "px",
          width: spanW(dragState.resize.targetW) + "px",
          height: spanH(dragState.resize.targetH) + "px",
        },
      });
    }

    var rendered = store.cards.map(function (card) {
      var Comp = cardComponents[card.type];
      if (!Comp) return null;
      return m(Comp, { card: card });
    });

    return m(".dashboard", [
      m(".grid", { style: { height: posY(rows) + GAP + "px" } }, [
        cells,
        preview,
        rendered,
        m(AddCard),
      ]),
    ]);
  },
};

function openAddAt(col, row) {
  dragState._addTargetCol = col;
  dragState._addTargetRow = row;
  m.redraw();
}

function openEditCard(card) {
  dragState.editCard = card;
  // Open the add modal by setting _addTargetCol to a dummy value
  // The AddCard component will detect editCard instead and pre-fill
  m.redraw();
}
