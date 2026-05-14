// Indicator card — shows one or more numeric values

function friendly(n, decimals) {
  decimals = decimals || 1;
  if (n === null || n === undefined) return "\u2014";
  return Number(n).toFixed(decimals);
}

var IndicatorCard = {
  view: function (vnode) {
    var card = vnode.attrs.card;

    var isDragging = dragState.drag && dragState.drag.id === card.id;
    var isResizing = dragState.resize && dragState.resize.id === card.id;

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
            return m(".metric-row", [
              m(".metric-value.neutral", friendly(val, 1)),
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
