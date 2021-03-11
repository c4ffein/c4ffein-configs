#!/usr/bin/env python3

import os
from pathlib import Path
import tarfile
import io
from hashlib import sha256

from helpers import get_aws_data


def install_local_scw():
    aws_data = get_aws_data(
        repo=b"scaleway/scaleway-cli",
        release_name_start="scw-",
        release_name_end="-linux-x86_64",
        version="v2.2.3",
    )
    # We can now read and write exec from .tar.gz file
    exe_io = io.BytesIO(aws_data)
    content = exe_io.read()

    h = sha256()
    h.update(content)
    if h.digest().hex() != "851fa7ec9fca593345cfb3c7d4946711275965741010234883dd1dca991a5486":
        raise Exception("BAD EXE HASH")

    scw_drop_dir = Path.home() / ".local/bin"
    scw_drop_dir.mkdir(parents=True, exist_ok=True)
    scw_drop_path = scw_drop_dir / "scw"
    with open(scw_drop_path, mode="wb") as scw_drop:
        scw_drop.write(content)
    os.chmod(scw_drop_path, 0o700)


if __name__ == "__main__":
    install_local_scw()
