# shellcheck shell=sh
# Dot-source after bin/banner.config.sh: replaces the positional params with
# the chafa flags built from CHAFA_*. Shared by banner.sh and the dev helpers
# (preview-bisio.sh, tune-bisio.sh) so they all render with the same preset.
set --
[ -n "${CHAFA_SYMBOLS:-}" ]           && set -- "$@" --symbols "$CHAFA_SYMBOLS"
[ -n "${CHAFA_COLORS:-}" ]            && set -- "$@" --colors "$CHAFA_COLORS"
[ -n "${CHAFA_FORMAT:-}" ]            && set -- "$@" --format "$CHAFA_FORMAT"
[ "${CHAFA_FG_ONLY:-}" = "yes" ]      && set -- "$@" --fg-only
[ -n "${CHAFA_DITHER:-}" ]            && set -- "$@" --dither "$CHAFA_DITHER"
[ -n "${CHAFA_DITHER_GRAIN:-}" ]      && set -- "$@" --dither-grain "$CHAFA_DITHER_GRAIN"
[ -n "${CHAFA_DITHER_INTENSITY:-}" ]  && set -- "$@" --dither-intensity "$CHAFA_DITHER_INTENSITY"
[ "${CHAFA_INVERT:-}" = "yes" ]       && set -- "$@" --invert
[ -n "${CHAFA_THRESHOLD:-}" ]         && set -- "$@" --threshold "$CHAFA_THRESHOLD"
[ -n "${CHAFA_FONT_RATIO:-}" ]        && set -- "$@" --font-ratio "$CHAFA_FONT_RATIO"
# CHAFA_EXTRA: deliberate word-split via eval - free-form flag string
[ -n "${CHAFA_EXTRA:-}" ] && eval "set -- \"\$@\" $CHAFA_EXTRA"
