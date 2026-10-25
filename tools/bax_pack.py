#!/usr/bin/env python3
"""
Project: PROS (Personal Research Operating System) / PRK-LLB
File: tools/bax_pack.py
Description: Converts ELF64 executables into native BAX (Basic Application eXecutable, NEO/PE-BAX)
             binaries with optional memory-mapped embedded resource assets (icons, manifests).
"""

import sys
import os
import struct
import argparse
import tarfile

# Magic signature: "NEO/BAX\0" (0x005841422F4F454E in uint64 LE)
BAX_MAGIC = b"NEO/BAX\x00"
BAX_FORMAT_VERSION = 1
BAX_ARCH_X86_64 = 1

SUBSYSTEM_CONSOLE     = 1
SUBSYSTEM_GUI         = 2
SUBSYSTEM_NEURAL_NODE = 3

ASSET_MANIFEST = 1
ASSET_ICON     = 2
ASSET_IMAGE    = 3
ASSET_FONT     = 4
ASSET_CUSTOM   = 5

DEFAULT_RESOURCE_VIRT_ADDR = 0x50000000

def parse_elf64(elf_bytes):
    if len(elf_bytes) < 64:
        raise ValueError("Invalid ELF: file too small for ELF64 header")
    if elf_bytes[:4] != b"\x7fELF":
        raise ValueError("Invalid ELF: magic mismatch")
    
    # 64-bit, little endian
    ei_class = elf_bytes[4]
    ei_data = elf_bytes[5]
    if ei_class != 2 or ei_data != 1:
        raise ValueError("Unsupported ELF: must be 64-bit Little-Endian")
    
    # Unpack ELF64 header
    # e_entry: offset 24, uint64
    # e_phoff: offset 32, uint64
    # e_phentsize: offset 54, uint16
    # e_phnum: offset 56, uint16
    e_entry, e_phoff = struct.unpack_from("<QQ", elf_bytes, 24)
    e_phentsize, e_phnum = struct.unpack_from("<HH", elf_bytes, 54)
    
    segments = []
    min_vaddr = None
    max_vaddr = None
    
    for i in range(e_phnum):
        ph_offset = e_phoff + (i * e_phentsize)
        # Elf64_Phdr layout:
        # uint32 p_type;
        # uint32 p_flags;
        # uint64 p_offset;
        # uint64 p_vaddr;
        # uint64 p_paddr;
        # uint64 p_filesz;
        # uint64 p_memsz;
        # uint64 p_align;
        p_type, p_flags, p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align = struct.unpack_from("<IIQQQQQQ", elf_bytes, ph_offset)
        if p_type == 1 and p_memsz > 0: # PT_LOAD
            data = elf_bytes[p_offset : p_offset + p_filesz]
            seg_info = {
                'vaddr': p_vaddr,
                'filesz': p_filesz,
                'memsz': p_memsz,
                'flags': p_flags,
                'data': data
            }
            segments.append(seg_info)
            if min_vaddr is None or p_vaddr < min_vaddr:
                min_vaddr = p_vaddr
            seg_end = p_vaddr + p_memsz
            if max_vaddr is None or seg_end > max_vaddr:
                max_vaddr = seg_end
                
    if not segments:
        raise ValueError("ELF contains no loadable (PT_LOAD) segments")
        
    return e_entry, min_vaddr, max_vaddr, segments

def pack_bax(elf_path, out_bax_path, subsystem=SUBSYSTEM_CONSOLE, manifest_path=None, icon_path=None, extra_assets=None):
    with open(elf_path, "rb") as f:
        elf_bytes = f.read()
        
    entry_point, image_base, max_vaddr, segments = parse_elf64(elf_bytes)
    image_size = max_vaddr - image_base
    
    # Process resources
    resources = []
    if manifest_path and os.path.exists(manifest_path):
        with open(manifest_path, "rb") as f:
            mdata = f.read()
        resources.append({
            'type': ASSET_MANIFEST,
            'id': 1,
            'name': b"manifest.json",
            'data': mdata
        })
        
    if icon_path and os.path.exists(icon_path):
        with open(icon_path, "rb") as f:
            idata = f.read()
        resources.append({
            'type': ASSET_ICON,
            'id': 2,
            'name': b"app_icon.png",
            'data': idata
        })
        
    if extra_assets:
        for a_type, a_id, a_name, a_path in extra_assets:
            if os.path.exists(a_path):
                with open(a_path, "rb") as f:
                    data = f.read()
                resources.append({
                    'type': a_type,
                    'id': a_id,
                    'name': a_name.encode('utf-8')[:15],
                    'data': data
                })
                
    num_segments = len(segments)
    num_resources = len(resources)
    
    header_size = 64
    seg_table_size = num_segments * 48
    res_dir_size = num_resources * 48 if num_resources > 0 else 0
    
    # Calculate file offsets
    # Header: [0 .. 64]
    # SegTable: [64 .. 64 + seg_table_size]
    # ResDir: [64 + seg_table_size .. 64 + seg_table_size + res_dir_size]
    # SegData starts aligned to 16 bytes
    cur_offset = header_size + seg_table_size + res_dir_size
    cur_offset = (cur_offset + 15) & ~15
    
    seg_file_offsets = []
    for seg in segments:
        seg_file_offsets.append(cur_offset)
        cur_offset += len(seg['data'])
        cur_offset = (cur_offset + 15) & ~15
        
    res_file_offsets = []
    res_virt_offsets = []
    res_virt_base = DEFAULT_RESOURCE_VIRT_ADDR if num_resources > 0 else 0
    
    # In user memory: [Resource Directory Array (res_dir_size)] followed by [Resource Data Blobs]
    res_data_cur_virt = res_virt_base + res_dir_size
    res_data_cur_virt = (res_data_cur_virt + 15) & ~15
    
    for res in resources:
        res_file_offsets.append(cur_offset)
        res_virt_offsets.append(res_data_cur_virt)
        
        blob_len = len(res['data'])
        cur_offset += blob_len
        cur_offset = (cur_offset + 15) & ~15
        
        res_data_cur_virt += blob_len
        res_data_cur_virt = (res_data_cur_virt + 15) & ~15
        
    # Build BaxHeader
    seg_offset = header_size
    res_offset = (header_size + seg_table_size) if num_resources > 0 else 0
    
    header_bytes = bytearray(64)
    # Magic (8 bytes)
    header_bytes[0:8] = BAX_MAGIC
    # FormatVersion (2 bytes)
    struct.pack_into("<H", header_bytes, 8, BAX_FORMAT_VERSION)
    # TargetArch (2 bytes)
    struct.pack_into("<H", header_bytes, 10, BAX_ARCH_X86_64)
    # Subsystem (2 bytes)
    struct.pack_into("<H", header_bytes, 12, subsystem)
    # Flags (2 bytes, 1 = ASLR_OK)
    struct.pack_into("<H", header_bytes, 14, 1)
    # EntryPoint (8 bytes)
    struct.pack_into("<Q", header_bytes, 16, entry_point)
    # ImageBase (8 bytes)
    struct.pack_into("<Q", header_bytes, 24, image_base)
    # ImageSize (8 bytes)
    struct.pack_into("<Q", header_bytes, 32, image_size)
    # SegmentsOffset (4 bytes)
    struct.pack_into("<I", header_bytes, 40, seg_offset)
    # SegmentCount (2 bytes)
    struct.pack_into("<H", header_bytes, 44, num_segments)
    # ResourceCount (2 bytes)
    struct.pack_into("<H", header_bytes, 46, num_resources)
    # ResourceOffset (4 bytes)
    struct.pack_into("<I", header_bytes, 48, res_offset)
    # ResourceVirtAddr (8 bytes)
    struct.pack_into("<Q", header_bytes, 52, res_virt_base)
    # Reserved (4 bytes) -> 0
    struct.pack_into("<I", header_bytes, 60, 0)
    
    out_bax = bytearray(header_bytes)
    
    # Append Segment Table
    for idx, seg in enumerate(segments):
        seg_entry = bytearray(48)
        # Name: 8 bytes
        name_bytes = f".seg{idx}\x00".encode('ascii')[:8]
        seg_entry[0:len(name_bytes)] = name_bytes
        # FileOffset (8 bytes)
        struct.pack_into("<Q", seg_entry, 8, seg_file_offsets[idx])
        # FileSize (8 bytes)
        struct.pack_into("<Q", seg_entry, 16, seg['filesz'])
        # VirtAddr (8 bytes)
        struct.pack_into("<Q", seg_entry, 24, seg['vaddr'])
        # MemSize (8 bytes)
        struct.pack_into("<Q", seg_entry, 32, seg['memsz'])
        # Flags (4 bytes): PF_X=1 -> 4, PF_W=2 -> 2, PF_R=4 -> 1
        flags = 0
        if seg['flags'] & 4: flags |= 1 # Read
        if seg['flags'] & 2: flags |= 2 # Write
        if seg['flags'] & 1: flags |= 4 # Execute
        struct.pack_into("<I", seg_entry, 40, flags)
        struct.pack_into("<I", seg_entry, 44, 0)
        out_bax.extend(seg_entry)
        
    # Append Resource Directory (if any)
    if num_resources > 0:
        for idx, res in enumerate(resources):
            res_entry = bytearray(48)
            # AssetType (4 bytes)
            struct.pack_into("<I", res_entry, 0, res['type'])
            # AssetId (4 bytes)
            struct.pack_into("<I", res_entry, 4, res['id'])
            # Name (16 bytes)
            name_b = res['name'][:15]
            res_entry[8:8+len(name_b)] = name_b
            # FileOffset (8 bytes)
            struct.pack_into("<Q", res_entry, 24, res_file_offsets[idx])
            # ByteLength (8 bytes)
            struct.pack_into("<Q", res_entry, 32, len(res['data']))
            # VirtAddr (8 bytes)
            struct.pack_into("<Q", res_entry, 40, res_virt_offsets[idx])
            out_bax.extend(res_entry)
            
    # Pad to first segment file offset
    if len(out_bax) < seg_file_offsets[0]:
        out_bax.extend(b"\x00" * (seg_file_offsets[0] - len(out_bax)))
        
    # Append Segment Data Payloads
    for idx, seg in enumerate(segments):
        target_offset = seg_file_offsets[idx]
        if len(out_bax) < target_offset:
            out_bax.extend(b"\x00" * (target_offset - len(out_bax)))
        out_bax.extend(seg['data'])
        
    # Append Resource Blobs
    if num_resources > 0:
        for idx, res in enumerate(resources):
            target_offset = res_file_offsets[idx]
            if len(out_bax) < target_offset:
                out_bax.extend(b"\x00" * (target_offset - len(out_bax)))
            out_bax.extend(res['data'])
            
    with open(out_bax_path, "wb") as f:
        f.write(out_bax)
        
    print(f"[BAX-PACK] Created {out_bax_path} ({len(out_bax)} bytes)")
    print(f"           Entry: 0x{entry_point:X}, Base: 0x{image_base:X}, Size: {image_size} bytes")
    print(f"           Segments: {num_segments}, Resources: {num_resources}")
    return out_bax_path

def create_initrd_tar(files_to_pack, out_tar_path):
    with tarfile.open(out_tar_path, "w") as tar:
        for arcname, filepath in files_to_pack.items():
            tar.add(filepath, arcname=arcname)
    print(f"[INITRD] Created USTAR archive: {out_tar_path} ({os.path.getsize(out_tar_path)} bytes)")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Package ELF64 into NEO/PE-BAX executable.")
    parser.add_argument("elf", help="Input ELF64 executable file")
    parser.add_argument("-o", "--output", help="Output BAX file (default: input with .bax)", default=None)
    parser.add_argument("--subsystem", choices=["console", "gui", "node"], default="console")
    parser.add_argument("--manifest", help="Optional JSON/TOML manifest file", default=None)
    parser.add_argument("--icon", help="Optional PNG/BMP icon file", default=None)
    parser.add_argument("--tar", help="Optional output initrd.tar to package", default=None)
    parser.add_argument("--extra", action="append", help="Extra file to include in initrd tar (format: name=path or path)", default=[])
    args = parser.parse_args()

    out_bax = args.output or os.path.splitext(args.elf)[0] + ".bax"
    subsys_map = {"console": SUBSYSTEM_CONSOLE, "gui": SUBSYSTEM_GUI, "node": SUBSYSTEM_NEURAL_NODE}
    
    pack_bax(args.elf, out_bax, subsystem=subsys_map[args.subsystem], manifest_path=args.manifest, icon_path=args.icon)

    if args.tar:
        files = {os.path.basename(out_bax): out_bax}
        for extra in args.extra:
            if "=" in extra:
                arcname, filepath = extra.split("=", 1)
            else:
                arcname, filepath = os.path.basename(extra), extra
            files[arcname] = filepath
        create_initrd_tar(files, args.tar)
