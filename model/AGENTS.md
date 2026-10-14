# model/ (AGENTS.md)

`copy_web_model`: pure logic with no DOM: routes, number and time formatting, leader table sorting
and filtering, chart tick and geometry, form validation, the agent status check, the mock account.
Tested natively by expect tests.

- Keep this directory free of `Bonsai` and `Js_of_ocaml` imports so the tests run natively.
- Validation messages are user text; a change to one changes what users see, so update its test.
