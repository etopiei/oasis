(** Setup script to customize a new oasis project.

    Patches to `dune-project` and the various `dune` files are done by parsing
    the S-expressions and replacing instances of `oasis` when it's in a
    non-label position in the `Sexp.List`.

    Source file patching (e.g. `bin/main.ml` is done by searching and replacing
    references to the Oasis module itself. *)

open Core

let dune_files = [ "dune-project"; "test/dune"; "lib/dune"; "bin/dune" ]

let rename_files =
  [ "oasis.opam"; "oasis.opam.template"; "test/oasis.ml" ]

let indent n = String.init n ~f:(fun _ -> ' ')

let pp_atom a =
  if String.contains a ' ' then
    "\"" ^ a ^ "\""
  else
    a

(** Convert an S-expression into a pretty-printed string in the style of a dune
    configuration file. *)
let pp_sexp s =
  let rec loop s' i f =
    match s' with
    | Sexp.Atom a -> pp_atom a
    | Sexp.List l ->
        let nl =
          if f then
            ""
          else
            "\n"
        in
        let prefix = sprintf "%s%s(" nl (indent (i * 2)) in
        let ls =
          List.foldi l ~init:"" ~f:(fun j acc s'' ->
              let sp =
                if j = 0 then
                  ""
                else
                  " "
              in
              acc ^ sp ^ loop s'' (i + 1) false)
        in
        prefix ^ ls ^ ")"
  in
  loop s 0 true ^ "\n"

(** Scan an S-expression and replace all instances of `from` with `into`, except
    for labels (the first atom in a list). *)
let sexp_patch s ~from ~into =
  let rec loop s' label =
    match (s', label) with
    | Sexp.Atom a, false when String.equal a from -> Sexp.Atom into
    | Sexp.Atom _, _ -> s'
    | Sexp.List l, _ ->
        Sexp.List
          (List.mapi l ~f:(fun i s'' ->
               if i = 0 then
                 loop s'' true
               else
                 loop s'' false))
  in
  loop s true

let patch_sfile filename from into =
  let f =
    Sexp.load_sexps filename
    |> List.map ~f:(sexp_patch ~from ~into)
    |> List.map ~f:pp_sexp
  in
  Out_channel.write_lines filename f

(** Scan lines in a source code file and replace all instances of `from` with
    `into`. *)
let patch_mlfile filename ~from ~into =
  let data =
    In_channel.read_all filename
    |> String.substr_replace_all ~pattern:from ~with_:into
  in
  Out_channel.write_all filename ~data

let () =
  Clap.description "Set up a new oasis project.";

  let dbname =
    Clap.optional_string ~long:"dbname" ~short:'d' ~placeholder:"DB_NAME" ()
      ~description:"Database name (default: oasis_dev)"
  in

  let projname =
    Clap.optional_string ~placeholder:"PROJECT_NAME" ()
      ~description:"Name of the oasis project (default: oasis)"
  in

  Clap.close ();

  let _ = Option.value dbname ~default:"oasis_dev" in
  let cwd = Core_unix.getcwd () |> String.split ~on:'/' |> List.last in
  let default_projname = Option.value cwd ~default:"oasis" in
  let projname' =
    String.lowercase (Option.value projname ~default:default_projname)
  in

  List.iter dune_files ~f:(fun file -> patch_sfile file "oasis" projname');

  let projname'' = String.capitalize projname' in
  patch_mlfile "bin/main.ml" ~from:"Oasis.Router.router"
    ~into:(projname'' ^ ".Router.router");

  printf "%d files were patched.\n" (List.length dune_files + 1);

  rename_files
  |> List.iter ~f:(fun oldpath ->
         let newpath =
           oldpath
           |> String.substr_replace_all ~pattern:"oasis" ~with_:projname'
         in
         Core_unix.rename ~src:oldpath ~dst:newpath);

  printf "%d files were renamed.\n" (List.length rename_files)
