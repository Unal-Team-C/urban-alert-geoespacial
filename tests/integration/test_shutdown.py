"""Graceful shutdown (RF-005): uvicorn started with the same flags as the Dockerfile CMD, then SIGTERM mid-request."""

import signal
import subprocess
import sys
import threading
import time

import httpx

PORT = 8765
UVICORN_FLAGS = ["--no-access-log", "--timeout-graceful-shutdown", "20"]


def wait_until_healthy(process: subprocess.Popen, timeout_s: float = 20) -> None:
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        assert process.poll() is None, "uvicorn exited before becoming healthy"
        try:
            if httpx.get(f"http://127.0.0.1:{PORT}/health", timeout=1).status_code == 200:
                return
        except httpx.TransportError:
            pass
        time.sleep(0.2)
    raise AssertionError("uvicorn did not become healthy")


def test_sigterm_finishes_in_flight_requests_and_closes_the_pool():
    process = subprocess.Popen(
        [sys.executable, "-m", "uvicorn", "tests.integration.slow_app:app", "--host", "127.0.0.1", "--port", str(PORT)]
        + UVICORN_FLAGS,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    try:
        wait_until_healthy(process)

        result: dict = {}

        def call_slow() -> None:
            result["response"] = httpx.get(f"http://127.0.0.1:{PORT}/slow", timeout=10)

        caller = threading.Thread(target=call_slow)
        caller.start()
        time.sleep(0.5)  # the request is now in flight
        process.send_signal(signal.SIGTERM)

        exit_code = process.wait(timeout=25)
        caller.join(timeout=5)
        output = process.stdout.read()
    finally:
        if process.poll() is None:
            process.kill()

    assert result["response"].status_code == 200
    assert result["response"].json() == {"done": True}
    # uvicorn re-raises the captured SIGTERM once shutdown completes, so a clean stop ends "killed by SIGTERM".
    assert exit_code in (0, -signal.SIGTERM)
    assert "database pool closed" in output
