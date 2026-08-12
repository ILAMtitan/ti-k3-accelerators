#!/usr/bin/env python3
import argparse
import hashlib
import struct
import sys
from pathlib import Path

PT_LOAD = 1
SHF_ALLOC = 0x2
SHT_NOBITS = 8

FILES = {
    "R5": Path("vision_apps/out/J722S/R5F/FREERTOS/release/vx_app_rtos_linux_mcu2_0.out"),
    "C7x_1": Path("vision_apps/out/J722S/C7524/FREERTOS/release/vx_app_rtos_linux_c7x_1.out"),
    "C7x_2": Path("vision_apps/out/J722S/C7524/FREERTOS/release/vx_app_rtos_linux_c7x_2.out"),
}

def sha(data):
    return hashlib.sha256(data).hexdigest()

def file_sha(path):
    return sha(path.read_bytes())

def expected_hashes(path):
    out = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        digest, name = line.split(None, 1)
        out[name.strip()] = digest
    return out

def parse_elf(path):
    data = path.read_bytes()
    if data[:4] != b"\x7fELF":
        raise RuntimeError(f"not ELF: {path}")

    cls = data[4]
    endian = "<" if data[5] == 1 else ">" if data[5] == 2 else None
    if endian is None:
        raise RuntimeError(f"bad ELF endian: {path}")

    if cls == 1:
        h = struct.unpack_from(endian + "HHIIIIIHHHHHH", data, 16)
        entry, phoff, shoff = h[3], h[4], h[5]
        phentsize, phnum, shentsize, shnum, shstrndx = h[8], h[9], h[10], h[11], h[12]
        def ph(i):
            p = struct.unpack_from(endian + "IIIIIIII", data, phoff + i * phentsize)
            return dict(type=p[0], offset=p[1], vaddr=p[2], paddr=p[3],
                        filesz=p[4], memsz=p[5], flags=p[6], align=p[7])
        def shdr(i):
            return struct.unpack_from(endian + "IIIIIIIIII", data, shoff + i * shentsize)
    elif cls == 2:
        h = struct.unpack_from(endian + "HHIQQQIHHHHHH", data, 16)
        entry, phoff, shoff = h[3], h[4], h[5]
        phentsize, phnum, shentsize, shnum, shstrndx = h[8], h[9], h[10], h[11], h[12]
        def ph(i):
            p = struct.unpack_from(endian + "IIQQQQQQ", data, phoff + i * phentsize)
            return dict(type=p[0], flags=p[1], offset=p[2], vaddr=p[3],
                        paddr=p[4], filesz=p[5], memsz=p[6], align=p[7])
        def shdr(i):
            return struct.unpack_from(endian + "IIQQQQIIQQ", data, shoff + i * shentsize)
    else:
        raise RuntimeError(f"unsupported ELF class {cls}: {path}")

    loads = []
    for i in range(phnum):
        p = ph(i)
        if p["type"] != PT_LOAD:
            continue
        blob = data[p["offset"]:p["offset"] + p["filesz"]]
        loads.append((p["flags"], p["vaddr"], p["paddr"], p["filesz"],
                      p["memsz"], p["align"], sha(blob)))

    sections = [shdr(i) for i in range(shnum)]
    shstr = sections[shstrndx]
    names = data[shstr[4]:shstr[4] + shstr[5]]

    def sec_name(off):
        end = names.find(b"\0", off)
        if end < 0:
            end = len(names)
        return names[off:end].decode(errors="replace")

    alloc = []
    for s in sections:
        name_off, stype, flags, addr, offset, size = s[:6]
        if not (flags & SHF_ALLOC):
            continue
        blob = b"" if stype == SHT_NOBITS else data[offset:offset + size]
        alloc.append((sec_name(name_off), stype, flags, addr, size, sha(blob)))

    return cls, entry, loads, alloc

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sdk-root", required=True, type=Path)
    ap.add_argument("--oracle-sdk-root", required=True, type=Path)
    args = ap.parse_args()

    repo = Path(__file__).resolve().parents[2]
    exp = expected_hashes(repo / "firmware/expected/j722s-r1-hardware-oracle.sha256")

    corefile = args.sdk_root / "vision_apps/.build_core.bak"
    want_cores = [
        "ENABLE_IPC_MPU1",
        "ENABLE_IPC_MCU2_0",
        "ENABLE_IPC_C7x_1",
        "ENABLE_IPC_C7x_2",
    ]

    print("=" * 64)
    print("IPC BUILD COHORT")
    print("=" * 64)

    if not corefile.is_file():
        print(f"ERROR: missing {corefile}")
        return 1

    got_cores = [x.strip() for x in corefile.read_text().splitlines() if x.strip()]
    for x in got_cores:
        print(x)

    if got_cores != want_cores:
        print("IPC_COHORT=DIFFERENT")
        return 1

    print("IPC_COHORT=PASS")
    ok = True

    for label, rel in FILES.items():
        cur = args.sdk_root / rel
        gold = args.oracle_sdk_root / rel

        print()
        print("=" * 64)
        print(label)
        print("=" * 64)

        if not cur.is_file() or not gold.is_file():
            print("ERROR: missing current/oracle file")
            print(f"current={cur}")
            print(f"oracle ={gold}")
            ok = False
            continue

        current_sha = file_sha(cur)
        oracle_sha = file_sha(gold)
        expected_sha = exp.get(cur.name)

        print(f"expected_full_sha={expected_sha}")
        print(f"oracle_full_sha  ={oracle_sha}")
        print(f"current_full_sha ={current_sha}")

        if expected_sha != oracle_sha:
            print("ORACLE_FULL_SHA=UNEXPECTED")
            ok = False
            continue

        print("ORACLE_FULL_SHA=PASS")
        print("FULL_ELF=" + ("BYTE_IDENTICAL" if current_sha == expected_sha else "DIFFERENT_NONFATAL"))

        gcls, gentry, gload, galloc = parse_elf(gold)
        ccls, centry, cload, calloc = parse_elf(cur)

        print(f"gold_entry=0x{gentry:x}")
        print(f"current_entry=0x{centry:x}")
        print(f"gold_load_count={len(gload)}")
        print(f"current_load_count={len(cload)}")

        load_ok = gcls == ccls and gentry == centry and gload == cload
        alloc_ok = galloc == calloc

        print("PT_LOAD=" + ("BYTE_IDENTICAL" if load_ok else "DIFFERENT"))
        print("SHF_ALLOC=" + ("BYTE_IDENTICAL" if alloc_ok else "DIFFERENT"))

        if load_ok and alloc_ok:
            print("RUNTIME_EQUIVALENCE=PASS")
        else:
            print("RUNTIME_EQUIVALENCE=FAIL")
            ok = False

    print()
    print("=" * 64)
    print("J722S_R1_VERIFICATION=" + ("PASS" if ok else "FAIL"))
    return 0 if ok else 1

if __name__ == "__main__":
    sys.exit(main())
