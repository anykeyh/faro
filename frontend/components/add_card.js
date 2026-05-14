// Add Card dialog — clicking an empty slot opens a modal

var AddCard = {
  oninit: function (vnode) {
    vnode.state.open = false;
    vnode.state.step = "type"; // 'type' | 'adapter' | 'metrics'
    vnode.state.type = "indicator";
    vnode.state.adapter = "";
    vnode.state.metrics = [];
  },
  view: function (vnode) {
    var s = vnode.state;

    // If the dashboard tells us to open at a slot, open the modal
    if (
      !s.open &&
      dragState._addTargetCol !== undefined &&
      dragState._addTargetCol !== null
    ) {
      s.open = true;
      s.step = "type";
      // Don't reset _addTargetCol yet — we keep it so store.addCard can use it
    }

    if (!s.open) {
      // Render nothing — the slots are handled by Dashboard
      return null;
    }

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
      var metrics = adapterData ? Object.keys(adapterData.series).sort() : [];

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
              var cardWidth = s.type === "graph" ? 2 : 1;
              store.addCard(
                s.type,
                s.adapter,
                s.metrics.slice(),
                cardWidth,
                dragState._addTargetCol,
                dragState._addTargetRow,
              );
              // Reset modal state and slot target
              s.open = false;
              s.step = "type";
              s.metrics = [];
              s.adapter = "";
              dragState._addTargetCol = null;
              dragState._addTargetRow = null;
            },
          },
          "Add card",
        ),
      ];
    }

    return m(
      ".add-card-overlay",
      {
        onclick: function (e) {
          if (e.target === e.currentTarget) {
            s.open = false;
            s.step = "type";
            s.metrics = [];
            s.adapter = "";
            dragState._addTargetCol = null;
            dragState._addTargetRow = null;
          }
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
