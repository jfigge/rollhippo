#!/usr/bin/env python3
"""Send a built App Bundle to Google Play. The Android half of `make upload`.

Apple gives you `xcrun altool`, which ships with Xcode and takes a key you
already have. Google gives you a REST API and expects you to reach it through
`fastlane`, or the Google API client libraries, or Gradle Play Publisher —
three toolchains, none of which this project has, all of which would be
installed to make four HTTP requests.

So this is those four requests. Nothing outside the standard library, except
`openssl` for the one thing Python cannot do unaided: sign a JWT with RS256.
There is no RSA in the stdlib, and adding `cryptography` to sign one token a
release would be the same bargain refused above.

WHAT IT DOES, in the order the API insists on:

    1. open an "edit"  — a transaction. Everything below happens inside it and
                         none of it is visible on Play until the commit.
    2. upload the .aab — which is what tells Play the versionCode; the number
                         is read back from the response rather than parsed out
                         of the bundle here, because Play's answer is the one
                         that counts.
    3. assign a track  — internal, alpha, beta or production, with the release
                         status. This is the step that decides who can install
                         it.
    4. commit          — one call, and the edit becomes real. Anything that
                         fails before this leaves Play exactly as it was, which
                         is the whole reason the API is shaped this way.

FIRST UPLOAD. Google requires an app's first bundle to go through the Console
by hand; the API returns 403 until one has. That is not a bug here and no
amount of permissions fixes it — upload once in the browser, then this works
forever after.
"""

from __future__ import annotations

import argparse
import base64
import json
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

TOKEN_URL = "https://oauth2.googleapis.com/token"
API = "https://androidpublisher.googleapis.com/androidpublisher/v3"
UPLOAD_API = "https://androidpublisher.googleapis.com/upload/androidpublisher/v3"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"

# Play's own vocabulary, and the order is the order of increasing exposure.
# `internal` is the fast one — available to its testers within minutes and not
# reviewed — which is why it is the default here. `production` is deliberately
# spellable but never the default: a release target you can reach by forgetting
# a flag is a release target that will one day be reached by forgetting a flag.
TRACKS = ("internal", "alpha", "beta", "production")


def b64(data: bytes) -> str:
    """base64url, unpadded — which is what JWT means by base64."""
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def access_token(key: dict[str, Any]) -> str:
    """Trade the service account's private key for an hour's access token.

    The assertion is a JWT the account signs about itself: I am `client_email`,
    I want `scope`, this is for Google's token endpoint, and it expires in an
    hour. Google verifies it against the public half it already holds and hands
    back a bearer token.
    """
    now = int(time.time())
    header = {"alg": "RS256", "typ": "JWT"}
    claims = {
        "iss": key["client_email"],
        "scope": SCOPE,
        "aud": TOKEN_URL,
        "iat": now,
        # An hour is the maximum Google accepts, and there is no reason to ask
        # for less: the token dies with the process either way.
        "exp": now + 3600,
    }
    signing_input = (
        b64(json.dumps(header).encode()) + "." + b64(json.dumps(claims).encode())
    ).encode("ascii")

    # The key goes to a file because `openssl dgst -sign` will not take it on
    # stdin — stdin is already the data being signed. Mode 0600 and deleted on
    # the way out, which is the best that can be done for a secret that has to
    # touch a filesystem at all.
    with tempfile.NamedTemporaryFile("w", suffix=".pem", delete=True) as pem:
        Path(pem.name).chmod(0o600)
        pem.write(key["private_key"])
        pem.flush()
        signed = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", pem.name],
            input=signing_input,
            capture_output=True,
            check=True,
        ).stdout

    assertion = signing_input.decode() + "." + b64(signed)
    body = urllib.parse.urlencode(
        {
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": assertion,
        }
    ).encode()
    with urllib.request.urlopen(
        urllib.request.Request(TOKEN_URL, data=body), timeout=60
    ) as response:
        return json.load(response)["access_token"]


def call(
    token: str,
    method: str,
    url: str,
    *,
    body: bytes | None = None,
    content_type: str = "application/json",
    timeout: int = 600,
) -> dict[str, Any]:
    """One API call, with Google's error text surfaced rather than swallowed.

    A failure here is almost always a sentence worth reading — the wrong
    package name, a service account nobody granted anything to, a versionCode
    Play has seen before. `HTTPError` on its own says only "400", so the body
    is what gets raised.
    """
    request = urllib.request.Request(url, data=body, method=method)
    request.add_header("Authorization", f"Bearer {token}")
    if body is not None:
        request.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")
        raise SystemExit(
            f"play_upload: {method} {url}\n  HTTP {error.code}\n  {detail}"
        ) from None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--key", required=True, help="service account JSON")
    parser.add_argument("--aab", required=True, help="the bundle to send")
    parser.add_argument("--package", required=True, help="applicationId")
    parser.add_argument("--track", default="internal", choices=TRACKS)
    parser.add_argument(
        "--status",
        default="completed",
        choices=("completed", "draft"),
        help="completed rolls out to the track's testers; draft parks it",
    )
    parser.add_argument("--release-name", default=None)
    args = parser.parse_args()

    aab = Path(args.aab)
    if not aab.is_file():
        raise SystemExit(f"play_upload: no bundle at {aab}")
    key_path = Path(args.key)
    if not key_path.is_file():
        raise SystemExit(f"play_upload: no service account key at {key_path}")

    key = json.loads(key_path.read_text())
    print(f"authenticating as {key['client_email']}")
    token = access_token(key)

    base = f"{API}/applications/{args.package}/edits"
    edit = call(token, "POST", base)["id"]
    print(f"edit {edit} opened")

    size = aab.stat().st_size
    print(f"uploading {aab.name} ({size / 1_000_000:.1f} MB) — this is the slow part")
    uploaded = call(
        token,
        "POST",
        f"{UPLOAD_API}/applications/{args.package}/edits/{edit}/bundles"
        "?uploadType=media",
        body=aab.read_bytes(),
        content_type="application/octet-stream",
    )
    version = uploaded["versionCode"]
    print(f"accepted as versionCode {version}")

    release: dict[str, Any] = {
        "versionCodes": [str(version)],
        "status": args.status,
    }
    if args.release_name:
        release["name"] = args.release_name
    call(
        token,
        "PUT",
        f"{base}/{edit}/tracks/{args.track}",
        body=json.dumps({"track": args.track, "releases": [release]}).encode(),
    )
    print(f"assigned to {args.track} ({args.status})")

    call(token, "POST", f"{base}/{edit}:commit")
    print(f"committed — versionCode {version} is live on the {args.track} track")
    return 0


if __name__ == "__main__":
    sys.exit(main())
