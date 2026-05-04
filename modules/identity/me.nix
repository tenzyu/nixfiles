{lib, ...}: {
  options.me = {
    username = lib.mkOption {
      type = lib.types.str;
      default = "tenzyu";
    };

    fullName = lib.mkOption {
      type = lib.types.str;
      default = "tenzyu";
    };

    email = lib.mkOption {
      type = lib.types.str;
      default = "tenzyu.on@gmail.com";
    };

    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "Asia/Tokyo";
    };

    stateVersion = lib.mkOption {
      type = lib.types.str;
      default = "25.11";
    };
  };
}
