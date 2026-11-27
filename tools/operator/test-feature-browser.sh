# Offline command boundary: real Git index, inert evaluation and selectors.
set -euo pipefail
browser=$1
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
mkdir -p "$scratch/repo/modules" "$scratch/bin"
cd "$scratch/repo"
git init -q
printf 'fixture\n' > modules/valid.nix
printf 'outside\n' > "$scratch/external"
ln -s "$scratch/external" modules/external.nix
printf 'untracked\n' > modules/untracked.nix
git add modules/valid.nix modules/external.nix
export PATH="$scratch/bin:$PATH" FIXTURE="$scratch"
stub() {
  printf '#!%s\n%s\n' "$(command -v bash)" "$2" > "$scratch/bin/$1"
  chmod +x "$scratch/bin/$1"
}
stub nix 'case "$*" in
  *operator.features) printf "%s\n" '"'"'[{"configuration":"host","scope":"system","feature":"fixture","moduleClass":"nixos","enabled":true,"sources":{"selection":["modules/valid.nix","modules/external.nix","modules/untracked.nix"]}}]'"'"' ;;
  *) printf "%s\n" '"'"'{"locations":[],"files":[]}'"'"' ;;
esac'
stub fzf 'case "$*" in
  *Source*) cat > "$FIXTURE/candidates"; head -n 1 "$FIXTURE/candidates" ;;
  *) head -n 1 ;;
esac'
stub rg 'exit 1'
stub fixture-editor 'printf "%s\n" "$@" > "$FIXTURE/editor"'
export NIXFILES_EDITOR=fixture-editor
bash -euo pipefail "$browser"
printf 'selection\tmodules/valid.nix\n' > "$scratch/expected"
cmp "$scratch/expected" "$scratch/candidates"
printf '+1\n--\nmodules/valid.nix\n' > "$scratch/expected-editor"
cmp "$scratch/expected-editor" "$scratch/editor"
