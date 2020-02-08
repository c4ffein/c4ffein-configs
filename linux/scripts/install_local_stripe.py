#!/usr/bin/env python3

import ssl
import socket
from base64 import b64decode
from hashlib import sha256
import json
import os
from pathlib import Path
from http.client import HTTPResponse
import tarfile
import io


def get(addr, url, cert_checksum, user_agent=None, type=None):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.settimeout(1)
    wrapped_socket = ssl.create_default_context().wrap_socket(sock, server_hostname=addr)

    try:
        wrapped_socket.connect((addr, 443))
    except:
        response = None
    else:
        der_cert_bin = wrapped_socket.getpeercert(True)
        if sha256(der_cert_bin).hexdigest() != cert_checksum:
            raise Exception("Incorrect certificate checksum")

        request_header = b"GET " + url + b" HTTP/1.0\r\nHost: " + addr
        if user_agent:
            request_header += b"\r\nUser-Agent: " + user_agent
        request_header += b"\r\n\r\n"
        wrapped_socket.send(request_header)

        response = HTTPResponse(wrapped_socket)
        response.begin()
        if type == "json":
            if response.getheader("Content-Type") != "application/json; charset=utf-8":
                raise Exception("Content-Type isn't application/json; charset=utf-8")
        body = response.read()
        wrapped_socket.close()

        return response, body


def get_body(addr, url, cert_checksum, user_agent=None, type=None):
    return get(addr, url, cert_checksum, user_agent=user_agent, type=type)[1]


def get_redirect(addr, url, cert_checksum, user_agent=None, type=None):
    response, _ = get(addr, url, cert_checksum, user_agent=user_agent, type=type)
    if response.getheader("Status") != "302 Found":
        raise Exception("Url is no redirect")
    return response.getheader("Location")


def get_site_and_path(url):
    splitted_url = url.split("/")
    site = splitted_url[2]
    path = "/" + "/".join(splitted_url[3:])
    return site, path


def install_local_stripe():
    # Get browser url of latest release
    data = json.loads(
        get_body(
            b"api.github.com",
            b"/repos/stripe/stripe-cli/releases/latest",
            "3aae0a71392f86225ef29fa9fe0c66bd8a85abf5c68ff2d1e333a8ef6feb5287",
            user_agent=b"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/79.0.3945.130 Safari/537.36",
            type=json,
        )
    )
    for asset in data["assets"]:
        if asset["name"].startswith("stripe_") and asset["name"].endswith("_linux_x86_64.tar.gz"):
            browser_download_url = asset["browser_download_url"]

    # Get corresponding S3 url
    site, path = get_site_and_path(browser_download_url)
    aws_url = get_redirect(
        site.encode(),
        path.encode(),
        "3111500c4a66012cdae333ec3fca1c9dde45c954440e7ee413716bff3663c074",
        user_agent=b"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/79.0.3945.130 Safari/537.36",
    )

    # S3 matches the hostname with the bucket name. So we can just use the *.s3.amazonaws.com cert
    site, path = get_site_and_path(aws_url)
    aws_request, aws_data = get(
        site.encode(),
        path.encode(),
        "272fc283bf3edc52f6f3387a9c5247a20c5d7176fe81ec3eaba4b3a8e57f8674",
        user_agent=b"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/79.0.3945.130 Safari/537.36",
    )
    if int(aws_request.getheader("Content-Length")) != len(aws_data):
        raise Exception("Incomplete data for stripe_.tar.gz")

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
