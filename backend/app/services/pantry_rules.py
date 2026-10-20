"""RULE PLACEHOLDER - replace with pantry_models_backend.joblib when available.

This is NOT a trained model. It exists so the Smart Pantry pipeline (sensor board,
backend, app) produces sensible freshness_score / rsl_h / stage values before the
real models are trained. InferenceRegistry.predict_pantry() uses the model when
`pantry_models_backend.joblib` loads and falls back to this rule otherwise, the same
pattern as the LPG model (see inference.py).

Anchors come from the project's literature numbers (stated by the project owner;
they are not stored anywhere else in the repo):

    ethanol  ~ 81 ppm  = ripe      ~ 108 ppm = decomposed
    ammonia  ~ 48 ppm  = ripe      ~ 111 ppm = decomposed

Rule, per gas sensor (piecewise linear):

    0 ppm      -> 100
    ripe ppm   ->  60   (SCORE_AT_RIPE)
    decomposed ->   0   (and stays 0 above it)

freshness_score = the WORSE of the two sensors. Shared-airspace note: the two
compartments (banana, potato) breathe the same air, so both get the same score until
camera features exist. rsl_h (remaining shelf life) is a crude linear map of the
score, 100 -> 168 h (7 days) down to 0 -> 0 h.
"""

from __future__ import annotations

from kitchenguard_schemas import PantryPrediction, PantryTelemetry

ETHANOL_RIPE_PPM = 81.0
ETHANOL_DECOMPOSED_PPM = 108.0
AMMONIA_RIPE_PPM = 48.0
AMMONIA_DECOMPOSED_PPM = 111.0

SCORE_AT_RIPE = 60.0
MAX_RSL_H = 168.0

# Stage boundaries on the 0-100 score.
FRESH_MIN = 75.0
RIPE_MIN = 40.0
DETERIORATING_MIN = 15.0


def sensor_score(ppm: float, ripe: float, decomposed: float) -> float:
    """Piecewise-linear 100 -> SCORE_AT_RIPE -> 0 for one gas sensor."""
    if ppm <= 0:
        return 100.0
    if ppm <= ripe:
        return 100.0 - (100.0 - SCORE_AT_RIPE) * ppm / ripe
    if ppm >= decomposed:
        return 0.0
    return SCORE_AT_RIPE * (decomposed - ppm) / (decomposed - ripe)


def stage_for(score: float) -> str:
    if score >= FRESH_MIN:
        return "Fresh"
    if score >= RIPE_MIN:
        return "Ripe"
    if score >= DETERIORATING_MIN:
        return "Deteriorating"
    return "Spoiled"


def rule_prediction(telemetry: PantryTelemetry) -> PantryPrediction:
    score = min(
        sensor_score(telemetry.mq3_ppm, ETHANOL_RIPE_PPM, ETHANOL_DECOMPOSED_PPM),
        sensor_score(telemetry.mq135_ppm, AMMONIA_RIPE_PPM, AMMONIA_DECOMPOSED_PPM),
    )
    return PantryPrediction(
        freshness_score=round(score, 1),
        rsl_h=round(MAX_RSL_H * score / 100.0, 1),
        stage=stage_for(score),
        source="rule_fallback",
    )
