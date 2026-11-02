{obs-studio}:
(obs-studio.override {browserSupport = false;}).overrideAttrs (old: {
  pname = "obs-studio-splitcast";
  patches = (old.patches or []) ++ [./obs-websocket-loopback.patch];
})
