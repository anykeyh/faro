// Indicator card — shows one or more numeric values

function friendly(n, decimals) {
  decimals = decimals || 1;
  if (n === null || n === undefined) return "\u2014";
  return Number(n).toFixed(decimals);
}

var IndicatorCard = {
  oninit: function (vnode) {
    vnode.state.dragging = false;
    vnode.state.dragX = 0;
    vnode.state.dragStartX = 0;
  },
  view: function (vnode) {
    var card = vnode.attrs.card;

    // Compute a grid-column span from card.w
    var style = "grid-column: span " + (card.w || 1) + ";";

    return m(".card", { style: style, key: card.id }, [
      m(".card-header", [
        m(
          "span.card-title",
          {
            config: function (el) {
              // inline edit on click
              el.onclick = function () {
                var newTitle = prompt("Card title:", card.title || "");
                if (newTitle !== null) {
                  store.updateCard(card, { title: newTitle || undefined });
                }
              };
            },
          },
          store.cardLabel(card),
        ),
        m(".card-actions", [
          m(
            "a.card-action",
            {
              href: "#",
              onclick: function (e) {
                e.preventDefault();
                var sizes = [1, 2, 3, 4];
                var next = sizes[(sizes.indexOf(card.w) + 1) % sizes.length];
                store.updateCard(card, { w: next });
              },
            },
            "\u2194",
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
          return m(".metric-row", [
            m(".metric-value.neutral", friendly(val, 1)),
            m(".metric-label", metric),
          ]);
        }),
      ),
    ]);
  },
};
