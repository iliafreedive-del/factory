"""Blender: выгрузить factory.glb для Godot из готового проекта twin/blender/factory.blend.

factory.blend уже собран скриптом build_factory.py (классы материалов, цвет и затенение в цвете вершин).
Правки, сделанные руками в Blender, попадут в двойник после этой выгрузки и новой веб-сборки.

Запуск: blender -b twin/blender/factory.blend -P twin/blender/export_glb.py -- twin/godot/assets/factory.glb
"""
import bpy, sys, os

argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
out = argv[0] if argv else os.path.join(os.path.dirname(bpy.data.filepath), '..', 'godot', 'assets', 'factory.glb')
out = os.path.abspath(out)
os.makedirs(os.path.dirname(out), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=False,
                          export_vertex_color='ACTIVE', export_all_vertex_colors=False,
                          export_lights=False, export_cameras=False, export_extras=False,
                          export_yup=True, export_image_format='AUTO')
print('done', out, os.path.getsize(out))
