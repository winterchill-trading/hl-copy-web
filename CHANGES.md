# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

### Added

- `Api_types`: `Scoring.Integrity_flag`, `Persistence`, `Persistence_point`, `Stats`,
  `Universe`; new optional summary and detail fields; `Leaders_response.universe`;
  `Follow_request.algo`, `Follow.algo`, `Follow.execution`, `Execution`,
  `Execution_report`. Every new field is optional and left out of the JSON when absent.
- Leaders page: a ranking check above the table and an integrity badge per flagged
  leader. Leader page: Integrity, Persistence and Selection statistics sections.
- Follow form: Immediate, TWAP, Adaptive or Passive execution (`Algo_choice`); follow
  cards show the algorithm and the engine's cost report.

### Changed

- `Follow_update.state` is optional and `Follow_update.algo` is new (the JSON of a state
  change is unchanged). `Follow_form.validate` returns `Follow_form.Valid.t`.
