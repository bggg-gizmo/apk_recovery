@tool
extends EditorPlugin

var export_plugin: EditorExportPlugin

func _enter_tree() -> void:
    export_plugin = preload("res://addons/bgg_android_manifest_fix/export_plugin.gd").new()
    add_export_plugin(export_plugin)

func _exit_tree() -> void:
    if export_plugin != null:
        remove_export_plugin(export_plugin)
        export_plugin = null
