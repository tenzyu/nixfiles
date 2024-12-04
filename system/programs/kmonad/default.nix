{pkgs, ...}: let
  hhkbtarget = "hhkb";
in {
  services.kmonad = {
    enable = true;
    keyboards = {
      default = {
        device = "/dev/input/event0";
        config = builtins.readFile ./default.kbd;
      };
      ${hhkbtarget} = {
        device = "/dev/input/${hhkbtarget}";
        config = builtins.readFile ./${hhkbtarget}.kbd;
      };
    };
  };

  # TODO: bind input/* to persistancy path
  services.udev.extraRules = ''
    SUBSYSTEM=="bluetooth", ATTRS{name}=="HHKB-Hybrid_1 Keyboard", SYMLINK+="input/${hhkbtarget}"
    SUBSYSTEM=="bluetooth", ATTRS{address}=="14:18:c3:be:6d:a0", SYMLINK+="input/${hhkbtarget}"
    SUBSYSTEM=="bluetooth", KERNEL=="hci0:*", ATTRS{name}=="HHKB-Hybrid_1 Keyboard", SYMLINK+="input/${hhkbtarget}"
    SUBSYSTEM=="bluetooth", KERNEL=="hci0:*", ATTRS{address}=="14:18:c3:be:6d:a0", SYMLINK+="input/${hhkbtarget}"
    SUBSYSTEM=="bluetooth", KERNEL=="uhid", ATTRS{name}=="HHKB-Hybrid_1 Keyboard", SYMLINK+="input/${hhkbtarget}"
    SUBSYSTEM=="bluetooth", KERNEL=="uhid", ATTRS{address}=="14:18:c3:be:6d:a0", SYMLINK+="input/${hhkbtarget}"
    ACTION=="add", SUBSYSTEM=="bluetooth", KERNEL=="hci0", ATTRS{idVendor}=="04fe", ATTRS{idProduct}=="0021", SYMLINK+="input/${hhkbtarget}"
    ATTRS{idVendor}=="04fe", ATTRS{idProduct}=="0021", SYMLINK+="${hhkbtarget}"
  '';
}
