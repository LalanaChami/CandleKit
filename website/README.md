# CandleKit Docs

The source for the CandleKit documentation site, built with [Docusaurus](https://docusaurus.io/).

## Local development

```bash
cd website
npm install
npm start
```

This starts a local dev server and opens a browser window. Most changes to docs pages are
reflected live without restarting the server.

## Deployment

This site deploys automatically to GitHub Pages via the `.github/workflows/deploy-docs.yml`
GitHub Actions workflow, on every push to `main` that touches the `website/` directory.

GitHub Pages needs to be enabled once, in the repository's settings:

1. Go to **Settings › Pages**.
2. Under **Build and deployment**, set **Source** to **GitHub Actions**.

After that, every push to `main` builds the site and publishes it automatically — no manual
`npm run deploy` step needed. You can also trigger a deploy manually from the **Actions** tab using
the workflow's `workflow_dispatch` trigger.
