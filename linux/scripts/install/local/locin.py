#!/usr/bin/env python3
# WARNING: This script is vulnerable to directory traversal attacks.
# Doesn't matter as it is only intended to be used as your local user, by yourself.
# In a PoC state, as it is used only by myself

import os
import sys
import argparse
from pathlib import Path
import tarfile
import io
import json
import urllib.request
import hashlib
from subprocess import check_output, Popen, PIPE, STDOUT



def parse_string(context, lis):
    if isinstance(lis, str):
        return lis if lis[0] != "$" else lis[1:] if lis[1] == "$" else str(context.get(lis[1:]))
    if isinstance(lis, list):
        return "".join(map(lambda l: parse_string(context, l), lis))
    raise Exception("BAD TYPE for parse_string")


def set(context, line):
    print(f"set: {line}")
    context[line[1]] = parse_string(context, line[2])


def download(context, line):
    print(f"download: {line}")
    r = urllib.request.urlopen(parse_string(context, line[1]))
    b = r.read()
    m = hashlib.sha256()
    m.update(b)
    if m.digest().hex() != parse_string(context, line[2]):
        raise Exception("BAD EXE HASH")
    context[parse_string(context, line[3])] = b


def one_tar_xz(context, line):
    print(f"tar.xz: {line}")
    tar_io = io.BytesIO(context.get(parse_string(context, line[1])))
    with tarfile.open(fileobj=tar_io) as tar:
        for member in tar:
            if member.name == parse_string(context, line[2]):
                extractable_file = tar.extractfile(member)
                drop_dir = Path.home() / parse_string(context, line[3])
                drop_dir.mkdir(parents=True, exist_ok=True)
                final_drop_path = drop_dir / parse_string(context, line[4])
                with open(final_drop_path, mode="wb") as final_drop:
                    content = extractable_file.read()
                    final_drop.write(content)
                os.chmod(final_drop_path, 0o700)


def tar_xz_exec(context, line):  # TODO : parse_string?
    print(f"tar_xz_exec: {line}")
    drop_path = parse_string(context, line[2])
    full_drop = (Path.home() / drop_path)
    full_drop.mkdir(parents=True, exist_ok=True)
    p = Popen(["tar", "xJ", "-C", str(full_drop)], stdout=PIPE, stdin=PIPE, stderr=PIPE)
    stdout_data = p.communicate(input=context.get(parse_string(context, line[1])))
    if stdout_data != (b'', b''): print("FAILED_STDOUT : ", stdout_data)


def tar_xz(context, line):  # also works for tar.gz
    print(f"tar.xz: {line}")
    tar_io = io.BytesIO(context.get(parse_string(context, line[1])))
    # with tarfile.open(fileobj=tar_io, mode="r:xz") as tar:  # xz mode may not be available
    with tarfile.open(fileobj=tar_io) as tar:
        subtar = [e for e in tar.getmembers() if e.name.startswith(parse_string(context, len[3]))] if len(line) > 3 and len[3] else None
        tar.extractall(path=Path.home() / parse_string(context, line[2]), members=subtar)


def mkdirp(context, line):
    print(f"mkdirp: {line}")
    (Path.home() / parse_string(context, line[1])).mkdir(parents=True, exist_ok=True)


def mv(context, line):
    print(f"mv: {line}")
    raise NotImplementedError


def lns(context, line):
    print(f"lns: {line}")
    os.symlink(Path.home() / parse_string(context, line[1]), Path.home() / parse_string(context, line[2]))


def comment(context, line):
    print(f"comment: {line}")
    print(f"comment: {line[1]}")


def cd(context, line):
    print(f"cd: {line}")
    os.chdir(Path.home() / parse_string(context, line[1]))


def hexec(context, line):  # TODO : parse_string?
    print(f"hexec: {line}")
    x = check_output([Path.home() / line[1], *(line[2][1:] if len(line[2]) > 1 else [])])
    print(x)


def sexec(context, line):  # TODO : parse_string?
    print(f"sexec: {line}")
    # os.execve(Path.home() / line[1], line[2] if len(line) > 2 else [], {})
    # os.execv(Path.home() / line[1], line[2] if len(line) > 2 else [])  # We want to keep env actually
    x = check_output([line[1], *(line[2][1:] if len(line) > 2 and len(line[2]) > 1 else [])])


def replace_line(context, line):  # file, line number, new line # TODO : parse_string?
    print(f"replace_line: {line}")
    with open(Path.home() / line[1], "r", encoding="utf-8") as file:
        data = file.readlines()
    data[line[2] - 1] = f"{line[3]}\n"
    with open(Path.home() / line[1], "w", encoding="utf-8") as file:
        file.writelines(data)


funcs = {
    "set": set,
    "download": download,
    "tar.xz": tar_xz,
    "exec_tar.xz": tar_xz_exec,
    "mkdirp": mkdirp,
    "mv": mv,
    "lns": lns,
    "comment": comment,
    "cd": cd,
    "hexec": hexec,
    "sexec": sexec,
    "replace line": replace_line,
}


def get_configs():
    dir = Path(os.path.realpath(__file__)).parent / "configs"
    return {n[:-5]: dir / n for n in os.listdir(dir) if n[-5:] == ".json"}  # TODO : raise if no config


def flist(args):
    configs = get_configs()
    for i in configs:
        print(i)


def autocomplete(args):
    instances = get_instances()
    for i in instances:
        if i.startswith(args.autocomplete):
            print(i)


def install(args):
    configs = get_configs()
    tool_name = args.tool
    t = configs.get(tool_name)
    if not t:
        print(f"{tcolors.FAIL}Config not found{tcolors.ENDC}")
        raise Exception
    with open(t) as json_file:
        tj = json.load(json_file)
    instructions = tj.get("install")
    if not instructions:
        print(f"{tcolors.FAIL}Instance has no deploy script{tcolors.ENDC}")
        raise Exception
    context = {}
    for instruction in instructions:
        funcs[instruction[0]](context, instruction) if funcs.get(instruction[0]) else print(
            f"command {instruction[0]} not found"
        )


def main(argv=None):
    parser = argparse.ArgumentParser(description="locin")
    subparsers = parser.add_subparsers(help="sub-command help", dest="command")  # dest needed to identify subcommand

    parser_install = subparsers.add_parser("install", help="deploy help")
    parser_install.add_argument("tool", metavar="TOOL")

    subparsers.add_parser("list", help="list-scripts help")

    parser_autocomplete = subparsers.add_parser("autocomplete", help="autocomplete help")
    parser_autocomplete.add_argument("autocomplete", metavar="INSTANCE_NAME_START")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return
    try:
        return {"install": install, "list": flist, "autocomplete": autocomplete}[args.command](args)
    except Exception as e:
        print(f"Exception: {e}")
        return -1


if __name__ == "__main__":
    sys.exit(main())
