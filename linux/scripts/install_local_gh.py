#!/usr/bin/env python3

import os
from pathlib import Path
import tarfile
import io

from helpers import get_aws_data


def install_local_gh():
    aws_data = get_aws_data(
        repo=b"cli/cli", release_name_start="gh_", release_name_end="_linux_amd64.tar.gz"
    )
    # We can now read and write exec from .tar.gz file
    tar_io = io.BytesIO(aws_data)
    with tarfile.open(fileobj=tar_io) as tar:
        for member in tar:
            if member.name.endswith("_linux_amd64/bin/gh"):
                gh_exec = tar.extractfile(member)
                gh_drop_dir = Path.home() / ".local/bin"
                gh_drop_dir.mkdir(parents=True, exist_ok=True)
                gh_drop_path = gh_drop_dir / "gh"
                with open(gh_drop_path, mode="wb") as gh_drop:
                    content = gh_exec.read()
                    gh_drop.write(content)
                os.chmod(gh_drop_path, 0o700)


if __name__ == "__main__":
    install_local_gh()
