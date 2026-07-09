# Publish ShelfBar to GitHub

Target release:

- Repository: `ShelfBar`
- Tag: `v1.0.0-beta.1`
- Release title: `ShelfBar v1.0 Beta`
- Pages source: `main` branch, `/docs` folder

## Required account

Publish from the GitHub account that belongs to:

```text
chenyouxiang0810@gmail.com
```

Before publishing, verify the logged-in GitHub account:

```bash
gh auth status
gh api user --jq '.login'
gh api user/emails --jq '.[] | select(.email == "chenyouxiang0810@gmail.com")'
```

If the email check returns nothing, stop and switch accounts.

## Install GitHub CLI if missing

```bash
brew install gh
```

## Login

```bash
gh auth login
```

Choose:

- GitHub.com
- HTTPS
- Login with a web browser

## Create / publish repository

From the project root:

```bash
cd /Users/seannb/TouchBarPrivateResearch
git remote remove origin 2>/dev/null || true
gh repo create ShelfBar --public --source . --remote origin --push
git push origin main --tags
```

If the repo already exists and should be replaced, do not delete it blindly. Confirm first, then either archive/delete that specific `ShelfBar` repo from GitHub settings or push over it intentionally.

## Enable GitHub Pages

```bash
gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  /repos/$(gh api user --jq .login)/ShelfBar/pages \
  -f source.branch=main \
  -f source.path=/docs
```

If Pages already exists, update it:

```bash
gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  /repos/$(gh api user --jq .login)/ShelfBar/pages \
  -f source.branch=main \
  -f source.path=/docs
```

Expected Pages URL:

```text
https://<github-login>.github.io/ShelfBar/
```

## Create GitHub Release

```bash
gh release create v1.0.0-beta.1 \
  build/Release/ShelfBar.dmg \
  build/Release/ShelfBar.zip \
  build/Release/SHA256SUMS.txt \
  --title "ShelfBar v1.0 Beta" \
  --notes-file Packaging/github/RELEASE_NOTES_v1.0.0-beta.1.md \
  --prerelease
```

Expected Release URL:

```text
https://github.com/<github-login>/ShelfBar/releases/tag/v1.0.0-beta.1
```
