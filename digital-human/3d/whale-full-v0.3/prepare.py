"""Bind the original full-resolution character without changing topology or shading."""
import bpy, math, json, os
from mathutils import Vector

OUT = os.path.dirname(os.path.abspath(__file__))
if bpy.data.scenes.get('Whale_Full_v03'):
    raise RuntimeError('Whale_Full_v03 already exists; reopen source.blend to rebuild.')
source = bpy.data.scenes['Scene']
scene = bpy.data.scenes.new('Whale_Full_v03')
bpy.context.window.scene = scene
meshes = []
source_count = 0
for original in source.objects:
    if original.type != 'MESH': continue
    source_count += len(original.data.vertices)
    obj = original.copy(); obj.data = original.data.copy()
    scene.collection.objects.link(obj)
    obj.parent = None; obj.matrix_world = original.matrix_world.copy()
    obj.hide_set(False); obj.hide_render = False
    obj['source_part'] = original.name
    bpy.context.view_layer.objects.active = obj; obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.select_set(False); meshes.append(obj)

data = bpy.data.armatures.new('WhaleFullSkeleton')
rig = bpy.data.objects.new('WhaleFullRig', data); scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig; rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
bones = [
 ('Root',(-.055,0,0),(-.055,0,.2),None),
 ('Hips',(-.055,0,.48),(-.055,0,.70),'Root'),
 ('Spine',(-.055,0,.70),(-.055,0,.92),'Hips'),
 ('Head',(-.055,0,.94),(-.055,0,1.50),'Spine'),
 ('Tail',(.18,.10,.40),(.63,.02,.47),'Hips'),
 ('TailTip',(.63,.02,.47),(.82,.02,.68),'Tail'),
]
for side, sign in [('L',1),('R',-1)]:
    x = -.055
    bones += [
      ('UpperArm.'+side,(x+sign*.19,-.13,.87),(x+sign*.31,-.17,.72),'Spine'),
      ('Forearm.'+side,(x+sign*.31,-.17,.72),(x+sign*.46,-.22,.63),'UpperArm.'+side),
      ('Thigh.'+side,(x+sign*.14,-.17,.49),(x+sign*.14,-.17,.30),'Hips'),
      ('Shin.'+side,(x+sign*.14,-.17,.30),(x+sign*.14,-.17,.13),'Thigh.'+side),
      ('Foot.'+side,(x+sign*.14,-.17,.13),(x+sign*.14,-.32,.08),'Shin.'+side),
    ]
for name, head, tail, parent in bones:
    bone = data.edit_bones.new(name); bone.head = head; bone.tail = tail
    if parent: bone.parent = data.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT')
rig.show_in_front = True

def blend(a,b,t): return {a:1-max(0,min(1,t)), b:max(0,min(1,t))}
for obj in meshes:
    part = obj['source_part']
    groups = {name:obj.vertex_groups.new(name=name) for name,_,_,_ in bones}
    for v in obj.data.vertices:
        x,y,z = v.co
        if part in ['root.0','root.3']: weights = {'Head':1}
        elif part in ['root.1.1','root.1.2']:
            side = 'R' if part == 'root.1.1' else 'L'
            weights = blend('UpperArm.'+side,'Forearm.'+side,(abs(x+.055)-.25)/.15)
        elif part in ['root.1.0.1','root.1.0.2']:
            side = 'R' if part == 'root.1.0.1' else 'L'
            weights = blend('Thigh.'+side,'Shin.'+side,(.38-z)/.16)
        elif part in ['root.1.4','root.1.5']: weights = {'Foot.'+('L' if part=='root.1.4' else 'R'):1}
        elif part in ['root.1.0.0','root.1.0.3','root.1.0.4']:
            weights = blend('Hips','Tail',(x-.12)/.30) if x < .55 else blend('Tail','TailTip',(x-.55)/.22)
        elif part in ['root.1.3','root.1.6']: weights = {'Spine':1}
        else: weights = {'Hips':1}
        for name, weight in weights.items():
            if weight > 0: groups[name].add([v.index],weight,'REPLACE')
    obj.parent = rig
    mod = obj.modifiers.new('Whale deformation','ARMATURE'); mod.object = rig
    if part == 'root.0':
        obj.shape_key_add(name='Basis')
        blink = obj.shape_key_add(name='Blink')
        mouth = obj.shape_key_add(name='Mouth_A')
        blink.value = 0; mouth.value = 0
        for i,v in enumerate(obj.data.vertices):
            x,y,z = v.co
            if y < -.27:
                front = min(1,(-y-.27)/.065)
                eye = max(math.exp(-(((x+.20)/.11)**4+((z-1.15)/.10)**4)),math.exp(-(((x-.09)/.11)**4+((z-1.15)/.10)**4))) * front
                blink.data[i].co.z -= (z-1.15)*.92*eye
                lip = math.exp(-(((x+.055)/.09)**4+((z-1.05)/.065)**4))*front
                mouth.data[i].co.z += (z-1.05)*.35*lip

for bone in rig.pose.bones: bone.rotation_mode = 'XYZ'
clips = {'Idle':(97,True),'Turn_360':(193,False),'Wave':(97,False),'Walk_In_Place':(49,True), 'Listening':(97,True),'Thinking':(97,True),'Tail_Swish':(97,False)}
for name,(end,loop) in clips.items():
    rig.animation_data_clear()
    for frame in range(1,end+1,3):
        t=(frame-1)/24; p=(frame-1)/(end-1); env=math.sin(math.pi*p)**2
        for b in rig.pose.bones: b.rotation_euler=(0,0,0); b.location=(0,0,0)
        if name=='Turn_360': rig.pose.bones['Root'].rotation_euler.y=2*math.pi*p
        if name=='Wave':
            rig.pose.bones['UpperArm.L'].rotation_euler.z=-.85*env
            rig.pose.bones['Forearm.L'].rotation_euler.z=-.35*env+math.sin(t*8)*.18*env
            rig.pose.bones['Forearm.L'].rotation_euler.x=.45*env
        if name=='Walk_In_Place':
            for side,sgn in [('L',1),('R',-1)]:
                phase=t*math.pi*2; swing=math.sin(phase)*sgn
                rig.pose.bones['Thigh.'+side].rotation_euler.x=.22*swing
                rig.pose.bones['Shin.'+side].rotation_euler.x=-.18*max(0,-swing)
                rig.pose.bones['UpperArm.'+side].rotation_euler.x=-.12*swing
            rig.pose.bones['Root'].location.y=.012*(1-math.cos(t*4*math.pi))
        if name=='Listening':rig.pose.bones['Head'].rotation_euler.x=.035+.025*math.sin(t*math.pi)
        if name=='Thinking':rig.pose.bones['Head'].rotation_euler.z=.09+.018*math.sin(t*math.pi)
        if name in ['Idle','Listening','Thinking','Tail_Swish']:
            rig.pose.bones['Tail'].rotation_euler.y=math.sin(t*math.pi)*(.12 if name=='Tail_Swish' else .025)
            rig.pose.bones['TailTip'].rotation_euler.y=math.sin(t*math.pi-.4)*.045
        for b in rig.pose.bones:
            b.keyframe_insert('rotation_euler',frame=frame,group=b.name)
            b.keyframe_insert('location',frame=frame,group=b.name)
    action=rig.animation_data.action; action.name='Full_'+name; action.use_fake_user=True
    rig.animation_data.action=None
    track=rig.animation_data.nla_tracks.new();track.name=name
    track.strips.new(name,1,action);track.mute=True
# Keep every clip addressable on one rig.
rig.animation_data_clear(); rig.animation_data_create()
for name in clips:
    action=bpy.data.actions['Full_'+name]
    track=rig.animation_data.nla_tracks.new();track.name=name
    track.strips.new(name,1,action);track.mute=name!='Idle'
scene.render.fps=24; scene.frame_start=1;scene.frame_end=193;scene.frame_set(1)
rig['source']='User live Blender imported character; source preserved separately; no external assets fetched.'
rig['limitations']='Prototype spatial weights. No finger rig, cloth simulation or IK. Facial morphs need art review.'
report={'source_vertices':source_count,'runtime_vertices':sum(len(o.data.vertices) for o in meshes),'bones':len(bones),'clips':list(clips),'all_weighted':all(v.groups for o in meshes for v in o.data.vertices), 'original_topology_preserved': all(len(o.data.vertices)==len(source.objects[o['source_part']].data.vertices) and len(o.data.polygons)==len(source.objects[o['source_part']].data.polygons) for o in meshes), 'reduction_applied':False}
with open(OUT+'/rig-validation.json','w') as f:json.dump(report,f,indent=2)
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/whale-full-v0.3.blend')
print(json.dumps(report))
