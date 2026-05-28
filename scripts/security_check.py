#!/usr/bin/env python3
"""Run security configuration checks against the JCM backend."""

from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "backend"


def check_env_file(path: Path) -> list[str]:
    findings: list[str] = []
    if not path.exists():
        return findings
    text = path.read_text(encoding="utf-8", errors="ignore")
    weak_patterns = [
        (r"API_SECRET_KEY=change-me", "API_SECRET_KEY is default"),
        (r"POSTGRES_PASSWORD=changeme\b", "POSTGRES_PASSWORD is default"),
        (r"^EVENT_WEBHOOK_SECRET=\s*$", "EVENT_WEBHOOK_SECRET is empty"),
    ]
    for pattern, msg in weak_patterns:
        if re.search(pattern, text, re.MULTILINE):
            findings.append(f"{path.name}: {msg}")
    return findings


def check_no_hardcoded_secrets() -> list[str]:
    findings: list[str] = []
    skip_dirs = {".git", "__pycache__", "node_modules", ".venv", "venv"}
    secret_patterns = [
        re.compile(r'password\s*=\s*["\'][^"\']{8,}["\']', re.I),
        re.compile(r'api_key\s*=\s*["\'][A-Za-z0-9]{20,}["\']', re.I),
    ]
    for path in BACKEND.rglob("*.py"):
        if any(part in skip_dirs for part in path.parts):
            continue
        if "test" in path.name:
            continue
        content = path.read_text(encoding="utf-8", errors="ignore")
        for pat in secret_patterns:
            if pat.search(content):
                findings.append(f"Possible hardcoded credential in {path.relative_to(ROOT)}")
                break
    return findings


def main() -> int:
    print("JCM Security Check")
    print("=" * 40)
    issues: list[str] = []

    for env_name in (".env", "backend/.env"):
        issues.extend(check_env_file(ROOT / env_name))

    issues.extend(check_no_hardcoded_secrets())

    env_path = ROOT / ".env"
    if env_path.exists():
        for line in env_path.read_text(encoding="utf-8", errors="ignore").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, val = line.partition("=")
            os.environ.setdefault(key.strip(), val.strip())

    os.chdir(BACKEND)
    sys.path.insert(0, str(BACKEND))
    from app.config import Settings  # noqa: E402

    prod = Settings()
    issues.extend(prod.validate_production_secrets())

    if issues:
        print("ISSUES FOUND:")
        for item in issues:
            print(f"  - {item}")
        print(f"\nTotal: {len(issues)} issue(s)")
        return 1

    print("No critical configuration issues detected.")
    print("Run 'pytest tests/' in backend/ for automated security tests.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
