# Contributing

Thanks for wanting to help. Here's how it works.

## Before you start

Make sure your git config (`user.name` and `user.email`) matches your GitHub profile. **Sign your commits** — here's [how to set that up](https://gist.github.com/Beneboe/3183a8a9eb53439dbee07c90b344c77e) if you haven't already.

## The workflow

1. Branch off `main`
2. Keep your branch up to date with `main`
3. Open a PR with a brief description of what changed and why
4. A maintainer will review it

We do linear commit history. One focused commit per PR is the norm — if you've got a stack of commits, we'll ask you to squash or rebase them cleanly. [This post](https://www.bitsnbites.eu/a-tidy-linear-git-history/) explains the reasoning.

## Commit messages

Clear and concise. Under 80 characters for the subject line. If you need more context, add a body (120 char line limit).

## Code style

Run `make check` before you push. If the linter is unhappy, fix it first.

## Running it locally

[Dev onboarding](docs/dev-onboarding.md) gets the backend and the app running. SQLite is the default database;
[PostgreSQL for local development](docs/architecture/postgres-dev.md) covers running against PostgreSQL with
`make serve/postgres` and `DB_BACKEND=postgres`.

## Found a bug or have an idea?

[Open an issue](https://github.com/autobutler-org/quark/issues/new). We read them.
