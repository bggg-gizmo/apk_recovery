extends "res://main.gd"

# v1.5.2 production hotfix: a user export is only successful when it reaches
# the destination explicitly selected through Android's native document picker.
# App-private user:// storage is staging only and is never reported as an export.
func _ready() -> void:
    super._ready()
    export_project_button.text = "Export Full Recovery Project ZIP"
    for connection in export_project_button.pressed.get_connections():
        export_project_button.pressed.disconnect(connection.callable)
    export_project_button.pressed.connect(_export_visible_project)

func _export_visible_project() -> void:
    _save_bundle_prompt()

# Override the v1.5.1 fallback. If the selected SAF/content:// destination fails,
# fail loudly instead of silently redirecting the result into app-private storage.
func _bundle_worker(path: String) -> void:
    var err = analyzer.write_recovery_bundle(path)
    call_deferred("_bundle_done", err, path)

func _bundle_done(err: int, path: String) -> void:
    if worker and worker.is_started():
        worker.wait_to_finish()
    _set_busy(false)
    if err == OK:
        _set_status("Recovery project ZIP saved to selected destination.", 100)
        _show("Recovery project ZIP saved to the user-visible destination you selected:\n" + path)
    else:
        _set_status("Recovery project ZIP export failed.", 0)
        _show("Recovery project ZIP export failed. Nothing was silently redirected to app-private storage.\n\n" + error_string(err))

# Reports follow the same contract: selected destination or explicit failure.
func _save_report_to(path: String) -> void:
    var err = analyzer.write_report(path)
    if err == OK:
        _show("Report saved to the selected user-visible destination:\n" + path)
    else:
        _show("Report export failed. Nothing was silently redirected to app-private storage.\n\n" + error_string(err))
