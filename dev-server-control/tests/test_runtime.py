#!/usr/bin/env python3
# 실제 EC2 변경 없이 대상 차단과 자동 시작 설정의 무중단 동작을 검증합니다.
import fcntl
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("runtime", Path(__file__).resolve().parents[1] / "runtime.py")
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.app = Path(self.directory.name).resolve()
        (self.app / "app.jar").write_bytes(b"existing jar")
        (self.app / "app.env").write_bytes(b"private settings")
        self.calls = []
        self.auto_start = False
        self.pid = "1234"
        self.environment_files = str(self.app / "app.env")
        self.patch(runtime, "APP_DIR", self.app)
        self.patch(runtime.os, "geteuid", return_value=0)
        self.identity = self.patch(runtime, "identity", return_value={
            "accountId": runtime.ACCOUNT_ID, "region": runtime.REGION, "instanceId": runtime.INSTANCE_ID})
        self.patch(runtime, "healthy", return_value=True)
        self.patch(runtime, "command", side_effect=self.command)

    def patch(self, target, name, *args, **kwargs):
        patcher = patch.object(target, name, *args, **kwargs)
        result = patcher.start()
        self.addCleanup(patcher.stop)
        return result

    def command(self, *args):
        self.calls.append(args)
        if args[0] == "findmnt":
            return "xfs"
        if args[1] == "enable":
            self.auto_start = True
            return ""
        if args[1] == "is-enabled":
            return "enabled" if self.auto_start else "disabled"
        if "ExecStart" in args:
            return "/usr/bin/java -jar " + str(self.app / "app.jar")
        if "EnvironmentFiles" in args:
            return self.environment_files
        if "MainPID" in args:
            return self.pid
        return ""

    def test_prepare_enables_existing_services_without_start_restart_or_file_changes(self):
        result = runtime.runtime("prepare")
        self.assertTrue(result["enabled"])
        self.assertEqual("1234", result["pid"])
        self.assertIn(("systemctl", "enable", *runtime.SERVICES), self.calls)
        self.assertFalse(any(call[1] in ("start", "stop", "restart") for call in self.calls))
        self.assertEqual(b"existing jar", (self.app / "app.jar").read_bytes())
        self.assertEqual(b"private settings", (self.app / "app.env").read_bytes())

    def test_wrong_instance_account_or_region_fails_before_any_system_command(self):
        for field in ("instanceId", "accountId", "region"):
            with self.subTest(field=field):
                value = {"accountId": runtime.ACCOUNT_ID, "region": runtime.REGION, "instanceId": runtime.INSTANCE_ID}
                value[field] = "production"
                self.identity.return_value = value
                with self.assertRaisesRegex(ValueError, "development EC2"):
                    runtime.runtime("prepare")
                self.assertEqual([], self.calls)

    def test_unprepared_service_cannot_pass_stop_or_start_verification(self):
        with self.assertRaisesRegex(ValueError, "prepare"):
            runtime.runtime("verify")
        self.assertFalse(any(call[1] == "enable" for call in self.calls))

    def test_missing_app_environment_does_not_enable_services(self):
        (self.app / "app.env").unlink()
        with self.assertRaisesRegex(ValueError, "Deploy"):
            runtime.runtime("prepare")
        self.assertFalse(self.auto_start)

    def test_service_must_reference_persistent_environment(self):
        self.environment_files = "/run/temporary.env"
        with self.assertRaisesRegex(ValueError, "app.env"):
            runtime.runtime("prepare")
        self.assertFalse(self.auto_start)

    def test_prepare_rejects_an_unhealthy_app_without_enabling(self):
        runtime.healthy.return_value = False
        with self.assertRaisesRegex(ValueError, "ready"):
            runtime.runtime("prepare")
        self.assertFalse(self.auto_start)

    def test_deployment_lock_blocks_prepare(self):
        with (self.app / ".deploy.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(BlockingIOError):
                runtime.runtime("prepare")
        self.assertFalse(self.auto_start)

    def test_verify_timeout_does_not_restart_the_app(self):
        self.auto_start = True
        runtime.healthy.return_value = False
        self.patch(runtime.time, "monotonic", side_effect=[0, 151])
        with self.assertRaisesRegex(RuntimeError, "remains running"):
            runtime.runtime("verify")
        self.assertFalse(any(call[1] in ("start", "stop", "restart", "enable") for call in self.calls))

    def test_verify_requires_no_mutation(self):
        self.auto_start = True
        self.assertTrue(runtime.runtime("verify")["ready"])
        self.assertFalse(any(call[1] in ("start", "stop", "restart", "enable") for call in self.calls))

    def test_missing_ssm_parameter_fails_closed(self):
        with self.assertRaisesRegex(ValueError, "Mode"):
            runtime.runtime("")
        self.assertEqual([], self.calls)


if __name__ == "__main__":
    unittest.main()
