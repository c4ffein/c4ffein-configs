#!/usr/bin/env python3

import os
from pathlib import Path
import tarfile
import io

from helpers import get_aws_data


def install_local_stripe():
    aws_data = get_aws_data(
        repo=b"stripe/stripe-cli",
        release_name_start="stripe_",
        release_name_end="_linux_x86_64.tar.gz",
    )
    # We can now read and write exec from .tar.gz file
    tar_io = io.BytesIO(aws_data)
    with tarfile.open(fileobj=tar_io) as tar:
        for member in tar:
            if member.name == "stripe":
                stripe_exec = tar.extractfile(member)
                stripe_drop_dir = Path.home() / ".local/bin"
                stripe_drop_dir.mkdir(parents=True, exist_ok=True)
                stripe_drop_path = stripe_drop_dir / "stripe"
                with open(stripe_drop_path, mode="wb") as stripe_drop:
                    content = stripe_exec.read()
                    stripe_drop.write(content)
                os.chmod(stripe_drop_path, 0o700)


if __name__ == "__main__":
    install_local_stripe()
