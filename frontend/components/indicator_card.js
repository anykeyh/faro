// Indicator card — shows one or more numeric values

function friendly(n, decimals) {
  decimals = decimals || 1;
  if (n === null || n === undefined) return "\u2014";
  return Number(n).toFixed(decimals);
}

// Format byte values into human-readable sizes
// If inKb is true, input is in kilobytes; otherwise raw bytes
function friendlyBytes(n, inKb) {
  if (n === null || n === undefined) return "\u2014";
  var bytes = inKb ? n * 1024 : n;
  if (bytes < 1024) return bytes.toFixed(0) + " B";
  var kb = bytes / 1024;
  if (kb < 1024) return kb.toFixed(1) + " KB";
  var mb = kb / 1024;
  if (mb < 1024) return mb.toFixed(1) + " MB";
  var gb = mb / 1024;
  if (gb < 1024) return gb.toFixed(2) + " GB";
  var tb = gb / 1024;
  return tb.toFixed(2) + " TB";
}

var IndicatorCard = {
  view: function (vnode) {
    var card = vnode.attrs.card;

    var isDragging = dragState.drag && dragState.drag.id === card.id;
    var isResizing = dragState.resize && dragState.resize.id === card.id;

    var useBytes = card.metrics.some(function (m) {
      return /_(kb|bytes)$/.test(m);
    });
    // Check if the first bytes metric ends with _kb (meaning input is in KB)
    var isKb = card.metrics.some(function (m) {
      return /_kb$/.test(m);
    });
    var usePct = card.metrics.some(function (m) {
      return /_pct$/.test(m);
    });

    return m(
      ".card",
      {
        class: [isDragging && "dragging", isResizing && "resizing"]
          .filter(Boolean)
          .join(" "),
        style: {
          left: posX(card.x) + "px",
          top: posY(card.y) + "px",
          width: spanW(card.w) + "px",
          height: spanH(card.h || 1) + "px",
        },
      },
      [
        m(".card-header", [
          m(
            ".card-title",
            {
              onmousedown: function (e) {
                if (e.button !== 0) return;
                e.preventDefault();
                var cardEl = e.currentTarget.parentElement;
                var r = cardEl.getBoundingClientRect();
                dragState.drag = {
                  id: card.id,
                  offsetX: e.clientX - r.left,
                  offsetY: e.clientY - r.top,
                  targetX: card.x,
                  targetY: card.y,
                  canDrop: true,
                };
              },
            },
            [m("span.dot"), m("span", store.cardLabel(card))],
          ),
          m(".card-actions", [
            m(
              "a.card-action",
              {
                href: "#",
                onclick: function (e) {
                  e.preventDefault();
                  openEditCard(card);
                },
              },
              "\u270E",
            ),
            m(
              "a.card-action",
              {
                href: "#",
                onclick: function (e) {
                  e.preventDefault();
                  if (confirm("Remove this card?")) store.removeCard(card);
                },
              },
              "\u2716",
            ),
          ]),
        ]),
        m(
          ".card-body",
          card.metrics.map(function (metric) {
            var val = store.getVal(card.adapter, metric);
            var displayVal;
            if (useBytes) displayVal = friendlyBytes(val, isKb);
            else if (usePct && val !== null && val !== undefined)
              displayVal = (val * 100).toFixed(1) + "%";
            else displayVal = friendly(val, 1);
            return m(".metric-row", [
              m(".metric-value.neutral", displayVal),
              m(".metric-label", metric),
            ]);
          }),
        ),
        m(".resize-handle", {
          onmousedown: function (e) {
            if (e.button !== 0) return;
            e.preventDefault();
            e.stopPropagation();
            dragState.resize = {
              id: card.id,
              startMouseX: e.clientX,
              startMouseY: e.clientY,
              startW: card.w,
              startH: card.h || 1,
              targetW: card.w,
              targetH: card.h || 1,
              canResize: true,
            };
          },
        }),
      ],
    );
  },
};
