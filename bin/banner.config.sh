# shellcheck shell=sh
# claude-bisio chafa render config.
# Edit values, save, run `bisio`. Cache auto-invalidates on change.
# Empty string = flag omitted. Boolean flags: "yes" to enable, "" to skip.
#
# Override without editing this file: export the variable in ~/.zshrc before
# the plugin source line. The `: "${VAR=default}"` form below assigns only
# when the variable is unset, so an exported value (including an explicit
# empty string) wins over the default here.

: "${CHAFA_SYMBOLS=block}"            # block | sextant | ascii | half | vhalf | quad | braille | all | ...
: "${CHAFA_COLORS=256}"               # 2 | 8 | 16 | 240 | 256 | full | none
: "${CHAFA_FORMAT=symbols}"           # symbols | sixels | kitty | iterm | ...
: "${CHAFA_FG_ONLY=yes}"              # "yes" => --fg-only

: "${CHAFA_DITHER=ordered}"           # none | ordered | diffusion
: "${CHAFA_DITHER_GRAIN=}"            # 1 | 2 | 4 | 8 (or WxH)
: "${CHAFA_DITHER_INTENSITY=1.0}"     # float, e.g. 1.0 | 1.5

: "${CHAFA_INVERT=}"                  # "yes" => --invert
: "${CHAFA_THRESHOLD=}"               # float 0..1
: "${CHAFA_FONT_RATIO=}"              # WxH, e.g. 1x2

# Free-form escape hatch for flags not modelled above. Word-split intentional.
: "${CHAFA_EXTRA=--probe=off --polite=on}"

# Rows reserved at the bottom of the viewport for Claude's own welcome box
# and prompt. Increase if your terminal still overflows; decrease if you see
# excess blank space below the banner.
: "${CLAUDE_BISIO_RESERVE=4}"

# Hard cap on portrait height in rows. Stops the image from filling the whole
# viewport on tall terminals. Independent of CLAUDE_BISIO_RESERVE: reserve
# protects the bottom (welcome box), this caps the top (image growth).
: "${CLAUDE_BISIO_MAX_HEIGHT=35}"

# Figlet title color (CLAUDE-CODE + BISIO). Defaults to the Claude Code
# interface coral/orange (#D97757 — close to the Anthropic brand color).
: "${CLAUDE_BISIO_TITLE_COLOR=1;38;2;217;119;87}"

# Bisiodex status line. Rendered under the BISIO title every launch.
# Colors are SGR sequences without the leading ESC[ and trailing m.
# Default = lab(82.6847 12.7256 54.1563) → sRGB #FFC367 → 38;2;255;195;103.
# Requires a truecolor-capable terminal (most modern ones).
: "${CLAUDE_BISIO_DEX_COLOR=1;38;2;255;195;103}"        # bold amber
: "${CLAUDE_BISIO_DEX_NEW_COLOR=1;38;2;255;195;103}"    # new-variant glow: same hue; prefix carries the signal
: "${CLAUDE_BISIO_DEX_FILLED=▰}"                        # filled segment glyph
: "${CLAUDE_BISIO_DEX_EMPTY=▱}"                         # empty segment glyph

# Pull rates for each portrait in assets/bisio/. Plain assignment: these are
# repo-level constants, not env-overridable. Edit here to retune. Numbers are
# relative weights (any positive integers); they don't need to sum to 100 but 
# are easier to reason about if they do.
# Files in assets/bisio/ that aren't listed below are never picked.
BISIO_WEIGHT_MAIN=45
BISIO_WEIGHT_ALLUCINATO=45
BISIO_WEIGHT_PHOTO=45
BISIO_WEIGHT_HAIR=30
BISIO_WEIGHT_RAPPUT=20
BISIO_WEIGHT_NOTBISIO=20
BISIO_WEIGHT_PATE=5
BISIO_WEIGHT_DUXIO=5

