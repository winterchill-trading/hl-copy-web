# dev/ (AGENTS.md)

JSON responses the app serves in mock mode: account, session, agent offer and challenge, and the
leaders in `dev/leaders/`. The expect tests decode every file, so a new fixture must decode.

- Prefer regenerating with `scripts/gen-fixtures.py` over editing JSON by hand.
- Fixtures are invented sample data. Keep them plausible and free of real account details.
