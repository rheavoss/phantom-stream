# Git Push SOP — PhantomStream

## Credential Setup (one-time per machine)

Uses `gh` CLI keyring — no PAT in URL or file.
```bash
gh auth switch --user rheavoss
```
That's it. `gh` already has rheavoss token in keyring.

---

## P20 Gate — Before Every Push

State this before pushing:
> "Pushing PhantomStream content to rheavoss/phantom-stream — correct: YES"

aka / PhantomStream → `rheavoss/phantom-stream` only. Never cross-push.

---

## Commit + Push Sequence

```bash
git status                        # see what changed
git diff --stat                   # confirm scope
git add file1 file2 file3         # specific files only — never git add -A
git commit -m "type: description"
gh auth switch --user rheavoss
git -c credential.helper="gh auth git-credential" push origin main
```

---

## Repo Map

| Dir | Repo |
|-----|------|
| `~/Desktop/phantom-stream` | `rheavoss/phantom-stream` |
| `~/Desktop/Instagram/00_agency` | `rheavoss/virtual-influencer-studio` |
