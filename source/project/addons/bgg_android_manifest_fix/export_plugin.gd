@tool
extends EditorExportPlugin

const RES_STRING_POOL := 0x0001
const RES_XML_START_ELEMENT_TYPE := 0x0102
const STARTUP_PROVIDER := "androidx.startup.InitializationProvider"
const COLLIDING_SUFFIX := ".fileprovider"
const REPAIRED_SUFFIX := ".initprovider"

func _get_name() -> String:
    return "BGGremlinAndroidManifestFix"

func _supports_platform(platform: EditorExportPlatform) -> bool:
    return platform.get_os_name() == "Android"

func _update_android_prebuilt_manifest(_platform: EditorExportPlatform, manifest_data: PackedByteArray) -> PackedByteArray:
    var repaired := manifest_data.duplicate()
    if repaired.size() < 16:
        return repaired

    var pool := _read_string_pool(repaired)
    if pool.is_empty():
        push_error("BG Gremlin manifest fix: Android binary XML string pool was not found.")
        return repaired

    var strings: Array = pool.strings
    var p := 8
    while p + 8 <= repaired.size():
        var chunk_type := _u16(repaired, p)
        var header_size := _u16(repaired, p + 2)
        var chunk_size := _u32(repaired, p + 4)
        if chunk_size < 8 or p + chunk_size > repaired.size():
            break
        if chunk_type == RES_XML_START_ELEMENT_TYPE and header_size >= 16:
            var tag_index := _u32(repaired, p + 20)
            var tag := _pool_string(strings, tag_index)
            if tag == "provider":
                var attrs := _read_attributes(repaired, p, strings)
                if String(attrs.get("name", {}).get("value", "")) == STARTUP_PROVIDER:
                    var auth: Dictionary = attrs.get("authorities", {})
                    var authority := String(auth.get("value", ""))
                    var string_index := int(auth.get("string_index", -1))
                    if authority.ends_with(COLLIDING_SUFFIX) and string_index >= 0:
                        var replacement := authority.trim_suffix(COLLIDING_SUFFIX) + REPAIRED_SUFFIX
                        if _replace_pool_string_same_length(repaired, pool, string_index, replacement):
                            print("BG Gremlin manifest fix: repaired InitializationProvider authority: ", replacement)
                        else:
                            push_error("BG Gremlin manifest fix: failed to rewrite InitializationProvider authority safely.")
                    return repaired
        p += chunk_size
    return repaired

func _read_string_pool(data: PackedByteArray) -> Dictionary:
    var p := 8
    while p + 8 <= data.size():
        var chunk_type := _u16(data, p)
        var header_size := _u16(data, p + 2)
        var chunk_size := _u32(data, p + 4)
        if chunk_size < 8 or p + chunk_size > data.size():
            return {}
        if chunk_type == RES_STRING_POOL:
            if header_size < 28:
                return {}
            var string_count := _u32(data, p + 8)
            var flags := _u32(data, p + 16)
            var strings_start := _u32(data, p + 20)
            var offsets_start := p + header_size
            if offsets_start + string_count * 4 > p + chunk_size:
                return {}
            var utf8 := (flags & 0x100) != 0
            var strings: Array = []
            var absolute_offsets: Array[int] = []
            for i in range(string_count):
                var rel := _u32(data, offsets_start + i * 4)
                var absolute := p + strings_start + rel
                if absolute < p or absolute >= p + chunk_size:
                    strings.append("")
                    absolute_offsets.append(-1)
                    continue
                strings.append(_read_pool_string(data, absolute, utf8))
                absolute_offsets.append(absolute)
            return {
                "strings": strings,
                "absolute_offsets": absolute_offsets,
                "utf8": utf8,
                "chunk_start": p,
                "chunk_size": chunk_size
            }
        p += chunk_size
    return {}

func _read_attributes(data: PackedByteArray, start: int, strings: Array) -> Dictionary:
    var out := {}
    if start + 36 > data.size():
        return out
    var attribute_start := _u16(data, start + 24)
    var attribute_size: int = max(20, _u16(data, start + 26))
    var attribute_count := _u16(data, start + 28)
    var base := start + 16 + attribute_start
    for i in range(attribute_count):
        var a: int = base + i * attribute_size
        if a + 20 > data.size():
            break
        var name_index := _u32(data, a + 4)
        var raw_index := _u32(data, a + 8)
        var data_type := int(data[a + 15])
        var typed_data := _u32(data, a + 16)
        var attr_name := _pool_string(strings, name_index)
        var value := ""
        var string_index := -1
        if raw_index != 0xffffffff and raw_index < strings.size():
            string_index = raw_index
            value = _pool_string(strings, raw_index)
        elif data_type == 3 and typed_data < strings.size():
            string_index = typed_data
            value = _pool_string(strings, typed_data)
        else:
            value = str(typed_data)
        out[attr_name] = {"value": value, "string_index": string_index}
    return out

func _replace_pool_string_same_length(data: PackedByteArray, pool: Dictionary, index: int, replacement: String) -> bool:
    var offsets: Array = pool.absolute_offsets
    if index < 0 or index >= offsets.size():
        return false
    var p := int(offsets[index])
    if p < 0 or p >= data.size():
        return false
    var utf8 := bool(pool.utf8)
    if utf8:
        var first := _read_len8(data, p)
        var utf16_len := int(first[0])
        p = int(first[1])
        var second := _read_len8(data, p)
        var byte_len := int(second[0])
        p = int(second[1])
        var encoded := replacement.to_utf8_buffer()
        if replacement.length() != utf16_len or encoded.size() != byte_len or p + byte_len > data.size():
            return false
        for i in range(byte_len):
            data[p + i] = encoded[i]
        return true

    var length_info := _read_len16(data, p)
    var char_len := int(length_info[0])
    p = int(length_info[1])
    if replacement.length() != char_len or p + char_len * 2 > data.size():
        return false
    for i in range(char_len):
        var code := replacement.unicode_at(i)
        if code > 0xffff:
            return false
        data[p + i * 2] = code & 0xff
        data[p + i * 2 + 1] = (code >> 8) & 0xff
    return true

func _read_pool_string(data: PackedByteArray, p: int, utf8: bool) -> String:
    if utf8:
        var a := _read_len8(data, p)
        p = int(a[1])
        var b := _read_len8(data, p)
        var byte_len := int(b[0])
        p = int(b[1])
        if p + byte_len > data.size():
            return ""
        return data.slice(p, p + byte_len).get_string_from_utf8()
    var a := _read_len16(data, p)
    var length := int(a[0])
    p = int(a[1])
    if p + length * 2 > data.size():
        return ""
    var result := ""
    for i in range(length):
        result += String.chr(_u16(data, p + i * 2))
    return result

func _read_len8(data: PackedByteArray, p: int) -> Array:
    if p >= data.size():
        return [0, p]
    var x := int(data[p])
    p += 1
    if (x & 0x80) == 0:
        return [x, p]
    if p >= data.size():
        return [x & 0x7f, p]
    return [((x & 0x7f) << 8) | int(data[p]), p + 1]

func _read_len16(data: PackedByteArray, p: int) -> Array:
    if p + 1 >= data.size():
        return [0, p]
    var length := _u16(data, p)
    p += 2
    if (length & 0x8000) != 0:
        if p + 1 >= data.size():
            return [length & 0x7fff, p]
        length = ((length & 0x7fff) << 16) | _u16(data, p)
        p += 2
    return [length, p]

func _pool_string(strings: Array, index: int) -> String:
    if index < 0 or index >= strings.size():
        return ""
    return String(strings[index])

static func _u16(data: PackedByteArray, p: int) -> int:
    if p < 0 or p + 1 >= data.size():
        return 0
    return int(data[p]) | (int(data[p + 1]) << 8)

static func _u32(data: PackedByteArray, p: int) -> int:
    if p < 0 or p + 3 >= data.size():
        return 0
    return int(data[p]) | (int(data[p + 1]) << 8) | (int(data[p + 2]) << 16) | (int(data[p + 3]) << 24)
