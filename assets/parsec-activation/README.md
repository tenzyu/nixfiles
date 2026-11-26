# Review Parsec activation and settings

The two Home Manager hooks run after `writeBoundary` and use the native
`run` function. A dry run prints the actions. It does not open Parsec files or create a directory. `local.parsecActivation` supplies the two leaf names,
the controller ID, and the mode. The `parsec` feature also installs
`parsec-activation-review` alongside `parsec-xwayland`.

## Why these settings exist

See [why the Parsec settings exist](design.md).

## Compatibility review gate

Check the [seed conditions](reference.md#compatibility-review-gate) before changing saved files.

## Review an existing installation

1. Run `parsec-activation-review` as the affected user. It prints the four
   declared values with their status in the observed saved config, any pending
   assignments for those keys in `config.txt` alongside `config.json`, and the
   count and match for controller ID `06cb,83d7`. If a mapping is absent or different, the command prints the desired row. Other settings and actual file
   values stay out of the output.
2. Review client settings in Parsec. For gamepad behavior, select the affected
   controller in the Gamepad section of Settings and check raw input and per-button
   mappings. Before editing a file, make and verify an independent backup.
   Establish control of every writer. Reconcile only the desired
   keys or the declared controller row, and preserve every unrelated mapping
   row in its original order. A closed window alone cannot establish control
   of all writers. [Parsec gamepad setup](https://support.parsec.app/hc/en-us/articles/32381705301908-Setup-Gamepad)
3. For an advanced config edit, use Parsec's documented restart procedure
   and review again after it saves. Verify client settings and controller
   behavior separately in the app. [Parsec configuration and migration](https://support.parsec.app/hc/en-us/articles/32381346632596-Accessing-Your-Advanced-Settings)

An older Home Manager store link can still block Parsec from writing or
clearing the linked file. Activation preserves it. Reconcile the link
separately with a verified backup and all writers stopped before expecting
Parsec to write the file.

The command exits `0` when the compared settings, mapping and applicable
modes match. It exits `1` for differences, missing required data, ambiguous
legacy input or an unsafe entry, and `74` for I/O errors. JSON comparison uses
the documented `{"value": …}` objects with numeric values for these four keys.
The command compares saved file contents and modes. Runtime precedence, negotiated
codec, effective decoding and controller behavior require app observations.
After `OutcomeUnknown`, run the review before retrying. Retrying preserves
any final entry that is already visible.

## Publication boundary

Before you edit or retry a seed, read the [publication and recovery rules](reference.md#publication-boundary).

## Fixture evidence

Run the [Parsec verification procedure](verify.md) to test the hooks and review command.
