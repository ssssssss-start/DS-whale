import bpy, os, json, struct
OUT = os.path.dirname(os.path.abspath(__file__))
scene = bpy.data.scenes['Whale_Full_v03']
bpy.context.window.scene = scene
rig = bpy.data.objects['WhaleFullRig']
for obj in scene.objects: obj.select_set(False)
rig.select_set(True)
for obj in rig.children:
    obj.select_set(True)
    if obj.type == 'MESH' and obj.data.shape_keys:
        for key in obj.data.shape_keys.key_blocks:
            if key.name != 'Basis': key.value = 0
bpy.context.view_layer.objects.active = rig
for track in rig.animation_data.nla_tracks: track.mute = False
path = OUT + '/whale-full-v0.3.glb'
bpy.ops.export_scene.gltf(filepath=path, use_selection=True, use_active_scene=True,
    export_animations=True, export_animation_mode='NLA_TRACKS',
    export_force_sampling=True, export_morph=True, export_anim_slide_to_zero=True,
    export_try_sparse_sk=False, export_try_omit_sparse_sk=False)
for track in rig.animation_data.nla_tracks: track.mute = True
scene.frame_set(1)
for bone in rig.pose.bones: bone.rotation_euler = (0,0,0); bone.location = (0,0,0)
bpy.context.view_layer.update()
bpy.ops.wm.save_as_mainfile(filepath=OUT + '/whale-full-v0.3.blend')
with open(path,'rb') as f: raw = f.read()
size = struct.unpack_from('<I',raw,12)[0]
doc = json.loads(raw[20:20+size])
report = {key:len(doc.get(key,[])) for key in ['meshes','nodes','skins','animations']}
report['clips'] = [clip['name'] for clip in doc['animations']]
report['bytes'] = len(raw)
assert report['meshes'] == 14 and report['skins'] == 1 and report['animations'] == 7, report
assert not any('sparse' in a for a in doc['accessors'])
assert all(not any(m.get('weights',[])) for m in doc['meshes'])
with open(OUT+'/export-validation.json','w') as f: json.dump(report,f,indent=2)
print(json.dumps(report))
