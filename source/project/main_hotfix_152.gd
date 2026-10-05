extends "res://main.gd"

# v1.5.2 production hotfix: never present app-private user:// storage as a
# successful user export. The primary export now always goes through Android's
# native save picker and the existing content://-aware recovery ZIP writer.
func _ready() -> void:
    super._ready()
    export_project_button.text = "Export Full Recovery Project ZIP"
    for connection in export_project_button.pressed.get_connections():
        export_project_button.pressed.disconnect(connection.callable)
    export_project_button.pressed.connect(_export_visible_project)

func _export_visible_project() -> void:
    _save_bundle_prompt()
