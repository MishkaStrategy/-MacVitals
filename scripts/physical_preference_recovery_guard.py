#!/usr/bin/env python3
"""Capture and restore MacVitals preferences around physical validation."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import NoReturn

TOKEN_RE = re.compile(r"[A-Za-z0-9._-]+\Z")
DOMAIN_RE = re.compile(r"[A-Za-z0-9.-]+\Z")


def fail(message: str) -> NoReturn:
    raise SystemExit(message)


def defaults_binary() -> str:
    value = os.environ.get("MACVITALS_DEFAULTS_BIN", "/usr/bin/defaults")
    path = Path(value)
    if not path.is_absolute() or not path.is_file() or path.is_symlink():
        fail("defaults binary is missing or unsafe")
    return str(path)


def run_defaults(*arguments: str) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        [defaults_binary(), *arguments],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def sha256(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def default_root() -> Path:
    return Path.home() / "Library" / "Caches" / "MacVitals-CI" / "physical-validation-recovery"


def validate_domain(domain: str) -> None:
    if not DOMAIN_RE.fullmatch(domain):
        fail("preferences domain contains unsafe characters")


def validate_token(token: str) -> None:
    if not TOKEN_RE.fullmatch(token):
        fail("recovery token contains unsafe characters")


def validate_root(root: Path, create: bool) -> Path:
    home = Path.home().resolve()
    candidate = root.expanduser()
    if not candidate.is_absolute():
        fail("recovery root must be absolute")

    current = candidate
    while current != home:
        if current.exists() or current.is_symlink():
            if current.is_symlink():
                fail("recovery root contains a symbolic link")
            if current != candidate and not current.is_dir():
                fail("recovery root parent is not a directory")
        parent = current.parent
        if parent == current:
            fail("recovery root must remain under the user home")
        current = parent
    try:
        candidate.relative_to(home)
    except ValueError as error:
        raise SystemExit("recovery root must remain under the user home") from error

    if create:
        candidate.mkdir(parents=True, exist_ok=True, mode=0o700)
    if not candidate.is_dir() or candidate.is_symlink():
        fail("recovery root is missing or unsafe")
    candidate.chmod(0o700)
    return candidate.resolve()


def recovery_paths(root: Path, token: str) -> tuple[Path, Path]:
    return root / f"recovery-{token}.json", root / f"recovery-{token}.plist"


def existing_recovery(root: Path) -> list[Path]:
    return sorted(
        path
        for pattern in ("recovery-*.json", "recovery-*.plist")
        for path in root.glob(pattern)
        if path.is_file() or path.is_symlink()
    )


def domain_file(domain: str) -> Path:
    return Path.home() / "Library" / "Preferences" / f"{domain}.plist"


def domain_appears_to_exist(domain: str) -> bool:
    path = domain_file(domain)
    if path.exists() or path.is_symlink():
        return True
    return run_defaults("read", domain).returncode == 0


def atomic_write(path: Path, payload: bytes, mode: int) -> None:
    temporary = path.with_name(path.name + f".tmp.{os.getpid()}")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    descriptor = os.open(temporary, flags, mode)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
        temporary.replace(path)
    except BaseException:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass
        raise


def capture(domain: str, token: str, root: Path) -> None:
    validate_domain(domain)
    validate_token(token)
    root = validate_root(root, create=True)
    pending = existing_recovery(root)
    if pending:
        fail("a preserved preference recovery backup already exists")

    metadata_path, backup_path = recovery_paths(root, token)
    exported = run_defaults("export", domain, "-")
    if exported.returncode == 0:
        if not exported.stdout:
            fail("preferences export produced an empty backup")
        try:
            plistlib.loads(exported.stdout)
        except Exception as error:
            raise SystemExit("preferences export is not a valid plist") from error
        existed = True
        payload = exported.stdout
    else:
        if domain_appears_to_exist(domain):
            fail("preferences domain appears to exist but could not be exported")
        existed = False
        payload = b""

    metadata = {
        "schemaVersion": 1,
        "domain": domain,
        "token": token,
        "existed": existed,
        "backupSha256": sha256(payload),
    }
    try:
        atomic_write(backup_path, payload, 0o600)
        atomic_write(
            metadata_path,
            (json.dumps(metadata, indent=2, sort_keys=True) + "\n").encode("utf-8"),
            0o600,
        )
    except BaseException:
        backup_path.unlink(missing_ok=True)
        metadata_path.unlink(missing_ok=True)
        raise
    print(f"Preference recovery capture complete: token={token} existed={str(existed).lower()}")


def read_metadata(path: Path) -> dict[str, object]:
    if path.is_symlink() or not path.is_file():
        fail("recovery metadata is missing or unsafe")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit("recovery metadata is invalid") from error
    if not isinstance(value, dict) or value.get("schemaVersion") != 1:
        fail("recovery metadata schema is invalid")
    return value


def semantic_plist(payload: bytes) -> object:
    try:
        return plistlib.loads(payload)
    except Exception as error:
        raise SystemExit("preference recovery plist is invalid") from error


def restore(domain: str, token: str, root: Path, allow_missing: bool) -> None:
    validate_domain(domain)
    validate_token(token)
    root = validate_root(root, create=True)
    metadata_path, backup_path = recovery_paths(root, token)
    if not metadata_path.exists() and not metadata_path.is_symlink():
        if allow_missing:
            print(f"Preference recovery restore skipped: token={token} metadata=missing")
            return
        fail("preference recovery metadata is missing")

    metadata = read_metadata(metadata_path)
    if metadata.get("domain") != domain or metadata.get("token") != token:
        fail("preference recovery identity mismatch")
    if backup_path.is_symlink() or not backup_path.is_file():
        fail("preference recovery backup is missing or unsafe")
    mode = stat.S_IMODE(backup_path.stat().st_mode)
    if mode & 0o077:
        fail("preference recovery backup permissions are too broad")
    payload = backup_path.read_bytes()
    if metadata.get("backupSha256") != sha256(payload):
        fail("preference recovery backup checksum mismatch")

    existed = metadata.get("existed")
    if existed is True:
        expected = semantic_plist(payload)
        imported = run_defaults("import", domain, str(backup_path))
        if imported.returncode != 0:
            fail("preferences import failed; durable recovery backup was preserved")
        verification = run_defaults("export", domain, "-")
        if verification.returncode != 0 or not verification.stdout:
            fail("restored preferences could not be exported; recovery backup was preserved")
        if semantic_plist(verification.stdout) != expected:
            fail("restored preferences differ from the captured plist; recovery backup was preserved")
    elif existed is False:
        run_defaults("delete", domain)
        if domain_appears_to_exist(domain):
            fail("previously absent preferences domain remains; recovery metadata was preserved")
    else:
        fail("preference recovery existed flag is invalid")

    backup_path.unlink()
    metadata_path.unlink()
    print(f"Preference recovery restore verified: token={token}")


def fake_defaults_script(root: Path) -> Path:
    script = root / "defaults"
    script.write_text(
        """#!/usr/bin/env python3
import os
import plistlib
import shutil
import sys
from pathlib import Path
state = Path(os.environ['FAKE_DEFAULTS_STATE'])
command = sys.argv[1]
if command == 'export':
    if not state.exists():
        raise SystemExit(1)
    sys.stdout.buffer.write(state.read_bytes())
elif command == 'read':
    raise SystemExit(0 if state.exists() else 1)
elif command == 'import':
    if os.environ.get('FAKE_DEFAULTS_FAIL_IMPORT') == '1':
        raise SystemExit(9)
    shutil.copyfile(sys.argv[3], state)
elif command == 'delete':
    state.unlink(missing_ok=True)
else:
    raise SystemExit(2)
""",
        encoding="utf-8",
    )
    script.chmod(0o700)
    return script


def self_test() -> None:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        state = root / "state.plist"
        recovery = root / "recovery"
        fake = fake_defaults_script(root)
        old_defaults = os.environ.get("MACVITALS_DEFAULTS_BIN")
        old_state = os.environ.get("FAKE_DEFAULTS_STATE")
        os.environ["MACVITALS_DEFAULTS_BIN"] = str(fake)
        os.environ["FAKE_DEFAULTS_STATE"] = str(state)
        try:
            original = plistlib.dumps({"value": 42}, fmt=plistlib.FMT_XML)
            state.write_bytes(original)
            capture("test.domain", "existing", recovery)
            state.write_bytes(plistlib.dumps({"value": 99}, fmt=plistlib.FMT_XML))
            restore("test.domain", "existing", recovery, allow_missing=False)
            assert plistlib.loads(state.read_bytes()) == {"value": 42}
            assert not existing_recovery(recovery)

            state.unlink()
            capture("test.domain", "absent", recovery)
            state.write_bytes(plistlib.dumps({"created": True}, fmt=plistlib.FMT_XML))
            restore("test.domain", "absent", recovery, allow_missing=False)
            assert not state.exists()
            assert not existing_recovery(recovery)

            state.write_bytes(original)
            capture("test.domain", "failed-import", recovery)
            os.environ["FAKE_DEFAULTS_FAIL_IMPORT"] = "1"
            try:
                restore("test.domain", "failed-import", recovery, allow_missing=False)
            except SystemExit:
                pass
            else:
                raise AssertionError("failing import unexpectedly passed")
            assert existing_recovery(recovery)
            os.environ.pop("FAKE_DEFAULTS_FAIL_IMPORT", None)
        finally:
            if old_defaults is None:
                os.environ.pop("MACVITALS_DEFAULTS_BIN", None)
            else:
                os.environ["MACVITALS_DEFAULTS_BIN"] = old_defaults
            if old_state is None:
                os.environ.pop("FAKE_DEFAULTS_STATE", None)
            else:
                os.environ["FAKE_DEFAULTS_STATE"] = old_state
            os.environ.pop("FAKE_DEFAULTS_FAIL_IMPORT", None)
    print("Physical preference recovery guard self-test passed")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    subcommands = result.add_subparsers(dest="command", required=True)
    for name in ("capture", "restore"):
        command = subcommands.add_parser(name)
        command.add_argument("--domain", required=True)
        command.add_argument("--token", required=True)
        command.add_argument("--root", type=Path, default=default_root())
        if name == "restore":
            command.add_argument("--allow-missing", action="store_true")
    subcommands.add_parser("self-test")
    return result


def main() -> int:
    args = parser().parse_args()
    if args.command == "self-test":
        self_test()
    elif args.command == "capture":
        capture(args.domain, args.token, args.root)
    elif args.command == "restore":
        restore(args.domain, args.token, args.root, args.allow_missing)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
