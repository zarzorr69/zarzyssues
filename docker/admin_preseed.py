#!/usr/bin/env python3
"""One-shot first admin provisioning in a temporary Odysseus Compose container.

Credentials arrive only via stdin. Never replaces an existing auth file.
This is not a password-reset utility.
"""
import os
import sys
from pathlib import Path


def main():
    os.chdir('/app')
    sys.path.insert(0, '/app')
    from src.constants import AUTH_FILE, PASSWORD_MIN_LENGTH
    from core.auth import AuthManager, RESERVED_USERNAMES

    # An existing auth.json may contain an older format; protect it regardless
    # of whether this version of AuthManager can parse it.
    if Path(AUTH_FILE).exists():
        print('EXISTING_AUTH_PRESERVED')
        return 0
    if len(sys.argv) == 2 and sys.argv[1] == 'status':
        print('FIRST_RUN_AVAILABLE')
        return 0
    if len(sys.argv) != 3 or not all(x.isdigit() for x in sys.argv[1:]):
        print('INVALID_INVOCATION', file=sys.stderr)
        return 2
    try:
        username = sys.stdin.readline().rstrip('\r\n').strip().lower()
        password = sys.stdin.readline().rstrip('\r\n')
        if (not isinstance(password, str) or len(password) < PASSWORD_MIN_LENGTH
                or not username or username in RESERVED_USERNAMES or len(username) > 32):
            print('INVALID_CREDENTIAL_POLICY', file=sys.stderr)
            return 2
        if not all(c.isalnum() or c in '._-' for c in username):
            print('INVALID_USERNAME', file=sys.stderr)
            return 2
        manager = AuthManager()
        if manager.is_configured or Path(AUTH_FILE).exists():
            print('EXISTING_AUTH_PRESERVED')
            return 0
        Path(AUTH_FILE).parent.mkdir(parents=True, exist_ok=True)
        if not manager.setup(username, password):
            print('SETUP_REJECTED', file=sys.stderr)
            return 2
        # The Docker image drops privileges from root after normal startup.
        # Ensure a one-shot root provisioning run leaves a writable auth file.
        if os.geteuid() == 0:
            os.chown(AUTH_FILE, int(sys.argv[1]), int(sys.argv[2]))
            os.chmod(AUTH_FILE, 0o600)
        print('ADMIN_CREATED')
        return 0
    except Exception as exc:
        print('ADMIN_SETUP_FAILED: ' + type(exc).__name__, file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
