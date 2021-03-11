#!/usr/bin/env python3

import argparse
import sys


def generate_file(ipv6, ipv6_prefix, ipv6_gateway):
    return (
        f"auto eth0\n"
        f"iface eth0 inet6 static\n"
        f"mtu 1500\n"
        f"address {ipv6}\n"
        f"netmask {ipv6_prefix}\n"
        f"post-up /sbin/ip -6 route add {ipv6_gateway} dev eth0\n"
        f"post-up /sbin/ip -6 route add default via {ipv6_gateway} dev eth0\n"
        f"pre-down /sbin/ip -6 route del default via {ipv6_gateway} dev eth0\n"
        f"pre-down /sbin/ip -6 route del {ipv6_gateway} dev eth0\n"
    )


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Get a config file for your static IPV6 on a Debian 10 Ovh server.\n"
            "Just redirect output on /etc/network/interfaces.d/51-cloud-init-ipv6.cfg\n"
            "Recommended to backup /etc/network/interfaces before"
        ),
        epilog="Use `service networking restart` or `systemctl restart networking` then.\n"
    )
    parser.add_argument("ipv6", help="your IPV6 address")
    parser.add_argument("ipv6_prefix", help="IPV6 prefix should be 64 by default")
    parser.add_argument("ipv6_gateway", help="your IPV6 gateway")
    args = parser.parse_args(args=None if sys.argv[1:] else ["--help"])
    print(generate_file(args.ipv6, args.ipv6_prefix, args.ipv6_gateway))


if __name__ == "__main__":
    main()
