// Add Card dialog — clicking an empty slot opens a modal

var AddCard = {
  oninit: function (vnode) {
    vnode.state.open = false;
    vnode.state.step = "type"; // 'type' | 'metrics' | 'alert-select'
    vnode.state.type = "indicator";
    vnode.state.probes = []; // [{ adapter, metric }]
    vnode.state.alertNames = [];
  },
  view: function (vnode) {
    var s = vnode.state;
    var editCard = dragState.editCard;

    if (!s.open) {
      if (editCard) {
        s.type = editCard.type;
        s.probes = (editCard.probes || []).map(function (p) {
          return { adapter: p.adapter, metric: p.metric };
        });
        s.alertNames = (editCard.alertNames || []).slice();
        if (editCard.type === "alert") {
          s.step = "alert-select";
        } else {
          s.step = "metrics";
        }
        s.open = true;
      } else if (
        dragState._addTargetCol !== undefined &&
        dragState._addTargetCol !== null
      ) {
        s.open = true;
        s.step = "type";
      }
    }

    if (!s.open) return null;

    var modalContent;

    if (s.step === "type") {
      modalContent = [
        m("h3", "Select card type"),
        m(
          "button.btn",
          {
            onclick: function () {
              s.type = "indicator";
              s.step = "metrics";
            },
          },
          "Indicator",
        ),
        m(
          "button.btn",
          {
            onclick: function () {
              s.type = "graph";
              s.step = "metrics";
            },
          },
          "Graph",
        ),
        m(
          "button.btn",
          {
            onclick: function () {
              s.type = "alert";
              s.step = "alert-select";
            },
          },
          "Alerts",
        ),
      ];
    } else if (s.step === "alert-select") {
      var groups = [];
      (store.latches || []).forEach(function (t) {
        groups.push(
          m(
            "p",
            { style: "font-size:12px;color:var(--text-dim);margin-top:10px;" },
            t.adapter + " / " + t.metric,
          ),
          t.latches.map(function (l) {
            var key = t.adapter + "." + t.metric + "." + l.name;
            var selected = s.alertNames.indexOf(key) >= 0;
            return m("label", { style: "display:block;margin:4px 0;" }, [
              m("input[type=checkbox]", {
                checked: selected,
                onchange: function () {
                  if (selected) {
                    s.alertNames = s.alertNames.filter(function (x) {
                      return x !== key;
                    });
                  } else {
                    s.alertNames.push(key);
                  }
                },
              }),
              " " +
                l.name +
                " (set: " +
                l.set +
                ", release: " +
                l.release +
                ")",
            ]);
          }),
        );
      });

      modalContent = [
        m("h3", "Select alerts"),
        groups.length === 0 ? m("p", "No alerts configured.") : groups,
        m(
          "button.btn",
          {
            onclick: function () {
              if (s.alertNames.length === 0) return;
              if (editCard) {
                editCard.alertNames = s.alertNames.slice();
                editCard.title = "Alerts";
                store.saveLayout();
              } else {
                var card = {
                  id: store.nextCardId++,
                  type: "alert",
                  probes: [],
                  alertNames: s.alertNames.slice(),
                  w: 1,
                  h: 1,
                  title: "Alerts",
                  range: 60,
                };
                if (
                  dragState._addTargetCol !== undefined &&
                  dragState._addTargetCol !== null
                ) {
                  if (
                    canPlace(
                      card.id,
                      dragState._addTargetCol,
                      dragState._addTargetRow,
                      card.w,
                      card.h,
                    )
                  ) {
                    card.x = dragState._addTargetCol;
                    card.y = dragState._addTargetRow;
                  } else {
                    store.autoPlace(card);
                  }
                } else {
                  store.autoPlace(card);
                }
                store.cards.push(card);
                store.saveLayout();
              }
              closeModal();
            },
          },
          "Add card",
        ),
      ];
    } else if (s.step === "metrics") {
      var groups = [];
      Object.keys(store.adapters)
        .sort()
        .forEach(function (a) {
          var ad = store.adapters[a];
          var metrics = Object.keys(ad.values || ad.series || {})
            .sort()
            .filter(function (m) {
              return m !== "_alive";
            });
          if (metrics.length === 0) return;
          var open = s._openGroup === a;
          var groupSelected = metrics.every(function (m) {
            return s.probes.some(function (p) {
              return p.adapter === a && p.metric === m;
            });
          });
          groups.push(
            m("div", { style: "margin:2px 0;" }, [
              m(
                "div",
                {
                  style:
                    "cursor:pointer;font-size:13px;padding:4px 6px;background:var(--surface-hover);border-radius:4px;display:flex;align-items:center;gap:8px;",
                  onclick: function () {
                    s._openGroup = open ? null : a;
                    m.redraw();
                  },
                },
                [
                  m("span", open ? "\u25BC" : "\u25B6"),
                  m("strong", a),
                  m(
                    "span",
                    {
                      style:
                        "font-size:11px;color:var(--text-dim);margin-left:auto;",
                    },
                    metrics.length +
                      " metrics" +
                      (groupSelected ? " \u2713" : ""),
                  ),
                ],
              ),
              open
                ? m(
                    "div",
                    {
                      style:
                        "padding:2px 0 4px 20px;max-height:200px;overflow-y:auto;",
                    },
                    metrics.map(function (metric) {
                      var selected = s.probes.some(function (p) {
                        return p.adapter === a && p.metric === metric;
                      });
                      return m(
                        "label",
                        { style: "display:block;margin:2px 0;" },
                        [
                          m("input[type=checkbox]", {
                            checked: selected,
                            onchange: function () {
                              if (selected) {
                                s.probes = s.probes.filter(function (p) {
                                  return p.adapter !== a || p.metric !== metric;
                                });
                              } else {
                                s.probes.push({
                                  adapter: a,
                                  metric: metric,
                                });
                              }
                            },
                          }),
                          " " + metric,
                        ],
                      );
                    }),
                  )
                : null,
            ]),
          );
        });

      modalContent = [
        m(
          "h3",
          s.type === "graph" ? "Select metrics for graph" : "Select metrics",
        ),
        m(
          "div",
          { style: "max-height:320px;overflow-y:auto;margin-bottom:12px;" },
          groups.length === 0 ? m("p", "No metrics available yet.") : groups,
        ),
        m(
          "button.btn",
          {
            onclick: function () {
              if (s.probes.length === 0) return;
              if (editCard) {
                editCard.probes = s.probes.map(function (p) {
                  return { adapter: p.adapter, metric: p.metric };
                });
                editCard.title = null;
                store.saveLayout();
              } else {
                var cardWidth = s.type === "graph" ? 2 : 1;
                store.addCard(
                  s.type,
                  s.probes.map(function (p) {
                    return { adapter: p.adapter, metric: p.metric };
                  }),
                  cardWidth,
                  dragState._addTargetCol,
                  dragState._addTargetRow,
                );
              }
              closeModal();
            },
          },
          editCard ? "Save" : "Add card",
        ),
      ];
    }

    function closeModal() {
      s.open = false;
      s.step = "type";
      s.probes = [];
      s.alertNames = [];
      dragState.editCard = null;
      dragState._addTargetCol = null;
      dragState._addTargetRow = null;
    }

    function onKeyDown(e) {
      if (e.key === "Escape") {
        closeModal();
        m.redraw();
      }
    }
    document.addEventListener("keydown", onKeyDown);

    return m(
      ".add-card-overlay",
      {
        onclick: function (e) {
          if (e.target === e.currentTarget) closeModal();
        },
        config: function (el, inited) {
          if (!inited) {
            el._closeHandler = onKeyDown;
          }
          return function () {
            document.removeEventListener("keydown", onKeyDown);
          };
        },
      },
      [
        m(
          ".add-card-modal",
          {
            onclick: function (e) {
              e.stopPropagation();
            },
          },
          modalContent,
        ),
      ],
    );
  },
};
