// Dashboard — the grid layout

var cardComponents = {
  indicator: IndicatorCard,
  graph: GraphCard
};

var Dashboard = {
  view: function() {
    if (Object.keys(store.adapters).length === 0) {
      return m('.dashboard', [
        m('.empty', [
          m('h2', 'Waiting for data\u2026'),
          m('p', 'Sensors will appear here once probes start reporting.')
        ])
      ]);
    }

    // Ensure every card has a component
    var rendered = store.cards.map(function(card) {
      var Comp = cardComponents[card.type];
      if (!Comp) return null;
      return m(Comp, { card: card });
    }).filter(function(x) { return x; });

    // Add the "+" card at the end
    rendered.push(m(AddCard));

    return m('.dashboard', rendered);
  }
};
