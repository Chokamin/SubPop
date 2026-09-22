"""Cross-process lease: jobs share it, application updates hold it exclusively."""
import fcntl
import os


class TaskLease:
    def __init__(self, path):
        self.fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)

    def acquire(self):
        try:
            fcntl.flock(self.fd, fcntl.LOCK_SH | fcntl.LOCK_NB)
            return True
        except BlockingIOError:
            return False

    def release(self):
        fcntl.flock(self.fd, fcntl.LOCK_UN)

    def close(self):
        os.close(self.fd)
