"""Bisiodex odds: tier shares, per-variant pull %, expected pulls to complete the dex.

Usage: python3 -I dex_odds.py <banner.config.sh> [SLUG=WEIGHT ...]
Extra SLUG=WEIGHT args add or override weights, to preview a proposal before editing the config.
Tier thresholds mirror _bisio_hof_tiles_frag in bin/_counter.sh.
"""
import math, re, sys

TIERS = [("Legendary", 5), ("Rare", 20), ("Uncommon", 30), ("Common", math.inf)]


def tier(w):
    return next(name for name, cap in TIERS if w <= cap)


def expected_completion(ps):
    # Coupon collector with unequal probabilities (Poissonised):
    # E[T] = integral_0^inf 1 - prod(1 - exp(-p_i t)) dt
    total, dt, t = 0.0, 0.05, 0.0
    while True:
        miss = 1 - math.prod(1 - math.exp(-p * t) for p in ps)
        if miss < 1e-9 and t > 0:
            return total
        total += miss * dt
        t += dt


weights = {
    m.group(1).lower(): int(m.group(2))
    for m in re.finditer(r"^BISIO_WEIGHT_([A-Z]+)=(\d+)", open(sys.argv[1]).read(), re.M)
}
for arg in sys.argv[2:]:
    slug, w = arg.split("=")
    weights[slug.lower()] = int(w)

total = sum(weights.values())
print(f"{len(weights)} variants, total weight {total}\n")
for name, _ in TIERS:
    members = [s for s, w in weights.items() if tier(w) == name]
    share = sum(weights[s] for s in members) / total
    print(f"{name:<10} {len(members):>2} variants  {share:6.1%}  ({', '.join(members)})")
print()
for s, w in sorted(weights.items(), key=lambda kv: -kv[1]):
    print(f"  {s:<16} w={w:<3} {w / total:6.2%}  {tier(w)}")
print(f"\nExpected pulls to complete the dex: {expected_completion([w / total for w in weights.values()]):.0f}")
