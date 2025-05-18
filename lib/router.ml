open Dream

let router () =
  Dream.router
    [
      scope "/"
      [
        Dream.logger;
        Dream.livereload;
        Dream.flash;
        Dream.cookie_sessions;
        Middleware.mailer_middleware Mailer.dev_mailer;
      ]
      [ 
        get "/**" @@ static "lib/webapp/";
        get "/assets/**" @@ static "assets";
      ];
    ]
