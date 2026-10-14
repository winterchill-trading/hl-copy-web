# scripts/ (AGENTS.md)

`dev.sh` builds the app, assembles `_site/` and serves it on port 8000 (`-r -p PORT` for a release
build on another port). `gen-fixtures.py` regenerates the JSON in `dev/`.

- `_site/` is generated and ignored by git. Do not commit it.
- Run from the repository root.
