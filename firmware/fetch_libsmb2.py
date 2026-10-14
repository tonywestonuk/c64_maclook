# PlatformIO pre-script: fetch libsmb2 (LGPL-2.1, github.com/sahlberg/libsmb2)
# into lib/libsmb2/libsmb2 the first time, at a fixed commit.
import os
import subprocess

Import("env")  # noqa: F821 (provided by PlatformIO)

LIBSMB2_URL = "https://github.com/sahlberg/libsmb2.git"
LIBSMB2_COMMIT = "4cce769"

here = env.subst("$PROJECT_DIR")  # noqa: F821
dest = os.path.join(here, "lib", "libsmb2", "libsmb2")
if not os.path.isdir(os.path.join(dest, "lib")):
    print("Fetching libsmb2 " + LIBSMB2_COMMIT)
    subprocess.check_call(["git", "clone", "-q", LIBSMB2_URL, dest])
    subprocess.check_call(["git", "-C", dest, "checkout", "-q", LIBSMB2_COMMIT])
