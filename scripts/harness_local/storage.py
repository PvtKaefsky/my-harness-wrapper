from collections.abc import Iterator
import contextlib
import ctypes
import json
import os
import stat
import tempfile
import time
from pathlib import Path

from .pack import safe


def owner_check(path: str | Path, allow_profile_owner: bool = False) -> None:
    path = safe(path)
    if os.name != "nt":
        info = path.stat()
        if info.st_uid != os.getuid() or info.st_mode & 0o022:
            raise ValueError("STATE_OWNER_OR_PERMISSIONS_UNSAFE")
        return
    from ctypes import wintypes
    advapi = ctypes.WinDLL("advapi32", use_last_error=True)
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    owner, acl, descriptor = ctypes.c_void_p(), ctypes.c_void_p(), ctypes.c_void_p()
    advapi.GetNamedSecurityInfoW.argtypes = [
        wintypes.LPWSTR, wintypes.DWORD, wintypes.DWORD, ctypes.POINTER(ctypes.c_void_p),
        ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p), ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_void_p)]
    result = advapi.GetNamedSecurityInfoW(str(path), 1, 5, ctypes.byref(owner),
                                        None, ctypes.byref(acl), None, ctypes.byref(descriptor))
    if result:
        raise ValueError("STATE_ACL_UNREADABLE")
    token = wintypes.HANDLE()
    kernel.GetCurrentProcess.restype = wintypes.HANDLE
    advapi.OpenProcessToken.argtypes = [wintypes.HANDLE, wintypes.DWORD, ctypes.POINTER(wintypes.HANDLE)]
    advapi.GetTokenInformation.argtypes = [
        wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD,
        ctypes.POINTER(wintypes.DWORD)]
    advapi.EqualSid.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    advapi.GetAclInformation.argtypes = [ctypes.c_void_p, ctypes.c_void_p, wintypes.DWORD, ctypes.c_int]
    advapi.GetAce.argtypes = [ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(ctypes.c_void_p)]
    advapi.ConvertSidToStringSidW.argtypes = [ctypes.c_void_p, ctypes.POINTER(wintypes.LPWSTR)]
    kernel.LocalFree.argtypes = [ctypes.c_void_p]
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    try:
        if not advapi.OpenProcessToken(kernel.GetCurrentProcess(), 8, ctypes.byref(token)):
            raise ValueError("STATE_OWNER_UNREADABLE")
        size = wintypes.DWORD()
        advapi.GetTokenInformation(token, 1, None, 0, ctypes.byref(size))
        buffer = ctypes.create_string_buffer(size.value)
        if not advapi.GetTokenInformation(token, 1, buffer, size, ctypes.byref(size)):
            raise ValueError("STATE_OWNER_UNREADABLE")
        user = ctypes.cast(buffer, ctypes.POINTER(ctypes.c_void_p))[0]
        trusted_owner = bool(advapi.EqualSid(owner, user))
        if not trusted_owner and allow_profile_owner and path.is_dir():
            owner_sid = wintypes.LPWSTR()
            if not advapi.ConvertSidToStringSidW(owner, ctypes.byref(owner_sid)):
                raise ValueError("STATE_OWNER_UNREADABLE")
            try:
                trusted_owner = owner_sid.value in {"S-1-5-18", "S-1-5-32-544"}
            finally:
                kernel.LocalFree(owner_sid)
        if not trusted_owner:
            owner_size = wintypes.DWORD()
            advapi.GetTokenInformation(token, 4, None, 0, ctypes.byref(owner_size))
            owner_buffer = ctypes.create_string_buffer(owner_size.value)
            if not advapi.GetTokenInformation(token, 4, owner_buffer, owner_size, ctypes.byref(owner_size)):
                raise ValueError("STATE_OWNER_UNREADABLE")
            default_owner = ctypes.cast(owner_buffer, ctypes.POINTER(ctypes.c_void_p))[0]
            default_sid = wintypes.LPWSTR()
            if not advapi.ConvertSidToStringSidW(default_owner, ctypes.byref(default_sid)):
                raise ValueError("STATE_OWNER_UNREADABLE")
            try:
                trusted_owner = (default_sid.value == "S-1-5-32-544"
                                 and bool(advapi.EqualSid(owner, default_owner)))
            finally:
                kernel.LocalFree(default_sid)
        if not trusted_owner or not acl:
            raise ValueError("STATE_OWNER_OR_PERMISSIONS_UNSAFE")
        info = (wintypes.DWORD * 3)()
        if not advapi.GetAclInformation(acl, info, ctypes.sizeof(info), 2):
            raise ValueError("STATE_ACL_UNREADABLE")
        for index in range(info[0]):
            ace = ctypes.c_void_p()
            if not advapi.GetAce(acl, index, ctypes.byref(ace)):
                raise ValueError("STATE_ACL_UNREADABLE")
            header = (ctypes.c_ubyte * 4).from_address(ace.value)
            if (header[1] & 8 and not path.is_dir()) or header[0] == 1:
                continue
            if header[0] != 0:
                raise ValueError("STATE_ACL_UNSUPPORTED_ACE")
            mask = wintypes.DWORD.from_address(ace.value + 4).value
            sid = wintypes.LPWSTR()
            if not advapi.ConvertSidToStringSidW(ace.value + 8, ctypes.byref(sid)):
                raise ValueError("STATE_ACL_UNREADABLE")
            try:
                if (mask & 0x500D0156 and not advapi.EqualSid(ace.value + 8, user)
                        and sid.value not in {"S-1-5-18", "S-1-5-32-544", "S-1-3-4"}
                        and not (header[1] & 8 and sid.value == "S-1-3-0")):
                    raise ValueError("STATE_ACL_BROAD_WRITE: " + str(path) + " principal=" + sid.value)
            finally:
                kernel.LocalFree(sid)
    finally:
        if token:
            kernel.CloseHandle(token)
        kernel.LocalFree(descriptor)


def atomic_write(path: str | Path, data: bytes) -> None:
    path = safe(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".harness-", delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if temporary and temporary.exists():
            temporary.unlink()


def json_bytes(value: object) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")


@contextlib.contextmanager
def lock(state: str | Path, timeout: float = 10) -> Iterator[None]:
    state = safe(state)
    parent = state.parent
    while not parent.exists():
        parent = parent.parent
    owner_check(parent)
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    owner_check(state)
    lock_path = safe(state / ".lock")
    if lock_path.exists() and (not lock_path.is_file() or lock_path.stat().st_nlink != 1):
        raise ValueError("STATE_LOCK_UNSAFE")
    with open(lock_path, "a+b") as stream:
        if stream.tell() == 0:
            stream.write(b"0")
            stream.flush()
        deadline = time.monotonic() + timeout
        acquired = False
        while not acquired:
            stream.seek(0)
            try:
                if os.name == "nt":
                    import msvcrt
                    msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                acquired = True
            except (OSError, BlockingIOError):
                if time.monotonic() >= deadline:
                    raise ValueError("STATE_LOCK_TIMEOUT")
                time.sleep(0.025)
        try:
            yield
        finally:
            stream.seek(0)
            if os.name == "nt":
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(stream.fileno(), fcntl.LOCK_UN)
