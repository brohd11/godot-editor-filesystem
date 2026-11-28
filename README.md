# EditorFS

Editor filesystem library behind [FileSystem Instances](https://github.com/brohd11/godot-filesystem-instances).
It mirrors Godot's FileSystem dock (file list, icons, previews, folder colors, favorites) and
drives the real dock for actions like rename, move and the context menu, so custom file views get
near-parity behavior.

## What's in it

- **`FileSystemSingleton`** (`EditorFS.Singleton`, `src/filesystem_singleton.gd`): the shared
  core. Caches every project path, type icons and previews, and emits `filesystem_changed` /
  `filesystem_paths_changed`. Static helpers cover the rest: `activate_path`, `get_preview`,
  `get_custom_tooltip`, `show_right_click_menu`, `show_file_move_dialog`, `rename_path`.
- **`EditorFS.Components.FSTree`** (`src/components/fs_tree.gd`): a filterable file tree with
  favorites, root pinning and the dock's context menu. Extend it and override
  `_process_custom_item`, `_custom_right_click_menu` and `_handle_custom_popup_id` for custom
  views (Script Dock does this).
- **`EditorFS.Components.SmallPopup`** (`src/util/fs_small_file_popup.gd`): adds a compact file
  context menu to an `Options` popup.
- **FileSystem tab** (`src/fs_tab/`): the full explorer that FileSystem Instances hosts, with a
  path bar, tree, places, item list/grid, Miller columns and a preview panel.
  `filesystem_tab.gd` is the entry point.
- **Utilities** (`src/util/`): filtering (`fs_filter.gd`), tooltips, rename, popup handlers and
  file-type lists. `fs_classes.gd` and `fs_util.gd` are preload hubs for these.

## Usage

The singleton is ref-counted: each plugin that uses it registers on enter and unregisters on exit.

```gdscript
func _enter_tree() -> void:
    FileSystemSingleton.register_node(self)
    FileSystemSingleton.call_on_ready(_on_fs_ready)

func _exit_tree() -> void:
    FileSystemSingleton.unregister_node(self)
```

`call_on_ready` waits for the editor's first scan and the initial path and preview build.

## Notes

- Rename drives the engine dock. It needs Godot 4.6+ and the Modern editor theme, and is
  disabled otherwise (`FSRename.is_rename_supported()`).
- Dependencies are listed in the `require` key of [package.cfg](./package.cfg).
