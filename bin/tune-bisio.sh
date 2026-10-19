#!/bin/sh
# shellcheck shell=sh
# Tune a bisio PNG for terminal rendering. Interactive mode re-renders the
# variant live through chafa (banner preset) while you nudge brightness,
# saturation, contrast, gamma, sharpening and zoom/pan; saving writes one row
# to assets/bisio/recipes.tsv and regenerates the asset from its untouched
# original in assets/bisio/src/, so edits never compound.
#
# Requires chafa and ImageMagick v7 (`magick`). Dev helper only; the plugin
# never calls this. The banner cache is keyed by PNG sha, so a tuned asset
# re-renders on the next launch without any cache flush.
# Usage: bin/tune-bisio.sh NN-slug.png           interactive tuner
#        bin/tune-bisio.sh --apply [NN-slug.png]  regenerate assets from recipes
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
bisio_dir="$repo_dir/assets/bisio"
src_dir="$bisio_dir/src"
recipes="$bisio_dir/recipes.tsv"
neutral="100 100 0 100 0 100 0 0"

for _t in chafa magick; do
  command -v "$_t" >/dev/null 2>&1 || { echo "tune-bisio: $_t required" >&2; exit 1; }
done

clamp() { # value lo hi
  if [ "$1" -lt "$2" ]; then echo "$2"; elif [ "$1" -gt "$3" ]; then echo "$3"; else echo "$1"; fi
}

# apply_recipe SRC OUT BRIGHT SAT CONTRAST GAMMAx100 SHARPENx10 ZOOM PANX PANY
# Zoom crops to 100/zoom of the source around its center, shifted by pan
# (percent of the source size), then the asset contracts are re-applied.
apply_recipe() {
  _src=$1 _out=$2 _b=$3 _s=$4 _c=$5 _g=$6 _n=$7 _z=$8 _px=$9 _py=${10}
  _dims=$(magick identify -format '%w %h' "$_src")
  _w=${_dims% *} _h=${_dims#* }
  _cw=$((_w * 100 / _z)) _ch=$((_h * 100 / _z))
  _x=$(clamp $(((_w - _cw) / 2 + _px * _w / 100)) 0 $((_w - _cw)))
  _y=$(clamp $(((_h - _ch) / 2 + _py * _h / 100)) 0 $((_h - _ch)))
  set -- "$_src" -crop "${_cw}x${_ch}+${_x}+${_y}" +repage -channel RGB \
    -modulate "$_b,$_s" -brightness-contrast "0x$_c" \
    -gamma "$(awk -v g="$_g" 'BEGIN { printf "%.2f", g / 100 }')"
  [ "$_n" -gt 0 ] && set -- "$@" -unsharp "0x$(awk -v n="$_n" 'BEGIN { printf "%.1f", n / 10 }')"
  magick "$@" +channel "$_out"
  "$repo_dir/bin/trim-bisios.sh" "$_out" >/dev/null
}

# Recipe row for an asset name, minus the name ("" when untuned).
recipe_of() {
  [ -f "$recipes" ] || return 0
  awk -v f="$1" '$1 == f { $1 = ""; sub(/^ +/, ""); print; exit }' "$recipes"
}

# write_recipe NAME PARAMS...: replace NAME's row; a neutral recipe drops it.
write_recipe() {
  _name=$1
  shift
  _tmp="$recipes.tmp"
  if [ -f "$recipes" ]; then
    awk -v f="$_name" '$1 != f' "$recipes" > "$_tmp"
  else
    printf '# file\tbright\tsat\tcontrast\tgamma_x100\tsharpen_x10\tzoom\tpan_x\tpan_y\n' > "$_tmp"
  fi
  [ "$*" = "$neutral" ] || { printf '%s' "$_name"; printf '\t%s' "$@"; printf '\n'; } >> "$_tmp"
  mv "$_tmp" "$recipes"
}

if [ "${1:-}" = "--apply" ]; then
  shift
  [ -f "$recipes" ] || { echo "tune-bisio: no recipes" >&2; exit 0; }
  [ "$#" -gt 0 ] || set -- $(awk '!/^#/ { print $1 }' "$recipes")
  for name in "$@"; do
    name=$(basename "$name")
    r=$(recipe_of "$name")
    [ -n "$r" ] || { echo "skip: $name (no recipe)" >&2; continue; }
    # shellcheck disable=SC2086 # recipe params are a deliberate word-split list
    apply_recipe "$src_dir/$name" "$bisio_dir/$name" $r
    echo "apply: $name ($r)"
  done
  exit 0
fi

[ "$#" -eq 1 ] || { echo "usage: bin/tune-bisio.sh NN-slug.png | --apply [NN-slug.png...]" >&2; exit 2; }
name=$(basename "$1")
asset="$bisio_dir/$name"
[ -f "$asset" ] || { echo "tune-bisio: $asset not found" >&2; exit 1; }

# shellcheck source=bin/banner.config.sh
. "$repo_dir/bin/banner.config.sh"
# shellcheck source=bin/_chafa_args.sh
. "$repo_dir/bin/_chafa_args.sh"
chafa_args=$*

tmp=$(mktemp -d)
saved_tty=$(stty -g </dev/tty)
trap 'stty "$saved_tty" </dev/tty; printf "\033[?25h"; rm -rf "$tmp"' EXIT
trap 'exit 130' INT TERM

# Untuned variants have no original yet: the current asset is the original.
orig="$src_dir/$name"
[ -f "$orig" ] || { orig="$tmp/orig.png"; cp "$asset" "$orig"; }
r=$(recipe_of "$name")
# shellcheck disable=SC2086 # recipe params are a deliberate word-split list
set -- ${r:-$neutral}
b=$1 s=$2 c=$3 g=$4 n=$5 z=$6 px=$7 py=$8
show_orig=0 msg=""

stty -icanon -echo min 1 time 0 </dev/tty
printf '\033[?25l'
while :; do
  if [ "$show_orig" -eq 1 ]; then
    view=$orig
  else
    view="$tmp/cur.png"
    apply_recipe "$orig" "$view" "$b" "$s" "$c" "$g" "$n" "$z" "$px" "$py"
  fi
  size=$(stty size </dev/tty)
  rows=${size% *} cols=${size#* }
  [ "$rows" -gt 8 ] && [ "$cols" -gt 0 ] || { rows=24 cols=80; }
  # Side panel right of the image when there is room, else below it.
  if [ "$cols" -ge 70 ]; then pcol=$((cols - 28)) iw=$((cols - 30)) ih=$((rows - 1)); else pcol=1 iw=$cols ih=$((rows - 16)); fi
  printf '\033[H\033[2J'
  # shellcheck disable=SC2086 # chafa_args is a deliberate word-split flag list
  chafa --size "${iw}x${ih}" $chafa_args "$view"
  [ "$pcol" -eq 1 ] && prow=$((ih + 2)) || prow=2
  pl() { printf '\033[%d;%dH%b' "$prow" "$pcol" "$1"; prow=$((prow + 1)); }
  # pv KEYS LABEL VALUE NEUTRAL: one param row, value in yellow once tuned.
  pv() {
    [ "$3" = "$4" ] && _v=$3 || _v="\033[1;33m$3\033[0m"
    pl "$(printf '\033[1m%-5s\033[0m %-9s %b' "$1" "$2" "$_v")"
  }
  pl "\033[1m$name\033[0m"
  if [ "$show_orig" -eq 1 ]; then pl "\033[7m ORIGINAL \033[0m  (o to go back)"; else pl ""; fi
  pl ""
  pv "b B" bright "$b" 100
  pv "s S" sat "$s" 100
  pv "c C" contrast "$c" 0
  pv "g G" gamma "$(awk -v g="$g" 'BEGIN { printf "%.2f", g / 100 }')" 1.00
  pv "n N" sharpen "$(awk -v n="$n" 'BEGIN { printf "%.1f", n / 10 }')" 0.0
  pv "z Z" zoom "$z%" 100%
  pv "hjkl" pan "$px,$py" 0,0
  pl ""
  pl "\033[2mlower = less, UPPER = more\033[0m"
  pl ""
  pl "\033[1mo\033[0m original   \033[1mr\033[0m reset"
  pl "\033[1mw\033[0m save       \033[1mq\033[0m quit"
  pl ""
  [ -n "$msg" ] && pl "\033[1;32m$msg\033[0m"
  msg=""
  key=$(dd bs=1 count=1 2>/dev/null </dev/tty)
  case $key in
    b) b=$(clamp $((b - 5)) 0 200) ;;   B) b=$(clamp $((b + 5)) 0 200) ;;
    s) s=$(clamp $((s - 5)) 0 200) ;;   S) s=$(clamp $((s + 5)) 0 200) ;;
    c) c=$(clamp $((c - 5)) -100 100) ;; C) c=$(clamp $((c + 5)) -100 100) ;;
    g) g=$(clamp $((g - 5)) 10 300) ;;  G) g=$(clamp $((g + 5)) 10 300) ;;
    n) n=$(clamp $((n - 5)) 0 50) ;;    N) n=$(clamp $((n + 5)) 0 50) ;;
    z) z=$(clamp $((z - 10)) 100 400) ;; Z) z=$(clamp $((z + 10)) 100 400) ;;
    h) px=$(clamp $((px - 2)) -50 50) ;; l) px=$(clamp $((px + 2)) -50 50) ;;
    k) py=$(clamp $((py - 2)) -50 50) ;; j) py=$(clamp $((py + 2)) -50 50) ;;
    o) show_orig=$((1 - show_orig)) ;;
    r) set -- $neutral; b=$1 s=$2 c=$3 g=$4 n=$5 z=$6 px=$7 py=$8 ;;
    w)
      write_recipe "$name" "$b" "$s" "$c" "$g" "$n" "$z" "$px" "$py"
      if [ "$b $s $c $g $n $z $px $py" = "$neutral" ]; then
        # Neutral = untuned: restore the original and drop it from src/.
        [ -f "$src_dir/$name" ] && mv "$src_dir/$name" "$asset"
        orig="$tmp/orig.png"; cp "$asset" "$orig"
        msg="saved (untuned, original restored)"
      else
        mkdir -p "$src_dir"
        [ "$orig" = "$src_dir/$name" ] || { cp "$orig" "$src_dir/$name"; orig="$src_dir/$name"; }
        apply_recipe "$orig" "$asset" "$b" "$s" "$c" "$g" "$n" "$z" "$px" "$py"
        msg="saved"
      fi ;;
    q) printf '\n'; exit 0 ;;
  esac
done
