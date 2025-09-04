# Sheer Internal Guide for @sheer/patchright

This document is for **Sheer Health engineers** who need to build and publish our patched Playwright fork (`@sheer/patchright`) into Google Artifact Registry (GAR).

---

## 📦 What is this package?

- A fork of [Patchright](https://github.com/Kaliiiiiiiiii-Vinyzu/patchright-nodejs).
- Applies Sheer-specific patches and rebranding to Playwright.
- Published to **GAR** under the scope `@sheer/patchright`.
- Versions match upstream Playwright (e.g. `1.52.5`).

---

## 🚀 Publishing a new version

1. **Authenticate with GCP**

   ```sh
   gcloud auth login
   gcloud config set project sheer-health-scratch
   ```

2. **Set the Playwright version you want to patch**

   ```sh
   export PLAYWRIGHT_VERSION=v1.52.5
   export PATCHRIGHT_SEMVER=1.52.5
   ```

3. **Run the build & patch script**

   ```sh
   pnpm run release:prep
   ```

4. **Authenticate npm to GAR**

   ```sh
   pnpm run release:auth
   ```

5. **Publish the package**
   ```sh
   pnpm run release:publish
   ```

Or, run everything in one step:

```sh
pnpm run release:gar
```

---

## 📝 Notes

- **Do not publish from the repo root.** Always publish from the generated directory:
  ```
  playwright/packages/patchright
  ```
- `pnpm publish` requires a clean tree. Use `--no-git-checks` if needed.
- The published README shown in GAR comes from the `README.md` inside `playwright/packages/patchright`.  
  Keep this `README-SHEER.md` for **internal instructions only**.

---

## 🔧 Common Issues

- **`ENEEDAUTH` error** → run `pnpm run release:auth` again to refresh your `.npmrc`.
- **Wrong version number** → check `package.json` in `playwright/packages/patchright` and confirm it matches the Playwright tag (`vX.Y.Z`).
- **Provenance errors** → do not use `--provenance`; GAR does not support it.

---
