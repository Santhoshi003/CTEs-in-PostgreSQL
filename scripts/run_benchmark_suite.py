from __future__ import annotations

import json
import re
import subprocess
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
QUERY_DIR = ROOT / "queries"
BENCH_DIR = ROOT / "benchmarks"
EXPLAIN_DIR = BENCH_DIR / "explain"
RAW_EXPLAIN_DIR = EXPLAIN_DIR / "raw"
PGBENCH_DIR = BENCH_DIR / "pgbench"
RESULTS_DIR = ROOT / "results"

POSTGRES_SERVICE = "postgres"
POSTGRES_USER = "analytics"
POSTGRES_DB = "analytics_benchmark"
COMPOSE = ["docker", "compose"]


def run(command: list[str], *, input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        input=input_text,
        text=True,
        capture_output=True,
        check=True,
        cwd=ROOT,
    )


def compose_exec(sql: str) -> str:
    command = COMPOSE + ["exec", "-T", POSTGRES_SERVICE, "psql", "-U", POSTGRES_USER, "-d", POSTGRES_DB, "-v", "ON_ERROR_STOP=1", "-X", "-qAt", "-c", sql]
    return run(command).stdout


def load_query(query_file: Path) -> str:
    return query_file.read_text(encoding="utf-8").strip().rstrip(";")


def explain(query_file: Path) -> dict:
    sql = f"EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) {load_query(query_file)};"
    parsed = json.loads(compose_exec(sql))[0]
    plan = parsed["Plan"]

    def walk(node: dict) -> tuple[bool, list[str]]:
        has_sort = node.get("Node Type") == "Sort"
        details: list[str] = []
        if node.get("Node Type") == "Sort":
            details.append(str(node.get("Sort Method", "Sort")))
            if node.get("Sort Space Type"):
                details.append(str(node.get("Sort Space Type")))
        for child in node.get("Plans", []) or []:
            child_has_sort, child_details = walk(child)
            has_sort = has_sort or child_has_sort
            details.extend(child_details)
        return has_sort, details

    has_sort, sort_details = walk(plan)
    return {
        "execution_time_ms": float(parsed["Execution Time"]),
        "shared_hit_blocks": int(plan.get("Shared Hit Blocks", 0)),
        "shared_dirtied_blocks": int(plan.get("Shared Dirtied Blocks", 0)),
        "has_sort": has_sort,
        "sort_details": sort_details,
        "plan": parsed,
    }


def explain_raw(query_file: Path) -> dict:
    sql = f"EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) {load_query(query_file)};"
    return json.loads(compose_exec(sql))


def exec_sql(sql: str) -> float:
    start = time.perf_counter()
    compose_exec(sql)
    return (time.perf_counter() - start) * 1000


def pgbench_run(query_file: Path, label: str) -> dict:
    PGBENCH_DIR.mkdir(parents=True, exist_ok=True)
    host_sql = PGBENCH_DIR / f"{label}.sql"
    host_sql.write_text(load_query(query_file) + ";\n", encoding="utf-8")
    command = COMPOSE + [
        "exec",
        "-T",
        POSTGRES_SERVICE,
        "pgbench",
        "-U",
        POSTGRES_USER,
        "-d",
        POSTGRES_DB,
        "-n",
        "-c",
        "10",
        "-j",
        "10",
        "-T",
        "60",
        "-f",
        f"/workspace/benchmarks/pgbench/{label}.sql",
    ]
    result = run(command)
    match_tps = re.search(r"tps = ([0-9.]+)", result.stdout)
    match_latency = re.search(r"latency average = ([0-9.]+) ms", result.stdout)
    return {
        "stdout": result.stdout,
        "tps": float(match_tps.group(1)) if match_tps else 0.0,
        "latency_ms": float(match_latency.group(1)) if match_latency else 0.0,
    }


def main() -> None:
    for folder in [BENCH_DIR, EXPLAIN_DIR, RAW_EXPLAIN_DIR, PGBENCH_DIR, RESULTS_DIR]:
        folder.mkdir(parents=True, exist_ok=True)

    queries = {
        "query_1_window": QUERY_DIR / "window_q1.sql",
        "query_1_cte": QUERY_DIR / "cte_q1.sql",
        "query_2_window": QUERY_DIR / "window_q2.sql",
        "query_2_cte": QUERY_DIR / "cte_q2.sql",
        "query_3_window": QUERY_DIR / "window_q3.sql",
        "query_3_cte": QUERY_DIR / "cte_q3.sql",
        "query_4_window": QUERY_DIR / "window_q4.sql",
        "query_4_cte": QUERY_DIR / "cte_q4.sql",
        "query_5_window": QUERY_DIR / "window_q5.sql",
        "query_5_cte": QUERY_DIR / "cte_q5.sql",
    }

    explain_data: dict[str, dict] = {}
    for key, path in queries.items():
        payload = explain(path)
        explain_data[key] = payload
        (EXPLAIN_DIR / f"{key}.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")
        (RAW_EXPLAIN_DIR / f"{key}.json").write_text(json.dumps(explain_raw(path), indent=2), encoding="utf-8")

    q1_before = explain_data["query_1_window"]["execution_time_ms"]
    q2_before = explain_data["query_2_window"]["execution_time_ms"]

    compose_exec("CREATE INDEX IF NOT EXISTS orders_user_created_at_idx ON orders (user_id, created_at);")
    compose_exec("CREATE INDEX IF NOT EXISTS users_cohort_month_idx ON users (cohort_month);")
    compose_exec("ANALYZE users;")
    compose_exec("ANALYZE orders;")

    q1_after = explain(queries["query_1_window"])["execution_time_ms"]
    q2_after = explain(queries["query_2_window"])["execution_time_ms"]

    q1_pgbench_wf = pgbench_run(queries["query_1_window"], "query_1_window")
    q1_pgbench_cte = pgbench_run(queries["query_1_cte"], "query_1_cte")
    q2_pgbench_wf = pgbench_run(queries["query_2_window"], "query_2_window")
    q2_pgbench_cte = pgbench_run(queries["query_2_cte"], "query_2_cte")

    mv_create_ms = exec_sql("DROP MATERIALIZED VIEW IF EXISTS daily_revenue_stats;")
    mv_create_ms += exec_sql(load_query(ROOT / "queries" / "materialized_view_daily_revenue_stats.sql"))

    compose_exec(
        "INSERT INTO orders (order_id, user_id, product_id, amount, status, created_at, updated_at) "
        "SELECT gen_random_uuid(), greatest(1, least(200000, floor(200000 * power(random(), 4))::int + 1)), "
        "floor(1 + random() * 5000)::int, round((1 + random() * 499)::numeric, 2), "
        "(ARRAY['pending', 'paid', 'shipped', 'completed', 'refunded'])[floor(1 + random() * 5)::int], "
        "now() - (random() * INTERVAL '30 days'), now() - (random() * INTERVAL '30 days') "
        "FROM generate_series(1, 10000);"
    )
    compose_exec("ANALYZE orders;")

    refresh_start = time.perf_counter()
    compose_exec("REFRESH MATERIALIZED VIEW daily_revenue_stats;")
    refresh_ms = (time.perf_counter() - refresh_start) * 1000

    mv_select_start = time.perf_counter()
    compose_exec("SELECT * FROM daily_revenue_stats ORDER BY day;")
    mv_select_ms = (time.perf_counter() - mv_select_start) * 1000

    raw_q1_start = time.perf_counter()
    compose_exec(load_query(queries["query_1_window"]))
    raw_q1_ms = (time.perf_counter() - raw_q1_start) * 1000

    results = {
        "query_1": {
            "wf_ms": round(q1_before, 3),
            "cte_ms": round(explain_data["query_1_cte"]["execution_time_ms"], 3),
            "index_speedup": round(q1_before / q1_after, 3) if q1_after else 0.0,
        },
        "query_2": {
            "wf_ms": round(q2_before, 3),
            "cte_ms": round(explain_data["query_2_cte"]["execution_time_ms"], 3),
            "index_speedup": round(q2_before / q2_after, 3) if q2_after else 0.0,
        },
        "query_3": {
            "wf_ms": round(explain_data["query_3_window"]["execution_time_ms"], 3),
            "cte_ms": round(explain_data["query_3_cte"]["execution_time_ms"], 3),
            "index_speedup": 1.0,
        },
        "query_4": {
            "wf_ms": round(explain_data["query_4_window"]["execution_time_ms"], 3),
            "cte_ms": round(explain_data["query_4_cte"]["execution_time_ms"], 3),
            "index_speedup": 1.0,
        },
        "query_5": {
            "wf_ms": round(explain_data["query_5_window"]["execution_time_ms"], 3),
            "cte_ms": round(explain_data["query_5_cte"]["execution_time_ms"], 3),
            "index_speedup": 1.0,
        },
        "pgbench_results": {
            "wf_tps_q1": round(q1_pgbench_wf["tps"], 3),
            "cte_tps_q1": round(q1_pgbench_cte["tps"], 3),
            "wf_latency_ms_q1": round(q1_pgbench_wf["latency_ms"], 3),
            "cte_latency_ms_q1": round(q1_pgbench_cte["latency_ms"], 3),
            "wf_tps_q2": round(q2_pgbench_wf["tps"], 3),
            "cte_tps_q2": round(q2_pgbench_cte["tps"], 3),
            "wf_latency_ms_q2": round(q2_pgbench_wf["latency_ms"], 3),
            "cte_latency_ms_q2": round(q2_pgbench_cte["latency_ms"], 3),
        },
        "materialized_view": {
            "create_ms": round(mv_create_ms, 3),
            "refresh_ms": round(refresh_ms, 3),
            "select_ms": round(mv_select_ms, 3),
            "raw_q1_ms": round(raw_q1_ms, 3),
        },
    }

    (RESULTS_DIR / "benchmarks.json").write_text(json.dumps(results, indent=2), encoding="utf-8")

    report = [
        "# Query 1 Index Impact Report",
        f"- Execution time before indexes: {q1_before:.3f} ms",
        f"- Execution time after indexes: {q1_after:.3f} ms",
        f"- Speedup ratio: {q1_before / q1_after if q1_after else 0:.3f}x",
        "",
        "# Query 2 Index Impact Report",
        f"- Execution time before indexes: {q2_before:.3f} ms",
        f"- Execution time after indexes: {q2_after:.3f} ms",
        f"- Speedup ratio: {q2_before / q2_after if q2_after else 0:.3f}x",
        "",
        "# Materialized View Metrics",
        f"- Initial creation time: {results['materialized_view']['create_ms']:.3f} ms",
        f"- Refresh time after 10,000 inserts: {refresh_ms:.3f} ms",
        f"- SELECT * FROM daily_revenue_stats: {mv_select_ms:.3f} ms",
        f"- Raw window query time: {raw_q1_ms:.3f} ms",
    ]
    (BENCH_DIR / "performance_report.md").write_text("\n".join(report) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
