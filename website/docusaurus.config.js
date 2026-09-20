// @ts-check
// Docusaurus config for the CandleKit documentation site.

const { themes: prismThemes } = require('prism-react-renderer');

/** @type {import('@docusaurus/types').Config} */
const config = {
  title: 'CandleKit',
  tagline: 'Interactive SwiftUI candlestick charts, built to feel like a native iOS control.',
  favicon: 'img/logo.svg',

  url: 'https://LalanaChami.github.io',
  baseUrl: '/CandleKit/',

  organizationName: 'LalanaChami',
  projectName: 'CandleKit',

  onBrokenLinks: 'throw',
  onBrokenMarkdownLinks: 'warn',

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  presets: [
    [
      'classic',
      /** @type {import('@docusaurus/preset-classic').Options} */
      ({
        docs: {
          routeBasePath: '/',
          sidebarPath: './sidebars.js',
          editUrl: 'https://github.com/LalanaChami/CandleKit/edit/main/website/',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      }),
    ],
  ],

  themeConfig:
    /** @type {import('@docusaurus/preset-classic').ThemeConfig} */
    ({
      image: 'img/screenshots/chart-hero.png',
      colorMode: {
        defaultMode: 'light',
        respectPrefersColorScheme: true,
      },
      navbar: {
        title: 'CandleKit',
        logo: {
          alt: 'CandleKit logo',
          src: 'img/logo.svg',
        },
        items: [
          {
            type: 'doc',
            docId: 'intro',
            position: 'left',
            label: 'Getting Started',
          },
          {
            type: 'doc',
            docId: 'guides/indicators',
            position: 'left',
            label: 'Guides',
          },
          {
            type: 'doc',
            docId: 'api/candlestick-chart',
            position: 'left',
            label: 'API Reference',
          },
          {
            href: 'https://github.com/LalanaChami/CandleKit',
            label: 'GitHub',
            position: 'right',
          },
        ],
      },
      footer: {
        style: 'dark',
        links: [
          {
            title: 'Docs',
            items: [
              { label: 'Getting Started', to: '/' },
              { label: 'Guides', to: '/guides/indicators' },
              { label: 'API Reference', to: '/api/candlestick-chart' },
            ],
          },
          {
            title: 'More',
            items: [
              { label: 'GitHub', href: 'https://github.com/LalanaChami/CandleKit' },
              { label: 'Issues', href: 'https://github.com/LalanaChami/CandleKit/issues' },
            ],
          },
        ],
        copyright: `Copyright © ${new Date().getFullYear()} CandleKit. Built with Docusaurus.`,
      },
      prism: {
        theme: prismThemes.github,
        darkTheme: prismThemes.dracula,
        additionalLanguages: ['swift'],
      },
    }),
};

module.exports = config;
