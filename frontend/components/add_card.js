// Add Card dialog — clicking an empty slot opens a modal

var AddCard = {
  oninit: function (vnode) {
    vnode.state.open = false;
    vnode.state.step = "type"; // 'type' | 'adapter' | 'metrics' | 'alert-select'
    vnode.state.type = "indicator";
    vnode.state.adapter = "";
    vnode.state.metrics = [];
    vnode.state.alertNames = []; // selected alert names
  },
  view: function (vnode) {
    var s = vnode.state;
    var editCard = dragState.editCard;

    if (!s.open) {
      if (editCard) {
        // Edit mode — pre-fill from the card being edited
        s.type = editCard.type;
        s.adapter = editCard.adapter || "";
        s.metrics = (editCard.metrics || []).slice();
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
    var adapters = Object.keys(store.adapters).sort();

    if (s.step === "type") {
      modalContent = [
        m("h3", "Select card type"),
        m(
          "button.btn",
          {
            onclick: function () {
              s.type = "indicator";
              s.step = "adapter";
            },
          },
          "Indicator",
        ),
        m(
          "button.btn",
          {
            onclick: function () {
              s.type = "graph";
              s.step = "adapter";
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
            var selected = s.alertNames.indexOf(l.name) >= 0;
            return m("label", { style: "display:block;margin:4px 0;" }, [
              m("input[type=checkbox]", {
                checked: selected,
                onchange: function () {
                  if (selected) {
                    s.alertNames = s.alertNames.filter(function (x) {
                      return x !== l.name;
                    });
                  } else {
                    s.alertNames.push(l.name);
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
                // Update existing alert card
                editCard.alertNames = s.alertNames.slice();
                editCard.title = "Alerts";
                store.saveLayout();
              } else {
                // Create new alert card
                var card = {
                  id: store.nextCardId++,
                  type: "alert",
                  adapter: "",
                  metrics: [],
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
              s.open = false;
              s.step = "type";
              s.alertNames = [];
              dragState.editCard = null;
              dragState._addTargetCol = null;
              dragState._addTargetRow = null;
            },
          },
          "Add card",
        ),
      ];
    } else if (s.step === "adapter") {
      modalContent = [
        m("h3", "Select adapter"),
        adapters.length === 0
          ? m("p", "No adapters with data yet.")
          : adapters.map(function (a) {
              return m(
                "button.btn",
                {
                  onclick: function () {
                    s.adapter = a;
                    s.step = "metrics";
                  },
                },
                a,
              );
            }),
      ];
    } else if (s.step === "metrics") {
      var adapterData = store.adapters[s.adapter];
      var metrics = adapterData
        ? Object.keys(adapterData.values || adapterData.series || {}).sort()
        : [];

      modalContent = [
        m("h3", "Select metrics"),
        m("p", "Adapter: " + s.adapter),
        m(
          "div",
          { style: "max-height:200px;overflow-y:auto;margin-bottom:12px;" },
          metrics.length === 0
            ? m("p", "No metrics available.")
            : metrics.map(function (metric) {
                var selected = s.metrics.indexOf(metric) >= 0;
                return m("label", { style: "display:block;margin:4px 0;" }, [
                  m("input[type=checkbox]", {
                    checked: selected,
                    onchange: function () {
                      if (selected) {
                        s.metrics = s.metrics.filter(function (x) {
                          return x !== metric;
                        });
                      } else {
                        s.metrics.push(metric);
                      }
                    },
                  }),
                  " " + metric,
                ]);
              }),
        ),
        m(
          "button.btn",
          {
            onclick: function () {
              if (s.metrics.length === 0) return;
              if (editCard) {
                editCard.adapter = s.adapter;
                editCard.metrics = s.metrics.slice();
                editCard.title = store.cardLabel(editCard);
                store.saveLayout();
              } else {
                var cardWidth = s.type === "graph" ? 2 : 1;
                store.addCard(
                  s.type,
                  s.adapter,
                  s.metrics.slice(),
                  cardWidth,
                  dragState._addTargetCol,
                  dragState._addTargetRow,
                );
              }
              s.open = false;
              s.step = "type";
              s.metrics = [];
              s.adapter = "";
              dragState.editCard = null;
              dragState._addTargetCol = null;
              dragState._addTargetRow = null;
            },
          },
          editCard ? "Save" : "Add card",
        ),
      ];
    }

    function closeModal() {
      s.open = false;
      s.step = "type";
      s.metrics = [];
      s.alertNames = [];
      dragState.editCard = null;
      s.adapter = "";
      dragState._addTargetCol = null;
      dragState._addTargetRow = null;
    }

    // Close on Escape key
    function onKeyDown(e) {
      if (e.key === "Escape") {
        closeModal();
        m.redraw();
      }
    }
    document.addEventListener("keydown", onKeyDown);
    // We use config to clean up the listener when the modal DOM is removed

    return m(
      ".add-card-overlay",
      {
        onclick: function (e) {
          if (e.target === e.currentTarget) {
            closeModal();
          }
        },
        config: function (el, inited) {
          if (!inited) {
            // On first init, store the cleanup function
            el._closeHandler = onKeyDown;
          }
          // Return a cleanup function that removes the listener
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
