"""App Store Connect helper for Ivrit Together (com.appsbybros.ivrittogether), adapted from
the Minik apps' Scripts/appstore-register-bundle-ids.py for this single app.

  check [--register]  TestFlight pre-flight on Linux: the API key works, can sign in the cloud
                      (Admin role), the App ID exists under APPLE_TEAM_ID (registered first with
                      --register when missing) and the App Store Connect app record exists.
  register            Registers the App ID when missing and reports the app record.
  next-build          Prints a build number above every build already uploaded.
  app-id              Prints the app's Apple ID (digits), or an empty line without an app record.
  upload <ipa>        Uploads an exported .ipa through the App Store Connect build upload API.

Needs ASC_KEY_ID, ASC_ISSUER_ID and ASC_PRIVATE_KEY (the .p8 text) in the environment, and
APPLE_TEAM_ID for check. Requires PyJWT with cryptography. Prints no secret values.
"""
import json
import os
import plistlib
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

import jwt

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.appsbybros.ivrittogether"
APP_NAME = "Ivrit Together"
RECORD_HELP = ("In App Store Connect, open Apps > + > New App: platform iOS, name \"Ivrit Together: Learn Hebrew\" "
               "(or another available name), primary language English (U.S.), bundle ID "
               f"{BUNDLE_ID}, and any unique SKU such as ivrit-together-ios.")


def token():
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
        os.environ["ASC_PRIVATE_KEY"],
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def call(method, path, body=None):
    # Busy or failing Apple servers (429/5xx) get up to four more tries.
    for attempt in range(5):
        request = urllib.request.Request(
            API + path,
            method=method,
            data=None if body is None else json.dumps(body).encode("utf-8"),
            headers={"Authorization": "Bearer " + token(), "Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=120) as response:
                return response.status, json.loads(response.read() or b"{}")
        except urllib.error.HTTPError as error:
            payload = error.read()
            if error.code in (429, 500, 502, 503, 504) and attempt < 4:
                time.sleep(2 ** attempt)
                continue
            try:
                return error.code, json.loads(payload or b"{}")
            except json.JSONDecodeError:
                return error.code, {"raw": payload.decode("utf-8", "replace")}
        except (urllib.error.URLError, TimeoutError) as error:
            if attempt < 4:
                time.sleep(2 ** attempt)
                continue
            return 0, {"errors": [{"detail": f"network error: {error}"}]}
    return 0, {"errors": [{"detail": "no response"}]}


def errors_text(payload):
    if not isinstance(payload, dict):
        return str(payload)
    return "; ".join(item.get("detail") or item.get("title", "") for item in payload.get("errors", []))


def require_key():
    for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY"):
        if not os.environ.get(name, "").strip():
            print(f"Missing required secret: {name}")
            return False
    return True


def find_bundle_id():
    """Returns (HTTP status, the bundleIds resource for BUNDLE_ID or None)."""
    query = urllib.parse.urlencode({"filter[identifier]": BUNDLE_ID, "limit": 200})
    status, payload = call("GET", f"/bundleIds?{query}")
    if status != 200:
        return status, payload
    matches = [item for item in payload.get("data", []) if item["attributes"]["identifier"] == BUNDLE_ID]
    return status, (matches[0] if matches else None)


def register_bundle_id():
    status, payload = call("POST", "/bundleIds", {
        "data": {"type": "bundleIds", "attributes": {"identifier": BUNDLE_ID, "name": APP_NAME, "platform": "IOS"}}
    })
    if status != 201:
        return None, f"registration failed (HTTP {status}): {errors_text(payload)}"
    return payload["data"], None


def find_app():
    """Returns (HTTP status, App Store Connect app id or None) for an exact bundle ID match."""
    query = urllib.parse.urlencode({"filter[bundleId]": BUNDLE_ID})
    status, payload = call("GET", f"/apps?{query}")
    if status != 200:
        return status, payload
    ids = [item["id"] for item in payload.get("data", []) if item.get("attributes", {}).get("bundleId") == BUNDLE_ID]
    return status, (ids[0] if ids else None)


def store_versions(app_id):
    query = urllib.parse.urlencode({"filter[platform]": "IOS", "limit": 10})
    status, payload = call("GET", f"/apps/{app_id}/appStoreVersions?{query}")
    if status != 200:
        return [f"(could not read versions: HTTP {status})"]
    texts = []
    for item in payload.get("data", []):
        attributes = item.get("attributes", {})
        state = attributes.get("appVersionState") or attributes.get("appStoreState") or "?"
        texts.append(f"{attributes.get('versionString')} {state}")
    return texts


def highest_build(app_id):
    """The highest numeric build number uploaded for the app (0 if none), or None if unreadable."""
    query = urllib.parse.urlencode({"filter[app]": app_id, "sort": "-uploadedDate", "limit": 200,
                                    "fields[builds]": "version"})
    status, payload = call("GET", f"/builds?{query}")
    if status != 200:
        return None
    numbers = [int(item["attributes"]["version"]) for item in payload.get("data", [])
               if str(item.get("attributes", {}).get("version", "")).isdigit()]
    return max(numbers, default=0)


def register():
    if not require_key():
        return 1
    status, existing = find_bundle_id()
    if status != 200:
        print(f"{BUNDLE_ID}: could not list App IDs (HTTP {status}): {errors_text(existing)}")
        return 1
    if existing:
        print(f"{BUNDLE_ID}: App ID already registered")
    else:
        created, problem = register_bundle_id()
        if problem:
            print(f"{BUNDLE_ID}: {problem}")
            return 1
        print(f"{BUNDLE_ID}: App ID registered")
    status, app_id = find_app()
    if status == 200 and app_id:
        print(f"{BUNDLE_ID}: App Store Connect app record exists (Apple ID {app_id})")
    elif status == 200:
        print(f"{BUNDLE_ID}: no App Store Connect app record yet. {RECORD_HELP}")
    else:
        print(f"{BUNDLE_ID}: could not check the app record (HTTP {status}): {errors_text(app_id)}")
    return 0


def check(register_missing):
    """Fast pre-flight for the TestFlight upload; uses no macOS minutes."""
    if not require_key():
        return 1
    team_id = "".join(os.environ.get("APPLE_TEAM_ID", "").split())
    problems = []
    status, payload = call("GET", "/apps?limit=1")
    if status != 200:
        print(f"The App Store Connect API key was not accepted (HTTP {status}): {errors_text(payload)}")
        print("Check that ASC_KEY_ID, ASC_ISSUER_ID and the full ASC_PRIVATE_KEY text belong to the same Team key.")
        return 1
    print("API key accepted.")
    status, payload = call("GET", "/certificates?limit=1")
    if status != 200:
        problems.append(f"The key cannot read certificates (HTTP {status}): {errors_text(payload)}. "
                        "Cloud signing needs a Team key with the Admin role.")
    else:
        print("Key can read certificates and profiles.")
    # Only Admin keys may read Users and Access; Xcode's cloud signing for the App Store
    # also needs the Admin role.
    status, payload = call("GET", "/users?limit=1")
    if status == 200:
        print("Key has the Admin role (needed for cloud signing).")
    elif status == 403:
        problems.append("The key does not have the Admin role, which Xcode's cloud signing needs. In App Store "
                        "Connect > Users and Access > Integrations > Team Keys, create a key with Admin access and "
                        "update the ASC_KEY_ID, ASC_ISSUER_ID and ASC_PRIVATE_KEY secrets.")
    else:
        print(f"Could not confirm the key's role (HTTP {status}): {errors_text(payload)}")

    status, bundle = find_bundle_id()
    if status != 200:
        problems.append(f"Could not list App IDs (HTTP {status}): {errors_text(bundle)}")
    elif bundle is None and register_missing:
        bundle, problem = register_bundle_id()
        if problem:
            problems.append(f"{BUNDLE_ID}: {problem}")
        else:
            print(f"{BUNDLE_ID}: App ID registered.")
    if status == 200 and bundle is None and not register_missing:
        problems.append(f"{BUNDLE_ID}: App ID not found. Run `python3 Scripts/appstore.py register`, or the "
                        "TestFlight workflow, which registers it.")
    if bundle:
        seed_id = bundle.get("attributes", {}).get("seedId")
        if seed_id and team_id and seed_id != team_id:
            problems.append(f"{BUNDLE_ID}: the App ID belongs to team {seed_id}, but the APPLE_TEAM_ID secret is "
                            f"different. Set APPLE_TEAM_ID to {seed_id}.")
        else:
            print(f"{BUNDLE_ID}: App ID registered under the APPLE_TEAM_ID team.")

    status, app_id = find_app()
    if status == 200 and app_id:
        print(f"App Store Connect record exists (Apple ID {app_id}).")
        # An upload must carry a higher version than the last approved one (ITMS-90062).
        print("App Store versions: " + (", ".join(store_versions(app_id)) or "none yet"))
    elif status == 200:
        problems.append(f"Create the App Store Connect app record for {BUNDLE_ID}. {RECORD_HELP}")
    else:
        problems.append(f"Could not check the app record (HTTP {status}): {errors_text(app_id)}")

    for problem in problems:
        print("PROBLEM: " + problem)
    return 1 if problems else 0


def next_build():
    """Prints one build number above every build App Store Connect has for the app.
    Only the number goes to stdout; notes go to stderr."""
    if not require_key():
        return 1
    highest = 0
    status, app_id = find_app()
    if status != 200 or not app_id:
        print("No app record, so no earlier builds", file=sys.stderr)
    else:
        number = highest_build(app_id)
        if number is None:
            print("Could not read earlier builds", file=sys.stderr)
        else:
            print(f"Highest uploaded build: {number}", file=sys.stderr)
            highest = number
    print(highest + 1)
    return 0


def app_id_command():
    if not require_key():
        return 1
    status, app_id = find_app()
    if status == 200 and app_id and str(app_id).isdigit():
        print(app_id)
    else:
        print("No App Store Connect app record found", file=sys.stderr)
        print("")
    return 0


def put_chunk(operation, data):
    headers = {item["name"]: item["value"] for item in operation.get("requestHeaders") or []}
    detail = ""
    for attempt in range(5):
        request = urllib.request.Request(operation["url"], method=operation["method"], data=data, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                response.read()
                return None
        except urllib.error.HTTPError as error:
            detail = f"HTTP {error.code}: {error.read()[:500].decode('utf-8', 'replace')}"
            if error.code not in (429, 500, 502, 503, 504):
                return detail
        except (urllib.error.URLError, TimeoutError) as error:
            detail = f"network error: {error}"
        if attempt < 4:
            time.sleep(2 ** attempt)
    return detail


def upload(ipa_path):
    """Uploads an exported .ipa through the App Store Connect build upload API, the path that
    needs no Xcode account and cannot pick a look-alike bundle ID."""
    if not require_key():
        return 1
    with zipfile.ZipFile(ipa_path) as archive:
        names = [item for item in archive.namelist() if re.fullmatch(r"Payload/[^/]+[.]app/Info[.]plist", item)]
        if not names:
            print(f"{ipa_path}: no Payload/*.app/Info.plist inside the .ipa")
            return 1
        info = plistlib.loads(archive.read(names[0]))
    bundle_id = info["CFBundleIdentifier"]
    version = info["CFBundleShortVersionString"]
    build = info["CFBundleVersion"]
    if bundle_id != BUNDLE_ID:
        print(f"The .ipa is {bundle_id}, not {BUNDLE_ID}; nothing was uploaded.")
        return 1
    print(f"Uploading {bundle_id} {version} ({build}) from {os.path.basename(ipa_path)}")

    status, app_id = find_app()
    if status != 200 or not app_id:
        print(f"No App Store Connect app record for {bundle_id} (HTTP {status}).")
        return 1

    status, payload = call("POST", "/buildUploads", {
        "data": {
            "type": "buildUploads",
            "attributes": {"platform": "IOS", "cfBundleShortVersionString": version, "cfBundleVersion": build},
            "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
        }
    })
    if status != 201:
        print(f"Could not start the build upload (HTTP {status}): {errors_text(payload)}")
        return 1
    upload_id = payload["data"]["id"]

    file_size = os.path.getsize(ipa_path)
    status, payload = call("POST", "/buildUploadFiles", {
        "data": {
            "type": "buildUploadFiles",
            "attributes": {"fileName": os.path.basename(ipa_path), "fileSize": file_size,
                           "assetType": "ASSET", "uti": "com.apple.ipa"},
            "relationships": {"buildUpload": {"data": {"type": "buildUploads", "id": upload_id}}},
        }
    })
    if status != 201:
        print(f"Could not register the .ipa file (HTTP {status}): {errors_text(payload)}")
        return 1
    file_id = payload["data"]["id"]
    operations = payload["data"].get("attributes", {}).get("uploadOperations") or []
    if not operations:
        print("App Store Connect returned no upload operations.")
        return 1

    with open(ipa_path, "rb") as handle:
        for index, operation in enumerate(operations, 1):
            handle.seek(operation["offset"])
            failure = put_chunk(operation, handle.read(operation["length"]))
            if failure:
                print(f"Part {index}/{len(operations)} failed: {failure}")
                return 1
    print(f"Sent {file_size} bytes in {len(operations)} parts.")

    status, payload = call("PATCH", f"/buildUploadFiles/{file_id}", {
        "data": {"type": "buildUploadFiles", "id": file_id, "attributes": {"uploaded": True}}
    })
    if status != 200:
        print(f"Could not complete the upload (HTTP {status}): {errors_text(payload)}")
        return 1

    # Apple checks the package within minutes; a rejection shows here instead of only by email.
    state = {}
    for _ in range(12):
        time.sleep(15)
        status, payload = call("GET", f"/buildUploads/{upload_id}")
        if status != 200:
            continue
        state = payload["data"].get("attributes", {}).get("state") or {}
        value = state.get("state") if isinstance(state, dict) else state
        if value == "FAILED":
            print("App Store Connect rejected the build:")
            print(json.dumps(state, indent=2))
            return 1
        if value == "COMPLETE":
            break
    print("App Store Connect state: " + json.dumps(state))
    print(f"Uploaded {bundle_id} build {build}. TestFlight shows it after Apple's processing.")
    return 0


def main(arguments):
    command = arguments[0] if arguments else ""
    if command == "check":
        return check("--register" in arguments[1:])
    if command == "register":
        return register()
    if command == "next-build":
        return next_build()
    if command == "app-id":
        return app_id_command()
    if command == "upload" and len(arguments) == 2:
        return upload(arguments[1])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
