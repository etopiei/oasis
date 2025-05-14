open Base

let () =
  if Poly.( = ) Oasis_conf.env Oasis_conf.Dev then
    Dream.initialize_log ~level:`Debug ();

  Dream.run ~interface:Oasis_conf.host ~port:Oasis_conf.port ~adjust_terminal:false
    ~error_handler:Dream.debug_error_handler
  @@ Dream.set_secret Oasis_conf.secret_key
  @@ Dream.sql_pool ~size:Oasis_conf.sql_pool_size Oasis_conf.sql_url
  @@ Oasis.Router.router ()
