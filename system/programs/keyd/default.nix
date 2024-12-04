{pkgs, ...}: let
  hhkb = "04fe:0021";
in {
  environment.systemPackages = [
    pkgs.keyd
  ];
  services.keyd = {
    enable = true;

    keyboards.global = {
      ids = [
        "*"
        "-${hhkb}"
      ];
      settings = {
        main = {
          backspace = "rightalt";
          rightalt = "space";
          space = "backspace";
        };
      };
    };

    keyboards.hhkb = {
      ids = ["${hhkb}"];
      settings = {
        main = {
          esc = "noop";
          "1" = "noop";
          "2" = "noop";
          "3" = "noop";
          "4" = "noop";
          "5" = "noop";
          "6" = "noop";
          "7" = "noop";
          "8" = "noop";
          "9" = "noop";
          "0" = "noop";
          "-" = "noop";
          "equal" = "noop";
          "backslash" = "noop";
          "`" = "noop";

          tab = "q";
          q = "w";
          w = "e";
          e = "r";
          r = "t";
          t = "noop";
          y = "noop";
          u = "noop";
          i = "y";
          o = "u";
          p = "i";
          "[" = "o";
          "]" = "p";
          backspace = "noop";

          leftcontrol = "a";
          a = "lettermod(meta, s, 120, 180)";
          s = "lettermod(alt, d, 120, 180)";
          d = "lettermod(shift, f, 120, 180)";
          f = "g";
          g = "noop";
          h = "noop";
          j = "noop";
          k = "h";
          l = "lettermod(shift, j, 120, 180)";
          ";" = "lettermod(altgr, k, 120, 180)";
          "'" = "lettermod(meta, l, 120, 180)";
          enter = "noop";

          leftshift = "z";
          z = "x";
          x = "c";
          c = "v";
          v = "b";
          b = "noop";
          n = "noop";
          m = "noop";
          "," = "n";
          "." = "m";
          "/" = ",";
          rightshift = ".";
          #fn

          leftmeta = "noop";
          leftalt = "overload(control, enter)";
          space = "lettermod(l1, backspace, 120, 180)";
          rightalt = "lettermod(l2, space, 120, 180)";
          rightmeta = "overload(control, tab)";
        };

        l1 = {
          tab = "noop";
          q = "1";
          w = "2";
          e = "3";
          r = "~";
          i = "^";
          o = "<";
          p = "=";
          "[" = ">";
          "]" = "noop";

          leftcontrol = "0";
          a = "4";
          s = "5";
          d = "6";
          f = "$";
          k = "+";
          l = "-";
          ";" = "*";
          "'" = "/";
          enter = "%";

          leftshift = "noop";
          z = "7";
          x = "8";
          c = "9";
          v = "_";
          "," = ":";
          "." = ";";
          "/" = "!";
          rightshift = "?";

          rightalt = "lettermod(l3, space, 120, 180)";
        };

        l2 = {
          tab = "noop";
          q = "{";
          w = "\"";
          e = "}";
          r = "#";
          i = "volumeup";
          o = "esc";
          p = "up";
          "[" = "capslock";
          "]" = "noop";

          leftcontrol = "@";
          a = "(";
          s = "'";
          d = ")";
          f = "&";
          k = "volumedown";
          l = "left";
          ";" = "down";
          "'" = "right";
          enter = "brightnessup";

          leftshift = "backslash";
          z = "[";
          x = "`";
          c = "]";
          v = "|";
          "," = "prev";
          "." = "play";
          "/" = "next";
          rightshift = "brightnessdown";

          space = "lettermod(l3, backspace, 120, 180)";
        };

        l3 = {
          tab = "f10";
          q = "f1";
          w = "f2";
          e = "f3";
          r = "noop";
          i = "noop";
          o = "insert";
          p = "home";
          "[" = "pageup";

          leftcontrol = "f11";
          a = "f4";
          s = "f5";
          d = "f6";
          f = "noop";
          k = "noop";
          l = "delete";
          ";" = "end";
          "'" = "pagedown";
          enter = "menu";

          leftshift = "f12";
          z = "f7";
          x = "f8";
          c = "f9";
          v = "noop";
          "," = "noop";
          "." = "noop";
          "/" = "noop";
          rightshift = "noop";
        };
      };
    };
  };
}
