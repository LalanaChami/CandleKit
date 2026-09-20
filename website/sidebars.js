/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  docsSidebar: [
    'intro',
    {
      type: 'category',
      label: 'Guides',
      collapsed: false,
      items: [
        'core-concepts/candles-and-viewport',
        'guides/indicators',
        'guides/drawing-tools',
        'guides/styling',
        'guides/gestures-and-crosshair',
      ],
    },
    {
      type: 'category',
      label: 'API Reference',
      collapsed: false,
      items: [
        'api/candlestick-chart',
        'api/candle',
        'api/candle-chart-state',
        'api/chart-indicator',
        'api/drawings',
        'api/style-and-configuration',
      ],
    },
  ],
};

module.exports = sidebars;
