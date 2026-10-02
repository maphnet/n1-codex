# Changelog

## 0.1.1

- Add optional acceptance-criteria evaluation before PR publication for hands-off
  runs, including standalone PR creation. Persist per-criterion evidence, block
  failed or stale results, and include verdicts and explicit waivers in PR content.
- Keep evaluation independent of live testing; default the gate to false.
