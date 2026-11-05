# Last Can product page

A one-page introduction to Last Can with an early-access sign-up. Plain HTML, CSS and JavaScript in `index.html`; no build step.

Live at **https://jameschu-byte337.github.io/caffine_tracker_-Last-Can-_dev/** once GitHub Pages is turned on.

## Publish on GitHub Pages

The site is served from the `gh-pages` branch, which holds just the contents of this folder.

One time: on GitHub, open the repo → **Settings** → **Pages** → **Build and deployment**, set **Source** to **Deploy from a branch**, pick **gh-pages** and **/ (root)**, and save.

After changing anything in this folder, commit it, then update the live site from the repo root:

```bash
git subtree push --prefix "product page" origin gh-pages
```

## Turn on email sign-ups

The page is static, so sign-ups need a form service to store the emails. Until one is set, the button shows "Sign-ups open very soon".

1. Create a free form at [formspree.io](https://formspree.io) and copy its endpoint (looks like `https://formspree.io/f/abcdwxyz`).
2. In `index.html`, set `const SIGNUP_ENDPOINT = "https://formspree.io/f/abcdwxyz";`.
3. Push. Sign-ups then arrive in your Formspree inbox.

The form only accepts `@uwaterloo.ca` addresses, matching the app's sign-in.

## Files

| Path | What it is |
|---|---|
| `index.html` | The page |
| `assets/screens/` | App screenshots used on the page (web size) |
| `assets/og-image.png` | Preview image LinkedIn and others show for the link |
| `screenshots/` | Full-resolution images for posts: `last-can-*.png` are app screens, `page-*.png` are sections of this page |

App screenshots come from the iPhone Air simulator with demo data (debug builds, launch argument `-seedDemoData`).
