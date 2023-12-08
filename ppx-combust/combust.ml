open Ppxlib
open Ast_helper
open Base

let deriver = "combust"

type primary_options = { auto_increment : bool; not_null : bool }

let parse_options options =
  let auto_increment = ref true in
  let not_null = ref false in
  options
  |> List.iter ~f:(fun (name, expr) ->
         match name with
         | "auto_increment" ->
             auto_increment := Ppx_deriving.Arg.(get_expr ~deriver bool) expr
         | "not_null" ->
             not_null := Ppx_deriving.Arg.(get_expr ~deriver bool) expr
         | _ ->
             Location.raise_errorf ~loc:expr.pexp_loc
               "%s does not support option %s" deriver name);
  { auto_increment = !auto_increment; not_null = !not_null }

let make_str_const ~loc s = Exp.constant (Pconst_string (s, loc, None))
let make_ident ~loc txt = Exp.ident { txt; loc }
let make_str_ident ~loc s = make_ident ~loc (Lident s)
let make_pattern ~loc name = Ast_helper.Pat.var { txt = name; loc }

module LabelUtil = struct
  let to_param_name lbl = lbl.pld_name.txt
  let to_field_name lbl = "f_" ^ to_param_name lbl
end

let constructify_pat ~loc xs f =
  let cons = { txt = Lident "::"; loc } in
  let nil = Ast_helper.Pat.construct { txt = Lident "[]"; loc } None in
  List.fold_right xs ~init:nil ~f:(fun item acc ->
      Ast_helper.Pat.construct cons
        (Some (Ast_helper.Pat.tuple [ f item; acc ])))

let constructify_exp ~loc xs f =
  let cons = { txt = Lident "::"; loc } in
  let nil = Ast_helper.Exp.construct { txt = Lident "[]"; loc } None in
  List.fold_right xs ~init:nil ~f:(fun item acc ->
      Ast_helper.Exp.construct cons
        (Some (Ast_helper.Exp.tuple [ f item; acc ])))

let make_pat_list ~loc labels =
  constructify_pat ~loc labels (fun lbl ->
      make_pattern (LabelUtil.to_field_name lbl) ~loc)

(* type petrol_type { *)

module FieldUtil = struct
  let primary_key_is_autoincrement attr =
    match attr.attr_payload with
    | PStr [ [%stri { auto_increment = true }] ] -> true
    | PStr [ [%stri { auto_increment = false }] ] -> false
    | PStr [ [%stri { auto_increment = [%e? _] }] ] ->
        Location.raise_errorf "Weird auto_increment value"
    | PStr [ _ ] -> Location.raise_errorf "Unrecognized keys in @primary"
    | _ -> false

  let primary_key_opt ?(include_autoincrement = true) lbl =
    List.find lbl.pld_attributes ~f:(fun attr ->
        String.(attr.attr_name.txt = "primary")
        && (include_autoincrement || primary_key_is_autoincrement attr))

  let unique_key_opt lbl =
    List.find lbl.pld_attributes ~f:(fun attr ->
        String.(attr.attr_name.txt = "unique"))

  let foreign_key_opt lbl =
    List.find lbl.pld_attributes ~f:(fun attr ->
        String.(attr.attr_name.txt = "foreign"))

  let find_primary_key labels =
    List.find labels ~f:(fun lbl -> primary_key_opt lbl |> Option.is_some)

  let filter_primary_key labels =
    List.filter labels ~f:(fun lbl ->
        primary_key_opt ~include_autoincrement:false lbl |> Option.is_none)

  let coltype_key_opt lbl =
    List.find lbl.pld_attributes ~f:(fun attr ->
        String.(attr.attr_name.txt = "coltype"))

  type petrol_type = {
    accessor : string option;
    ident : string;
    nullable : bool;
  }

  let get_type ~loc lbl =
    let rec get_type' ~nullable typ =
      match typ.ptyp_desc with
      | Ptyp_constr ({ txt = Lident "option"; _ }, [ typ ]) ->
          get_type' ~nullable:true typ
      | Ptyp_constr ({ txt = Lident li; _ }, _) ->
          { ident = li; accessor = None; nullable }
      | Ptyp_constr ({ txt = Ldot (Lident li, acc); _ }, _) ->
          { ident = li; accessor = Some acc; nullable }
      | _ -> Location.raise_errorf ~loc:lbl.pld_loc "Unknown type in combust"
    in
    get_type' ~nullable:false lbl.pld_type

  let is_nullable ~loc lbl = (get_type ~loc lbl).nullable

  let petrol_type ~loc lbl =
    let long_ident ty accessor =
      make_ident ~loc @@ Longident.(Ldot (Lident ty, accessor))
    in
    let ty = get_type ~loc lbl in
    let coltype = coltype_key_opt lbl in
    let ident =
      if Option.is_some coltype then
        match (Option.value_exn coltype).attr_payload with
        | PStr [ { pstr_desc = Pstr_eval (expr, _); pstr_loc } ] -> expr
        | _ ->
            Location.raise_errorf ~loc:lbl.pld_loc "Unknown petrol column type"
      else
        match ty with
        | { ident = "int"; _ } -> long_ident "Type" "int"
        | { ident = "int64"; _ } -> long_ident "Type" "big_int"
        | { ident = "string"; _ } -> long_ident "Type" "text"
        | { ident = "bool"; _ } -> long_ident "Type" "bool"
        | { ident = "Ptime"; accessor = Some "t"; _ } ->
            long_ident "Type" "time"
        | { ident = "float"; _ } -> long_ident "Type" "real"
        | { ident = ty; accessor = Some "t"; _ } -> long_ident ty "petrol_types"
        | { ident = ty; _ } -> (
            match lbl.pld_type.ptyp_desc with
            | Ptyp_constr (_, types_) ->
                Location.raise_errorf ~loc:lbl.pld_loc
                  "Unknown petrol type: %s %d" ty (List.length types_)
            | _ ->
                Location.raise_errorf ~loc:lbl.pld_loc "Unknown petrol type: %s"
                  ty)
    in
    if ty.nullable then
      [%expr Type.null_ty [%e ident]]
    else
      ident

  let petrol_type_fn ~loc lbl =
    match get_type ~loc lbl with
    | { ident = "int"; nullable = true; _ } -> make_str_ident ~loc "i_opt"
    | { ident = "int"; nullable = false; _ } -> make_str_ident ~loc "i"
    | { ident = "int64"; nullable = true; _ } -> [%expr vl_opt ~ty:Type.big_int]
    | { ident = "int64"; nullable = false; _ } -> [%expr vl ~ty:Type.big_int]
    | { ident = "string"; nullable = true; _ } -> make_str_ident ~loc "s_opt"
    | { ident = "string"; nullable = false; _ } -> make_str_ident ~loc "s"
    | { ident = "bool"; nullable = false; _ } -> make_str_ident ~loc "bl"
    | { ident = "bool"; nullable = true; _ } -> make_str_ident ~loc "bl_opt"
    | { ident = "float"; nullable = false; _ } -> make_str_ident ~loc "f"
    | { ident = "float"; nullable = true; _ } -> make_str_ident ~loc "f_opt"
    | { ident = "Ptime"; accessor = Some "t"; nullable = false; _ } ->
        [%expr vl ~ty:Type.time]
    | { ident = "Ptime"; accessor = Some "t"; nullable = true; _ } ->
        [%expr vl_opt ~ty:Type.time]
    | { ident = ty; accessor = Some _; _ } ->
        let ty = Longident.(Ldot (Lident ty, "petrol_typed")) in
        let ty = make_ident ~loc:lbl.pld_loc ty in
        [%expr vl ~ty:[%e ty]]
    | { ident = ty; _ } ->
        Location.raise_errorf ~loc:lbl.pld_loc "Unknown petrol type fn: %s" ty
end

let make_field_from_label ~loc lbl =
  let name = make_str_const ~loc lbl.pld_name.txt in
  let primary_attr = FieldUtil.primary_key_opt lbl in
  let unique_attr = FieldUtil.unique_key_opt lbl in
  let foreign_attr = FieldUtil.foreign_key_opt lbl in
  let ty = FieldUtil.petrol_type ~loc lbl in
  let nullable = FieldUtil.is_nullable ~loc lbl in
  match (primary_attr, unique_attr, foreign_attr) with
  | Some primary, _, _ ->
      let payload = primary.attr_payload in
      let autoincrement =
        match payload with
        | PStr [ [%stri { auto_increment = true }] ] -> true
        | PStr [ [%stri { auto_increment = false }] ] -> false
        | PStr [ [%stri { auto_increment = [%e? _] }] ] ->
            Location.raise_errorf ~loc "Weird auto_increment value"
        | PStr [ _ ] ->
            Location.raise_errorf ~loc "Unrecognized keys in @primary"
        | _ -> false
      in
      if autoincrement then
        [%expr
          field [%e name] ~ty:[%e ty]
            ~constraints:[ primary_key ~auto_increment:true (); not_null () ]]
      else
        [%expr
          field [%e name] ~ty:[%e ty]
            ~constraints:[ primary_key ~on_conflict:`REPLACE (); not_null () ]]
  | _, Some unique, _ ->
      let unique_name = make_str_const ~loc (lbl.pld_name.txt ^ "_unique") in
      [%expr
        field [%e name] ~ty:[%e ty]
          ~constraints:[ unique ~name:[%e unique_name] (); not_null () ]]
  | _, _, Some foreign ->
      let payload = foreign.attr_payload in
      let tbl, id =
        match payload with
        | PStr [ [%stri [%e? tbl] [%e? id]] ] -> (tbl, id)
        | _ -> Location.raise_errorf ~loc "we not got it"
      in
      [%expr
        field [%e name] ~ty:[%e ty]
          ~constraints:
            [
              not_null ();
              foreign_key ~table:[%e tbl]
                ~columns:Expr.([%e id])
                  (* TODO: Need to make these configurable *)
                ~on_update:`RESTRICT ~on_delete:`CASCADE ();
            ]]
  | _ ->
      if nullable then
        [%expr field [%e name] ~ty:[%e ty]]
      else
        [%expr field [%e name] ~ty:[%e ty] ~constraints:[ not_null () ]]

let tuplify ~loc labels f =
  List.fold_right labels ~init:(make_pattern ~loc "()") ~f:(fun lbl acc ->
      Ast_helper.Pat.tuple ~loc [ f lbl; acc ])

let make_decode ~loc labels =
  let make_pattern = make_pattern ~loc in
  let unpacked =
    List.fold_right labels ~init:(make_pattern "()") ~f:(fun lbl acc ->
        Ast_helper.Pat.tuple ~loc [ make_pattern lbl.pld_name.txt; acc ])
  in
  let expr =
    List.fold_right labels ~init:[] ~f:(fun lbl acc ->
        let ident = { txt = Lident lbl.pld_name.txt; loc } in
        (ident, Ast_helper.Exp.ident ident) :: acc)
  in
  let expr = Ast_helper.Exp.record expr None in
  [%stri let decode [%p unpacked] = [%e expr]]

let make_create ~loc labels =
  let fields = FieldUtil.filter_primary_key labels in
  let values =
    constructify_exp ~loc fields (fun lbl ->
        let field_name = LabelUtil.to_field_name lbl |> make_str_ident ~loc in
        let petrol_type = FieldUtil.petrol_type_fn ~loc lbl in
        let param_name = LabelUtil.to_param_name lbl |> make_str_ident ~loc in
        [%expr [%e field_name] := [%e petrol_type] [%e param_name]])
  in
  let body =
    match FieldUtil.find_primary_key labels with
    | Some lbl ->
        let primary_field =
          LabelUtil.to_field_name lbl |> make_str_ident ~loc
        in
        [%expr
          fun db ->
            Query.insert ~table ~values:Expr.([%e values])
            |> Query.returning Expr.[ [%e primary_field] ]
            |> Request.make_one
            |> Petrol.find db
            |> Lwt_result.map fst]
    | None ->
        [%expr
          fun db ->
            Query.insert ~table ~values:Expr.([%e values])
            |> Request.make_zero
            |> Petrol.exec db]
  in
  let f =
    List.fold_right fields ~init:body ~f:(fun item acc ->
        let default =
          List.find_map item.pld_attributes ~f:(fun attr ->
              match (attr.attr_name.txt, attr.attr_payload) with
              | ( "default",
                  PStr [ { pstr_desc = Pstr_eval (expr, _); pstr_loc } ] ) ->
                  Some expr
              | _ -> None)
        in
        let name = item.pld_name.txt in
        let arg_name =
          match default with
          | Some _ -> Optional name
          | None -> Labelled name
        in
        Ast_helper.Exp.fun_ arg_name default (make_pattern ~loc name) acc)
  in
  let v = [%pat? create] in
  [%stri let [%p v] = [%e f]]

(* let make_upsert ~loc labels = *)
(*   let fields = FieldUtil.filter_primary_key labels in *)
(*   let values = *)
(*     constructify_exp ~loc fields (fun lbl -> *)
(* let field_name = LabelUtil.to_field_name lbl |> make_str_ident ~loc in *)
(* let petrol_type = FieldUtil.petrol_type_fn ~loc lbl in *)
(* let param_name = LabelUtil.to_param_name lbl |> make_str_ident ~loc in *)
(*       [%expr [%e field_name] := [%e petrol_type] [%e param_name]]) *)
(*   in *)
(*   let body = *)
(*     match FieldUtil.find_primary_key labels with *)
(*     | Some lbl -> *)
(* let primary_field = LabelUtil.to_field_name lbl |> make_str_ident ~loc in *)
(*       [%expr *)
(*         fun db -> *)
(*           let values = ref [ f_twitch_user_id ] in *)
(*           if Option.is_some twitch_display_name *)
(*           then values := Expr.(f_twitch_display_name :: !values; *)
(*           (* if Option.is_some twitch_profile_url *) *)
(*           (* then values := f_twitch_profile_url :: !values; *) *)
(*           Query.upsert *)
(*             ~table *)
(*             ~values:!values *)
(*             ~on_conflict: *)
(*               (Some *)
(*                  (`DO_UPDATE *)
(*                    ( "twitch_user_id" *)
(* , "SET twitch_display_name = excluded.twitch_display_name \ *) (* broken"
   ))) *)
(*           |> Query.returning Expr.[ [%e primary_field] ] *)
(*           |> Request.make_one *)
(*           |> Petrol.find db *)
(*           |> Lwt_result.map fst] *)
(*     | None -> *)
(*       [%expr *)
(*         fun db -> *)
(*           Query.insert ~table ~values:Expr.([%e values]) *)
(*           |> Request.make_zero *)
(*           |> Petrol.exec db] *)
(*   in *)
(*   let f = *)
(*     List.fold_right fields ~init:body ~f:(fun item acc -> *)
(*       let default = *)
(*         List.find_map item.pld_attributes ~f:(fun attr -> *)
(*           match attr.attr_name.txt, attr.attr_payload with *)
(* | "default", PStr [ { pstr_desc = Pstr_eval (expr, _); pstr_loc } ] -> *)
(*             Some expr *)
(*           | _ -> None) *)
(*       in *)
(*       let name = item.pld_name.txt in *)
(*       let arg_name = *)
(*         match default with *)
(*         | Some _ -> Optional name *)
(*         | None -> Labelled name *)
(*       in *)
(*       Ast_helper.Exp.fun_ arg_name default (make_pattern ~loc name) acc) *)
(*   in *)
(*   let v = [%pat? upsert] in *)
(*   [%stri let [%p v] = [%e f]] *)
(* ;; *)

let make_read ~loc labels =
  match FieldUtil.find_primary_key labels with
  | Some primary_key ->
      let field_name =
        LabelUtil.to_field_name primary_key |> make_str_ident ~loc
      in
      let fun_name = FieldUtil.petrol_type_fn ~loc primary_key in
      [%stri
        let read id db =
          Query.select ~from:table fields
          |> Query.where Expr.([%e field_name] = [%e fun_name] id)
          |> Request.make_zero_or_one
          |> Petrol.find_opt db
          |> Lwt_result.map (Option.map ~f:decode)]
  | _ -> [%stri let () = ()]

let make_delete ~loc labels =
  match FieldUtil.find_primary_key labels with
  | Some primary_key ->
      let field_name =
        LabelUtil.to_field_name primary_key |> make_str_ident ~loc
      in
      let fun_name = FieldUtil.petrol_type_fn ~loc primary_key in
      [%stri
        let delete id db =
          Query.delete ~from:table
          |> Query.where Expr.([%e field_name] = [%e fun_name] id)
          |> Request.make_zero
          |> Petrol.exec db]
  | _ -> [%stri let () = ()]

let generate_impl ~ctxt (_rec_flag, type_decls) name constraints =
  let loc = Expansion_context.Deriver.derived_item_loc ctxt in
  let name =
    match name with
    | Some name -> name
    | None -> Location.raise_errorf ~loc "Missing table name"
  in
  let constraints =
    match constraints with
    | Some constraints -> constraints
    | None -> [%expr []]
  in
  List.map type_decls ~f:(function
    | { ptype_kind = Ptype_record labels; ptype_manifest; ptype_name; _ } ->
        let name = make_str_const ~loc name in
        let schema_fields =
          List.map labels ~f:(make_field_from_label ~loc)
          |> Ast_builder.Default.elist ~loc
        in
        let pat_name = make_pat_list ~loc labels in
        let names = [%pat? [%p pat_name]] in
        let field_destructure = [%stri let Expr.([%p names]) = fields] in
        let decode = make_decode ~loc labels in
        [%stri
          include struct
            open Base
            open Petrol
            open Petrol.Postgres

            let table, fields =
              StaticSchema.declare_table schema ~name:[%e name]
                ~constraints:[%e constraints]
                Schema.([%e schema_fields])

            (* TODO: Should keep track of all custom types and assert that they
               match the module type we need *)

            [%%i field_destructure]
            [%%i decode]

            let find_one ?where db =
              let qry = Query.select fields ~from:table in
              let qry =
                match where with
                | Some where -> qry |> Query.where where
                | None -> qry
              in
              qry |> Request.make_one |> Petrol.find db |> Lwt_result.map decode

            let find_many ?where db =
              let qry = Query.select fields ~from:table in
              let qry =
                match where with
                | Some where -> qry |> Query.where where
                | None -> qry
              in
              qry
              |> Request.make_many
              |> Petrol.collect_list db
              |> Lwt_result.map (List.map ~f:decode)

            let find_one_opt ?where db =
              let qry = Query.select fields ~from:table in
              let qry =
                match where with
                | Some where -> qry |> Query.where where
                | None -> qry
              in
              qry
              |> Request.make_zero_or_one
              |> Petrol.find_opt db
              |> Lwt_result.map (Option.map ~f:decode)
          end]
        (* Location.raise_errorf ~loc "not yet implemented" *)
    | _ -> assert false)

let args =
  let open Deriving.Args in
  empty +> arg "name" (estring __) +> arg "constraints" __

let impl_generator = Deriving.Generator.V2.make args generate_impl
let combust = Deriving.add "combust" ~str_type_decl:impl_generator
