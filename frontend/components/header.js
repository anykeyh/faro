// Header component

var Header = {
  view: function() {
    return m('header', [
      m('h1', 'Faro'),
      m('span', {
        class: 'status ' + (store.online ? 'online' : 'offline')
      }, store.online ? 'Online' : 'Offline'),
      m('span', { id: 'clock' }, store.clock)
    ]);
  }
};
