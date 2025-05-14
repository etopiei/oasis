# Oasis

This is an opinionated template repository to get up and running with a full-stack OCaml web application. It's basically just Dream, but with some pre-configured setup to take some of the thought out of it.

This is a fork of the wonderful [fsocaml](https://github.com/pjlast/fsocaml) but with no tailwind or templates. Instead the frontend for this framework is `Fmlib_browser` which allows writing an Elm-like frontend.

## About

Oasis is an opinionated framework where it should be clear where to add new features.

It's very much a work in progress right now and should be considered 'alpha-stage' right now. But the long-term goal is to have a easy-to-use and well documented full stack experience with Ocaml. And through this bring type-safety, speed, and simplicity to full-stack applications.

## Getting started

### Dependencies

 - opam installed

Opam can be installed with:

```bash
bash -c "sh <(curl -fsSL https://opam.ocaml.org/install.sh)"
```

### Setup

Next, clone this repository and remove the `.git` folder. E.g. if you want to create a project named `myproject`, run the following command:

```bash
git clone --depth=1 --branch=main git@github.com:etopiei/oasis.git myproject
rm -rf ./myproject/.git

cd myproject
opam update
opam install . --deps-only
```

to use the name of the project folder as the project name:

```bash
dune exec setup
```

or to rename:


```bash
dune exec setup newproject
```

which can be used to give it a different name.

## Running the project

### postgres

Before you can run the project, you'll need to set up your database. Oasis assumes there's a Postgres instance running and that there is a `postgres` user with the password `postgres`. You can adjust these settings in `bin/config/oasis_conf.ml`. In the `db_params` record, adjust the parameters as desired.

For quick setup you can run postgres in docker with the following command:

```
docker run --name oasis-postgres -e POSTGRES_PASSWORD=mysecretpassword -p 5432:5432 -d postgres
```

And edit `bin/config/oasis_conf.ml` to include the password in the previous command.

### migrations

Once you've configured your DB paramaters to your liking, you'll have to create the database and run any existing migrations:

```bash
dune exec migrate create
dune exec migrate up
```

### build the frontend

Build the frontend with:

```
dune build lib/webapp/webapp.js
```

Note: at the moment you'll need to manually build the frontend after changes, but hopefully this will be fixed soon.

### running the server

Start the project by running

```bash
dune exec myproject -w
```

This will start the server with live-reloading enabled. Whenever you change a source file, the project will be recompiled and executed.

## Expanding your project

The project is set up in a way so that most of the work you'll be doing is in the `lib` directory.

You can add new routes in `lib/router.ml`.

Frontend changes are added to `lib/webapp`.

Database models are added to `lib/models`. More info on this to come later.

## Database migrations

Oasis has a CLI tool to manage database migrations.

To create a new database:

```bash
dune exec migrate create
```

To create a new migration:

```bash
dune exec migrate new 'your migration name'
```

To run all upward migrations:

```bash
dune exec migrate up
```

To run all downward migrations:

```bash
dune exec migrate down
```
