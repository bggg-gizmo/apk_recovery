extends RefCounted
class_name ApkRecoveryAnalyzer

const MAX_TEXT_SEARCH = 24 * 1024 * 1024
const MAX_BINARY_SEARCH = 192 * 1024 * 1024

var source_path: String = ""
var apk_path: String = ""
var staged_path: String = ""
var zip = ZIPReader.new()
var zip_opened := false
var entries: Array = []
var entry_map: Dictionary = {}
var zip_metadata: Dictionary = {}
var analysis: Dictionary = {}

func open_apk(path: String) -> Dictionary:
    close()
    source_path = path
    analysis = {}
    entries = []
    entry_map.clear()
    zip_metadata = {}
    var prepared = _prepare_source(path)
    if not bool(prepared.get("ok", false)):
        return prepared
    apk_path = String(prepared.path)
    entries = _read_zip_directory(apk_path)
    if entries.is_empty() and not bool(zip_metadata.get("valid", false)):
        return {"ok": false, "error": String(zip_metadata.get("error", "ZIP central directory could not be parsed."))}
    for e in entries:
        entry_map[String(e.name)] = e
    var zerr = zip.open(apk_path)
    if zerr != OK:
        return {"ok": false, "error": "ZIPReader failed to open APK: %s" % error_string(zerr)}
    zip_opened = true
    analysis = _analyze()
    analysis.ok = true
    analysis.source_path = source_path
    return analysis

func close() -> void:
    if zip and zip_opened:
        zip.close()
        zip_opened = false
    if not staged_path.is_empty():
        var absolute := ProjectSettings.globalize_path(staged_path)
        if FileAccess.file_exists(staged_path):
            DirAccess.remove_absolute(absolute)
        staged_path = ""
    apk_path = ""

func _prepare_source(path: String) -> Dictionary:
    if not path.begins_with("content://"):
        var f = FileAccess.open(path, FileAccess.READ)
        if f == null:
            return {"ok": false, "error": "Unable to read selected APK: %s" % error_string(FileAccess.get_open_error())}
        return {"ok": true, "path": path}

    var src = FileAccess.open(path, FileAccess.READ)
    if src == null:
        return {"ok": false, "error": "Unable to read Android document URI: %s" % error_string(FileAccess.get_open_error())}
    var staging_dir := "user://staging"
    var mkerr := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(staging_dir))
    if mkerr != OK and mkerr != ERR_ALREADY_EXISTS:
        return {"ok": false, "error": "Unable to create staging directory: %s" % error_string(mkerr)}
    staged_path = "%s/apk_%d.apk" % [staging_dir, Time.get_ticks_usec()]
    var dst = FileAccess.open(staged_path, FileAccess.WRITE)
    if dst == null:
        return {"ok": false, "error": "Unable to create local staging copy: %s" % error_string(FileAccess.get_open_error())}
    var total := src.get_length()
    while src.get_position() < total:
        var remaining := total - src.get_position()
        var chunk := src.get_buffer(min(1024 * 1024, remaining))
        if chunk.is_empty() and remaining > 0:
            return {"ok": false, "error": "Read failed while staging selected APK."}
        dst.store_buffer(chunk)
    dst.flush()
    return {"ok": true, "path": staged_path}

func _file_size(path: String) -> int:
    var f = FileAccess.open(path, FileAccess.READ)
    return f.get_length() if f != null else 0

func _read_zip_directory(path: String) -> Array:
    zip_metadata = {"valid": false, "zip64": false, "central_directory_offset": 0, "central_directory_size": 0, "entry_count": 0, "error": ""}
    var f = FileAccess.open(path, FileAccess.READ)
    if f == null:
        zip_metadata.error = "Unable to open APK for ZIP parsing."
        return []
    var file_size := f.get_length()
    if file_size < 22:
        zip_metadata.error = "File is too small to be a ZIP/APK."
        return []
    var tail_len: int = int(min(file_size, 65557))
    var tail_start := file_size - tail_len
    f.seek(tail_start)
    var tail = f.get_buffer(tail_len)
    var eocd := -1
    for i in range(tail.size() - 22, -1, -1):
        if _u32(tail, i) == 0x06054b50:
            eocd = i
            break
    if eocd < 0:
        zip_metadata.error = "ZIP end-of-central-directory record not found."
        return []

    var count: int = _u16(tail, eocd + 10)
    var cd_size: int = _u32(tail, eocd + 12)
    var cd_off: int = _u32(tail, eocd + 16)
    var needs_zip64 := count == 0xffff or cd_size == 0xffffffff or cd_off == 0xffffffff
    if needs_zip64:
        var locator_abs := tail_start + eocd - 20
        if locator_abs < 0:
            zip_metadata.error = "ZIP64 metadata is required but its locator is missing."
            return []
        f.seek(locator_abs)
        var locator := f.get_buffer(20)
        if locator.size() != 20 or _u32(locator, 0) != 0x07064b50:
            zip_metadata.error = "ZIP64 locator is malformed."
            return []
        var zip64_eocd_off := _u64(locator, 8)
        if zip64_eocd_off < 0 or zip64_eocd_off + 56 > file_size:
            zip_metadata.error = "ZIP64 end-of-central-directory offset is invalid."
            return []
        f.seek(zip64_eocd_off)
        var z64 := f.get_buffer(56)
        if z64.size() < 56 or _u32(z64, 0) != 0x06064b50:
            zip_metadata.error = "ZIP64 end-of-central-directory record is malformed."
            return []
        count = _u64(z64, 32)
        cd_size = _u64(z64, 40)
        cd_off = _u64(z64, 48)
        zip_metadata.zip64 = true

    if count < 0 or count > 2000000 or cd_off < 0 or cd_size < 0 or cd_off + cd_size > file_size:
        zip_metadata.error = "ZIP central-directory bounds are invalid."
        return []

    var out: Array = []
    f.seek(cd_off)
    for _i in range(count):
        var h = f.get_buffer(46)
        if h.size() < 46 or _u32(h, 0) != 0x02014b50:
            zip_metadata.error = "ZIP central-directory entry is malformed."
            return []
        var method := _u16(h, 10)
        var crc := _u32(h, 16)
        var csize: int = _u32(h, 20)
        var usize: int = _u32(h, 24)
        var nl := _u16(h, 28)
        var xl := _u16(h, 30)
        var cl := _u16(h, 32)
        var local_off: int = _u32(h, 42)
        if nl < 0 or xl < 0 or cl < 0 or f.get_position() + nl + xl + cl > file_size:
            zip_metadata.error = "ZIP central-directory variable fields exceed file bounds."
            return []
        var name_b = f.get_buffer(nl)
        var name = name_b.get_string_from_utf8()
        var extra := f.get_buffer(xl) if xl > 0 else PackedByteArray()
        if cl > 0:
            f.seek(f.get_position() + cl)
        if usize == 0xffffffff or csize == 0xffffffff or local_off == 0xffffffff:
            var zvals := _parse_zip64_extra(extra, usize == 0xffffffff, csize == 0xffffffff, local_off == 0xffffffff)
            if usize == 0xffffffff: usize = int(zvals.get("usize", -1))
            if csize == 0xffffffff: csize = int(zvals.get("csize", -1))
            if local_off == 0xffffffff: local_off = int(zvals.get("local_offset", -1))
        if usize < 0 or csize < 0 or local_off < 0 or local_off >= file_size:
            zip_metadata.error = "ZIP64 entry metadata is incomplete or invalid."
            return []
        out.append({"name": name, "method": method, "crc": crc, "compressed_size": csize, "size": usize, "local_offset": local_off})

    zip_metadata.valid = true
    zip_metadata.central_directory_offset = cd_off
    zip_metadata.central_directory_size = cd_size
    zip_metadata.entry_count = count
    zip_metadata.error = ""
    return out

func _parse_zip64_extra(extra: PackedByteArray, need_usize: bool, need_csize: bool, need_offset: bool) -> Dictionary:
    var out := {}
    var p := 0
    while p + 4 <= extra.size():
        var field_id := _u16(extra, p)
        var field_size := _u16(extra, p + 2)
        p += 4
        if p + field_size > extra.size():
            break
        if field_id == 0x0001:
            var q := p
            var end := p + field_size
            if need_usize and q + 8 <= end:
                out.usize = _u64(extra, q); q += 8
            if need_csize and q + 8 <= end:
                out.csize = _u64(extra, q); q += 8
            if need_offset and q + 8 <= end:
                out.local_offset = _u64(extra, q); q += 8
            return out
        p += field_size
    return out

func _analyze() -> Dictionary:
    var names: Array[String] = []
    var total_size := _file_size(apk_path)
    for e in entries:
        names.append(String(e.name).to_lower())
    var sha = _sha256_file(apk_path)
    var manifest = {"package_name": "Unknown", "version_name": "Unknown", "version_code": -1, "min_sdk": -1, "target_sdk": -1, "providers": []}
    if zip.file_exists("AndroidManifest.xml"):
        manifest = _parse_manifest(zip.read_file("AndroidManifest.xml"))

    var dex_list: Array = []
    var dex_bytes := 0
    for e in entries:
        var n = String(e.name)
        var l = n.to_lower()
        if _is_dex_name(l):
            dex_bytes += int(e.size)
            dex_list.append(_parse_dex(n, zip.read_file(n)))

    var native_count := 0
    var native_bytes := 0
    var abi_set := {}
    for e in entries:
        var l = String(e.name).to_lower()
        if l.begins_with("lib/") and l.ends_with(".so"):
            native_count += 1
            native_bytes += int(e.size)
            var parts := String(e.name).split("/", false)
            if parts.size() >= 3:
                abi_set[String(parts[1])] = true
    var abis: Array[String] = []
    for abi in abi_set.keys():
        abis.append(String(abi))
    abis.sort()

    var dex_strings: Array[String] = []
    var all_classes: Array = []
    var all_methods: Array = []
    for d in dex_list:
        if bool(d.get("valid", false)):
            for value in d.strings:
                dex_strings.append(String(value))
            all_classes.append_array(d.classes)
            all_methods.append_array(d.methods)

    var markers = _detect_frameworks(names, dex_strings)
    var kotlin = _array_contains_ci(dex_strings, "kotlin/") or _classes_contain(all_classes, "Lkotlin/")
    var compose = _array_contains_ci(dex_strings, "androidx/compose/") or _classes_contain(all_classes, "Landroidx/compose/")
    var obf = _estimate_obfuscation(all_classes, all_methods)
    var artifacts: Array = []
    var remnants: Array[String] = []
    var mapping := false
    var sourcemap := false
    for e in entries:
        var a = _classify_artifact(String(e.name), int(e.size))
        if not a.is_empty():
            artifacts.append(a)
        var l = String(e.name).to_lower()
        if _is_high_value(l):
            remnants.append(String(e.name))
        if l.ends_with("mapping.txt") or l.contains("proguard.map"):
            mapping = true
        if l.ends_with(".map") or l.contains("sourcemap"):
            sourcemap = true
    artifacts.sort_custom(func(a,b): return int(a.priority) < int(b.priority) if int(a.priority) != int(b.priority) else int(a.size) > int(b.size))

    var primary = "Native Android / Java / Kotlin"
    var best := 0
    for fw in markers:
        if int(fw.confidence) > best:
            best = int(fw.confidence)
            primary = String(fw.name)
    if best == 0 and native_bytes > max(5 * 1024 * 1024, dex_bytes * 3):
        primary = "Native-heavy Android"
    var native_heavy = native_bytes > max(10 * 1024 * 1024, dex_bytes * 3)
    var locations = _recoverable_locations(primary, names, dex_list)
    var patch = _patch_guidance(primary, obf, native_heavy)
    var health := _build_health(manifest, dex_list)

    return {
        "name": source_path.get_file() if not source_path.is_empty() else apk_path.get_file(),
        "path": source_path if not source_path.is_empty() else apk_path,
        "working_path": apk_path,
        "size": total_size, "sha256": sha,
        "manifest": manifest, "entries": entries, "zip_metadata": zip_metadata, "health": health,
        "dex": dex_list, "dex_bytes": dex_bytes, "native_count": native_count, "native_bytes": native_bytes, "abis": abis,
        "frameworks": markers, "primary": primary, "kotlin": kotlin, "compose": compose, "obfuscation": obf,
        "artifacts": artifacts, "remnants": remnants, "mapping": mapping, "sourcemap": sourcemap,
        "native_heavy": native_heavy, "locations": locations, "patch": patch
    }

func _build_health(manifest: Dictionary, dex_list: Array) -> Dictionary:
    var critical: Array[String] = []
    var warnings: Array[String] = []
    var info: Array[String] = []

    if not entry_map.has("AndroidManifest.xml"):
        critical.append("AndroidManifest.xml is missing.")

    var authorities := {}
    for provider in manifest.get("providers", []):
        var authority := String(provider.get("authorities", "")).strip_edges()
        if authority.is_empty():
            continue
        if not authorities.has(authority):
            authorities[authority] = []
        authorities[authority].append(String(provider.get("name", "<unnamed>")))
    var duplicate_authorities: Array = []
    for authority in authorities.keys():
        var owners: Array = authorities[authority]
        if owners.size() > 1:
            duplicate_authorities.append({"authority": String(authority), "providers": owners})
            critical.append("Duplicate ContentProvider authority '%s' is declared by %s." % [authority, ", ".join(owners)])

    var bad_dex: Array[String] = []
    for d in dex_list:
        if not bool(d.get("valid", false)):
            bad_dex.append("%s: %s" % [d.get("name", "DEX"), d.get("error", "parse failure")])
        elif not bool(d.get("integrity_ok", false)):
            bad_dex.append("%s: header checksum/signature/size validation failed" % d.get("name", "DEX"))
    if not bad_dex.is_empty():
        critical.append("DEX integrity problem(s): %s" % "; ".join(bad_dex))
    elif not dex_list.is_empty():
        info.append("All %d DEX file(s) passed structural, SHA-1 header-signature, Adler-32, size and endian checks." % dex_list.size())

    var alignment := _check_zip_alignment()
    if int(alignment.get("misaligned_count", 0)) > 0:
        warnings.append("%d stored ZIP entr%s not 4-byte aligned." % [int(alignment.misaligned_count), "y is" if int(alignment.misaligned_count) == 1 else "ies are"])
    else:
        info.append("All stored ZIP entries inspected are 4-byte aligned.")

    var signing := _detect_signing_schemes()
    if bool(signing.get("v2", false)) or bool(signing.get("v3", false)) or bool(signing.get("v31", false)):
        var schemes: Array[String] = []
        if bool(signing.get("v2", false)): schemes.append("v2")
        if bool(signing.get("v3", false)): schemes.append("v3")
        if bool(signing.get("v31", false)): schemes.append("v3.1")
        info.append("APK Signing Block contains scheme marker(s): %s." % ", ".join(schemes))
    elif bool(signing.get("v1_metadata", false)):
        warnings.append("No APK Signing Block (v2/v3) was found; only JAR/v1 signature metadata is present. Cryptographic verification is outside this in-app static check.")
    else:
        critical.append("No APK signing-scheme metadata was detected; an unsigned APK is not installable as a normal release package.")

    if bool(zip_metadata.get("zip64", false)):
        info.append("ZIP64 central-directory metadata is present and was parsed.")

    var status := "OK"
    if not critical.is_empty(): status = "Critical"
    elif not warnings.is_empty(): status = "Warnings"
    return {
        "status": status,
        "critical": critical,
        "warnings": warnings,
        "info": info,
        "duplicate_authorities": duplicate_authorities,
        "signing": signing,
        "alignment": alignment,
        "dex_problem_count": bad_dex.size()
    }

func _check_zip_alignment() -> Dictionary:
    var out := {"checked": 0, "misaligned_count": 0, "misaligned": [], "native_page_checked": 0, "native_page_misaligned": []}
    var f = FileAccess.open(apk_path, FileAccess.READ)
    if f == null:
        return out
    var file_size := f.get_length()
    for e in entries:
        if int(e.method) != 0 or String(e.name).ends_with("/"):
            continue
        var local_off := int(e.local_offset)
        if local_off < 0 or local_off + 30 > file_size:
            continue
        f.seek(local_off)
        var h := f.get_buffer(30)
        if h.size() != 30 or _u32(h, 0) != 0x04034b50:
            continue
        var data_off := local_off + 30 + _u16(h, 26) + _u16(h, 28)
        out.checked = int(out.checked) + 1
        if data_off % 4 != 0:
            out.misaligned_count = int(out.misaligned_count) + 1
            if out.misaligned.size() < 50:
                out.misaligned.append({"name": String(e.name), "offset": data_off})
        if String(e.name).to_lower().begins_with("lib/") and String(e.name).to_lower().ends_with(".so"):
            out.native_page_checked = int(out.native_page_checked) + 1
            if data_off % 16384 != 0 and out.native_page_misaligned.size() < 50:
                out.native_page_misaligned.append({"name": String(e.name), "offset": data_off})
    return out

func _detect_signing_schemes() -> Dictionary:
    var result := {"v1_metadata": false, "v2": false, "v3": false, "v31": false, "signing_block": false}
    var has_sig := false
    var has_sf := false
    for e in entries:
        var n := String(e.name).to_upper()
        if n.begins_with("META-INF/") and (n.ends_with(".RSA") or n.ends_with(".DSA") or n.ends_with(".EC")):
            has_sig = true
        if n.begins_with("META-INF/") and n.ends_with(".SF"):
            has_sf = true
    result.v1_metadata = has_sig and has_sf

    var cd_off := int(zip_metadata.get("central_directory_offset", 0))
    if cd_off < 24:
        return result
    var f = FileAccess.open(apk_path, FileAccess.READ)
    if f == null:
        return result
    f.seek(cd_off - 24)
    var footer := f.get_buffer(24)
    if footer.size() != 24 or footer.slice(8, 24).get_string_from_ascii() != "APK Sig Block 42":
        return result
    var block_size := _u64(footer, 0)
    var total_size := block_size + 8
    var block_start := cd_off - total_size
    if block_size < 24 or block_start < 0 or total_size > 64 * 1024 * 1024:
        return result
    f.seek(block_start)
    var block := f.get_buffer(total_size)
    if block.size() != total_size or _u64(block, 0) != block_size:
        return result
    result.signing_block = true
    var p := 8
    var pairs_end := block.size() - 24
    while p + 12 <= pairs_end:
        var pair_len := _u64(block, p)
        if pair_len < 4 or p + 8 + pair_len > pairs_end:
            break
        var id := _u32(block, p + 8)
        if id == 0x7109871a: result.v2 = true
        elif id == 0xf05368c0: result.v3 = true
        elif id == 0x1b93ad61: result.v31 = true
        p += 8 + pair_len
    return result

func search(query: String, max_hits: int = 500) -> Array:
    var q = query.strip_edges()
    if q.is_empty() or analysis.is_empty():
        return []
    var ql = q.to_lower()
    var hits: Array = []
    for d in analysis.dex:
        if not bool(d.get("valid", false)):
            continue
        var c = 0
        for m in d.methods:
            var md = String(m.get("class_descriptor", ""))
            var mn = String(m.get("name", ""))
            if md.to_lower().contains(ql) or mn.to_lower().contains(ql):
                hits.append({"path": d.name, "type": "DEX method/class", "detail": _method_display(m), "score": 100})
                c += 1
                if c >= 300: break
        c = 0
        for s in d.strings:
            var st = String(s)
            if st.to_lower().contains(ql):
                hits.append({"path": d.name, "type": "DEX string", "detail": st.substr(0, min(st.length(), 700)), "score": 80})
                c += 1
                if c >= 300: break
    for e in entries:
        var name = String(e.name)
        var l = name.to_lower()
        if l.contains(ql):
            hits.append({"path": name, "type": "Entry name", "detail": name, "score": 75})
        if hits.size() >= max_hits:
            break
        var usize = int(e.size)
        if _is_text_like(l) and usize <= MAX_TEXT_SEARCH:
            var b = zip.read_file(name)
            var t = b.get_string_from_utf8()
            var at = t.to_lower().find(ql)
            if at >= 0:
                var start = max(0, at - 220)
                var ln = min(t.length() - start, q.length() + 520)
                hits.append({"path": name, "type": "Text asset", "detail": t.substr(start, ln).replace("\n", " ").replace("\r", " "), "score": 90})
        elif _is_binary_searchable(l) and q.length() >= 4 and usize <= MAX_BINARY_SEARCH:
            var b = zip.read_file(name)
            var ascii_at := _byte_index_ascii_ci(b, ql.to_utf8_buffer())
            var utf16_needle := _ascii_utf16le(ql)
            var utf16_at := _byte_index(b, utf16_needle) if not utf16_needle.is_empty() else -1
            if ascii_at >= 0:
                hits.append({"path": name, "type": "Binary ASCII hit", "detail": "Case-insensitive ASCII token at byte offset 0x%X. Investigate strings, symbols and callers in this artifact." % ascii_at, "score": 70})
            if utf16_at >= 0 and hits.size() < max_hits:
                hits.append({"path": name, "type": "Binary UTF-16LE hit", "detail": "UTF-16LE token at byte offset 0x%X. Investigate wide strings and references in this artifact." % utf16_at, "score": 70})
        if hits.size() >= max_hits:
            break
    hits.sort_custom(func(a,b): return int(a.score) > int(b.score))
    return hits

func report_text() -> String:
    if analysis.is_empty():
        return "No APK analyzed.\n"
    var a = analysis
    var m = a.manifest
    var lines: Array[String] = []
    lines.append("BACKGROUND GREMLIN GROUP — APK RECOVERY ANALYSIS")
    lines.append("don't do evil")
    lines.append("")
    lines.append("APK: %s" % a.name)
    lines.append("SHA-256: %s" % a.sha256)
    lines.append("Size: %s" % _human(int(a.size)))
    lines.append("Package: %s" % m.package_name)
    lines.append("Version: %s (code %s)" % [m.version_name, str(m.version_code)])
    lines.append("SDK: min %s / target %s" % [str(m.min_sdk), str(m.target_sdk)])
    lines.append("Primary stack: %s" % a.primary)
    lines.append("Kotlin: %s | Jetpack Compose: %s" % [str(a.kotlin), str(a.compose)])
    lines.append("DEX: %d file(s), %s" % [a.dex.size(), _human(int(a.dex_bytes))])
    lines.append("Native: %d .so file(s), %s | ABIs: %s" % [int(a.native_count), _human(int(a.native_bytes)), ", ".join(a.abis) if not a.abis.is_empty() else "none"])
    lines.append("Packaging health: %s" % a.health.status)
    for x in a.health.critical:
        lines.append("  CRITICAL: %s" % x)
    for x in a.health.warnings:
        lines.append("  WARNING: %s" % x)
    for x in a.health.info:
        lines.append("  INFO: %s" % x)
    for d in a.dex:
        lines.append("  DEX %s: version=%s parseable=%s integrity=%s SHA1=%s Adler32=%s declared=%s actual=%s" % [d.name, d.version, str(d.valid), str(d.integrity_ok), str(d.sha1_ok), str(d.adler32_ok), str(d.declared_file_size), str(d.size)])
    lines.append("Obfuscation: %s / %d/100 heuristic" % [a.obfuscation.level, int(a.obfuscation.score)])
    for r in a.obfuscation.reasons:
        lines.append("  - %s" % r)
    lines.append("")
    lines.append("FRAMEWORK EVIDENCE")
    for fw in a.frameworks:
        lines.append("- %s — %d%% confidence" % [fw.name, int(fw.confidence)])
        for ev in fw.evidence:
            lines.append("    Found marker: %s" % ev)
    lines.append("")
    lines.append("RECOVERABLE APPLICATION CODE LOCATIONS")
    for x in a.locations:
        lines.append("- %s" % x)
    lines.append("")
    lines.append("MOST PRACTICAL PATCH PATH")
    lines.append(a.patch)
    lines.append("")
    lines.append("HIGH-VALUE REMNANTS")
    if a.remnants.is_empty():
        lines.append("- None detected by filename heuristics. Continue searching strings/assets manually.")
    else:
        for x in a.remnants:
            lines.append("- %s" % x)
    lines.append("")
    lines.append("RECOVERY PLAN")
    for x in recovery_plan():
        lines.append(x)
    lines.append("")
    lines.append("TOP RECOVERY ARTIFACTS")
    for x in a.artifacts:
        lines.append("[P%d] %s  %s  %s" % [int(x.priority), x.kind, _human(int(x.size)), x.name])
        lines.append("    %s" % x.note)
    lines.append("")
    lines.append("HARD LIMITS")
    lines.append("An APK normally cannot restore material that never made it into the package: comments, Git history, original Gradle project files, tests, source-only annotations, or code removed before packaging. R8/ProGuard may irreversibly rename symbols unless mapping information survives. Native libraries require native reverse engineering. This analyzer pivots to source maps, managed assemblies, debug artifacts, strings, resources, metadata, assets, JNI/native strings, and behavioral identifiers rather than treating those limits as the end of the trail.")
    return "\n".join(lines) + "\n"

func recovery_plan() -> Array[String]:
    var a = analysis
    var p: Array[String] = []
    p.append("1. Preserve the original APK. Work only on a copy and record its SHA-256: %s" % a.sha256)
    p.append("2. Export the report and preservation bundle before modifying anything.")
    if a.mapping:
        p.append("3. IMMEDIATELY duplicate mapping/proguard artifacts. They may restore minified class/member names.")
    if a.sourcemap:
        p.append("3. IMMEDIATELY preserve source maps. They may restore original JavaScript/TypeScript source names and locations.")
    p.append("4. Run JADX against the untouched APK: jadx -d recovered-jadx \"%s\"" % a.name)
    p.append("5. Decode a separate working copy with Apktool: apktool d \"%s\" -o recovered-apk" % a.name)
    p.append("6. Search for the target function name, UI strings, URLs, log messages, preference keys, JSON field names, constants, and nearby call sites.")
    p.append("7. Correlate readable JADX output with matching smali under smali*/. Patch the smallest possible method body.")
    p.append("8. Rebuild: apktool b recovered-apk -o rebuilt-unsigned.apk")
    p.append("9. Align/sign with zipalign + apksigner using your own release/upload key.")
    p.append("10. Verify and test on an emulator/disposable device before replacing anything important.")
    if a.native_heavy:
        p.append("Native-code branch: preserve every ABI under lib/ and identify JNI entry points/call sites leading to the target before binary patching.")
    if int(a.obfuscation.score) >= 40:
        p.append("Obfuscation branch: names are unreliable. Pivot on strings, resource IDs, manifest components, data-flow, method signatures, call graphs, and native/JNI boundaries.")
    return p

func write_report(path: String) -> int:
    var f = FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        return FileAccess.get_open_error()
    f.store_string(report_text())
    return OK

func write_recovery_bundle(path: String, progress: Callable = Callable()) -> int:
    if analysis.is_empty():
        return ERR_UNCONFIGURED
    var exported := export_recovery_project(default_output_root(), progress)
    var err := int(exported.get("error", ERR_CANT_CREATE))
    if err != OK:
        return err
    var project_dir := String(exported.get("path", ""))
    if project_dir.is_empty():
        return ERR_CANT_CREATE
    var zip_destination := path
    var staged_zip := ""
    if path.begins_with("content://"):
        var staging_dir := "user://staging"
        var mk := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(staging_dir))
        if mk != OK and mk != ERR_ALREADY_EXISTS:
            return mk
        staged_zip = "%s/recovery_project_%d.zip" % [staging_dir, Time.get_ticks_usec()]
        zip_destination = staged_zip
    err = _zip_project_directory(project_dir, zip_destination, progress)
    if err != OK:
        if not staged_zip.is_empty() and FileAccess.file_exists(staged_zip):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(staged_zip))
        return err
    if not staged_zip.is_empty():
        err = _copy_file_bytes(staged_zip, path)
        if FileAccess.file_exists(staged_zip):
            DirAccess.remove_absolute(ProjectSettings.globalize_path(staged_zip))
    return err

func default_output_root() -> String:
    return "user://BGGremlinAPKRecovery/Output"

func project_output_name() -> String:
    if analysis.is_empty():
        return "unconfigured"
    var base := _safe_filename(String(analysis.get("name", "apk")))
    if base.to_lower().ends_with(".apk"):
        base = base.substr(0, base.length() - 4)
    var sha := String(analysis.get("sha256", ""))
    var suffix := sha.substr(0, 12) if sha.length() >= 12 else sha
    return "%s_%s" % [base, suffix] if not suffix.is_empty() else base

func export_recovery_project(root_dir: String = "", progress: Callable = Callable()) -> Dictionary:
    if analysis.is_empty() or not zip_opened:
        return {"error": ERR_UNCONFIGURED, "path": ""}
    if root_dir.is_empty():
        root_dir = default_output_root()
    var project_dir := root_dir.path_join(project_output_name())
    var abs_project := _absolute_path(project_dir)
    var mk := DirAccess.make_dir_recursive_absolute(abs_project)
    if mk != OK and mk != ERR_ALREADY_EXISTS:
        return {"error": mk, "path": project_dir}

    var dirs := [
        "reports", "inventories", "raw_apk", "raw_apk/tree", "rebuild", "rebuild/dex",
        "rebuild/resources", "recovered_sources", "framework_payloads", "native", "obfuscation",
        "binary_evidence", "checksums"
    ]
    for rel in dirs:
        mk = DirAccess.make_dir_recursive_absolute(_absolute_path(project_dir.path_join(rel)))
        if mk != OK and mk != ERR_ALREADY_EXISTS:
            return {"error": mk, "path": project_dir}

    var total_steps := entries.size() + 14
    var step := 0
    var err := _copy_file_bytes(apk_path, project_dir.path_join("raw_apk/original.apk"))
    if err != OK:
        return {"error": err, "path": project_dir}
    step += 1
    if progress.is_valid(): progress.call(step, total_steps, "Preserved original APK")

    var source_inventory: Array[String] = []
    var framework_inventory: Array[String] = []
    var native_inventory: Array[String] = []
    var obfuscation_inventory: Array[String] = []
    var extracted_count := 0
    var extracted_bytes := 0

    for e in entries:
        step += 1
        var entry_name := String(e.name)
        if entry_name.ends_with("/"):
            continue
        var safe_rel := _safe_bundle_entry(entry_name)
        var data := zip.read_file(entry_name)
        var raw_path := project_dir.path_join("raw_apk/tree").path_join(safe_rel)
        err = _write_bytes(raw_path, data)
        if err != OK:
            return {"error": err, "path": project_dir}
        extracted_count += 1
        extracted_bytes += data.size()

        var lower := entry_name.to_lower()
        if _is_dex_name(lower):
            err = _write_bytes(project_dir.path_join("rebuild/dex").path_join(safe_rel.get_file()), data)
            if err != OK: return {"error": err, "path": project_dir}
            var dex_dump := _dex_rebuild_dump(entry_name, data)
            err = _write_text(project_dir.path_join("rebuild/dex").path_join(safe_rel.get_file() + ".code-items.txt"), dex_dump.code_items)
            if err != OK: return {"error": err, "path": project_dir}
            err = _write_text(project_dir.path_join("rebuild/dex").path_join(safe_rel.get_file() + ".classes.tsv"), dex_dump.classes)
            if err != OK: return {"error": err, "path": project_dir}
            err = _write_text(project_dir.path_join("rebuild/dex").path_join(safe_rel.get_file() + ".methods.tsv"), dex_dump.methods)
            if err != OK: return {"error": err, "path": project_dir}
            err = _write_text(project_dir.path_join("rebuild/dex").path_join(safe_rel.get_file() + ".strings.txt"), dex_dump.strings)
            if err != OK: return {"error": err, "path": project_dir}
        elif lower == "androidmanifest.xml":
            err = _write_bytes(project_dir.path_join("rebuild/AndroidManifest.xml"), data)
            if err != OK: return {"error": err, "path": project_dir}
        elif lower == "resources.arsc":
            err = _write_bytes(project_dir.path_join("rebuild/resources/resources.arsc"), data)
            if err != OK: return {"error": err, "path": project_dir}

        if _is_source_or_text_artifact(lower):
            var source_path := project_dir.path_join("recovered_sources").path_join(safe_rel)
            err = _write_bytes(source_path, data)
            if err != OK: return {"error": err, "path": project_dir}
            source_inventory.append(entry_name)

        if _is_framework_payload(lower):
            var fw_path := project_dir.path_join("framework_payloads").path_join(safe_rel)
            err = _write_bytes(fw_path, data)
            if err != OK: return {"error": err, "path": project_dir}
            framework_inventory.append(entry_name)

        if lower.begins_with("lib/") and lower.ends_with(".so"):
            var parts := entry_name.split("/", false)
            var abi := String(parts[1]) if parts.size() >= 3 else "unknown-abi"
            var native_path := project_dir.path_join("native").path_join(_safe_filename(abi)).path_join(_safe_filename(entry_name.get_file()))
            err = _write_bytes(native_path, data)
            if err != OK: return {"error": err, "path": project_dir}
            native_inventory.append(entry_name)
            var string_text := _extract_binary_strings(data, 4)
            err = _write_text(native_path + ".strings.txt", string_text)
            if err != OK: return {"error": err, "path": project_dir}

        if _is_obfuscation_artifact(lower):
            var obf_path := project_dir.path_join("obfuscation").path_join(safe_rel)
            err = _write_bytes(obf_path, data)
            if err != OK: return {"error": err, "path": project_dir}
            obfuscation_inventory.append(entry_name)

        if _is_binary_searchable(lower) and not (lower.begins_with("lib/") and lower.ends_with(".so")):
            var evidence_name := _safe_filename(entry_name.replace("/", "__")) + ".strings.txt"
            err = _write_text(project_dir.path_join("binary_evidence").path_join(evidence_name), _extract_binary_strings(data, 4))
            if err != OK: return {"error": err, "path": project_dir}

        if progress.is_valid(): progress.call(step, total_steps, entry_name)

    var reports := {
        "reports/analysis.txt": report_text(),
        "reports/analysis.html": report_html(),
        "reports/analysis.json": report_json(),
        "inventories/recovery_artifacts.csv": artifacts_csv(),
        "inventories/apk_structure.csv": structure_csv(),
        "inventories/dex_inventory.csv": dex_inventory_csv(),
        "inventories/recovered_source_files.txt": "\n".join(source_inventory) + ("\n" if not source_inventory.is_empty() else ""),
        "inventories/framework_payloads.txt": "\n".join(framework_inventory) + ("\n" if not framework_inventory.is_empty() else ""),
        "inventories/native_libraries.txt": "\n".join(native_inventory) + ("\n" if not native_inventory.is_empty() else ""),
        "inventories/obfuscation_artifacts.txt": "\n".join(obfuscation_inventory) + ("\n" if not obfuscation_inventory.is_empty() else ""),
        "rebuild/AndroidManifest.summary.txt": _manifest_summary(),
        "rebuild/REBUILD_GUIDE.txt": _rebuild_guide(),
        "README.txt": _project_readme(extracted_count, extracted_bytes)
    }
    for rel in reports.keys():
        err = _write_text(project_dir.path_join(String(rel)), String(reports[rel]))
        if err != OK: return {"error": err, "path": project_dir}
        step += 1
        if progress.is_valid(): progress.call(step, total_steps, String(rel))

    var manifest := {
        "format": "BGGremlin APK Recovery Project",
        "format_version": 1,
        "tool_version": "1.5.1",
        "source_apk": String(analysis.get("name", "")),
        "source_sha256": String(analysis.get("sha256", "")),
        "source_size": int(analysis.get("size", 0)),
        "package_name": String(analysis.get("manifest", {}).get("package_name", "Unknown")),
        "primary_stack": String(analysis.get("primary", "Unknown")),
        "project_folder": project_output_name(),
        "entry_count": entries.size(),
        "extracted_file_count": extracted_count,
        "extracted_uncompressed_bytes": extracted_bytes,
        "dex_count": analysis.get("dex", []).size(),
        "native_library_count": int(analysis.get("native_count", 0)),
        "abis": analysis.get("abis", []),
        "obfuscation": analysis.get("obfuscation", {}),
        "frameworks": analysis.get("frameworks", []),
        "output_sections": ["reports", "inventories", "raw_apk", "rebuild", "recovered_sources", "framework_payloads", "native", "obfuscation", "binary_evidence", "checksums"]
    }
    err = _write_text(project_dir.path_join("project_manifest.json"), JSON.stringify(manifest, "  ", false) + "\n")
    if err != OK: return {"error": err, "path": project_dir}
    err = _write_text(project_dir.path_join("checksums/SOURCE_APK_SHA256.txt"), "%s  %s\n" % [analysis.sha256, analysis.name])
    if err != OK: return {"error": err, "path": project_dir}
    _write_text(project_dir.path_join("checksums/OUTPUT_SHA256.txt"), _directory_checksums(project_dir))
    return {"error": OK, "path": project_dir, "absolute_path": abs_project, "files": extracted_count, "bytes": extracted_bytes}

func report_json() -> String:
    return JSON.stringify(analysis, "  ", false) + "\n"

func report_html() -> String:
    var title := "BG Gremlin APK Recovery — %s" % String(analysis.get("name", "APK"))
    var body := _html_escape(report_text())
    return "<!doctype html>\n<html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>%s</title><style>body{background:#050505;color:#f2f2f2;font-family:ui-monospace,monospace;margin:24px}h1{color:#a6ff00}pre{white-space:pre-wrap;word-break:break-word;background:#141414;border:1px solid #383838;padding:16px;border-radius:10px}</style></head><body><h1>%s</h1><pre>%s</pre></body></html>\n" % [_html_escape(title), _html_escape(title), body]

func artifacts_csv() -> String:
    var rows: Array[String] = ["priority,kind,size_bytes,path,note"]
    for item in analysis.get("artifacts", []):
        rows.append("%d,%s,%d,%s,%s" % [int(item.get("priority", 0)), _csv(String(item.get("kind", ""))), int(item.get("size", 0)), _csv(String(item.get("name", ""))), _csv(String(item.get("note", "")))])
    return "\n".join(rows) + "\n"

func structure_csv() -> String:
    var rows: Array[String] = ["path,size_bytes,compressed_size,compression_method,crc32,local_header_offset"]
    for item in entries:
        rows.append("%s,%d,%d,%d,%d,%d" % [_csv(String(item.name)), int(item.size), int(item.compressed_size), int(item.method), int(item.crc), int(item.local_offset)])
    return "\n".join(rows) + "\n"

func dex_inventory_csv() -> String:
    var rows: Array[String] = ["dex,version,size_bytes,valid,integrity_ok,string_count,class_count,method_count"]
    for d in analysis.get("dex", []):
        rows.append("%s,%s,%d,%s,%s,%d,%d,%d" % [_csv(String(d.get("name", ""))), _csv(String(d.get("version", ""))), int(d.get("size", 0)), str(bool(d.get("valid", false))), str(bool(d.get("integrity_ok", false))), d.get("strings", []).size(), d.get("classes", []).size(), d.get("methods", []).size()])
    return "\n".join(rows) + "\n"

func _dex_rebuild_dump(dex_name: String, b: PackedByteArray) -> Dictionary:
    var invalid := {"code_items": "DEX parse failed for %s\n" % dex_name, "classes": "descriptor\tsource\n", "methods": "method_index\tclass\tname\tsignature\n", "strings": ""}
    if b.size() < 112 or b.slice(0, 4).get_string_from_ascii() != "dex\n":
        return invalid
    var ss := _u32(b, 56); var so := _u32(b, 60)
    var ts := _u32(b, 64); var to := _u32(b, 68)
    var ps := _u32(b, 72); var po := _u32(b, 76)
    var ms := _u32(b, 88); var mo := _u32(b, 92)
    var cs := _u32(b, 96); var co := _u32(b, 100)
    if ss > 5000000 or ts > 5000000 or ps > 5000000 or ms > 20000000 or cs > 5000000:
        return invalid
    if so + ss * 4 > b.size() or to + ts * 4 > b.size() or po + ps * 12 > b.size() or mo + ms * 8 > b.size() or co + cs * 32 > b.size():
        return invalid
    var strings: Array[String] = []
    for i in range(ss):
        var sp := _u32(b, so + i * 4)
        if sp >= b.size():
            strings.append("")
            continue
        var u := _read_uleb(b, sp); sp = int(u[1])
        var se: int = sp; var hard: int = int(min(b.size(), sp + 4000000))
        while se < hard and b[se] != 0: se += 1
        strings.append(_decode_mutf8(b, sp, se))
    var tids: Array[int] = []
    for i in range(ts): tids.append(_u32(b, to + i * 4))
    var methods: Array = []
    var method_lines: Array[String] = ["method_index\tclass\tname\tsignature"]
    for i in range(ms):
        var mp := mo + i * 8
        var class_idx := _u16(b, mp)
        var proto_idx := _u16(b, mp + 2)
        var name_idx := _u32(b, mp + 4)
        var class_desc := _type_descriptor(tids, strings, class_idx)
        var method_name := String(strings[name_idx]) if name_idx < strings.size() else ""
        var sig := _proto_descriptor(b, po, ps, proto_idx, tids, strings)
        methods.append({"index": i, "class": class_desc, "name": method_name, "signature": sig})
        method_lines.append("%d\t%s\t%s\t%s" % [i, _tsv(class_desc), _tsv(method_name), _tsv(sig)])
    var class_lines: Array[String] = ["descriptor\tsource"]
    var code_lines: Array[String] = []
    code_lines.append("# Exact DEX code-item export for %s" % dex_name)
    code_lines.append("# Every insn word below is the original 16-bit Dalvik code unit in file order. Obfuscated names are preserved exactly as present in the DEX.")
    code_lines.append("# This is lossless code-item evidence; classes*.dex beside this file remains the authoritative rebuild input.\n")
    for ci in range(cs):
        var cp := co + ci * 32
        var class_idx := _u32(b, cp)
        var source_idx := _u32(b, cp + 16)
        var class_data_off := _u32(b, cp + 24)
        var class_desc := _type_descriptor(tids, strings, class_idx)
        var source_name := "" if source_idx == 0xffffffff or source_idx >= strings.size() else String(strings[source_idx])
        class_lines.append("%s\t%s" % [_tsv(class_desc), _tsv(source_name)])
        if class_data_off == 0 or class_data_off >= b.size():
            continue
        var q := class_data_off
        var r := _read_uleb(b, q); var static_fields := int(r[0]); q = int(r[1])
        r = _read_uleb(b, q); var instance_fields := int(r[0]); q = int(r[1])
        r = _read_uleb(b, q); var direct_methods := int(r[0]); q = int(r[1])
        r = _read_uleb(b, q); var virtual_methods := int(r[0]); q = int(r[1])
        for _f in range(static_fields + instance_fields):
            r = _read_uleb(b, q); q = int(r[1])
            r = _read_uleb(b, q); q = int(r[1])
        var running_method_idx := 0
        for kind_index in range(2):
            var count := direct_methods if kind_index == 0 else virtual_methods
            running_method_idx = 0
            for _mi in range(count):
                r = _read_uleb(b, q); running_method_idx += int(r[0]); q = int(r[1])
                r = _read_uleb(b, q); var access_flags := int(r[0]); q = int(r[1])
                r = _read_uleb(b, q); var code_off := int(r[0]); q = int(r[1])
                var md: Dictionary = methods[running_method_idx] if running_method_idx >= 0 and running_method_idx < methods.size() else {"class": class_desc, "name": "method_%d" % running_method_idx, "signature": ""}
                code_lines.append("METHOD index=%d kind=%s class=%s name=%s signature=%s access_flags=0x%X code_off=0x%X" % [running_method_idx, "direct" if kind_index == 0 else "virtual", String(md.class), String(md.name), String(md.signature), access_flags, code_off])
                if code_off == 0:
                    code_lines.append("  no_code_item=true\n")
                    continue
                if code_off + 16 > b.size():
                    code_lines.append("  ERROR code item outside DEX\n")
                    continue
                var registers_size := _u16(b, code_off)
                var ins_size := _u16(b, code_off + 2)
                var outs_size := _u16(b, code_off + 4)
                var tries_size := _u16(b, code_off + 6)
                var debug_info_off := _u32(b, code_off + 8)
                var insns_size := _u32(b, code_off + 12)
                var insns_off := code_off + 16
                var byte_count := insns_size * 2
                code_lines.append("  registers=%d ins=%d outs=%d tries=%d debug_info_off=0x%X insns_size_code_units=%d" % [registers_size, ins_size, outs_size, tries_size, debug_info_off, insns_size])
                if insns_off + byte_count > b.size():
                    code_lines.append("  ERROR instruction array outside DEX\n")
                    continue
                var line := "  code_units:"
                for word_index in range(insns_size):
                    if word_index % 16 == 0:
                        if line != "  code_units:": code_lines.append(line)
                        line = "    %08X:" % word_index
                    line += " %04X" % _u16(b, insns_off + word_index * 2)
                if line != "  code_units:": code_lines.append(line)
                code_lines.append("")
    return {
        "code_items": "\n".join(code_lines) + "\n",
        "classes": "\n".join(class_lines) + "\n",
        "methods": "\n".join(method_lines) + "\n",
        "strings": "\n".join(strings) + ("\n" if not strings.is_empty() else "")
    }

func _type_descriptor(tids: Array[int], strings: Array[String], type_idx: int) -> String:
    if type_idx < 0 or type_idx >= tids.size(): return ""
    var string_idx := tids[type_idx]
    return String(strings[string_idx]) if string_idx >= 0 and string_idx < strings.size() else ""

func _proto_descriptor(b: PackedByteArray, proto_off: int, proto_size: int, proto_idx: int, tids: Array[int], strings: Array[String]) -> String:
    if proto_idx < 0 or proto_idx >= proto_size: return ""
    var p := proto_off + proto_idx * 12
    if p + 12 > b.size(): return ""
    var return_idx := _u32(b, p + 4)
    var params_off := _u32(b, p + 8)
    var params: Array[String] = []
    if params_off != 0 and params_off + 4 <= b.size():
        var count := _u32(b, params_off)
        if count < 100000 and params_off + 4 + count * 2 <= b.size():
            for i in range(count):
                params.append(_type_descriptor(tids, strings, _u16(b, params_off + 4 + i * 2)))
    return "(%s)%s" % ["".join(params), _type_descriptor(tids, strings, return_idx)]

func _extract_binary_strings(data: PackedByteArray, min_len: int = 4) -> String:
    var out: Array[String] = []
    var current := PackedByteArray()
    for byte in data:
        var c := int(byte)
        if c >= 32 and c <= 126:
            current.append(c)
        else:
            if current.size() >= min_len:
                out.append(current.get_string_from_ascii())
            current.clear()
    if current.size() >= min_len:
        out.append(current.get_string_from_ascii())
    if data.size() <= 32 * 1024 * 1024:
        var utf16_chars: Array[int] = []
        var i := 0
        while i + 1 < data.size():
            var lo := int(data[i]); var hi := int(data[i + 1])
            if hi == 0 and lo >= 32 and lo <= 126:
                utf16_chars.append(lo)
                i += 2
            else:
                if utf16_chars.size() >= min_len:
                    var s := ""
                    for cp in utf16_chars: s += String.chr(cp)
                    out.append("[UTF16LE] " + s)
                utf16_chars.clear()
                i += 2
        if utf16_chars.size() >= min_len:
            var s := ""
            for cp in utf16_chars: s += String.chr(cp)
            out.append("[UTF16LE] " + s)
    return "\n".join(out) + ("\n" if not out.is_empty() else "")

func _is_source_or_text_artifact(lower: String) -> bool:
    for ext in [".java", ".kt", ".kts", ".smali", ".cs", ".fs", ".vb", ".dart", ".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx", ".lua", ".py", ".rb", ".php", ".go", ".rs", ".c", ".cc", ".cpp", ".cxx", ".h", ".hpp", ".html", ".htm", ".css", ".scss", ".sass", ".less", ".xml", ".json", ".json5", ".yaml", ".yml", ".toml", ".ini", ".cfg", ".conf", ".properties", ".gradle", ".txt", ".md", ".csv", ".sql", ".graphql", ".proto", ".map", ".jsbundle"]:
        if lower.ends_with(ext): return true
    return lower.ends_with("index.android.bundle") or lower.contains("mapping.txt") or lower.contains("project.godot")

func _is_framework_payload(lower: String) -> bool:
    return lower.begins_with("assets/flutter_assets/") or lower.contains("kernel_blob") or lower.contains("snapshot") or lower.ends_with("index.android.bundle") or (lower.contains("hermes") and not lower.ends_with(".so")) or (lower.contains("reactnative") and not lower.ends_with(".so")) or lower.contains("global-metadata.dat") or (lower.contains("il2cpp") and not lower.ends_with(".so")) or (lower.contains("unity") and not lower.ends_with(".so")) or lower.begins_with("assets/bin/data/") or lower.begins_with("assemblies/") or lower.contains("assemblies.blob") or lower.begins_with("assets/www/") or lower.contains("cordova") or lower.contains("capacitor") or lower.begins_with("assets/.godot/") or lower.ends_with("project.godot")

func _is_obfuscation_artifact(lower: String) -> bool:
    return lower.contains("mapping.txt") or lower.contains("proguard") or lower.ends_with(".map") or lower.ends_with(".pdb") or lower.ends_with(".mdb") or lower.ends_with(".symbols") or lower.ends_with(".sym")

func _manifest_summary() -> String:
    var m: Dictionary = analysis.get("manifest", {})
    var lines: Array[String] = []
    lines.append("Package: %s" % String(m.get("package_name", "Unknown")))
    lines.append("Version name: %s" % String(m.get("version_name", "Unknown")))
    lines.append("Version code: %s" % str(m.get("version_code", -1)))
    lines.append("Min SDK: %s" % str(m.get("min_sdk", -1)))
    lines.append("Target SDK: %s" % str(m.get("target_sdk", -1)))
    lines.append("Application category: %s" % String(m.get("application_category", "")))
    lines.append("isGame: %s" % str(bool(m.get("is_game", false))))
    lines.append("Providers:")
    for provider in m.get("providers", []):
        lines.append("  %s | authorities=%s | exported=%s" % [String(provider.get("name", "")), String(provider.get("authorities", "")), String(provider.get("exported", ""))])
    return "\n".join(lines) + "\n"

func _rebuild_guide() -> String:
    var apk_name := String(analysis.get("name", "application.apk"))
    var project := project_output_name()
    var lines: Array[String] = []
    lines.append("BG Gremlin APK Recovery 1.5.1 — rebuild-oriented export")
    lines.append("")
    lines.append("Project folder: %s" % project)
    lines.append("Source APK: %s" % apk_name)
    lines.append("Source SHA-256: %s" % String(analysis.get("sha256", "")))
    lines.append("")
    lines.append("The raw_apk/original.apk file is an exact preserved copy. raw_apk/tree contains every APK ZIP entry extracted without semantic rewriting. rebuild/dex contains the untouched classes*.dex files plus exact DEX strings, class/method tables, signatures, code offsets and original 16-bit Dalvik code units for encoded methods, including obfuscated methods. Native and framework payloads remain byte-identical copies.")
    lines.append("")
    lines.append("For a conventional Android rebuild on a workstation, from this project folder run:")
    lines.append("apktool d -f raw_apk/original.apk -o apktool-decoded")
    lines.append("jadx -d jadx-decompiled raw_apk/original.apk")
    lines.append("apktool b apktool-decoded -o rebuilt-unsigned.apk")
    lines.append("zipalign -P 16 -f 4 rebuilt-unsigned.apk rebuilt-aligned.apk")
    lines.append("Signing cannot be made into a concrete command from APK contents because the private signing keystore path and alias are not present in the APK. Sign rebuilt-aligned.apk with the private key that belongs to the package if update compatibility is required.")
    lines.append("")
    lines.append("The signing command necessarily depends on the private keystore you control; no signing secret is embedded or manufactured by this recovery export. If the original signing key is unavailable, Android will not accept the rebuilt package as an in-place update to an installation signed by a different key.")
    return "\n".join(lines) + "\n"

func _project_readme(extracted_count: int, extracted_bytes: int) -> String:
    var lines: Array[String] = []
    lines.append("BG Gremlin APK Recovery 1.5.1")
    lines.append("Background Gremlin Group — don't do evil")
    lines.append("")
    lines.append("This directory is the recovery project for %s." % String(analysis.get("name", "APK")))
    lines.append("Source SHA-256: %s" % String(analysis.get("sha256", "")))
    lines.append("Extracted APK entries: %d" % extracted_count)
    lines.append("Extracted uncompressed bytes: %d" % extracted_bytes)
    lines.append("")
    lines.append("raw_apk/original.apk is the untouched source APK. raw_apk/tree is the complete ZIP payload. rebuild contains the manifest, resource table, untouched DEX files and exact DEX reconstruction evidence. recovered_sources collects source-like and text artifacts that actually survived in the APK. framework_payloads collects Flutter, React Native/Hermes, Unity, Xamarin/.NET, Cordova/Capacitor and Godot payloads. native contains ABI-separated shared objects and printable string evidence. obfuscation preserves mapping, source-map and debug-name artifacts. binary_evidence contains printable string extraction for other binary payloads. reports and inventories provide human- and machine-readable indexes.")
    lines.append("")
    lines.append("Obfuscated identifiers are never discarded. The exporter preserves the raw DEX, original method/class names exactly as encoded, access flags, method signatures, code offsets and exact instruction code units. When decompilation cannot recover original source names or comments, those facts cannot be recreated from information that is absent from the APK; the bytecode and surviving metadata remain available here for reconstruction.")
    return "\n".join(lines) + "\n"

func _zip_project_directory(project_dir: String, zip_path: String, progress: Callable = Callable()) -> int:
    var files: Array[String] = []
    _collect_files_recursive(project_dir, project_dir, files)
    var pack := ZIPPacker.new()
    var err := pack.open(zip_path)
    if err != OK: return err
    for i in range(files.size()):
        var full := files[i]
        var prefix_len := project_dir.length() + (0 if project_dir.ends_with("/") else 1)
        var rel := full.substr(prefix_len) if full.length() >= prefix_len else full.get_file()
        var src := FileAccess.open(full, FileAccess.READ)
        if src == null:
            pack.close(); return FileAccess.get_open_error()
        err = pack.start_file(project_output_name() + "/" + rel.replace("\\", "/"))
        if err != OK:
            pack.close(); return err
        while src.get_position() < src.get_length():
            var chunk := src.get_buffer(min(1024 * 1024, src.get_length() - src.get_position()))
            err = pack.write_file(chunk)
            if err != OK:
                pack.close_file(); pack.close(); return err
        err = pack.close_file()
        if err != OK:
            pack.close(); return err
        if progress.is_valid(): progress.call(i + 1, files.size(), rel)
    return pack.close()

func _collect_files_recursive(root_dir: String, current_dir: String, out: Array[String]) -> void:
    var abs := _absolute_path(current_dir)
    var d := DirAccess.open(abs)
    if d == null: return
    d.list_dir_begin()
    while true:
        var name := d.get_next()
        if name.is_empty(): break
        if name == "." or name == "..": continue
        var child := current_dir.path_join(name)
        if d.current_is_dir(): _collect_files_recursive(root_dir, child, out)
        else: out.append(child)
    d.list_dir_end()

func _directory_checksums(project_dir: String) -> String:
    var files: Array[String] = []
    _collect_files_recursive(project_dir, project_dir, files)
    files.sort()
    var lines: Array[String] = []
    for path in files:
        if path.ends_with("checksums/OUTPUT_SHA256.txt"): continue
        var prefix_len := project_dir.length() + (0 if project_dir.ends_with("/") else 1)
        var rel := path.substr(prefix_len) if path.length() >= prefix_len else path.get_file()
        lines.append("%s  %s" % [_sha256_file(path), rel])
    return "\n".join(lines) + ("\n" if not lines.is_empty() else "")

func _write_bytes(path: String, data: PackedByteArray) -> int:
    var abs := _absolute_path(path)
    var parent := abs.get_base_dir()
    var mk := DirAccess.make_dir_recursive_absolute(parent)
    if mk != OK and mk != ERR_ALREADY_EXISTS: return mk
    var f := FileAccess.open(abs, FileAccess.WRITE)
    if f == null: return FileAccess.get_open_error()
    f.store_buffer(data)
    f.flush()
    return OK

func _write_text(path: String, text: String) -> int:
    return _write_bytes(path, text.to_utf8_buffer())

func _copy_file_bytes(src_path: String, dst_path: String) -> int:
    var src := FileAccess.open(src_path, FileAccess.READ)
    if src == null: return FileAccess.get_open_error()
    var abs := _absolute_path(dst_path)
    var mk := DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
    if mk != OK and mk != ERR_ALREADY_EXISTS: return mk
    var dst := FileAccess.open(abs, FileAccess.WRITE)
    if dst == null: return FileAccess.get_open_error()
    while src.get_position() < src.get_length():
        dst.store_buffer(src.get_buffer(min(1024 * 1024, src.get_length() - src.get_position())))
    dst.flush()
    return OK

func _absolute_path(path: String) -> String:
    return ProjectSettings.globalize_path(path) if path.begins_with("user://") or path.begins_with("res://") else path

func _safe_filename(value: String) -> String:
    var out := ""
    for c in value:
        if "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-".contains(c): out += c
        else: out += "_"
    return out if not out.is_empty() else "unnamed"

func _csv(value: String) -> String:
    return "\"%s\"" % value.replace("\"", "\"\"")

func _tsv(value: String) -> String:
    return value.replace("\t", " ").replace("\r", " ").replace("\n", "\\n")

func _html_escape(value: String) -> String:
    return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;")

func _safe_bundle_entry(name: String) -> String:
    var normalized := name.replace("\\", "/").trim_prefix("/")
    var clean_parts: Array[String] = []
    for raw in normalized.split("/", false):
        var part := String(raw)
        if part.is_empty() or part == ".":
            continue
        if part == "..":
            part = "_parent_"
        var clean := ""
        for ch in part:
            if "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-+@()[]{} ".contains(ch):
                clean += ch
            else:
                clean += "_"
        clean = clean.strip_edges()
        if clean.is_empty() or clean == "." or clean == "..":
            clean = "_entry_"
        clean_parts.append(clean)
    return "/".join(clean_parts) if not clean_parts.is_empty() else "_entry_"

func _unique_bundle_path(path: String, used: Dictionary) -> String:
    if not used.has(path):
        used[path] = true
        return path
    var n := 2
    while used.has("%s.__dup%d" % [path, n]):
        n += 1
    var unique := "%s.__dup%d" % [path, n]
    used[unique] = true
    return unique

func _detect_frameworks(names: Array[String], dex_strings: Array[String]) -> Array:
    var defs = [
        {"name":"Godot Engine", "markers":["libgodot_android.so","org/godotengine/","project.godot",".godot/","assets.sparsepck"]},
        {"name":"Flutter", "markers":["assets/flutter_assets/","libflutter.so","libapp.so","kernel_blob.bin","vm_snapshot_data"]},
        {"name":"React Native / Hermes", "markers":["index.android.bundle","libhermes.so","libreactnativejni.so","hermes-bytecode","react-native"]},
        {"name":"Unity IL2CPP / Mono", "markers":["global-metadata.dat","libil2cpp.so","libunity.so","assets/bin/data/managed/","unityplayeractivity"]},
        {"name":"Xamarin / .NET MAUI", "markers":["assemblies.blob","assemblies/","libmonodroid.so","libmonosgen-2.0.so","microsoft.maui"]},
        {"name":"Cordova / Ionic / Capacitor", "markers":["assets/www/","cordova.js","capacitor.config","ionic"]}
    ]
    var out: Array = []
    for d in defs:
        var evidence: Array[String] = []
        for m in d.markers:
            var hit = ""
            for n in names:
                if n == String(m).to_lower() or n.ends_with("/" + String(m).to_lower()) or n.contains(String(m).to_lower()):
                    hit = n
                    break
            if hit.is_empty():
                for s in dex_strings:
                    if String(s).to_lower().contains(String(m).to_lower()):
                        hit = "DEX:" + String(m)
                        break
            if not hit.is_empty(): evidence.append(hit)
        var confidence = 0
        if not evidence.is_empty():
            confidence = min(99, 50 + evidence.size() * 12)
            if d.name == "Godot Engine" and _name_contains(names, "libgodot_android.so"):
                confidence = max(confidence, 90)
            if d.name == "Flutter" and _name_contains(names, "libapp.so") and _name_contains(names, "flutter_assets"):
                confidence = max(confidence, 88)
            if d.name.begins_with("Unity") and _name_contains(names, "global-metadata.dat") and _name_contains(names, "libil2cpp.so"):
                confidence = max(confidence, 92)
        if confidence > 0:
            out.append({"name": d.name, "confidence": confidence, "evidence": evidence})
    out.sort_custom(func(a,b): return int(a.confidence) > int(b.confidence))
    return out

func _estimate_obfuscation(classes: Array, methods: Array) -> Dictionary:
    var app_classes: Array = []
    for c in classes:
        var d = String(c.get("descriptor", ""))
        if d.is_empty(): continue
        var dl = d.to_lower()
        if dl.begins_with("landroid/") or dl.begins_with("landroidx/") or dl.begins_with("ljava/") or dl.begins_with("ljavax/") or dl.begins_with("lkotlin/") or dl.begins_with("lkotlinx/") or dl.begins_with("lcom/google/") or dl.begins_with("lorg/godotengine/"):
            continue
        app_classes.append(c)
    var short_classes = 0
    var source_missing = 0
    for c in app_classes:
        var d = String(c.get("descriptor", ""))
        var base = d.trim_prefix("L").trim_suffix(";").get_file()
        if base.length() <= 2: short_classes += 1
        if String(c.get("source", "")).is_empty(): source_missing += 1
    var app_methods = 0
    var short_methods = 0
    for m in methods:
        var cd = String(m.get("class_descriptor", "")).to_lower()
        if cd.begins_with("landroid/") or cd.begins_with("landroidx/") or cd.begins_with("ljava/") or cd.begins_with("lkotlin/") or cd.begins_with("lcom/google/") or cd.begins_with("lorg/godotengine/"):
            continue
        var mn = String(m.get("name", ""))
        if mn in ["<init>","<clinit>"]: continue
        app_methods += 1
        if mn.length() <= 2: short_methods += 1
    var c_ratio = float(short_classes) / max(1.0, float(app_classes.size()))
    var m_ratio = float(short_methods) / max(1.0, float(app_methods))
    var s_ratio = float(source_missing) / max(1.0, float(app_classes.size()))
    var score = int(clamp(round(c_ratio * 50.0 + m_ratio * 35.0 + s_ratio * 15.0), 0, 100))
    var reasons: Array[String] = []
    if c_ratio > 0.35: reasons.append("Many application class names are only one or two characters long.")
    if m_ratio > 0.35: reasons.append("Many application method names are only one or two characters long.")
    if s_ratio > 0.60: reasons.append("Source-file metadata is absent for most application classes.")
    if app_classes.size() < 8 and methods.size() > 1000: reasons.append("Very little recognizable application namespace remains relative to total method volume.")
    var level = "Low / not obvious"
    if score >= 70: level = "High"
    elif score >= 40: level = "Moderate"
    return {"score": score, "level": level, "reasons": reasons, "app_class_count": app_classes.size(), "app_method_count": app_methods}

func _recoverable_locations(primary: String, names: Array[String], dex_list: Array) -> Array[String]:
    var out: Array[String] = []
    match primary:
        "Godot Engine":
            out.append("assets/*.pck, assets.sparsepck and project.binary/project.godot — Godot project resources/scripts packaged for export")
            out.append("assets/*.gdc — compiled GDScript bytecode; recoverable through Godot-specific script analysis/decompilation workflows")
            out.append("lib/<abi>/libgodot_android.so — Godot engine/runtime, usually not the application logic")
            out.append("classes*.dex — Android Godot host/plugin bridge code")
        "Flutter":
            out.append("lib/<abi>/libapp.so — release/profile Dart AOT application code")
            out.append("assets/flutter_assets/ — bundled assets, configs, JSON, fonts and occasional debug/source remnants")
            if _name_contains(names, "kernel_blob.bin"): out.append("assets/flutter_assets/kernel_blob.bin — unusually valuable Dart kernel/intermediate representation")
            out.append("classes*.dex — Android host/plugin glue; usually not the main Dart business logic")
        "React Native / Hermes":
            out.append("assets/index.android.bundle or *.jsbundle — JavaScript/Hermes application payload")
            out.append("*.map/source maps — if present, highest-value path back to original JS/TS filenames and source")
            out.append("classes*.dex — native Android modules and package glue")
            out.append("lib/<abi>/libhermes.so and other native libs — runtime/native modules")
        "Unity IL2CPP / Mono":
            out.append("assets/bin/Data/Managed/*.dll — Mono builds may retain decompilable C# assemblies")
            out.append("global-metadata.dat + libil2cpp.so — critical IL2CPP reconstruction pair")
            out.append("assets/bin/Data/ — scenes, serialized data and Unity metadata")
        "Xamarin / .NET MAUI":
            out.append("assemblies/*.dll or assemblies.blob — primary managed application code/store")
            out.append("*.pdb/*.mdb — symbols if preserved")
            out.append("classes*.dex and libmonodroid/libmonosgen — platform/runtime glue")
        "Cordova / Ionic / Capacitor":
            out.append("assets/www/ — packaged HTML/CSS/JS application source/bundles")
            out.append("source maps (*.map) — potentially reconstruct original TS/JS source names and locations")
            out.append("classes*.dex — WebView/plugin/native bridge code")
        "Native-heavy Android":
            out.append("lib/<abi>/*.so — substantial application logic appears native")
            out.append("classes*.dex — Java/Kotlin/JNI bridge code and entry points")
            out.append("AndroidManifest.xml + resources.arsc/res — components, resource IDs and behavioral anchors")
        _:
            out.append("classes*.dex — primary Java/Kotlin bytecode; use JADX for readable reconstruction")
            out.append("AndroidManifest.xml — components, application class, entry points, permissions and SDK targets")
            out.append("resources.arsc + res/ — UI/resource names and IDs recoverable via Apktool")
            out.append("assets/ — configs, databases, scripts and possible source/debug remnants")
    return out

func _patch_guidance(primary: String, obf: Dictionary, native_heavy: bool) -> String:
    var prefix = ""
    if int(obf.score) >= 40:
        prefix = "R8/ProGuard-style minification appears plausible, so search by behavior (strings, resources, signatures and call sites) rather than trusting symbol names. "
    match primary:
        "Godot Engine": return prefix + "Preserve assets/*.pck, assets.sparsepck, project.binary/project.godot, and assets/*.gdc first. Compiled GDScript bytecode and packaged Godot resources are the primary application-recovery targets; libgodot_android.so is normally engine/runtime code, while classes*.dex is mainly Android host/plugin glue."
        "Flutter": return prefix + "Start with libapp.so and flutter_assets. A release Flutter app is not a normal smali-only patch: identify the Dart AOT target in libapp.so, or reconstruct/rebuild from recovered Dart/kernel/source artifacts if any survived. Patch Android plugin code in classes*.dex only when the target behavior actually lives there."
        "React Native / Hermes": return prefix + "Recover the JS/Hermes bundle first. If source maps survived, use them before touching smali. Patch Java/Kotlin only for native modules/bridges; app behavior usually lives in the bundle."
        "Unity IL2CPP / Mono": return prefix + "Determine Mono versus IL2CPP. Mono assemblies may decompile cleanly. IL2CPP requires global-metadata.dat correlated with libil2cpp.so before binary/native patching."
        "Xamarin / .NET MAUI": return prefix + "Extract managed assemblies/assembly stores first and decompile those. Java/Kotlin smali is commonly platform glue rather than the main app logic."
        "Cordova / Ionic / Capacitor": return prefix + "Inspect assets/www and source maps first. Much of the app may be directly recoverable HTML/CSS/JS; rebuild the web payload before considering smali patches."
        "Native-heavy Android": return prefix + "Map JNI bridges in classes*.dex to lib/<abi>/*.so and patch the smallest verified native target. Preserve every ABI and test each architecture you intend to ship."
        _: return prefix + "Use JADX for readable Java-like reconstruction, correlate the exact method with Apktool smali, patch the smallest method body, rebuild, align, sign, verify, and test."

func _classify_artifact(name: String, size: int) -> Dictionary:
    var l = name.to_lower()
    if _is_dex_name(l): return {"name":name,"kind":"DEX bytecode","size":size,"priority":1,"note":"Primary Java/Kotlin bytecode; feed to JADX and correlate with smali."}
    if l == "androidmanifest.xml": return {"name":name,"kind":"Manifest","size":size,"priority":1,"note":"Package, components, permissions, SDK targets and entry points."}
    if l.ends_with("mapping.txt") or l.contains("proguard.map"): return {"name":name,"kind":"R8/ProGuard mapping","size":size,"priority":0,"note":"Extremely valuable: may restore original obfuscated class and member names."}
    if l.ends_with(".map") or l.contains("sourcemap"): return {"name":name,"kind":"Source map","size":size,"priority":0,"note":"May restore original JavaScript/TypeScript source names and locations."}
    if l.ends_with(".gdc"): return {"name":name,"kind":"Godot compiled GDScript","size":size,"priority":1,"note":"Application script bytecode; high-value Godot recovery target."}
    if l.contains("assets.sparsepck") or l.ends_with(".pck") or l.ends_with("project.binary") or l.ends_with("project.godot"): return {"name":name,"kind":"Godot project payload","size":size,"priority":1,"note":"Godot project metadata/resources; preserve before reconstruction."}
    if l.begins_with("assets/flutter_assets/"): return {"name":name,"kind":"Flutter asset","size":size,"priority":2,"note":"Inspect for configs, JSON, assets and debug/source remnants."}
    if l.ends_with("libapp.so"): return {"name":name,"kind":"Flutter AOT","size":size,"priority":1,"note":"Release Flutter/Dart application AOT code commonly lives here."}
    if l.ends_with("libflutter.so"): return {"name":name,"kind":"Flutter engine","size":size,"priority":4,"note":"Framework engine, not primarily application logic."}
    if l.ends_with("index.android.bundle") or l.ends_with(".jsbundle"): return {"name":name,"kind":"React Native bundle","size":size,"priority":1,"note":"Primary JavaScript/Hermes application bundle; major recovery target."}
    if l.contains("global-metadata.dat"): return {"name":name,"kind":"Unity IL2CPP metadata","size":size,"priority":1,"note":"Critical pair with libil2cpp.so for IL2CPP reconstruction."}
    if l.ends_with("libil2cpp.so"): return {"name":name,"kind":"Unity IL2CPP native code","size":size,"priority":1,"note":"Managed code compiled to native; analyze with global-metadata.dat."}
    if l.begins_with("assets/bin/data/managed/") and l.ends_with(".dll"): return {"name":name,"kind":"Unity managed assembly","size":size,"priority":1,"note":"Mono managed assembly; often decompilable to useful C#."}
    if (l.begins_with("assemblies/") and l.ends_with(".dll")) or l.ends_with("assemblies.blob"): return {"name":name,"kind":".NET/Xamarin assembly","size":size,"priority":1,"note":"Managed application code or packaged assembly store."}
    if l.begins_with("lib/") and l.ends_with(".so"): return {"name":name,"kind":"Native library","size":size,"priority":2,"note":"ELF native code; use native reverse-engineering if application logic is here."}
    if l.begins_with("assets/") and not l.ends_with("/"): return {"name":name,"kind":"Asset","size":size,"priority":3,"note":"Bundled application data; search configs, scripts, databases and source remnants."}
    if l == "resources.arsc": return {"name":name,"kind":"Resource table","size":size,"priority":2,"note":"Compiled Android resources; Apktool reconstructs much of res/."}
    if l.begins_with("res/") and not l.ends_with("/"): return {"name":name,"kind":"Android resource","size":size,"priority":4,"note":"Recoverable UI/resource material."}
    return {}

func _is_high_value(l: String) -> bool:
    return l.ends_with(".kt") or l.ends_with(".java") or l.ends_with(".cs") or l.ends_with(".dart") or l.ends_with(".pdb") or l.ends_with(".mdb") or l.ends_with(".symbols") or l.ends_with(".sym") or l.contains("mapping.txt") or (l.contains("source") and l.ends_with(".map")) or l.contains("kernel_blob") or l.contains("snapshot") or l.contains("global-metadata.dat")

func _should_bundle(l: String) -> bool:
    return l == "androidmanifest.xml" or l == "resources.arsc" or _is_dex_name(l) or l.begins_with("assets/") or l.begins_with("lib/") or l.begins_with("res/") or l.begins_with("assemblies/") or l.ends_with("mapping.txt") or l.ends_with(".map") or l.contains("global-metadata.dat") or l.ends_with(".dll") or l.ends_with(".pdb") or l.ends_with(".mdb")

func _is_dex_name(l: String) -> bool:
    if not l.begins_with("classes") or not l.ends_with(".dex"): return false
    var mid = l.substr(7, l.length() - 11)
    return mid.is_empty() or mid.is_valid_int()

func _is_text_like(l: String) -> bool:
    for ext in [".txt",".json",".xml",".js",".jsx",".ts",".tsx",".html",".css",".map",".yaml",".yml",".properties",".cfg",".ini",".csv",".md",".dart",".kt",".java",".cs",".jsbundle"]:
        if l.ends_with(ext): return true
    return l.ends_with("index.android.bundle")

func _is_binary_searchable(l: String) -> bool:
    for ext in [".so",".dll",".bin",".blob",".dat"]:
        if l.ends_with(ext): return true
    return false

func _method_display(m: Dictionary) -> String:
    var c = String(m.get("class_descriptor", "")).trim_prefix("L").trim_suffix(";").replace("/", ".")
    return "%s.%s" % [c, String(m.get("name", ""))]

func _classes_contain(classes: Array, needle: String) -> bool:
    var q = needle.to_lower()
    for c in classes:
        if String(c.get("descriptor", "")).to_lower().contains(q): return true
    return false

func _array_contains_ci(arr: Array[String], needle: String) -> bool:
    var q = needle.to_lower()
    for x in arr:
        if x.to_lower().contains(q): return true
    return false

func _name_contains(names: Array[String], needle: String) -> bool:
    var q = needle.to_lower()
    for x in names:
        if x.contains(q): return true
    return false

func _byte_index(h: PackedByteArray, n: PackedByteArray) -> int:
    if n.is_empty() or h.size() < n.size(): return -1
    for i in range(0, h.size() - n.size() + 1):
        var ok = true
        for j in range(n.size()):
            if h[i+j] != n[j]:
                ok = false
                break
        if ok: return i
    return -1

func _byte_index_ascii_ci(h: PackedByteArray, lower_needle: PackedByteArray) -> int:
    if lower_needle.is_empty() or h.size() < lower_needle.size():
        return -1
    for i in range(0, h.size() - lower_needle.size() + 1):
        var ok := true
        for j in range(lower_needle.size()):
            var c := int(h[i + j])
            if c >= 65 and c <= 90:
                c += 32
            if c != int(lower_needle[j]):
                ok = false
                break
        if ok:
            return i
    return -1

func _ascii_utf16le(text: String) -> PackedByteArray:
    var out := PackedByteArray()
    for i in range(text.length()):
        var cp := text.unicode_at(i)
        if cp > 0x7f:
            return PackedByteArray()
        out.append(cp)
        out.append(0)
    return out

func _parse_dex(name: String, b: PackedByteArray) -> Dictionary:
    var out = {
        "name": name, "size": b.size(), "valid": false, "error": "", "strings": [], "classes": [], "methods": [],
        "version": "", "declared_file_size": -1, "header_size": -1, "endian_tag": 0,
        "sha1_ok": false, "adler32_ok": false, "size_ok": false, "header_size_ok": false, "endian_ok": false, "integrity_ok": false
    }
    if b.size() < 112 or b.slice(0, 4).get_string_from_ascii() != "dex\n":
        out.error = "Not a DEX header"
        return out
    out.version = b.slice(4, 7).get_string_from_ascii()
    out.declared_file_size = _u32(b, 32)
    out.header_size = _u32(b, 36)
    out.endian_tag = _u32(b, 40)
    out.size_ok = int(out.declared_file_size) == b.size()
    out.header_size_ok = int(out.header_size) == 0x70
    out.endian_ok = int(out.endian_tag) == 0x12345678

    var sha1 = HashingContext.new()
    if sha1.start(HashingContext.HASH_SHA1) == OK:
        sha1.update(b.slice(32))
        out.sha1_ok = sha1.finish() == b.slice(12, 32)
    out.adler32_ok = _adler32(b, 12) == _u32(b, 8)
    out.integrity_ok = bool(out.size_ok) and bool(out.header_size_ok) and bool(out.endian_ok) and bool(out.sha1_ok) and bool(out.adler32_ok)

    var ss = _u32(b,56); var so = _u32(b,60)
    var ts = _u32(b,64); var to = _u32(b,68)
    var ms = _u32(b,88); var mo = _u32(b,92)
    var cs = _u32(b,96); var co = _u32(b,100)
    if ss > 5000000 or ts > 5000000 or ms > 20000000 or cs > 5000000:
        out.error = "DEX table count is implausibly large"
        return out
    if so + ss*4 > b.size() or to + ts*4 > b.size() or mo + ms*8 > b.size() or co + cs*32 > b.size():
        out.error = "DEX table outside file"
        return out
    var strings: Array = []
    for i in range(ss):
        var p = _u32(b, so + i*4)
        if p < 0 or p >= b.size():
            out.error = "DEX string offset outside file"
            return out
        var u = _read_uleb(b,p); p = int(u[1])
        var e = p; var hard = min(b.size(), p + 2000000)
        while e < hard and b[e] != 0: e += 1
        strings.append(_decode_mutf8(b, p, e))
    var tids: Array[int] = []
    for i in range(ts): tids.append(_u32(b,to+i*4))
    for i in range(cs):
        var p = co + i*32
        var ci = _u32(b,p); var si = _u32(b,p+16)
        var desc = ""
        if ci < tids.size() and tids[ci] < strings.size(): desc = String(strings[tids[ci]])
        var src = ""
        if si != 0xffffffff and si < strings.size(): src = String(strings[si])
        out.classes.append({"descriptor":desc,"source":src})
    for i in range(ms):
        var p = mo + i*8
        var ci = _u16(b,p); var ni = _u32(b,p+4)
        var desc = ""
        if ci < tids.size() and tids[ci] < strings.size(): desc = String(strings[tids[ci]])
        var mn = String(strings[ni]) if ni < strings.size() else ""
        out.methods.append({"class_descriptor":desc,"name":mn})
    out.strings = strings
    out.valid = true
    return out

func _adler32(data: PackedByteArray, start: int = 0) -> int:
    const MOD_ADLER := 65521
    var a := 1
    var b := 0
    var i: int = max(0, start)
    while i < data.size():
        var end: int = min(data.size(), i + 5552)
        while i < end:
            a += int(data[i])
            b += a
            i += 1
        a %= MOD_ADLER
        b %= MOD_ADLER
    return ((b << 16) | a) & 0xffffffff

func _parse_manifest(b: PackedByteArray) -> Dictionary:
    var out = {
        "package_name":"Unknown", "version_name":"Unknown", "version_code":-1, "min_sdk":-1, "target_sdk":-1,
        "providers": [], "application_category": "", "is_game": false
    }
    if b.is_empty(): return out
    if b[0] == 60:
        var x = b.get_string_from_utf8()
        out.package_name = _xml_attr(x,"package",out.package_name)
        out.version_name = _xml_attr(x,"android:versionName",out.version_name)
        var vc = _xml_attr(x,"android:versionCode","")
        if vc.is_valid_int(): out.version_code = int(vc)
        var mi = _xml_attr(x,"android:minSdkVersion","")
        if mi.is_valid_int(): out.min_sdk = int(mi)
        var ta = _xml_attr(x,"android:targetSdkVersion","")
        if ta.is_valid_int(): out.target_sdk = int(ta)
        var app_tag_re := RegEx.new()
        if app_tag_re.compile("<application\\b[^>]*>") == OK:
            var match := app_tag_re.search(x)
            if match:
                var app_tag := match.get_string()
                out.application_category = _xml_attr(app_tag, "android:appCategory", "")
                out.is_game = String(_xml_attr(app_tag, "android:isGame", "false")).to_lower() == "true"
        var provider_re := RegEx.new()
        if provider_re.compile("<provider\\b[^>]*>") == OK:
            for match in provider_re.search_all(x):
                var tag := match.get_string()
                out.providers.append({
                    "name": String(_xml_attr(tag, "android:name", "")),
                    "authorities": String(_xml_attr(tag, "android:authorities", "")),
                    "exported": String(_xml_attr(tag, "android:exported", ""))
                })
        return out

    var pool: Array = []
    var p = 8
    while p + 8 <= b.size():
        var typ = _u16(b,p); var hs = _u16(b,p+2); var size = _u32(b,p+4)
        if size < 8 or p + size > b.size(): break
        if typ == 1:
            if hs < 28 or p + hs > b.size(): break
            var sc = _u32(b,p+8); var flags = _u32(b,p+16); var start = _u32(b,p+20)
            var utf8 = (flags & 0x100) != 0; var offs = p + hs
            if offs + sc * 4 > p + size: break
            pool.clear()
            for i in range(sc):
                var q = p + start + _u32(b,offs+i*4)
                if q < p or q >= p + size:
                    pool.append("")
                elif utf8: pool.append(_read_utf8_pool(b,q))
                else: pool.append(_read_utf16_pool(b,q))
        elif typ == 0x102 and not pool.is_empty():
            var name_i = _u32(b,p+20)
            var tag = String(pool[name_i]) if name_i < pool.size() else ""
            var astart = _u16(b,p+24); var asize = max(20,_u16(b,p+26)); var acount = _u16(b,p+28)
            var base = p + 16 + astart
            var attrs := {}
            var attr_data := {}
            for i in range(acount):
                var a = base + i*asize
                if a + 20 > p + size or a + 20 > b.size(): break
                var an_i = _u32(b,a+4); var raw = _u32(b,a+8); var dt = b[a+15]; var data = _u32(b,a+16)
                var an = String(pool[an_i]) if an_i < pool.size() else ""
                var val = ""
                if raw != 0xffffffff and raw < pool.size(): val = String(pool[raw])
                elif dt == 3 and data < pool.size(): val = String(pool[data])
                elif dt == 0x12: val = "true" if data != 0 else "false"
                else: val = str(data)
                attrs[an] = val
                attr_data[an] = {"type": int(dt), "data": data}
            if tag == "manifest":
                if attrs.has("package"): out.package_name = attrs.package
                if attrs.has("versionName"): out.version_name = attrs.versionName
                if attrs.has("versionCode"):
                    var vd: Dictionary = attr_data.versionCode
                    out.version_code = int(vd.data) if int(vd.type) != 3 else int(attrs.versionCode) if String(attrs.versionCode).is_valid_int() else -1
            elif tag == "uses-sdk":
                if attrs.has("minSdkVersion"):
                    var md: Dictionary = attr_data.minSdkVersion
                    out.min_sdk = int(md.data) if int(md.type) != 3 else int(attrs.minSdkVersion) if String(attrs.minSdkVersion).is_valid_int() else -1
                if attrs.has("targetSdkVersion"):
                    var td: Dictionary = attr_data.targetSdkVersion
                    out.target_sdk = int(td.data) if int(td.type) != 3 else int(attrs.targetSdkVersion) if String(attrs.targetSdkVersion).is_valid_int() else -1
            elif tag == "application":
                if attrs.has("appCategory"): out.application_category = String(attrs.appCategory)
                if attrs.has("isGame"): out.is_game = String(attrs.isGame).to_lower() == "true" or String(attrs.isGame) == "1"
            elif tag == "provider":
                out.providers.append({
                    "name": String(attrs.get("name", "")),
                    "authorities": String(attrs.get("authorities", "")),
                    "exported": String(attrs.get("exported", ""))
                })
        p += size
    return out

func _xml_attr(x: String, key: String, fallback: Variant) -> Variant:
    var needle = key + "=\""
    var p = x.find(needle)
    if p < 0: return fallback
    p += needle.length()
    var e = x.find("\"", p)
    return x.substr(p, e-p) if e >= p else fallback

func _read_utf8_pool(b: PackedByteArray, p: int) -> String:
    var r = _read_len8(b,p); p = int(r[1])
    r = _read_len8(b,p); var ln = int(r[0]); p = int(r[1])
    return _decode_mutf8(b, p, min(b.size(), p + ln))

func _read_utf16_pool(b: PackedByteArray, p: int) -> String:
    var ln = _u16(b,p); p += 2
    if (ln & 0x8000) != 0:
        ln = ((ln & 0x7fff) << 16) | _u16(b,p); p += 2
    var s = ""
    for _i in range(ln):
        if p + 1 >= b.size(): break
        s += String.chr(_u16(b,p)); p += 2
    return s

func _read_len8(b: PackedByteArray, p: int) -> Array:
    var x = int(b[p]); p += 1
    if (x & 128) == 0: return [x,p]
    return [((x & 127) << 8) | int(b[p]), p+1]

func _decode_mutf8(b: PackedByteArray, start: int, end: int) -> String:
    var s := ""
    var i := start
    var limit: int = min(end, b.size())
    while i < limit:
        var c := int(b[i])
        if c == 0:
            break
        if c < 0x80:
            s += String.chr(c)
            i += 1
            continue
        if (c & 0xE0) == 0xC0 and i + 1 < limit:
            var c2 := int(b[i + 1])
            if (c2 & 0xC0) != 0x80:
                s += String.chr(0xFFFD)
                i += 1
                continue
            var cp := ((c & 0x1F) << 6) | (c2 & 0x3F)
            if cp == 0:
                s += "\\u0000"
            else:
                s += String.chr(cp)
            i += 2
            continue
        if (c & 0xF0) == 0xE0 and i + 2 < limit:
            var c2 := int(b[i + 1])
            var c3 := int(b[i + 2])
            if (c2 & 0xC0) != 0x80 or (c3 & 0xC0) != 0x80:
                s += String.chr(0xFFFD)
                i += 1
                continue
            var cp := ((c & 0x0F) << 12) | ((c2 & 0x3F) << 6) | (c3 & 0x3F)
            i += 3
            if cp >= 0xD800 and cp <= 0xDBFF and i + 2 < limit:
                var d1 := int(b[i])
                var d2 := int(b[i + 1])
                var d3 := int(b[i + 2])
                if (d1 & 0xF0) == 0xE0 and (d2 & 0xC0) == 0x80 and (d3 & 0xC0) == 0x80:
                    var low := ((d1 & 0x0F) << 12) | ((d2 & 0x3F) << 6) | (d3 & 0x3F)
                    if low >= 0xDC00 and low <= 0xDFFF:
                        var full := 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00)
                        s += String.chr(full)
                        i += 3
                        continue
            if cp >= 0xD800 and cp <= 0xDFFF:
                s += String.chr(0xFFFD)
            else:
                s += String.chr(cp)
            continue
        if (c & 0xF8) == 0xF0 and i + 3 < limit:
            var c2 := int(b[i + 1])
            var c3 := int(b[i + 2])
            var c4 := int(b[i + 3])
            if (c2 & 0xC0) == 0x80 and (c3 & 0xC0) == 0x80 and (c4 & 0xC0) == 0x80:
                var cp := ((c & 0x07) << 18) | ((c2 & 0x3F) << 12) | ((c3 & 0x3F) << 6) | (c4 & 0x3F)
                if cp <= 0x10FFFF:
                    s += String.chr(cp)
                    i += 4
                    continue
        s += String.chr(0xFFFD)
        i += 1
    return s

func _read_uleb(b: PackedByteArray, p: int) -> Array:
    var r = 0; var shift = 0
    for _i in range(5):
        if p >= b.size(): break
        var x = int(b[p]); p += 1
        r |= (x & 127) << shift
        if (x & 128) == 0: return [r,p]
        shift += 7
    return [r,p]

func _sha256_file(path: String) -> String:
    var f = FileAccess.open(path, FileAccess.READ)
    if f == null: return ""
    var h = HashingContext.new()
    h.start(HashingContext.HASH_SHA256)
    while f.get_position() < f.get_length():
        h.update(f.get_buffer(min(1024*1024, f.get_length()-f.get_position())))
    return h.finish().hex_encode()

static func _u16(b: PackedByteArray, p: int) -> int:
    if p + 1 >= b.size(): return 0
    return int(b[p]) | (int(b[p+1]) << 8)

static func _u32(b: PackedByteArray, p: int) -> int:
    if p < 0 or p + 3 >= b.size(): return 0
    return int(b[p]) | (int(b[p+1]) << 8) | (int(b[p+2]) << 16) | (int(b[p+3]) << 24)

static func _u64(b: PackedByteArray, p: int) -> int:
    if p < 0 or p + 7 >= b.size(): return 0
    var lo := _u32(b, p)
    var hi := _u32(b, p + 4)
    return lo | (hi << 32)

static func _human(n: int) -> String:
    var v = float(n); var units = ["B","KiB","MiB","GiB"]; var i = 0
    while v >= 1024.0 and i < units.size()-1:
        v /= 1024.0; i += 1
    return ("%.1f %s" % [v,units[i]]) if i > 0 else ("%d B" % n)
