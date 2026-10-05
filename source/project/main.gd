extends Control

const Analyzer = preload("res://analyzer.gd")
const YELLOW := Color("a6ff00")
const BG := Color("050505")
const PANEL := Color("141414")
const PANEL2 := Color("1c1c1c")
const TEXT := Color("f2f2f2")
const MUTED := Color("aaaaaa")
const LINE := Color("383838")
const OKC := Color("8cff70")
const WARNC := Color("ffd375")

var analyzer = Analyzer.new()
var selected_apk := ""
var worker: Thread
var overview_text: RichTextLabel
var artifacts_text: RichTextLabel
var hunt_text: RichTextLabel
var plan_text: RichTextLabel
var structure_text: RichTextLabel
var diagnostics_text: RichTextLabel
var hunt_input: LineEdit
var file_label: Label
var status_label: Label
var progress: ProgressBar
var analyze_button: Button
var search_button: Button
var report_button: Button
var bundle_button: Button
var export_project_button: Button
var copy_button: Button
var file_dialog: FileDialog
var save_report_dialog: FileDialog
var save_bundle_dialog: FileDialog
var popup: AcceptDialog

func _ready() -> void:
    get_viewport().set_embedding_subwindows(false)
    DisplayServer.screen_set_orientation(DisplayServer.SCREEN_PORTRAIT)
    _build_ui()
    _set_status("Ready. Select the untouched APK first.", 0)

func _exit_tree() -> void:
    if worker and worker.is_started():
        worker.wait_to_finish()
    analyzer.close()

func _build_ui() -> void:
    var bg = ColorRect.new()
    bg.color = BG
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(bg)

    var margin = MarginContainer.new()
    margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    margin.add_theme_constant_override("margin_left", 14)
    margin.add_theme_constant_override("margin_right", 14)
    margin.add_theme_constant_override("margin_top", 14)
    margin.add_theme_constant_override("margin_bottom", 14)
    add_child(margin)

    var root = VBoxContainer.new()
    root.add_theme_constant_override("separation", 10)
    margin.add_child(root)

    var header = PanelContainer.new()
    header.add_theme_stylebox_override("panel", _panel_style(PANEL, YELLOW, 1, 14))
    root.add_child(header)
    var hmargin = MarginContainer.new()
    hmargin.add_theme_constant_override("margin_left", 12)
    hmargin.add_theme_constant_override("margin_right", 12)
    hmargin.add_theme_constant_override("margin_top", 10)
    hmargin.add_theme_constant_override("margin_bottom", 10)
    header.add_child(hmargin)
    var hbox = HBoxContainer.new()
    hbox.add_theme_constant_override("separation", 12)
    hmargin.add_child(hbox)
    var logo = TextureRect.new()
    logo.texture = load("res://logo.jpg")
    logo.custom_minimum_size = Vector2(92,92)
    logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    hbox.add_child(logo)
    var hv = VBoxContainer.new()
    hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    hbox.add_child(hv)
    var title = _label("BG Gremlin APK Recovery", 27, YELLOW, true)
    title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    hv.add_child(title)
    hv.add_child(_label("Local APK disaster-recovery analyzer", 16, TEXT, true))
    hv.add_child(_label("don't do evil", 15, MUTED, false))

    var intro = _label("Recover as much rebuildable material as the APK actually contains. Preserve the untouched package, extract the complete APK tree, retain obfuscated DEX code and metadata, recover surviving source/text/framework/native artifacts, search functions and strings, and export a structured per-project recovery workspace.", 14, MUTED, false)
    intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    root.add_child(intro)

    var source_panel = PanelContainer.new()
    source_panel.add_theme_stylebox_override("panel", _panel_style(PANEL, LINE, 1, 10))
    root.add_child(source_panel)
    var sm = MarginContainer.new()
    for side in ["left","right","top","bottom"]:
        sm.add_theme_constant_override("margin_" + side, 10)
    source_panel.add_child(sm)
    var sv = VBoxContainer.new(); sv.add_theme_constant_override("separation", 8); sm.add_child(sv)
    sv.add_child(_label("APK SOURCE", 12, YELLOW, true))
    file_label = _label("No APK selected", 15, TEXT, true)
    file_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    sv.add_child(file_label)
    var source_buttons = HBoxContainer.new(); source_buttons.add_theme_constant_override("separation", 8); sv.add_child(source_buttons)
    var pick = _button("Select APK", true); pick.pressed.connect(_select_apk); source_buttons.add_child(pick)
    analyze_button = _button("Analyze", false); analyze_button.disabled = true; analyze_button.pressed.connect(_start_analysis); source_buttons.add_child(analyze_button)

    status_label = _label("", 13, MUTED, false)
    status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    root.add_child(status_label)
    progress = ProgressBar.new()
    progress.min_value = 0; progress.max_value = 100; progress.value = 0; progress.show_percentage = false
    progress.custom_minimum_size.y = 6
    progress.add_theme_stylebox_override("background", _panel_style(Color("222222"), Color.TRANSPARENT, 0, 4))
    progress.add_theme_stylebox_override("fill", _panel_style(YELLOW, Color.TRANSPARENT, 0, 4))
    root.add_child(progress)

    var tabs = TabContainer.new()
    tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
    tabs.custom_minimum_size.y = 600
    tabs.add_theme_font_size_override("font_size", 14)
    root.add_child(tabs)
    overview_text = _add_text_tab(tabs, "Overview")
    artifacts_text = _add_text_tab(tabs, "Recovery Artifacts")
    _add_hunt_tab(tabs)
    plan_text = _add_text_tab(tabs, "Recovery Plan")
    diagnostics_text = _add_text_tab(tabs, "Diagnostics")
    structure_text = _add_text_tab(tabs, "APK Structure")
    _set_empty_state()

    var actions = VBoxContainer.new(); actions.add_theme_constant_override("separation", 7); root.add_child(actions)
    export_project_button = _button("Export Full Recovery Project ZIP", true); export_project_button.disabled = true; export_project_button.pressed.connect(_save_bundle_prompt); actions.add_child(export_project_button)
    var action_row = HBoxContainer.new(); action_row.add_theme_constant_override("separation", 7); actions.add_child(action_row)
    report_button = _button("Export Report", false); report_button.disabled = true; report_button.pressed.connect(_save_report_prompt); action_row.add_child(report_button)
    bundle_button = _button("Export Project ZIP", false); bundle_button.disabled = true; bundle_button.pressed.connect(_save_bundle_prompt); action_row.add_child(bundle_button)
    copy_button = _button("Copy Report", false); copy_button.disabled = true; copy_button.pressed.connect(_copy_report); action_row.add_child(copy_button)

    var footer = _label("Background Gremlin Group • offline recovery tooling • don't do evil", 11, Color("777777"), false)
    footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    root.add_child(footer)

    file_dialog = FileDialog.new()
    file_dialog.title = "Select untouched APK"
    file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    file_dialog.access = FileDialog.ACCESS_FILESYSTEM
    file_dialog.filters = PackedStringArray(["*.apk ; Android application package"])
    file_dialog.use_native_dialog = true
    file_dialog.file_selected.connect(_apk_selected)
    add_child(file_dialog)

    save_report_dialog = FileDialog.new()
    save_report_dialog.title = "Save APK recovery report"
    save_report_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
    save_report_dialog.access = FileDialog.ACCESS_FILESYSTEM
    save_report_dialog.filters = PackedStringArray(["*.txt ; Text report"])
    save_report_dialog.use_native_dialog = true
    save_report_dialog.file_selected.connect(_save_report_to)
    add_child(save_report_dialog)

    save_bundle_dialog = FileDialog.new()
    save_bundle_dialog.title = "Save complete recovery project ZIP"
    save_bundle_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
    save_bundle_dialog.access = FileDialog.ACCESS_FILESYSTEM
    save_bundle_dialog.filters = PackedStringArray(["*.zip ; ZIP archive"])
    save_bundle_dialog.use_native_dialog = true
    save_bundle_dialog.file_selected.connect(_save_bundle_to)
    add_child(save_bundle_dialog)

    popup = AcceptDialog.new()
    popup.title = "BG Gremlin APK Recovery"
    add_child(popup)

func _label(text: String, size: int, color: Color, bold: bool) -> Label:
    var l = Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", color)
    if bold:
        l.add_theme_color_override("font_shadow_color", Color(0,0,0,0.5))
        l.add_theme_constant_override("shadow_offset_x", 1)
        l.add_theme_constant_override("shadow_offset_y", 1)
    return l

func _button(text: String, primary: bool) -> Button:
    var b = Button.new(); b.text = text; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; b.custom_minimum_size.y = 46
    b.add_theme_font_size_override("font_size", 14)
    if primary:
        b.add_theme_color_override("font_color", BG)
        b.add_theme_color_override("font_hover_color", BG)
        b.add_theme_color_override("font_pressed_color", BG)
        b.add_theme_stylebox_override("normal", _panel_style(YELLOW, YELLOW, 1, 9))
        b.add_theme_stylebox_override("hover", _panel_style(Color("c8ff66"), YELLOW, 1, 9))
        b.add_theme_stylebox_override("pressed", _panel_style(Color("83cc00"), YELLOW, 1, 9))
    else:
        b.add_theme_color_override("font_color", TEXT)
        b.add_theme_stylebox_override("normal", _panel_style(PANEL2, Color("555555"), 1, 9))
        b.add_theme_stylebox_override("hover", _panel_style(Color("292929"), Color("707070"), 1, 9))
        b.add_theme_stylebox_override("pressed", _panel_style(Color("101010"), YELLOW, 1, 9))
    return b

func _panel_style(color: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
    var s = StyleBoxFlat.new(); s.bg_color = color
    if width > 0:
        s.border_width_left = width; s.border_width_right = width; s.border_width_top = width; s.border_width_bottom = width
        s.border_color = border
    s.corner_radius_top_left = radius; s.corner_radius_top_right = radius; s.corner_radius_bottom_left = radius; s.corner_radius_bottom_right = radius
    return s

func _add_text_tab(tabs: TabContainer, name: String) -> RichTextLabel:
    var panel = PanelContainer.new(); panel.name = name; panel.add_theme_stylebox_override("panel", _panel_style(PANEL, LINE, 1, 8)); tabs.add_child(panel)
    var m = MarginContainer.new(); m.add_theme_constant_override("margin_left", 10); m.add_theme_constant_override("margin_right",10); m.add_theme_constant_override("margin_top",10); m.add_theme_constant_override("margin_bottom",10); panel.add_child(m)
    var r = RichTextLabel.new(); r.bbcode_enabled = true; r.fit_content = false; r.scroll_active = true; r.selection_enabled = true; r.context_menu_enabled = true; r.add_theme_font_size_override("normal_font_size", 14); r.add_theme_color_override("default_color", TEXT); m.add_child(r)
    return r

func _add_hunt_tab(tabs: TabContainer) -> void:
    var panel = PanelContainer.new(); panel.name = "Function Hunt"; panel.add_theme_stylebox_override("panel", _panel_style(PANEL, LINE, 1, 8)); tabs.add_child(panel)
    var m = MarginContainer.new()
    for side in ["left","right","top","bottom"]:
        m.add_theme_constant_override("margin_"+side,10)
    panel.add_child(m)
    var v = VBoxContainer.new(); v.add_theme_constant_override("separation",8); m.add_child(v)
    var h = HBoxContainer.new(); h.add_theme_constant_override("separation",8); v.add_child(h)
    hunt_input = LineEdit.new(); hunt_input.placeholder_text = "Function, class, URL, log text, preference key"; hunt_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hunt_input.custom_minimum_size.y = 44; hunt_input.add_theme_font_size_override("font_size",14); h.add_child(hunt_input)
    hunt_input.text_submitted.connect(func(_t): _start_search())
    search_button = _button("Search", true); search_button.size_flags_horizontal = Control.SIZE_SHRINK_END; search_button.disabled = true; search_button.pressed.connect(_start_search); h.add_child(search_button)
    hunt_text = RichTextLabel.new(); hunt_text.bbcode_enabled = true; hunt_text.selection_enabled = true; hunt_text.size_flags_vertical = Control.SIZE_EXPAND_FILL; hunt_text.add_theme_font_size_override("normal_font_size",14); hunt_text.add_theme_color_override("default_color",TEXT); v.add_child(hunt_text)

func _set_empty_state() -> void:
    overview_text.text = "[color=#777777]Select an APK and press Analyze.[/color]"
    artifacts_text.text = "[color=#777777]Analyze an APK first.[/color]"
    hunt_text.text = "[color=#777777]Analyze an APK first, then search for a surviving function name or behavioral string.[/color]"
    plan_text.text = "[color=#777777]Analyze an APK first.[/color]"
    diagnostics_text.text = "[color=#777777]Analyze an APK first.[/color]"
    structure_text.text = "[color=#777777]Analyze an APK first.[/color]"

func _select_apk() -> void:
    file_dialog.popup_centered_ratio(0.92)

func _apk_selected(path: String) -> void:
    selected_apk = path
    file_label.text = "%s • %s" % [path.get_file(), _human(_path_size(path))]
    analyze_button.disabled = false
    _set_status("APK selected. The source file will only be read.", 0)
    _set_empty_state()

func _set_busy(busy: bool) -> void:
    analyze_button.disabled = busy or selected_apk.is_empty()
    search_button.disabled = busy or analyzer.analysis.is_empty()
    report_button.disabled = busy or analyzer.analysis.is_empty()
    bundle_button.disabled = busy or analyzer.analysis.is_empty()
    export_project_button.disabled = busy or analyzer.analysis.is_empty()
    copy_button.disabled = busy or analyzer.analysis.is_empty()

func _start_analysis() -> void:
    if selected_apk.is_empty() or (worker and worker.is_started()): return
    _set_busy(true); _set_status("Analyzing APK structure, DEX and framework markers", 12)
    worker = Thread.new()
    worker.start(Callable(self, "_analysis_worker").bind(selected_apk))

func _analysis_worker(path: String) -> void:
    var result = analyzer.open_apk(path)
    call_deferred("_analysis_done", result)

func _analysis_done(result: Dictionary) -> void:
    if worker and worker.is_started(): worker.wait_to_finish()
    if not bool(result.get("ok", false)):
        _set_status("Analysis failed: %s" % result.get("error", "unknown error"), 0); _set_busy(false); return
    _render_analysis()
    _set_status("Analysis complete. Export preservation artifacts before patching anything.", 100)
    _set_busy(false)

func _render_analysis() -> void:
    var a = analyzer.analysis; var m = a.manifest
    var o: Array[String] = []
    o.append("[font_size=22][color=#a6ff00][b]%s[/b][/color][/font_size]" % _bb(a.name))
    o.append("[color=#aaaaaa]SHA-256[/color]  [font=][code]%s[/code][/font]" % _bb(a.sha256))
    o.append("")
    o.append("[b]Package[/b]  %s" % _bb(str(m.package_name)))
    o.append("[b]Version[/b]  %s  • code %s" % [_bb(str(m.version_name)), str(m.version_code)])
    o.append("[b]SDK[/b]  min %s  • target %s" % [str(m.min_sdk), str(m.target_sdk)])
    o.append("[b]Primary stack[/b]  [color=#a6ff00][b]%s[/b][/color]" % _bb(a.primary))
    o.append("[b]Kotlin[/b]  %s     [b]Jetpack Compose[/b]  %s" % [_yesno(a.kotlin), _yesno(a.compose)])
    o.append("[b]DEX[/b]  %d file(s), %s     [b]Native[/b]  %d .so, %s" % [a.dex.size(), _human(a.dex_bytes), a.native_count, _human(a.native_bytes)])
    o.append("[b]ABIs[/b]  %s" % (_bb(", ".join(a.abis)) if not a.abis.is_empty() else "none"))
    var health_color = "#8cff70" if a.health.status == "OK" else "#ffd375" if a.health.status == "Warnings" else "#ff7777"
    o.append("[b]Packaging health[/b]  [color=%s][b]%s[/b][/color]" % [health_color, _bb(a.health.status)])
    o.append("[b]Obfuscation heuristic[/b]  %s • %d/100" % [_bb(a.obfuscation.level), a.obfuscation.score])
    for r in a.obfuscation.reasons: o.append("  [color=#ffd375]• %s[/color]" % _bb(r))
    o.append("\n[color=#a6ff00][b]FRAMEWORK EVIDENCE[/b][/color]")
    if a.frameworks.is_empty(): o.append("No non-native framework markers detected.")
    for fw in a.frameworks:
        o.append("[b]%s[/b] — %d%% confidence" % [_bb(fw.name), fw.confidence])
        for ev in fw.evidence: o.append("  • [code]%s[/code]" % _bb(ev))
    o.append("\n[color=#a6ff00][b]RECOVERABLE APPLICATION CODE LOCATIONS[/b][/color]")
    for x in a.locations: o.append("• %s" % _bb(x))
    o.append("\n[color=#a6ff00][b]MOST PRACTICAL PATCH PATH[/b][/color]\n%s" % _bb(a.patch))
    if not a.remnants.is_empty():
        o.append("\n[color=#a6ff00][b]HIGH-VALUE REMNANTS[/b][/color]")
        for x in a.remnants: o.append("• [code]%s[/code]" % _bb(x))
    overview_text.text = "\n".join(o)

    var ar: Array[String] = []
    ar.append("[color=#a6ff00][b]PRIORITIZED RECOVERY ARTIFACTS[/b][/color]\n")
    for x in a.artifacts:
        var pri = "#a6ff00" if int(x.priority) <= 1 else "#f2f2f2"
        ar.append("[color=%s][b][P%d] %s[/b][/color]  •  %s\n[code]%s[/code]\n[color=#aaaaaa]%s[/color]\n" % [pri, int(x.priority), _bb(x.kind), _human(x.size), _bb(x.name), _bb(x.note)])
    artifacts_text.text = "\n".join(ar)

    var pl: Array[String] = ["[color=#a6ff00][b]RECOVERY PLAN[/b][/color]\n"]
    for p in analyzer.recovery_plan(): pl.append(_bb(p) + "\n")
    plan_text.text = "\n".join(pl)

    var dg: Array[String] = ["[color=#a6ff00][b]APK / DEX DIAGNOSTICS[/b][/color]\n"]
    var h = a.health
    var hcolor = "#8cff70" if h.status == "OK" else "#ffd375" if h.status == "Warnings" else "#ff7777"
    dg.append("[b]Overall packaging health:[/b] [color=%s][b]%s[/b][/color]\n" % [hcolor, _bb(h.status)])
    for x in h.critical: dg.append("[color=#ff7777][b]CRITICAL[/b][/color]  %s" % _bb(x))
    for x in h.warnings: dg.append("[color=#ffd375][b]WARNING[/b][/color]  %s" % _bb(x))
    for x in h.info: dg.append("[color=#8cff70][b]INFO[/b][/color]  %s" % _bb(x))
    dg.append("\n[color=#a6ff00][b]DEX INTEGRITY[/b][/color]")
    if a.dex.is_empty():
        dg.append("No classes*.dex files were found.")
    for d in a.dex:
        var dc = "#8cff70" if bool(d.integrity_ok) else "#ff7777"
        dg.append("[color=%s][b]%s[/b][/color]  version %s  • %s" % [dc, _bb(d.name), _bb(d.version), _human(int(d.size))])
        dg.append("  parseable=%s  SHA-1=%s  Adler-32=%s  size=%s  header=%s  endian=%s" % [_plain_yesno(bool(d.valid)), _plain_yesno(bool(d.sha1_ok)), _plain_yesno(bool(d.adler32_ok)), _plain_yesno(bool(d.size_ok)), _plain_yesno(bool(d.header_size_ok)), _plain_yesno(bool(d.endian_ok))])
        if not String(d.error).is_empty(): dg.append("  [color=#ff7777]%s[/color]" % _bb(d.error))
    dg.append("\n[color=#a6ff00][b]MANIFEST PROVIDERS[/b][/color]")
    if m.providers.is_empty():
        dg.append("No providers declared.")
    for provider in m.providers:
        dg.append("• [code]%s[/code]\n  authority: [code]%s[/code]  exported=%s" % [_bb(provider.name), _bb(provider.authorities), _bb(provider.exported)])
    dg.append("\n[color=#a6ff00][b]APK SIGNING MARKERS[/b][/color]")
    var sg = h.signing
    dg.append("v1/JAR metadata=%s  • v2=%s  • v3=%s  • v3.1=%s" % [_plain_yesno(bool(sg.v1_metadata)), _plain_yesno(bool(sg.v2)), _plain_yesno(bool(sg.v3)), _plain_yesno(bool(sg.v31))])
    var al = h.alignment
    dg.append("\n[color=#a6ff00][b]ZIP ALIGNMENT[/b][/color]")
    dg.append("Stored entries checked: %d  •  4-byte misaligned: %d" % [int(al.checked), int(al.misaligned_count)])
    for item in al.misaligned:
        dg.append("• [code]%s[/code] at 0x%X" % [_bb(item.name), int(item.offset)])
    diagnostics_text.text = "\n".join(dg)

    var st: Array[String] = []
    st.append("[color=#a6ff00][b]APK ZIP STRUCTURE[/b][/color]")
    st.append("%d entries. Paths below are read-only inventory.\n" % a.entries.size())
    var limit = min(5000, a.entries.size())
    for i in range(limit):
        var e = a.entries[i]
        st.append("[code]%-10s  %s[/code]" % [_human(e.size), _bb(e.name)])
    if a.entries.size() > limit: st.append("\n[color=#ffd375]Display limited to %d of %d entries.[/color]" % [limit,a.entries.size()])
    structure_text.text = "\n".join(st)
    hunt_text.text = "[color=#aaaaaa]Enter a function/class name or something likely to have survived obfuscation: URL, log message, UI text, preference key, JSON field, database/table name, filename, protocol token or constant.[/color]"

func _start_search() -> void:
    var q = hunt_input.text.strip_edges()
    if q.is_empty() or analyzer.analysis.is_empty() or (worker and worker.is_started()): return
    _set_busy(true); _set_status("Searching DEX, assets and native binaries for: %s" % q, 20)
    worker = Thread.new(); worker.start(Callable(self,"_search_worker").bind(q))

func _search_worker(q: String) -> void:
    var hits = analyzer.search(q, 500)
    call_deferred("_search_done", q, hits)

func _search_done(q: String, hits: Array) -> void:
    if worker and worker.is_started(): worker.wait_to_finish()
    var out: Array[String] = []
    out.append("[color=#a6ff00][b]%d hit(s) for %s[/b][/color]\n" % [hits.size(), _bb(q)])
    for h in hits:
        out.append("[b]%s[/b] • score %d\n[code]%s[/code]\n[color=#aaaaaa]%s[/color]\n" % [_bb(h.type), h.score, _bb(h.path), _bb(h.detail)])
    if hits.is_empty(): out.append("[color=#777777]No direct hit. Search a behavioral constant: URL, error text, UI label, JSON field, preference key, table name, protocol token or filename.[/color]")
    hunt_text.text = "\n".join(out); _set_status("Function Hunt complete — %d hit(s)." % hits.size(), 100); _set_busy(false)

func _save_report_prompt() -> void:
    if analyzer.analysis.is_empty(): return
    save_report_dialog.current_file = "BGGremlin-APK-Recovery-%s.txt" % _safe(analyzer.analysis.name)
    save_report_dialog.popup_centered_ratio(0.92)

func _save_report_to(path: String) -> void:
    var err = analyzer.write_report(path)
    if err == OK:
        _show("Report saved to the selected user-visible destination:\n" + path)
    else:
        _show("Report export failed. Nothing was silently redirected to app-private storage.\n\n" + error_string(err))

func _save_bundle_prompt() -> void:
    if analyzer.analysis.is_empty(): return
    save_bundle_dialog.current_file = "BGGremlin-RECOVERY-PROJECT-%s.zip" % _safe(analyzer.analysis.name)
    save_bundle_dialog.popup_centered_ratio(0.92)

func _save_bundle_to(path: String) -> void:
    if worker and worker.is_started(): return
    _set_busy(true); _set_status("Building complete recovery project ZIP", 10)
    worker = Thread.new(); worker.start(Callable(self,"_bundle_worker").bind(path))

func _bundle_worker(path: String) -> void:
    var err = analyzer.write_recovery_bundle(path)
    call_deferred("_bundle_done", err, path)

func _bundle_done(err: int, path: String) -> void:
    if worker and worker.is_started(): worker.wait_to_finish()
    _set_busy(false)
    if err == OK:
        _set_status("Recovery project ZIP saved to selected destination.", 100); _show("Recovery project ZIP saved to the user-visible destination you selected:\n" + path)
    else:
        _set_status("Recovery project ZIP export failed.", 0); _show("Recovery project ZIP export failed. Nothing was silently redirected to app-private storage.\n\n" + error_string(err))

func _copy_report() -> void:
    DisplayServer.clipboard_set(analyzer.report_text())
    _set_status("Full analysis report copied to clipboard.", 100)

func _default_export_dir() -> String:
    var d = "user://BGGremlinAPKRecovery/Output"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
    return d

func _show(msg: String) -> void:
    popup.dialog_text = msg
    popup.popup_centered_ratio(0.86)

func _set_status(text: String, p: float) -> void:
    status_label.text = text; progress.value = p

func _safe(s: String) -> String:
    var out = ""
    for c in s:
        if "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-".contains(c): out += c
        else: out += "_"
    if out.to_lower().ends_with(".apk"): out = out.substr(0,out.length()-4)
    return out

func _path_size(path: String) -> int:
    var f = FileAccess.open(path, FileAccess.READ)
    return f.get_length() if f != null else 0

func _plain_yesno(v: bool) -> String:
    return "yes" if v else "no"

func _human(n: int) -> String:
    var v = float(n); var units = ["B","KiB","MiB","GiB"]; var i = 0
    while v >= 1024.0 and i < units.size()-1: v /= 1024.0; i += 1
    return ("%.1f %s" % [v,units[i]]) if i > 0 else ("%d B" % n)

func _yesno(v: bool) -> String:
    return "[color=#8cff70]yes[/color]" if v else "[color=#aaaaaa]no[/color]"

func _bb(s: Variant) -> String:
    return String(s).replace("[","[lb]")
