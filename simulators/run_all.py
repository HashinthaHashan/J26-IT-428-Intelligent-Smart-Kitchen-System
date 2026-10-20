from __future__ import annotations

import asyncio

from common import parser
from child_sim import run as child_run
from lpg_sim import run as lpg_run
from pantry_sim import run as pantry_run
from pest_sim import run as pest_run


async def main() -> None:
    ap = parser("Run all KitchenGuard simulators")
    ap.add_argument(
        "--skip",
        nargs="*",
        default=[],
        choices=["lpg", "pantry", "pest", "child"],
        help="simulators to leave out, e.g. --skip lpg pantry once that real hardware is connected",
    )
    args = ap.parse_args()
    runners = {"lpg": lpg_run, "pantry": pantry_run, "pest": pest_run, "child": child_run}
    await asyncio.gather(
        *(run(args.host, args.port, args.speed) for name, run in runners.items() if name not in args.skip)
    )


if __name__ == "__main__":
    asyncio.run(main())
