from __future__ import annotations

import pytest
from httpx import ASGITransport, AsyncClient

from app.core.config import Settings
from app.db.mongo import close, connect
from app.main import app
from app.services.inference import init_registry


@pytest.fixture(autouse=True)
async def memory_backend(tmp_path):
    await connect(Settings(use_memory_db=True, start_mqtt=False, ml_models_dir=tmp_path))
    init_registry(tmp_path)
    yield
    await close()


@pytest.fixture
async def api_client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        client.headers["Authorization"] = "Bearer dev-token"
        yield client
