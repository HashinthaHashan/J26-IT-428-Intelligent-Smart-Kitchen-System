from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

import joblib

from kitchenguard_schemas import (
    ChildEvent,
    ChildRiskPrediction,
    LpgFeatures,
    LpgPrediction,
    PantryPrediction,
    PantryTelemetry,
)

from app.services.lpg_features import FEATURE_ORDER
from app.services.pantry_rules import rule_prediction

log = logging.getLogger(__name__)


class InferenceRegistry:
    def __init__(self, models_dir: Path) -> None:
        self.models_dir = models_dir
        self.lpg: dict[str, Any] | None = None
        self.pantry: dict[str, Any] | None = None

    def load(self) -> None:
        self.lpg = self._load_optional("lpg_rf_backend.joblib")
        self.pantry = self._load_optional("pantry_models_backend.joblib")

    def _load_optional(self, name: str) -> dict[str, Any] | None:
        path = self.models_dir / name
        try:
            return joblib.load(path)
        except FileNotFoundError:
            log.warning("ML model %s is missing; using documented rule fallback", path)
        except Exception as exc:  # noqa: BLE001
            log.warning("ML model %s failed to load (%s); using documented rule fallback", path, exc)
        return None

    def predict_lpg(self, features: LpgFeatures) -> LpgPrediction:
        if features.ppm_comp >= 700:
            return LpgPrediction(cloud_tier="Critical", source="safety_override", confidence=1.0)
        if self.lpg:
            values = [[getattr(features, name) for name in self.lpg.get("features", FEATURE_ORDER)]]
            model = self.lpg["model"]
            tier = str(model.predict(values)[0])
            confidence = None
            if hasattr(model, "predict_proba"):
                confidence = float(max(model.predict_proba(values)[0]))
            return LpgPrediction(cloud_tier=tier, source="model", confidence=confidence)
        ppm = features.ppm_comp
        tier = "Safe" if ppm < 150 else "Warning" if ppm < 300 else "Dangerous"
        return LpgPrediction(cloud_tier=tier, source="rule_fallback")

    def predict_pantry(self, telemetry: PantryTelemetry, features: dict[str, float]) -> PantryPrediction:
        if self.pantry:
            by_item = self.pantry.get("models", {}).get(telemetry.compartment)
            if by_item:
                values = [[features.get(name, getattr(telemetry, name, 0.0) or 0.0) for name in self.pantry.get("features", [])]]
                freshness = float(by_item["freshness"].predict(values)[0])
                rsl_h = float(by_item["rsl_h"].predict(values)[0])
                stages = self.pantry.get("stages", ["Fresh", "Ripe", "Deteriorating", "Spoiled"])
                stage = stages[int(by_item["stage"].predict(values)[0])]
                return PantryPrediction(freshness_score=freshness, rsl_h=rsl_h, stage=stage, source="model")
        # RULE PLACEHOLDER - replace with pantry_models_backend.joblib when available.
        return rule_prediction(telemetry)

    def predict_child(self, event: ChildEvent) -> ChildRiskPrediction:
        overlaps = any(_iou(person.box, hazard.box) > 0 for person in event.persons for hazard in event.hazards)
        return ChildRiskPrediction(
            risk_level="Warning" if overlaps else "Safe",
            danger_prob=0.5 if overlaps else 0.05,
            source="rule_fallback",
        )


registry: InferenceRegistry | None = None


def init_registry(models_dir: Path) -> InferenceRegistry:
    global registry
    registry = InferenceRegistry(models_dir)
    registry.load()
    return registry


def get_registry() -> InferenceRegistry:
    if registry is None:
        raise RuntimeError("Inference registry is not initialized")
    return registry


def _iou(a: list[float], b: list[float]) -> float:
    x0 = max(a[0], b[0])
    y0 = max(a[1], b[1])
    x1 = min(a[2], b[2])
    y1 = min(a[3], b[3])
    inter = max(0.0, x1 - x0) * max(0.0, y1 - y0)
    area_a = max(0.0, a[2] - a[0]) * max(0.0, a[3] - a[1])
    area_b = max(0.0, b[2] - b[0]) * max(0.0, b[3] - b[1])
    denom = area_a + area_b - inter
    return inter / denom if denom else 0.0
