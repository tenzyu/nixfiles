{lib}: let
  validLabel = s: builtins.isString s && s != "";
  validStep = s:
    builtins.isAttrs s && s ? name && validLabel s.name
    && s ? run && builtins.isFunction s.run;
  checkedSteps = label: steps:
    assert lib.assertMsg (validLabel label)
      "namedPipeline: label must be a nonempty string";
    assert lib.assertMsg (builtins.isList steps)
      "namedPipeline '${label}': expected a list of stages";
    assert lib.assertMsg (builtins.all validStep steps)
      "namedPipeline '${label}': each stage needs a name and run function";
    let names = map (step: step.name) steps;
    in assert lib.assertMsg (builtins.length (lib.unique names) == builtins.length names)
      "namedPipeline '${label}': duplicate stage names";
    steps;
in {
  # Names and stage order remain inspectable without running the pipeline.
  # Delegates value semantics to native lib.pipe; no custom merge logic.
  namedPipeline = {label, steps}: let
    validated = checkedSteps label steps;
  in {
    inherit label;
    stageNames = map (step: step.name) validated;
    run = input:
      lib.pipe input (map (step: value:
        builtins.addErrorContext
          "in named pipeline '${label}', stage '${step.name}'"
          (step.run value)
      ) validated);
  };
  # A collision is detected by key membership, not by forcing attribute
  # values. Unlike unionOfDisjoint, failure is immediate when the merged
  # attrset is demanded and identifies both contributing layers.
  namedDisjoint = {label, layers}: let
    validLayer = layer:
      builtins.isAttrs layer
      && layer ? name && validLabel layer.name
      && layer ? attrs && builtins.isAttrs layer.attrs;
    checked =
      assert lib.assertMsg (validLabel label)
        "namedDisjoint: label must be a nonempty string";
      assert lib.assertMsg (builtins.isList layers)
        "namedDisjoint '${label}': layers must be a list";
      assert lib.assertMsg (builtins.all validLayer layers)
        "namedDisjoint '${label}': each layer requires a name and an attrset 'attrs'";
      let names = map (layer: layer.name) layers;
      in assert lib.assertMsg (builtins.length (lib.unique names) == builtins.length names)
        "namedDisjoint '${label}': duplicate layer names";
      layers;
    result = lib.foldl'
      (state: layer: let
        keys = builtins.attrNames layer.attrs;
        collisions = lib.filter (key: builtins.hasAttr key state.owners) keys;
        details = lib.concatMapStringsSep ", "
          (key: "${key} (${state.owners.${key}} versus ${layer.name})")
          collisions;
      in
        assert lib.assertMsg (collisions == [])
          "namedDisjoint '${label}': collision: ${details}";
        {
          # Only shallow *plain data* is composed. Never merge mkIf,
          # mkMerge or other NixOS option-definition sentinels this way.
          merged = state.merged // layer.attrs;
          owners = state.owners // lib.genAttrs keys (_: layer.name);
        })
      {merged = {}; owners = {};}
      checked;
  in {
    inherit label;
    layerNames = map (layer: layer.name) checked;
    inherit (result) merged owners;
  };

  # Unlike lib.overrideExisting, rejects typoed keys rather than silently
  # dropping them. Uses the native shallow override operator intentionally.
  overrideExisting = {label, base, replacements}:
    assert lib.assertMsg (validLabel label)
      "overrideExisting: label must be a nonempty string";
    assert lib.assertMsg (builtins.isAttrs base && builtins.isAttrs replacements)
      "overrideExisting '${label}': base and replacements must be attrsets";
    let
      unknown = lib.filter
        (key: !(builtins.hasAttr key base))
        (builtins.attrNames replacements);
    in
      assert lib.assertMsg (unknown == [])
        "overrideExisting '${label}': cannot replace absent keys: ${lib.concatStringsSep ", " unknown}";
      base // replacements;
}
