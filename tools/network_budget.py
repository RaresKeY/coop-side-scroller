#!/usr/bin/env python3
"""Plan shared Realtime egress from provider-metered rates, not game payloads.

This calculator neither reads account usage nor enforces a provider spending cap.
Recheck Cloudflare's current terms before using these assumptions operationally.
"""
import argparse
import json
import math


def estimate(billed_kbps, match_hours, allowance_gb=1000, other_gb=0, reserve_gb=200):
    values = (billed_kbps, match_hours, allowance_gb, other_gb, reserve_gb)
    if any(not math.isfinite(v) or v < 0 for v in values) or billed_kbps == 0:
        raise ValueError('Rates must be finite/nonnegative; billed_kbps must be positive')
    usable = max(0, allowance_gb - other_gb - reserve_gb)
    gb_per_hour = billed_kbps * .0036
    usage = gb_per_hour * match_hours
    if not math.isfinite(gb_per_hour) or gb_per_hour <= 0:
        raise ValueError('Rate exceeds the supported numeric range')
    hours = usable / gb_per_hour
    if not math.isfinite(usage) or not math.isfinite(hours) or (match_hours > 0 and usage == 0):
        raise ValueError('Estimate exceeds the supported numeric range')
    return {'total_billed_kB_per_second_both_players': billed_kbps,
            'two_player_match_hours': match_hours,
            'gameplay_egress_gb': round(usage, 6), 'other_realtime_egress_gb': other_gb,
            'shared_allowance_gb': allowance_gb, 'planning_reserve_gb': reserve_gb,
            'match_hours_within_planning_budget': round(hours, 2),
            'fits_planning_budget': usage <= usable,
            'enforces_spending_cap': False,
            'excludes': 'Workers/DO requests, duration and storage; account usage is not queried'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--billed-kbytes-per-second', dest='billed_kbps', type=float, required=True,
                        help='Decimal kB/s TOTAL Cloudflare-to-client egress, both players, including overhead')
    parser.add_argument('--match-hours', type=float, default=1000)
    parser.add_argument('--allowance-gb', type=float, default=1000)
    parser.add_argument('--other-gb', type=float, default=0)
    parser.add_argument('--reserve-gb', type=float, default=200)
    args = parser.parse_args()
    try:
        result = estimate(args.billed_kbps, args.match_hours, args.allowance_gb,
                          args.other_gb, args.reserve_gb)
    except ValueError as error:
        parser.error(str(error))
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0 if result['fits_planning_budget'] else 2


if __name__ == '__main__':
    raise SystemExit(main())
