# SHIFTCAST web lobby E2E

Serve the exported web build from the repository root, then run:

```powershell
python -m http.server 8790 --directory build/web
```

In another shell:

```powershell
cd tools/web_e2e
npm install
npm test -- --url http://127.0.0.1:8790/index.html --headed
```

The test opens two isolated Chromium contexts, records each browser console and captures screenshots in `output/`. Chromium uses SwiftShader flags for software WebGL and backgrounds the host page while the joiner connects. Each run is capped at 45 seconds. Run the command again to repeat; each attempt creates a fresh host/join pair.
