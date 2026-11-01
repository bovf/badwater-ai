# Deliberately credential-free managed subset; writable user auth stays opaque.
{lib}: server: let
  http = server ? url;
  type =
    server.type or (
      if http
      then "http"
      else "stdio"
    );
  url = server.url or null;
  # Match the merger's conservative URL grammar, including exact fixture loopbacks.
  parsed =
    if builtins.isString url
    then builtins.match "(https?)://([A-Za-z0-9][A-Za-z0-9.-]*|[[]::1[]])(:([1-9][0-9]{0,4}))?(/[^[:space:]?#@]*)?" url
    else null;
  validUrl =
    parsed
    != null
    && !(lib.hasInfix "\\" url)
    && (builtins.elemAt parsed 0 == "https" || builtins.elem (builtins.elemAt parsed 1) ["localhost" "127.0.0.1" "[::1]"])
    && (builtins.elemAt parsed 3 == null || lib.toInt (builtins.elemAt parsed 3) <= 65535);
  absent = names: lib.all (name: !(builtins.hasAttr name server)) names;
in
  builtins.elem (server.exposure or "deferred") ["codemode" "deferred" "direct" "hidden"]
  && (
    if http
    then
      builtins.elem type ["http" "streamable-http"]
      && validUrl
      && absent ["command" "args" "env" "cwd" "headers" "auth" "oauth"]
    else
      type
      == "stdio"
      && builtins.isString (server.command or null)
      && lib.hasPrefix "/" server.command
      && builtins.isList (server.args or [])
      && lib.all builtins.isString (server.args or [])
      && absent ["headers" "auth" "oauth"]
  )
