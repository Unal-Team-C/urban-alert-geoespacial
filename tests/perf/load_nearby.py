"""Load test for GET /api/v1/geospatial/reports (RNF-001 / MS-002). Not collected by pytest.

Run inside the compose network, against the seeded database. A single generator process saturates
its own CPU above ~25 concurrent requests, so measure 50 concurrent as several generators in parallel
(e.g. 5 x --concurrency 10) and pass --db-url to only one of them:

    for seed in 1 2 3 4 5; do
        docker compose --profile test run --rm tests python -m tests.perf.load_nearby \
            --concurrency 10 --requests 1000 --seed $seed \
            $([ $seed = 1 ] && echo --db-url postgresql://geospatial:geospatial@db:5432/geospatial) &
    done; wait
"""

import argparse
import asyncio
import random
import statistics
import time

import asyncpg
import httpx

URL = "/api/v1/geospatial/reports"
URBAN_LAT = (4.47, 4.80)
URBAN_LON = (-74.20, -74.02)
RADIUS_M = (500, 6000)


def percentile(sorted_values: list[float], pct: float) -> float:
    index = max(0, min(len(sorted_values) - 1, round(pct / 100 * len(sorted_values)) - 1))
    return sorted_values[index]


async def sample_connections(db_url: str, stop: asyncio.Event) -> int:
    """Peak number of client connections to the service database while the test runs (sampler excluded)."""
    peak = 0
    connection = await asyncpg.connect(db_url)
    try:
        while not stop.is_set():
            count = await connection.fetchval(
                "SELECT count(*) FROM pg_stat_activity"
                " WHERE datname = current_database() AND backend_type = 'client backend' AND pid <> pg_backend_pid()"
                # Network clients only: excludes local tools such as the db container's pg_isready healthcheck.
                " AND client_addr IS NOT NULL AND client_addr <> '127.0.0.1'"
            )
            peak = max(peak, count)
            await asyncio.sleep(0.05)
    finally:
        await connection.close()
    return peak


async def run(base_url: str, concurrency: int, requests: int, seed: int, db_url: str | None) -> None:
    rng = random.Random(seed)
    queries = [
        {
            "lat": round(rng.uniform(*URBAN_LAT), 6),
            "lon": round(rng.uniform(*URBAN_LON), 6),
            "radius": rng.randint(*RADIUS_M),
        }
        for _ in range(requests)
    ]
    latencies_ms: list[float] = []
    results: list[int] = []
    errors = 0
    queue: asyncio.Queue[dict] = asyncio.Queue()
    for query in queries:
        queue.put_nowait(query)

    async def worker(client: httpx.AsyncClient) -> None:
        nonlocal errors
        while True:
            try:
                params = queue.get_nowait()
            except asyncio.QueueEmpty:
                return
            start = time.perf_counter()
            try:
                response = await client.get(URL, params=params)
                elapsed = (time.perf_counter() - start) * 1000
                if response.status_code == 200:
                    latencies_ms.append(elapsed)
                    # Count without decoding: the load generator must not be the CPU bottleneck.
                    results.append(response.content.count(b'"reportId"'))
                else:
                    errors += 1
            except httpx.HTTPError:
                errors += 1

    stop = asyncio.Event()
    sampler = asyncio.create_task(sample_connections(db_url, stop)) if db_url else None
    limits = httpx.Limits(max_connections=concurrency, max_keepalive_connections=concurrency)
    async with httpx.AsyncClient(base_url=base_url, limits=limits, timeout=30) as client:
        await client.get(URL, params=queries[0])  # warm-up
        started = time.perf_counter()
        await asyncio.gather(*(worker(client) for _ in range(concurrency)))
        wall_s = time.perf_counter() - started
    stop.set()
    peak_connections = await sampler if sampler else None

    latencies_ms.sort()
    print(f"concurrency={concurrency} requests={requests} ok={len(latencies_ms)} errors={errors} wall={wall_s:.1f}s "
          f"throughput={len(latencies_ms) / wall_s:.0f} req/s")
    if latencies_ms:
        print(f"latency ms: p50={percentile(latencies_ms, 50):.1f} p95={percentile(latencies_ms, 95):.1f} "
              f"p99={percentile(latencies_ms, 99):.1f} max={latencies_ms[-1]:.1f}")
        print(f"reports per response: mean={statistics.mean(results):.0f} max={max(results)}")
    if peak_connections is not None:
        print(f"peak database connections: {peak_connections}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base-url", default="http://api:8000")
    parser.add_argument("--concurrency", type=int, default=50)
    parser.add_argument("--requests", type=int, default=2000)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--db-url", default=None, help="Service database URL to sample pg_stat_activity")
    args = parser.parse_args()
    asyncio.run(run(args.base_url, args.concurrency, args.requests, args.seed, args.db_url))


if __name__ == "__main__":
    main()
