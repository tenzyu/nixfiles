"""Private Linux calls for the Bash library's inherited descriptors."""

import errno
import os
import sys

operation, descriptor, *leaves = sys.argv[1:]
fd = int(descriptor)
try:
    if operation == "fsync" and not leaves:
        os.fsync(fd)
    elif operation == "link" and len(leaves) == 2:
        stage, final = leaves
        if any(leaf in ("", ".", "..") or "/" in leaf for leaf in leaves):
            sys.exit(64)
        os.link(stage, final, src_dir_fd=fd, dst_dir_fd=fd, follow_symlinks=False)
    else:
        sys.exit(64)
except OSError as error:
    if operation == "link" and error.errno == errno.EEXIST:
        result, status = "Conflict", 73
    elif error.errno in (errno.ENOSYS, errno.EOPNOTSUPP, errno.EXDEV) or (
        operation == "link" and error.errno == errno.EPERM
    ) or (
        operation == "fsync" and error.errno == errno.EINVAL
    ):
        result, status = "Unsupported", 69
    elif operation == "link" and error.errno not in (
        errno.EACCES, errno.EDQUOT, errno.EMLINK, errno.ENOSPC, errno.EROFS
    ):
        result, status = "OutcomeUnknown", 75
    else:
        result, status = "IOError", 74
    print(f"{result}: {operation}: errno {error.errno}: {error.strerror}", file=sys.stderr)
    sys.exit(status)
