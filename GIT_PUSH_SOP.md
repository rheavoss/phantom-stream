# Git Push SOP — PhantomStream / aka

## Credential Setup (one-time per machine)

Token is embedded in the remote URL. Get it from the Instagram repo:
```bash
git -C ~/Desktop/Instagram/00_agency remote get-url origin
```
Then set it here:
```bash
git -C ~/Desktop/phantom-stream remote set-url origin \
  "https://rheavoss:<TOKEN>@github.com/rheavoss/phantom-stream.git"
```
Run once in Terminal. After that, `git push` works with no auth prompt.

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
git push origin main
```

---

## Repo Map

| Dir | Repo |
|-----|------|
| `~/Desktop/phantom-stream` | `rheavoss/phantom-stream` |
| `~/Desktop/Instagram/00_agency` | `rheavoss/virtual-influencer-studio` |
