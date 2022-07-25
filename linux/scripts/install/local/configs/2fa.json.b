{"install":[
["download", "https://github.com/rsc/2fa/archive/refs/tags/v1.2.0.tar.gz", "d8db6b9a714c9146a4b82fd65b54f9bdda3e58380bce393f45e1ef49e4e9bee5", "2fa-1.2.0.tar.gz"],
["tar.xz", "2fa-1.2.0.tar.gz", ".local/external/2fa"],
["cd", ".local/external/2fa/2fa-1.2.0"],
["comment", "`go mod vendor` does not install everything, the clipboard module is already included, it only reconstructs a missing file"],
["set", "VENDOR_MODULES.TXT", "# github.com/atotto/clipboard v0.1.2\n## explicit\ngithub.com/atotto/clipboard"],
[""]
["hexec", ".local/bin/go", ["go", "build", "-mod", "vendor"]],
["lns", ".local/external/2fa/2fa-1.2.0/2fa", ".local/bin/2fa"]
]}
