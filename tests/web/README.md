# Web UI tests (jsdom)

Dev-only headless test for the browser wizard (`src/PocketPrep/web/`). It loads
`index.html` + `app.js` in [jsdom](https://github.com/jsdom/jsdom) with a stubbed
`fetch`, and asserts the wizard bootstraps, calls the token-authenticated API, and
renders the first step without errors. **Not** a runtime dependency of the app.

```bash
cd tests/web
npm install      # or: npm ci
npm test
```

CI runs this on Node 20. `node_modules/` is gitignored.
