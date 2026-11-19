{
  coreutils,
  python3,
  replaceVars,
  util-linux,
}:
replaceVars ./operations.sh {
  inherit coreutils python3 util-linux;
  native = "${./native.py}";
}
