from __future__ import annotations

from kitchenguard_schemas import ChildEvent, ChildRiskPrediction

from app.services.inference import get_registry


def predict(event: ChildEvent) -> ChildRiskPrediction:
    return get_registry().predict_child(event)
