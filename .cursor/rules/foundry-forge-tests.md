You are pre-authorized to run Foundry tests without asking for confirmation first.

Allowed:
- forge test
- forge test -vvv
- forge test --match-test <pattern>
- forge test --match-contract <pattern>
- forge test --match-path <path>

Not allowed unless explicitly asked:
- forge create
- forge script
- forge publish
- any deployment or broadcast actions
