#!/usr/bin/env python3
# 고정된 개발 EC2에서 앱 자동 시작을 설정하거나 재부팅 후 서비스 상태를 검증합니다.
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.request


INSTANCE_ID = "i-06da8518d0a416c98"
ACCOUNT_ID = "395931907754"
REGION = "ap-northeast-2"
APP_DIR = Path("/opt/nearby")
SERVICES = ("nearby.service", "caddy.service", "amazon-cloudwatch-agent.service")
HEALTH_URL = "http://127.0.0.1:8080/readyz"


def command(*args):
    completed = subprocess.run(args, text=True, capture_output=True, timeout=20)
    if completed.returncode:
        # 환경 파일, systemd Environment 및 애플리케이션 로그를 출력하지 않습니다.
        raise RuntimeError("Command failed: " + " ".join(args[:2]))
    return completed.stdout.strip()


def identity():
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    request = urllib.request.Request(
        "http://169.254.169.254/latest/api/token", method="PUT",
        headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"})
    with opener.open(request, timeout=3) as response:
        token = response.read().decode()
    request = urllib.request.Request(
        "http://169.254.169.254/latest/dynamic/instance-identity/document",
        headers={"X-aws-ec2-metadata-token": token})
    with opener.open(request, timeout=3) as response:
        return json.load(response)


def healthy():
    try:
        with urllib.request.urlopen(HEALTH_URL, timeout=5) as response:
            body = json.load(response)
            return response.status == 200 and isinstance(body, dict) and body.get("status") == "UP"
    except (OSError, ValueError):
        return False


def verify_files():
    for path in (APP_DIR / "app.jar", APP_DIR / "app.env"):
        if not path.is_file() or path.is_symlink() or path.stat().st_size == 0:
            raise ValueError("Deploy the application and persistent environment file first")
    if APP_DIR.resolve() != APP_DIR:
        raise ValueError("Application directory must not be a symbolic link")
    if command("findmnt", "-n", "-o", "FSTYPE", "--target", str(APP_DIR)) in ("tmpfs", "ramfs"):
        raise ValueError("Application must reside on persistent storage")
    if str(APP_DIR / "app.jar") not in command("systemctl", "show", "nearby.service", "-p", "ExecStart", "--value"):
        raise ValueError("Unexpected application service")
    if str(APP_DIR / "app.env") not in command("systemctl", "show", "nearby.service", "-p", "EnvironmentFiles", "--value"):
        raise ValueError("Service must load the persistent app.env file")


def enabled():
    for service in SERVICES:
        if command("systemctl", "is-enabled", service) != "enabled":
            raise ValueError("Run prepare while the development server is running")


def active():
    for service in SERVICES:
        command("systemctl", "is-active", "--quiet", service)


def runtime(mode):
    if mode not in ("prepare", "verify"):
        raise ValueError("Mode must be prepare or verify; an up-to-date SSM Agent is required")
    if os.geteuid() != 0:
        raise ValueError("SSM must execute as root")
    actual = identity()
    if (actual.get("accountId"), actual.get("region"), actual.get("instanceId")) != (ACCOUNT_ID, REGION, INSTANCE_ID):
        raise ValueError("This document can only run on the Nearby development EC2")
    verify_files()
    # 최신 배포 스크립트와 같은 EC2 내부 잠금을 사용합니다.
    with (APP_DIR / ".deploy.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if mode == "prepare":
            active()
            if not healthy():
                raise ValueError("Application must already be ready before preparing automatic startup")
            pid = command("systemctl", "show", "nearby.service", "-p", "MainPID", "--value")
            if not pid.isdecimal() or int(pid) == 0:
                raise ValueError("Application has no running process")
            # --now를 쓰지 않으므로 프로세스를 시작하거나 재시작하지 않습니다.
            command("systemctl", "enable", *SERVICES)
            enabled()
            active()
            if command("systemctl", "show", "nearby.service", "-p", "MainPID", "--value") != pid:
                raise RuntimeError("Application process changed during prepare")
        else:
            enabled()
            deadline = time.monotonic() + 150
            while not healthy():
                if time.monotonic() >= deadline:
                    raise RuntimeError("Application readiness timed out; EC2 remains running")
                time.sleep(3)
            active()
            pid = command("systemctl", "show", "nearby.service", "-p", "MainPID", "--value")
            if not pid.isdecimal() or int(pid) == 0:
                raise ValueError("Application has no running process")
        return {"instance_id": INSTANCE_ID, "mode": mode, "enabled": True,
                "active": True, "ready": True, "pid": pid}


def main():
    try:
        result = runtime(os.environ.get("SSM_Mode", ""))
        print("NEARBY_RUNTIME_RESULT=" + json.dumps(result))
        return 0
    except Exception as error:
        message = str(error) if isinstance(error, (ValueError, RuntimeError)) else type(error).__name__
        print("Development runtime check failed: " + message, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
