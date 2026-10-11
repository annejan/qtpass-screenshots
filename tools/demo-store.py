#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Anne Jan Brouwer
# SPDX-License-Identifier: GPL-3.0-or-later
"""Create the demo key and password store used for the QtPass screenshots
(the same "Anne Example" store as qtpass.org's tools/screenshots.sh), and
a portable qtpass.ini next to the QtPass executable.

    demo-store.py GPG STORE_DIR INI_PATH

GNUPGHOME must point to an empty, private directory.
"""
import os, pathlib, subprocess, sys

gpg, store, ini = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
# GnuPG does not create GNUPGHOME; loopback pinentry is allowed by default.
# On Windows the workflow creates it, as GNUPGHOME is an MSYS path there.
if os.name != "nt":
    pathlib.Path(os.environ["GNUPGHOME"]).mkdir(mode=0o700, parents=True, exist_ok=True)

def run(*args, **kw):
    return subprocess.run([gpg, "--batch", "--pinentry-mode", "loopback",
                           "--passphrase", "", *args], check=True, **kw)

run("--quick-gen-key", "Anne Example <anne@example.com>", "ed25519",
    "sign,cert", "never")
out = run("--list-keys", "--with-colons", "anne@example.com",
          capture_output=True, text=True).stdout
fpr = next(l.split(":")[9] for l in out.splitlines() if l.startswith("fpr"))
run("--quick-add-key", fpr, "cv25519", "encr", "never")

store.mkdir(parents=True, exist_ok=True)
(store / ".gpg-id").write_text(fpr + "\n")
here = pathlib.Path(__file__).parent
for line in (here / "demo-entries.txt").read_text().splitlines():
    name, content = line.split("|", 1)
    target = store / (name + ".gpg")
    target.parent.mkdir(parents=True, exist_ok=True)
    run("--trust-model", "always", "--encrypt", "--recipient", fpr,
        "--output", str(target),
        input=(content.replace("\\n", "\n") + "\n").encode())

posix = lambda p: str(p).replace("\\", "/")
ini.write_text(f"""[General]
usePass=false
passStore={posix(store)}/
gpgExecutable={posix(gpg)}
useGit=false
useOtp=true
otpMigratedToNative=true
hidePassword=true
useAutoclear=true
autoclearSeconds=45
useAutoclearPanel=false
clipBoardType=1
passwordLength=16
useTrayIcon=false
useTemplate=true
version=1.8.3

[mainwindow]
pos=@Point(40 40)
size=@Size(900 660)
""")
print("store", store, "key", fpr, "ini", ini)
