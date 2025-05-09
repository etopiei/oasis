# Oasis

This is an opinionated template repository to get up and running with a full-stack OCaml web application. It's basically just Dream, but with some pre-configured setup to take some of the thought out of it.

This is a fork of the wonderful [fsocaml](https://github.com/pjlast/fsocaml) but with no tailwind or templates. Instead the frontend for this framework is `Fmlib_browser` which allows writing an Elm-like frontend.

Essentially if fsocaml is django the aim of oasis is: drf + elm.

## About

This project is heavily inspired by Elixir Phoenix/Ruby on Rails. It also follows the same Model View Controller (MVC) setup and the "convention over configuration" mindset. The idea is that adding features to your project should be a no-brainer. Database access functions go into `lib/models`, routing goes into `lib/router.ml`, the handling of routes goes into `lib/controllers` and `lib/webapp` is where the front-end app goes.

Hopefully this eliminates the decision fatigue around the trivial stuff, and lets you focus on simply building what you want to build.

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

Before you can run the project, you'll need to set up your database. Oasis assumes there's a Postgres instance running and that there is a `postgres` user with the password `postgres`. You can adjust these settings in `bin/config/oasis_conf.ml`. In the `db_params` record, adjust the parameters as desired.

Once you've configured your DB paramaters to your liking, you'll have to create the database and run any existing migrations:

```bash
dune exec migrate create
dune exec migrate up
```

Start the project by running

```bash
dune exec myproject -w
```

This will start the server with live-reloading enabled. Whenever you change a source file, the project will be recompiled and executed, and any open tabs will be reloaded.

## Expanding your project

The project is set up in a way so that most of the work you'll be doing is in the `lib` directory.

You can add new routes in `lib/router.ml`.

Route handlers are added to `lib/controllers`.

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
