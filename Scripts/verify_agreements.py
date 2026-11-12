"""Check published agreement bytes and print matching client configuration."""

import argparse
import hashlib
import json
import re
from pathlib import Path
from urllib.parse import urlsplit
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "App" / "CommunityContent"
SOURCE = ROOT / "Docs" / "Backend" / "Agreements"
LIMIT = 1_048_576
PATH_PATTERN = re.compile(r"/storage/v1/object/public/agreements/[A-Za-z0-9][A-Za-z0-9_-]*/[A-Za-z0-9][A-Za-z0-9_-]*[.]pdf")


def verified_pdf(filename, address, host):
    parsed = urlsplit(address)
    if (parsed.scheme != "https" or parsed.netloc != host or
            parsed.query or parsed.fragment or parsed.geturl() != address or
            not PATH_PATTERN.fullmatch(parsed.path)):
        raise ValueError(f"{filename} must use a versioned PDF URL on the configured project.")

    text = (SOURCE / filename.replace(".pdf", ".md")).read_text(encoding="utf-8")
    if "Draft for owner review" in text:
        raise ValueError(f"{filename} is still marked as a draft.")

    local = (RESOURCES / filename).read_bytes()
    if not local.startswith(b"%PDF-") or len(local) > LIMIT:
        raise ValueError(f"{filename} must be a bundled PDF within the bucket size limit.")

    with urlopen(address, timeout=12) as response:
        if (response.status != 200 or response.url != address or
                response.headers.get_content_type() != "application/pdf"):
            raise ValueError(f"The published {filename} URL did not return the expected PDF.")
        if response.read(LIMIT + 1) != local:
            raise ValueError(f"The public and bundled {filename} bytes differ.")

    return parsed.path.rsplit("/", 1)[0], hashlib.sha256(local).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--terms-url", required=True)
    parser.add_argument("--privacy-url", required=True)
    args = parser.parse_args()
    config = json.loads((RESOURCES / "Backend.json").read_text(encoding="utf-8"))
    host = urlsplit(config["url"]).netloc
    if args.terms_url == args.privacy_url:
        parser.error("Terms and Privacy must use separate PDF URLs.")
    try:
        terms_dir, terms_hash = verified_pdf("Terms.pdf", args.terms_url, host)
        privacy_dir, privacy_hash = verified_pdf("Privacy.pdf", args.privacy_url, host)
        if terms_dir != privacy_dir:
            raise ValueError("Both PDFs must use the same version directory.")
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")
    fingerprint = (
        f"agreements-v1\nterms\n{args.terms_url}\n{terms_hash}\n"
        f"privacy\n{args.privacy_url}\n{privacy_hash}\n"
    )
    print(json.dumps({
        "agreementRevision": "sha256:" + hashlib.sha256(fingerprint.encode()).hexdigest(),
        "termsURL": args.terms_url,
        "privacyURL": args.privacy_url,
    }, indent=2))


if __name__ == "__main__":
    main()
