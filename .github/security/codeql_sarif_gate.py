from __future__ import annotations

import json
import math
import sys
from pathlib import Path
from typing import Any, Iterable


HIGH_SECURITY_SEVERITY = 7.0


class SarifGateError(ValueError):
    pass


def _mapping(value: Any, context: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise SarifGateError(f"{context} must be an object")
    return value


def _sequence(value: Any, context: str) -> list[Any]:
    if not isinstance(value, list):
        raise SarifGateError(f"{context} must be an array")
    return value


def _bounded_repr(value: Any) -> str:
    try:
        rendered = repr(value)
    except (ValueError, OverflowError):
        return f"<{type(value).__name__}>"
    if len(rendered) > 200:
        return f"{rendered[:197]}..."
    return rendered


def _security_severity(rule_id: str, rule: dict[str, Any]) -> tuple[bool, float]:
    properties = _mapping(rule.get("properties", {}), f"rule {rule_id!r}.properties")
    if "security-severity" not in properties:
        return False, 0.0

    raw_score = properties["security-severity"]
    if isinstance(raw_score, bool):
        raise SarifGateError(
            f"rule {rule_id!r} has invalid security-severity {_bounded_repr(raw_score)}"
        )
    try:
        score = float(raw_score)
    except (TypeError, ValueError, OverflowError) as error:
        raise SarifGateError(
            f"rule {rule_id!r} has invalid security-severity {_bounded_repr(raw_score)}"
        ) from error
    if not math.isfinite(score) or not 0.0 <= score <= 10.0:
        raise SarifGateError(
            f"rule {rule_id!r} has invalid security-severity {_bounded_repr(raw_score)}"
        )
    return True, score


def _result_location(result: dict[str, Any]) -> str:
    locations = result.get("locations")
    if not isinstance(locations, list) or not locations or not isinstance(locations[0], dict):
        return "<unknown>"

    physical = locations[0].get("physicalLocation")
    if not isinstance(physical, dict):
        return "<unknown>"
    artifact = physical.get("artifactLocation")
    if not isinstance(artifact, dict):
        return "<unknown>"
    uri = artifact.get("uri")
    if not isinstance(uri, str) or not uri:
        return "<unknown>"
    safe_uri = "".join(char if char.isprintable() else "?" for char in uri)
    safe_uri = " ".join(safe_uri.split())[:500]
    if not safe_uri:
        return "<unknown>"

    region = physical.get("region")
    start_line = region.get("startLine") if isinstance(region, dict) else None
    if isinstance(start_line, int) and not isinstance(start_line, bool) and start_line > 0:
        return f"{safe_uri}:{start_line}"
    return safe_uri


def evaluate_documents(
    documents: Iterable[dict[str, Any]],
) -> tuple[int, list[tuple[str, float, str, str]]]:
    rule_count = 0
    high_capable_rule_count = 0
    run_count = 0
    failures: list[tuple[str, float, str, str]] = []

    for document_index, raw_document in enumerate(documents):
        document = _mapping(raw_document, f"document[{document_index}]")
        runs = _sequence(document.get("runs", []), f"document[{document_index}].runs")
        for run_index, raw_run in enumerate(runs):
            run_count += 1
            context = f"document[{document_index}].runs[{run_index}]"
            run = _mapping(raw_run, context)
            tool = _mapping(run.get("tool"), f"{context}.tool")
            driver = _mapping(tool.get("driver"), f"{context}.tool.driver")
            raw_extensions = _sequence(
                tool.get("extensions", []),
                f"{context}.tool.extensions",
            )
            components = [driver]
            components.extend(
                _mapping(extension, f"{context}.tool.extensions[{index}]")
                for index, extension in enumerate(raw_extensions)
            )

            rules_by_id: dict[str, dict[str, Any]] = {}
            severity_by_id: dict[str, float] = {}
            for component_index, component in enumerate(components):
                rules = _sequence(
                    component.get("rules", []),
                    f"{context}.tool component[{component_index}].rules",
                )
                rule_count += len(rules)
                for rule_index, raw_rule in enumerate(rules):
                    rule = _mapping(
                        raw_rule,
                        f"{context}.tool component[{component_index}].rules[{rule_index}]",
                    )
                    rule_id = rule.get("id")
                    if not isinstance(rule_id, str) or not rule_id:
                        raise SarifGateError(f"{context} contains a rule without an id")
                    previous = rules_by_id.get(rule_id)
                    if previous is not None and previous != rule:
                        raise SarifGateError(f"{context} contains conflicting rule id {rule_id!r}")
                    if previous is None:
                        has_security_severity, score = _security_severity(rule_id, rule)
                        rules_by_id[rule_id] = rule
                        severity_by_id[rule_id] = score
                        if has_security_severity and score >= HIGH_SECURITY_SEVERITY:
                            high_capable_rule_count += 1

            results = _sequence(run.get("results", []), f"{context}.results")
            for result_index, raw_result in enumerate(results):
                result_context = f"{context}.results[{result_index}]"
                result = _mapping(raw_result, result_context)
                rule_id = result.get("ruleId")
                if not isinstance(rule_id, str) or rule_id not in rules_by_id:
                    raise SarifGateError(
                        f"{result_context} references an unknown rule id {rule_id!r}"
                    )

                score = severity_by_id[rule_id]

                if score >= HIGH_SECURITY_SEVERITY:
                    message = _mapping(
                        result.get("message", {}),
                        f"{result_context}.message",
                    )
                    text = message.get("text") or message.get("markdown") or "CodeQL finding"
                    failures.append(
                        (
                            rule_id,
                            score,
                            _result_location(result),
                            " ".join(str(text).split())[:500],
                        )
                    )

    if run_count == 0:
        raise SarifGateError("CodeQL SARIF contains no analysis runs")
    if rule_count == 0:
        raise SarifGateError("CodeQL SARIF contains no evaluated rules")
    if high_capable_rule_count == 0:
        raise SarifGateError("CodeQL SARIF contains no high/critical-capable rules")
    return rule_count, failures


def evaluate_directory(directory: Path) -> tuple[int, list[tuple[str, float, str, str]]]:
    paths = sorted(directory.rglob("*.sarif"))
    if not paths:
        raise SarifGateError("CodeQL did not produce a SARIF report")

    documents = []
    for path in paths:
        try:
            documents.append(json.loads(path.read_text(encoding="utf-8")))
        except (OSError, UnicodeError, ValueError) as error:
            raise SarifGateError(f"Unable to read CodeQL SARIF report {path.name!r}") from error
    return evaluate_documents(documents)


def _fixture(rule: dict[str, Any], *, extension: bool, results: list[dict[str, Any]]) -> dict[str, Any]:
    driver: dict[str, Any] = {"name": "CodeQL", "rules": [] if extension else [rule]}
    tool: dict[str, Any] = {"driver": driver}
    if extension:
        tool["extensions"] = [{"name": "codeql/test", "rules": [rule]}]
    return {"runs": [{"tool": tool, "results": results}]}


def self_test() -> None:
    extension_rule = {"id": "js/example", "properties": {"security-severity": "8.0"}}
    count, failures = evaluate_documents([_fixture(extension_rule, extension=True, results=[])])
    if count != 1 or failures:
        raise SarifGateError("extension-rule fixture did not pass")

    driver_rule = {"id": "js/no-security-severity", "properties": {}}
    mixed_fixture = {
        "runs": [
            {
                "tool": {
                    "driver": {"name": "CodeQL", "rules": [driver_rule]},
                    "extensions": [{"name": "codeql/test", "rules": [extension_rule]}],
                },
                "results": [],
            }
        ]
    }
    count, failures = evaluate_documents([mixed_fixture])
    if count != 2 or failures:
        raise SarifGateError("mixed driver-and-extension fixture did not pass")

    high_rule = {"id": "js/high", "properties": {"security-severity": "7.0"}}
    _, failures = evaluate_documents(
        [
            _fixture(
                high_rule,
                extension=True,
                results=[
                    {
                        "ruleId": "js/high",
                        "message": {"text": "high finding"},
                        "locations": [
                            {
                                "physicalLocation": {
                                    "artifactLocation": {"uri": "tests/example.js"},
                                    "region": {"startLine": 42},
                                }
                            }
                        ],
                    }
                ],
            )
        ]
    )
    if failures != [("js/high", 7.0, "tests/example.js:42", "high finding")]:
        raise SarifGateError("high-severity fixture was not rejected")

    unsafe_location = {
        "locations": [
            {
                "physicalLocation": {
                    "artifactLocation": {"uri": "tests/\n::error::example.js"},
                    "region": {"startLine": 7},
                }
            }
        ]
    }
    if _result_location(unsafe_location) != "tests/?::error::example.js:7":
        raise SarifGateError("result location was not safely normalized")

    error_fixtures = [
        _fixture(
            extension_rule,
            extension=True,
            results=[{"ruleId": "js/unknown", "message": {"text": "unknown"}}],
        ),
        _fixture(
            {"id": "js/nan", "properties": {"security-severity": "NaN"}},
            extension=True,
            results=[{"ruleId": "js/nan", "message": {"text": "invalid"}}],
        ),
        _fixture(
            {"id": "js/overflow", "properties": {"security-severity": 10**1000}},
            extension=True,
            results=[{"ruleId": "js/overflow", "message": {"text": "invalid"}}],
        ),
        _fixture(
            {"id": "js/medium-only", "properties": {"security-severity": "6.9"}},
            extension=True,
            results=[],
        ),
        _fixture(
            {"id": "js/zero-only", "properties": {"security-severity": "0.0"}},
            extension=True,
            results=[],
        ),
        _fixture(driver_rule, extension=False, results=[]),
        {"runs": [{"tool": {"driver": {"name": "CodeQL", "rules": []}}, "results": []}]},
    ]
    for index, fixture in enumerate(error_fixtures):
        try:
            evaluate_documents([fixture])
        except SarifGateError:
            continue
        raise SarifGateError(f"fail-closed fixture {index} unexpectedly passed")

    print("Validated CodeQL SARIF gate fixtures.")


def main(argv: list[str]) -> int:
    try:
        if argv == ["--self-test"]:
            self_test()
            return 0
        if len(argv) != 1:
            raise SarifGateError("usage: codeql_sarif_gate.py <sarif-directory> | --self-test")

        rule_count, failures = evaluate_directory(Path(argv[0]))
        if failures:
            for rule_id, score, location, message in failures:
                print(f"CodeQL {rule_id} ({score}) at {location}: {message}")
            raise SarifGateError(
                f"CodeQL found {len(failures)} high or critical result(s)"
            )
        print(
            f"CodeQL evaluated {rule_count} JavaScript/TypeScript rules "
            "with no high or critical results."
        )
        return 0
    except SarifGateError as error:
        print(error, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
