#!/usr/bin/env python3
"""Test-only fault injector for the real transaction helper."""

import importlib.util
import sys
from pathlib import Path


module_path = Path(__file__).resolve().parents[1] / "engine/lib/transaction.py"
spec = importlib.util.spec_from_file_location("theme_transaction_under_test", module_path)
transaction = importlib.util.module_from_spec(spec)
spec.loader.exec_module(transaction)


def main() -> int:
    command, mode, txn_path = sys.argv[1:4]
    txn = Path(txn_path)
    original_atomic = transaction.atomic_file
    original_cleanup = transaction.cleanup

    if mode in {"install_first", "install_second", "rollback_failure", "copy", "rename"} and command == "install":
        limit = 1 if mode == "install_first" else 2
        count = 0

        def fail_at_install(*args, **kwargs):
            nonlocal count
            count += 1
            if count == limit:
                if mode == "copy":
                    original_copy = transaction.shutil.copy2
                    try:
                        transaction.shutil.copy2 = lambda *a, **k: (_ for _ in ()).throw(OSError("injected copy failure"))
                        return original_atomic(*args, **kwargs)
                    finally:
                        transaction.shutil.copy2 = original_copy
                if mode == "rename":
                    original_replace = transaction.os.replace
                    try:
                        transaction.os.replace = lambda *a, **k: (_ for _ in ()).throw(OSError("injected rename failure"))
                        return original_atomic(*args, **kwargs)
                    finally:
                        transaction.os.replace = original_replace
                raise OSError(f"injected install write {count} failure")
            return original_atomic(*args, **kwargs)

        transaction.atomic_file = fail_at_install
    elif mode == "mkdir" and command == "install":
        def fail_directory(*args, **kwargs):
            raise OSError("injected destination directory creation failure")

        transaction.ensure_parents = fail_directory
    elif mode in {"commit_before", "commit_after", "state_rollback_failure"} and command == "commit":
        def fail_commit(*args, **kwargs):
            if mode in {"commit_after", "state_rollback_failure"}:
                original_atomic(*args, **kwargs)
            raise OSError("injected state update failure")

        transaction.atomic_file = fail_commit
    elif mode in {"rollback_failure", "state_rollback_failure"} and command == "rollback":
        def fail_restore(dest, source=None, data=None):
            if mode == "rollback_failure" or str(dest).endswith("current_theme"):
                raise OSError("injected rollback write failure")
            return original_atomic(dest, source=source, data=data)

        transaction.atomic_file = fail_restore
    elif mode in {"cleanup", "partial_cleanup"} and command == "finish":
        def fail_cleanup(*args, **kwargs):
            if mode == "partial_cleanup":
                transaction.shutil.rmtree(txn / "stage")
            raise OSError("injected cleanup failure")

        transaction.cleanup = fail_cleanup
    elif mode == "rollback_cleanup" and command == "rollback":
        def fail_cleanup(*args, **kwargs):
            raise OSError("injected rollback cleanup failure")

        transaction.cleanup = fail_cleanup

    try:
        if command == "install":
            transaction.install(txn)
        elif command == "commit":
            transaction.commit(txn)
        elif command == "rollback":
            transaction.rollback(txn)
        elif command == "finish":
            transaction.finish(txn)
        else:
            raise ValueError("unknown injection command")
        return 0
    except (OSError, transaction.TransactionError) as error:
        print(f"injected transaction failure: {error}", file=sys.stderr)
        return 1
    finally:
        transaction.atomic_file = original_atomic
        transaction.cleanup = original_cleanup


if __name__ == "__main__":
    raise SystemExit(main())
