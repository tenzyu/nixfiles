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
}
