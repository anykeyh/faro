// Alert card — shows thresholds grouped by adapter, with grey/red indicators

var LatchCard = {
  view: function (vnode) {
    var card = vnode.attrs.card;

    var isDragging = dragState.drag && dragState.drag.id === card.id;
    var isResizing = dragState.resize && dragState.resize.id === card.id;

    // Group alerts by threshold (adapter + metric), keeping only selected alert names
    var alertNames = card.alertNames || [];
    var groups = [];
    (store.latches || []).forEach(function (t) {
      var matched = [];
      t.latches.forEach(function (l) {
        if (alertNames.indexOf(l.name) >= 0) {
          matched.push(l);
        }
      });
      if (matched.length > 0) {
        groups.push({ adapter: t.adapter, metric: t.metric, alerts: matched });
      }
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
                  if (confirm("Remove this card?")) store.removeCard(card);
                },
              },
              "\u2716",
            ),
          ]),
        ]),
        m(
          ".card-body.alert-body",
          groups.length === 0
            ? m(".alert-empty", "No alerts selected")
            : groups.map(function (g) {
                return m(".alert-group", [
                  m(".alert-group-title", g.adapter + " \u00b7 " + g.metric),
                  g.alerts.map(function (l) {
                    var active = l.open;
                    return m(
                      ".alert-row" + (active ? ".alert-row-active" : ""),
                      [
                        m(".alert-indicator", {
                          class: active ? "alert-open" : "alert-idle",
                        }),
                        m(
                          ".alert-name" + (active ? ".alert-name-active" : ""),
                          l.name,
                        ),
                        active
                          ? m(".alert-badge.alert-badge-open", "ACTIVE")
                          : null,
                      ],
                    );
                  }),
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
