{lib, ...}: let
  version = "2.2.6";

  mkAppimage = pkgs:
    pkgs.appimageTools.wrapType2 rec {
      pname = "android-mic";
      inherit version;

      src = pkgs.fetchurl {
        url = "https://github.com/teamclouday/AndroidMic/releases/download/${version}/android-mic_${version}_x86_64.AppImage";
        hash = "sha256-5xMc/xv+MXjFllK7S68RgOeej9KBo8I/qTtb2P36EF0=";
      };

      extraInstallCommands = let
        contents = pkgs.appimageTools.extract {inherit pname version src;};
      in ''
        install -m 444 -D ${contents}/usr/share/applications/android-mic.desktop \
          $out/share/applications/android-mic.desktop
        substituteInPlace $out/share/applications/android-mic.desktop \
          --replace-fail 'Exec=android-mic ' 'Exec=android-mic'
        cp -r ${contents}/usr/share/icons $out/share/
      '';

      meta = {
        description = "Use an Android phone as a microphone for a PC";
        homepage = "https://github.com/teamclouday/AndroidMic";
        license = lib.licenses.gpl3Only;
        mainProgram = "android-mic";
        platforms = ["x86_64-linux"];
      };
    };
in {
  flake.features.android-mic.projections.nixos.payload = {
    lib,
    ...
  }: {
    security.rtkit.enable = lib.mkDefault true;
    services.pipewire = {
      enable = lib.mkDefault true;
      alsa.enable = lib.mkDefault true;
      pulse.enable = lib.mkDefault true;
      wireplumber.enable = lib.mkDefault true;

      extraConfig.pipewire-pulse."90-android-mic-virtual-mic" = {
        "pulse.cmd" = [
          {
            cmd = "load-module";
            args = "module-null-sink sink_name=android_mic sink_properties=device.description=AndroidMic_Output";
            flags = ["nofail"];
          }
          {
            cmd = "load-module";
            args = "module-remap-source master=android_mic.monitor source_name=android_mic_source source_properties=device.description=AndroidMic_Microphone";
            flags = ["nofail"];
          }
        ];
      };
    };

    services.udev.extraRules = ''
      # Android Open Accessory mode used by AndroidMic USB Serial.
      SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", ATTR{idProduct}=="2d0[0-5]", TAG+="uaccess"
    '';
  };

  flake.features.android-mic.projections.homeManager.payload = {
    lib,
    pkgs,
    ...
  }: {
    home.packages = lib.optionals pkgs.stdenv.hostPlatform.isx86_64 [
      (mkAppimage pkgs)
      pkgs.android-tools
    ];
  };
}
