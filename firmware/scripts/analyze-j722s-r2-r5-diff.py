#!/usr/bin/env python3
import argparse
import hashlib
import string
import struct
import sys
from pathlib import Path

SHT_SYMTAB = 2
SHT_STRTAB = 3
SHT_NOBITS = 8
SHF_ALLOC = 0x2
TARGET = "vx_app_rtos_linux_mcu2_0.out"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def printable_window(data: bytes, center: int, radius: int = 96) -> str:
    lo = max(0, center - radius)
    hi = min(len(data), center + radius)
    chunk = data[lo:hi]
    out = []
    for b in chunk:
        c = chr(b)
        out.append(c if c in string.printable and c not in "\r\n\t\x0b\x0c" else ".")
    return "".join(out)


class Elf:
    def __init__(self, path: Path):
        self.path = path
        self.data = path.read_bytes()
        if len(self.data) < 16 or self.data[:4] != b"\x7fELF":
            raise ValueError(f"not an ELF file: {path}")
        cls = self.data[4]
        enc = self.data[5]
        if cls not in (1, 2) or enc not in (1, 2):
            raise ValueError(f"unsupported ELF format: {path}")
        self.bits = 32 if cls == 1 else 64
        self.endian = "<" if enc == 1 else ">"
        self._parse_header()
        self._parse_sections()
        self._parse_symbols()

    def _unpack(self, fmt: str, off: int):
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

    def _parse_sections(self):
        raw = []
        for idx in range(self.shnum):
            off = self.shoff + idx * self.shentsize
            if self.bits == 32:
                vals = self._unpack("IIIIIIIIII", off)
                name, typ, flags, addr, sec_off, size, link, info, align, entsize = vals
            else:
                vals = self._unpack("IIQQQQIIQQ", off)
                name, typ, flags, addr, sec_off, size, link, info, align, entsize = vals
            raw.append({
                "index": idx,
                "name_index": name,
                "type": typ,
                "flags": flags,
                "addr": addr,
                "offset": sec_off,
                "size": size,
                "link": link,
                "info": info,
                "align": align,
                "entsize": entsize,
            })
        if self.shstrndx >= len(raw):
            raise ValueError(f"bad section string table index in {self.path}")
        shstr = raw[self.shstrndx]
        names = self.data[shstr["offset"]:shstr["offset"] + shstr["size"]]

        def get_name(pos: int) -> str:
            if pos >= len(names):
                return f"<bad-name-{pos}>"
            end = names.find(b"\0", pos)
            if end < 0:
                end = len(names)
            return names[pos:end].decode("utf-8", "replace")

        self.sections = []
        self.section_by_name = {}
        for sec in raw:
            sec = dict(sec)
            sec["name"] = get_name(sec["name_index"])
            if sec["type"] == SHT_NOBITS:
                sec["data"] = b""
            else:
                sec["data"] = self.data[sec["offset"]:sec["offset"] + sec["size"]]
            self.sections.append(sec)
            self.section_by_name.setdefault(sec["name"], []).append(sec)

    @staticmethod
    def _strtab_lookup(data: bytes, pos: int) -> str:
        if pos >= len(data):
            return f"<bad-string-{pos}>"
        end = data.find(b"\0", pos)
        if end < 0:
            end = len(data)
        return data[pos:end].decode("utf-8", "replace")

    def _parse_symbols(self):
        self.symbols = []
        for sec in self.sections:
            if sec["type"] != SHT_SYMTAB or not sec["entsize"]:
                continue
            if sec["link"] >= len(self.sections):
                continue
            strings = self.sections[sec["link"]]["data"]
            count = sec["size"] // sec["entsize"]
            for i in range(count):
                off = sec["offset"] + i * sec["entsize"]
                if self.bits == 32:
                    name, value, size, info, other, shndx = self._unpack("IIIBBH", off)
                else:
                    name, info, other, shndx, value, size = self._unpack("IBBHQQ", off)
                if shndx == 0 or shndx >= len(self.sections):
                    continue
                sym_name = self._strtab_lookup(strings, name)
                self.symbols.append({
                    "name": sym_name,
                    "value": value,
                    "size": size,
                    "info": info,
                    "shndx": shndx,
                    "section": self.sections[shndx]["name"],
                })
        self.symbols.sort(key=lambda s: (s["value"], s["size"], s["name"]))

    def nearest_symbol(self, addr: int, section_name: str):
        candidates = [
            s for s in self.symbols
            if s["section"] == section_name and s["value"] <= addr
        ]
        if not candidates:
            return None
        sym = max(candidates, key=lambda s: s["value"])
        return sym


def resolve(root: Path) -> Path:
    candidates = [
        root / TARGET,
        root / "usr/lib/firmware/vision_apps_evm" / TARGET,
        root / "vision_apps_evm" / TARGET,
        root / "vision_apps/out/J722S/R5F/FREERTOS/release" / TARGET,
    ]
    for p in candidates:
        if p.is_file():
            return p
    raise FileNotFoundError(f"could not find {TARGET} under {root}")


def diff_runs(a: bytes, b: bytes):
    n = min(len(a), len(b))
    runs = []
    start = None
    for i in range(n):
        different = a[i] != b[i]
        if different and start is None:
            start = i
        elif not different and start is not None:
            runs.append((start, i))
            start = None
    if start is not None:
        runs.append((start, n))
    if len(a) != len(b):
        runs.append((n, max(len(a), len(b))))
    return runs


def compare_section(ref: Elf, cand: Elf, name: str, max_runs: int):
    ref_list = ref.section_by_name.get(name, [])
    cand_list = cand.section_by_name.get(name, [])
    if len(ref_list) != 1 or len(cand_list) != 1:
        print(f"section={name} status=missing-or-ambiguous ref_count={len(ref_list)} cand_count={len(cand_list)}")
        return
    a = ref_list[0]
    b = cand_list[0]
    print(f"===== {name} =====")
    print(f"ref_addr=0x{a['addr']:x} cand_addr=0x{b['addr']:x}")
    print(f"ref_size={a['size']} cand_size={b['size']}")
    print(f"ref_sha256={sha256(a['data'])}")
    print(f"cand_sha256={sha256(b['data'])}")
    runs = diff_runs(a["data"], b["data"])
    diff_bytes = sum(end - start for start, end in runs)
    print(f"diff_run_count={len(runs)}")
    print(f"diff_byte_count={diff_bytes}")
    for idx, (start, end) in enumerate(runs[:max_runs]):
        addr = a["addr"] + start
        rsym = ref.nearest_symbol(addr, name)
        csym = cand.nearest_symbol(addr, name)
        rs = "none" if rsym is None else f"{rsym['name']}+0x{addr-rsym['value']:x}"
        cs = "none" if csym is None else f"{csym['name']}+0x{addr-csym['value']:x}"
        print(
            f"run[{idx}] start=0x{start:x} end=0x{end:x} bytes={end-start} "
            f"vaddr=0x{addr:x} ref_symbol={rs!r} cand_symbol={cs!r}"
        )
        print(f"run[{idx}] ref_hex={a['data'][start:min(end, start+32)].hex()}")
        print(f"run[{idx}] cand_hex={b['data'][start:min(end, start+32)].hex()}")
        print(f"run[{idx}] ref_ascii={printable_window(a['data'], start)!r}")
        print(f"run[{idx}] cand_ascii={printable_window(b['data'], start)!r}")
    if len(runs) > max_runs:
        print(f"diff_runs_omitted={len(runs)-max_runs}")
    print()


def main():
    ap = argparse.ArgumentParser(description="Localize runtime differences in qualified vs source-built J722S Main R5 firmware")
    ap.add_argument("reference_root", type=Path)
    ap.add_argument("candidate_root", type=Path)
    ap.add_argument("--max-runs", type=int, default=30)
    args = ap.parse_args()
    ref_path = resolve(args.reference_root)
    cand_path = resolve(args.candidate_root)
    ref = Elf(ref_path)
    cand = Elf(cand_path)
    print(f"reference_path={ref_path}")
    print(f"candidate_path={cand_path}")
    print(f"reference_sha256={sha256(ref.data)}")
    print(f"candidate_sha256={sha256(cand.data)}")
    print(f"machine_reference={ref.machine}")
    print(f"machine_candidate={cand.machine}")
    print()
    for name in (".text", ".rodata", ".data"):
        compare_section(ref, cand, name, args.max_runs)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(2)
