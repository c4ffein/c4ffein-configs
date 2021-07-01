#!/usr/bin/env python3

import re


def print_secured_config_file(file_path):
    r = []
    pass_disabled_found = False
    with open(file_path, "r") as bigsad_f:
        for l in bigsad_f.readlines():
            m = re.match("([^#]*PasswordAuthentication.*yes.*)", l)
            if m:
                r.append(f"#{m[1]}")
            else:
                m = re.match("[#]*([^#]*PasswordAuthentication.*no.*)", l)
                if m:
                    r.append(f"{m[1]}")
                    pass_disabled_found = True
                else:
                    r.append(l)
    if not pass_disabled_found:
        r.append("PasswordAuthentication no")
    print("".join(r))


if __name__ == "__main__":
    print_secured_config_file("/etc/ssh/ssh_config")
