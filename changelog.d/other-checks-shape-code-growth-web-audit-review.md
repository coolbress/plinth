### Changed

- The last of #1100: `ci / code-growth`, `ci / web-audit` and
  `third-party / review` say what they report in the shared shape's words.
  Their `not yet confirmed:` lines say one fact per sentence (#1156's form),
  `ci / code-growth`'s stopped-step line included. Each `ci / code-growth`
  warning on a function or file is one sentence naming it and the fix
  ("Function x has complexity 12 where the convention is 10, so ask Claude
  to run /improve-codebase-architecture on ..."), and each annotation
  `third-party / review` prints is one sentence too, the detail it carried
  (gh's words, the value given) moved to a plain log line before it. Its
  bare `(#205)`, `(#386)` and `(#674)` linked to the project's own issues;
  they are now links to `docs/how-to/configure-the-third-party-reviewer.md`
  at the plinth commit the project calls. The titled annotation every
  failing check prints keeps #1098's form, what failed and the next step.
  No job, step id, check name, input or secret is renamed.
