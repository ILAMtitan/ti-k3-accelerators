#!/usr/bin/env python3
import argparse
import hashlib
import struct
import sys
from pathlib import Path

PT_LOAD = 1
SHT_NOBITS = 8
SHF_ALLOC = 0x2
NAMES = (
    "vx_app_rtos_linux_mcu2_0.out",
    "vx_app_rtos_linux_c7x_1.out",
    "vx_app_rtos_linux_c7x_2.out",
)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


class Elf:
    def __init__(self, path: Path):
        self.path = path
        self.data = path.read_bytes()
        if len(self.data) < 16 or self.data[:4] != b"\x7fELF":
            raise ValueError(f"not an ELF file: {path}")
        cls = self.data[4]
        enc = self.data[5]
        if cls not in (1, 2) or enc not in (1, 2):
            raise ValueError(f"unsupported ELF class/data encoding: {path}")
        self.bits = 32 if cls == 1 else 64
        self.endian = "<" if enc == 1 else ">"
        self._parse_header()
        self._parse_program_headers()
        self._parse_sections()

    def _unpack(self, fmt, off):
        size = struct.calcsize(self.endian + fmt)
        end = off + size
        if end > len(self.data):
            raise ValueError(f"truncated ELF structure in {self.path}")
        return struct.unpack(self.endian + fmt, self.data[off:end])

    def _parse_header(self):
        if self.bits == 32:
            vals = self._unpack("HHIIIIIHHHHHH", 16)
            (_, self.machine, _, self.entry, self.phoff, self.shoff,
             _, _, self.phentsize, self.phnum, self.shentsize,
             self.shnum, self.shstrndx) = vals
        else:
            vals = self._unpack("HHIQQQIHHHHHH", 16)
            (_, self.machine, _, self.entry, self.phoff, self.shoff,
             _, _, self.phentsize, self.phnum, self.shentsize,
             self.shnum, self.shstrndx) = vals

    def _parse_program_headers(self):
        self.loads = []
        for i in range(self.phnum):
            off = self.phoff + i * self.phentsize
            if self.bits == 32:
                p_type, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_flags, p_align = self._unpack("IIIIIIII", off)
            else:
                p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align = self._unpack("IIQQQQQQ", off)
            if p_type != PT_LOAD:
                continue
            end = p_offset + p_filesz
            if end > len(self.data):
                raise ValueError(f"PT_LOAD exceeds file size in {self.path}")
            payload = self.data[p_offset:end]
            self.loads.append({
                "vaddr": p_vaddr,
                "paddr": p_paddr,
                "filesz": p_filesz,
                "memsz": p_memsz,
                "flags": p_flags,
                "align": p_align,
                "sha256": sha256(payload),
                "payload": payload,
            })

    def _parse_sections(self):
        raw = []
        for i in range(self.shnum):
            off = self.shoff + i * self.shentsize
            if self.bits == 32:
                vals = self._unpack("IIIIIIIIII", off)
                name, typ, flags, addr, sec_off, size, _, _, _, _ = vals
            else:
                vals = self._unpack("IIQQQQIIQQ", off)
                name, typ, flags, addr, sec_off, size, _, _, _, _ = vals
            raw.append((name, typ, flags, addr, sec_off, size))
        if self.shstrndx >= len(raw):
            self.sections = []
            return
        _, typ, _, _, off, size = raw[self.shstrndx]
        if typ == SHT_NOBITS:
            names = b""
        else:
            names = self.data[off:off + size]

        def secname(idx):
            if idx >= len(names):
                return f"<bad-name-{idx}>"
            end = names.find(b"\0", idx)
            if end < 0:
                end = len(names)
            return names[idx:end].decode("utf-8", "replace")

        self.sections = []
        for name_idx, typ, flags, addr, off, size in raw:
            payload = b"" if typ == SHT_NOBITS else self.data[off:off + size]
            self.sections.append({
                "name": secname(name_idx),
                "type": typ,
                "flags": flags,
                "addr": addr,
                "size": size,
                "sha256": sha256(payload),
            })


def first_diff(a: bytes, b: bytes):
    n = min(len(a), len(b))
    for i in range(n):
        if a[i] != b[i]:
            return i
    return n if len(a) != len(b) else None


def compare_one(reference: Path, candidate: Path):
    a = Elf(reference)
    b = Elf(candidate)
    print(f"===== {reference.name} =====")
    print(f"reference_sha256={sha256(a.data)}")
    print(f"candidate_sha256={sha256(b.data)}")
    print(f"elf_class_reference={a.bits}")
    print(f"elf_class_candidate={b.bits}")
    print(f"machine_reference={a.machine}")
    print(f"machine_candidate={b.machine}")
    print(f"entry_reference=0x{a.entry:x}")
    print(f"entry_candidate=0x{b.entry:x}")

    same_layout = len(a.loads) == len(b.loads)
    same_loads = same_layout
    if same_layout:
        for i, (x, y) in enumerate(zip(a.loads, b.loads)):
            meta_x = (x["vaddr"], x["paddr"], x["filesz"], x["memsz"], x["flags"], x["align"])
            meta_y = (y["vaddr"], y["paddr"], y["filesz"], y["memsz"], y["flags"], y["align"])
            equal = meta_x == meta_y and x["sha256"] == y["sha256"]
            same_loads &= equal
            print(
                f"load[{i}] equal={'yes' if equal else 'no'} "
                f"ref_vaddr=0x{x['vaddr']:x} cand_vaddr=0x{y['vaddr']:x} "
                f"ref_filesz={x['filesz']} cand_filesz={y['filesz']} "
                f"ref_sha256={x['sha256']} cand_sha256={y['sha256']}"
            )
            if meta_x == meta_y and x["sha256"] != y["sha256"]:
                d = first_diff(x["payload"], y["payload"])
                if d is not None:
                    print(f"load[{i}] first_payload_diff=0x{d:x}")
    else:
        print(f"load_segment_count_reference={len(a.loads)}")
        print(f"load_segment_count_candidate={len(b.loads)}")

    ref_secs = {(s["name"], s["addr"]): s for s in a.sections}
    cand_secs = {(s["name"], s["addr"]): s for s in b.sections}
    changed = []
    for key in sorted(set(ref_secs) | set(cand_secs)):
        x = ref_secs.get(key)
        y = cand_secs.get(key)
        if x is None or y is None:
            changed.append((key[0], "ALLOC" if ((x or y)["flags"] & SHF_ALLOC) else "NONALLOC", "missing"))
            continue
        if (x["type"], x["flags"], x["size"], x["sha256"]) != (y["type"], y["flags"], y["size"], y["sha256"]):
            changed.append((key[0], "ALLOC" if ((x["flags"] | y["flags"]) & SHF_ALLOC) else "NONALLOC", f"ref_size={x['size']} cand_size={y['size']}"))

    alloc_changed = [x for x in changed if x[1] == "ALLOC"]
    nonalloc_changed = [x for x in changed if x[1] == "NONALLOC"]
    print(f"pt_load_identical={'yes' if same_loads else 'no'}")
    print(f"changed_alloc_sections={len(alloc_changed)}")
    print(f"changed_nonalloc_sections={len(nonalloc_changed)}")
    for name, kind, detail in changed[:40]:
        print(f"section_changed kind={kind} name={name!r} {detail}")
    if len(changed) > 40:
        print(f"section_changed_omitted={len(changed)-40}")

    if same_loads:
        verdict = "LOAD_IMAGE_IDENTICAL"
    elif not alloc_changed:
        verdict = "LOAD_SEGMENTS_DIFFER_BUT_NO_ALLOC_SECTION_DIFF_DETECTED"
    else:
        verdict = "RUNTIME_CONTENT_DIFFERS"
    print(f"verdict={verdict}")
    print()
    return verdict


def resolve(root: Path, name: str) -> Path:
    candidates = [
        root / name,
        root / "usr/lib/firmware/vision_apps_evm" / name,
        root / "vision_apps_evm" / name,
    ]
    for p in candidates:
        if p.is_file():
            return p
    raise FileNotFoundError(f"could not find {name} under {root}")


def main():
    ap = argparse.ArgumentParser(description="Compare qualified and source-built J722S R2 firmware ELF load images")
    ap.add_argument("reference_root", type=Path)
    ap.add_argument("candidate_root", type=Path)
    args = ap.parse_args()
    verdicts = []
    for name in NAMES:
        verdicts.append(compare_one(resolve(args.reference_root, name), resolve(args.candidate_root, name)))
    if all(v == "LOAD_IMAGE_IDENTICAL" for v in verdicts):
        print("J722S_R2_LOAD_IMAGE_COMPARISON=IDENTICAL")
        return 0
    if any(v == "RUNTIME_CONTENT_DIFFERS" for v in verdicts):
        print("J722S_R2_LOAD_IMAGE_COMPARISON=RUNTIME_CONTENT_DIFFERS")
        return 2
    print("J722S_R2_LOAD_IMAGE_COMPARISON=INDETERMINATE")
    return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(3)
