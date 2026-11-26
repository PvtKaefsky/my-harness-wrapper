# Python experiment layer template

These files add an experiment layer to a Python project. A session copies them into the project when it creates the repository or when the user asks for the layer. Each file lands at the same path relative to the project root.

## Files

| Template path | What it is |
| --- | --- |
| `.env.example` | Tracked example of the untracked `.env`, listing every environment name with a safe value. |
| `.gitignore` | Fragment appended to the project's `.gitignore`: `.env`, `.env.*` except `.env.example`, `runs/` and `__pycache__/`. |
| `.dockerignore` | Fragment appended to the project's `.dockerignore`: `.env`, `.env.*` and `runs/`, so no secret or run output enters the image. |
| `Makefile` | Root targets `build`, `up`, `down`, `test` and `experiment EXP=<name>`, run in the project's image. |
| `conf/config.yaml` | Hydra base configuration with the shared defaults; environment values are read with `${oc.env:<NAME>}`. |
| `research/HYP-1-example/experiments/baseline.yaml` | Sample experiment: an override file merged over `conf/config.yaml`. |
| `src/package/run.py` | Run entry module: `run(cfg)` is the programmatic interface, `main()` reads the configuration and calls it. |
| `src/package/hyp_1_example/task.py` | Sample hypothesis task named by `task._target_` in `conf/config.yaml`. |

## Placeholders

| Placeholder | Replace with |
| --- | --- |
| `<package>` in file contents | The project's import package name. |
| `src/package/` directory | `src/<package>/`. |
| `<image>` in `Makefile` | The tag of the project's image, built from the root `Dockerfile`. |
| `HYP-1-example`, `hyp_1_example` | The first hypothesis's directory and module names, or remove both. |

The `Makefile` assumes a root `Dockerfile` whose image has Python, `git`, the project's dependencies, `hydra-core`, `python-dotenv` and `pytest`, with `git config --system --add safe.directory /app`. It mounts the project at `/app` with `PYTHONPATH=src`.

## Layout rules

- An experiment is an override file `research/HYP-<n>-<slug>/experiments/<name>.yaml` plus its runs.
- `make experiment EXP=<name>` runs the override file named `<name>.yaml` in any hypothesis directory, so experiment names are unique across hypotheses.
- Hypothesis code lives in `src/<package>/<hypothesis>/`, its tests in `tests/<hypothesis>/`, and its module docstring names its `HYP-<n>`.
- Run outputs go to the ignored `runs/` directory. A shared experiment tracker is added only where the team has agreed one; otherwise the session asks first.

## Runs

`python -m <package>.run <override file>` loads `.env` through `python-dotenv`, composes `conf/config.yaml` with Hydra, merges the override file, and calls `run`. Values already set in the process environment win over `.env`.

`run` calls `task._target_` with the task's configured arguments and `run_dir`, the run's directory `runs/<run_id>/`. That directory holds:

| File | Content |
| --- | --- |
| `config.yaml` | The resolved configuration with secrets redacted, plus `experiment`, the override file's path. |
| `metadata.json` | The fields in the next table. |
| Files the task writes | The run's results. |

| `metadata.json` field | Value |
| --- | --- |
| `run_id` | UTC start time and a random suffix, `YYYYMMDDTHHMMSSZ-xxxxxxxx`. |
| `experiment` | The override file's path. |
| `commit` | `git rev-parse HEAD` at the start of the run. |
| `dirty` | `true` when `git status --porcelain` printed anything at the start of the run: a tracked change, or an untracked file that is not ignored. |
| `seed` | The configuration's `seed`. |
| `environment` | `python` version and `platform` string; no environment variables. |
| `status` | `completed`, `failed` when the task raises, or `interrupted` on Ctrl+C or SIGTERM. |

A run with `dirty: true` is cited by no `results.md`.

## Secrets

A configuration key is secret when one of its words is `secret`, `secrets`, `password`, `passwords`, `passwd`, `token`, `key`, `apikey`, `credential`, `credentials` or `auth`, case-insensitive, at any depth, including mappings inside lists. Words are separated by `_`, `-` or a camelCase boundary. `api_token`, `private_key`, `api-key`, `clientSecret` and `sort_key` are secret; `max_tokens`, `maxTokens` and `tokenizer` are not. `config.yaml` stores `'***'` as each secret key's value. A secret held under a key that does not match, or inside a value such as a URL with a password, is saved in clear, so secret values take matching key names.
