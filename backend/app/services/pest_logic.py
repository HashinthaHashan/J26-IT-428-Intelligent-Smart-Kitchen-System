from __future__ import annotations

from kitchenguard_schemas import PestEvent


def is_pest_warning(event: PestEvent) -> bool:
    return event.yolo_pred in {"rat", "cockroach"} and (event.yolo_conf or 0.0) >= 0.6
