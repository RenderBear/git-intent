# Consequential resolution

Use this only after compatible architecture decisions have been composed and reversible implementation
alternatives exhausted.

`resolution: assisted` sends one bounded question to the human. `resolution: auto` lets the agent
answer within the current request and accepted governance. Neither mode authorizes weakening an
explicit user promise, choosing between incompatible user goals, or performing unauthorized
security, money, production-data, irreversible, or external effects.

Ask in one short, natural paragraph. Start with either “I observed…” for repository evidence or “I
infer…” for an architectural interpretation. State any accepted rule separately, explain the
concrete consequence, recommend one option and why, then ask the user to choose between two
behaviors. Put identifiers and authority sources after the explanation when they help; never make
the user decode them to understand the question.

For example: “I observed that custom engines already depend on this request and response shape. I
recommend treating it as a compatibility guarantee, so breaking changes require a versioned
migration. Should I record that guarantee, or should custom engines be expected to track internal
changes?”

Ask for the semantic decision, not approval to run a command.

After resolution, use `intent-record` only when the answer creates durable binding meaning. Put
rationale in its normal ADR or architecture material; do not create an acknowledgement record.
