class_name ProceduralMeshes
extends RefCounted
## Builds realistic sculpted 3D meshes for the snake body, viper head,
## eyes, forked tongue, apples, leaves, and craggy boulders.

const TUBE_RADIAL_SEGS := 14


static func update_snake_body_mesh(
	mesh: ArrayMesh,
	spine_dirs: PackedVector3Array,
	planet_radius: float,
	body_radius: float,
	cell_world_len: float,
	slither_phase: float
) -> void:
	## Extrudes an organic scaly reptile body along spherical centerline points.
	## spine_dirs[0] is at the neck behind the head; spine_dirs[-1] is the tail tip.
	mesh.clear_surfaces()
	var count := spine_dirs.size()
	if count < 2:
		return

	# 1. Chaikin corner-smoothing pass (keeps endpoints anchored, smooths 90-deg turns)
	var smooth_dirs := PackedVector3Array()
	smooth_dirs.append(spine_dirs[0].normalized())
	for i in range(count - 1):
		var a := spine_dirs[i].normalized()
		var b := spine_dirs[i + 1].normalized()
		if i > 0:
			smooth_dirs.append(_slerp(a, b, 0.25))
		if i < count - 2:
			smooth_dirs.append(_slerp(a, b, 0.75))
	smooth_dirs.append(spine_dirs[count - 1].normalized())

	# 2. Subdivide each span for silky spherical curvature
	var fine_dirs := PackedVector3Array()
	for i in range(smooth_dirs.size() - 1):
		var a := smooth_dirs[i]
		var b := smooth_dirs[i + 1]
		var steps := 2 if a.angle_to(b) > 0.04 else 1
		for s in range(steps):
			fine_dirs.append(_slerp(a, b, float(s) / float(steps)))
	fine_dirs.append(smooth_dirs[smooth_dirs.size() - 1])

	var m := fine_dirs.size()
	if m < 2:
		return

	# 3. Compute arc-length and apply subtle organic slither undulation on straight segments
	var arc_len := PackedFloat32Array()
	arc_len.resize(m)
	arc_len[0] = 0.0
	for i in range(1, m):
		var ang := fine_dirs[i - 1].angle_to(fine_dirs[i])
		arc_len[i] = arc_len[i - 1] + ang * planet_radius

	var total_len := maxf(arc_len[m - 1], 0.001)
	var tangents := PackedVector3Array()
	tangents.resize(m)
	for i in range(m):
		var prev_p := fine_dirs[maxi(i - 1, 0)]
		var next_p := fine_dirs[mini(i + 1, m - 1)]
		var up_n := fine_dirs[i]
		var raw_t := next_p - prev_p
		raw_t = raw_t - up_n * raw_t.dot(up_n)
		if raw_t.length_squared() < 1e-8:
			raw_t = up_n.cross(Vector3.UP)
			if raw_t.length_squared() < 1e-8:
				raw_t = up_n.cross(Vector3.RIGHT)
		tangents[i] = raw_t.normalized()

	var slither_dirs := PackedVector3Array()
	slither_dirs.resize(m)
	for i in range(m):
		var up_n := fine_dirs[i]
		var fwd := tangents[i]
		var right := up_n.cross(fwd).normalized()
		var s := arc_len[i]

		# Attenuate wave near neck, tail tip, and tight corners
		var head_env := clampf(s / (cell_world_len * 0.75), 0.0, 1.0)
		var tail_env := clampf((total_len - s) / (cell_world_len * 0.65), 0.0, 1.0)
		var straightness := 1.0
		if i > 0 and i < m - 1:
			straightness = clampf((tangents[i - 1].dot(tangents[i + 1]) - 0.5) * 2.0, 0.0, 1.0)

		var wave_ang := sin((s / maxf(cell_world_len, 0.01)) * 2.6 - slither_phase)
		var offset_ang := (body_radius * 0.16 / planet_radius) * wave_ang * head_env * tail_env * straightness
		slither_dirs[i] = (up_n + right * offset_ang).normalized()

	# Recompute clean tangents after subtle slither
	for i in range(m):
		var prev_p := slither_dirs[maxi(i - 1, 0)]
		var next_p := slither_dirs[mini(i + 1, m - 1)]
		var up_n := slither_dirs[i]
		var raw_t := next_p - prev_p
		raw_t = raw_t - up_n * raw_t.dot(up_n)
		if raw_t.length_squared() > 1e-8:
			tangents[i] = raw_t.normalized()

	# 4. Build extruded ring geometry
	var ring_stride := TUBE_RADIAL_SEGS + 1
	var vert_count := m * ring_stride + 1 # +1 for closed tail tip
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	positions.resize(vert_count)
	normals.resize(vert_count)
	uvs.resize(vert_count)

	var v_scale := 1.0 / maxf(cell_world_len * 1.15, 0.05)

	for i in range(m):
		var up_n := slither_dirs[i]
		var fwd := tangents[i]
		var right := up_n.cross(fwd).normalized()

		var t_norm := arc_len[i] / total_len
		# Radius envelope: smooth neck collar meeting skull, slender muscular body, graceful tail taper
		var neck_taper := lerpf(0.92, 1.0, clampf(arc_len[i] / (cell_world_len * 0.55), 0.0, 1.0))
		var tail_t := clampf((t_norm - 0.62) / 0.38, 0.0, 1.0)
		var tail_taper := lerpf(1.0, 0.14, tail_t * tail_t * (3.0 - 2.0 * tail_t))
		var r_local := body_radius * neck_taper * tail_taper

		# Belly sits flush against the bumped planet surface
		var surf_r := planet_radius + SphereGrid.surface_bump(up_n)
		var center := up_n * (surf_r + r_local * 0.68)
		var v_coord := arc_len[i] * v_scale

		for j in range(ring_stride):
			var u_frac := float(j) / float(TUBE_RADIAL_SEGS)
			var theta := u_frac * TAU
			var c_th := cos(theta)
			var s_th := sin(theta)

			# Slightly wider oval belly + subtle dorsal ridge crest
			var rx := r_local * 1.12
			var ry := r_local * (0.70 if c_th > 0.0 else 0.98)
			var dorsal_ridge := maxf(0.0, -c_th)
			ry += r_local * 0.08 * pow(dorsal_ridge, 4.0)

			var local_dir := (-up_n * c_th * ry + right * s_th * rx)
			var pos := center + local_dir
			var norm := (-up_n * c_th + right * s_th).normalized()

			var idx := i * ring_stride + j
			positions[idx] = pos
			normals[idx] = norm
			uvs[idx] = Vector2(u_frac, v_coord)

	# Tail tip cap vertex
	var tail_tip_idx := m * ring_stride
	var tail_up := slither_dirs[m - 1]
	var tail_fwd := tangents[m - 1]
	var tail_surf := planet_radius + SphereGrid.surface_bump(tail_up)
	positions[tail_tip_idx] = tail_up * (tail_surf + body_radius * 0.11) + tail_fwd * (body_radius * 0.35)
	normals[tail_tip_idx] = (tail_fwd + tail_up * 0.3).normalized()
	uvs[tail_tip_idx] = Vector2(0.5, total_len * v_scale + 0.15)

	var indices := PackedInt32Array()
	var quad_count := (m - 1) * TUBE_RADIAL_SEGS
	indices.resize(quad_count * 6 + TUBE_RADIAL_SEGS * 3)
	var ic := 0
	for i in range(m - 1):
		var row0 := i * ring_stride
		var row1 := (i + 1) * ring_stride
		for j in range(TUBE_RADIAL_SEGS):
			var p00 := row0 + j
			var p01 := row0 + j + 1
			var p10 := row1 + j
			var p11 := row1 + j + 1
			# Clockwise winding viewed from outside
			indices[ic] = p00
			indices[ic + 1] = p10
			indices[ic + 2] = p11
			indices[ic + 3] = p00
			indices[ic + 4] = p11
			indices[ic + 5] = p01
			ic += 6

	# Cap tail tip
	var last_row := (m - 1) * ring_stride
	for j in range(TUBE_RADIAL_SEGS):
		indices[ic] = last_row + j
		indices[ic + 1] = tail_tip_idx
		indices[ic + 2] = last_row + j + 1
		ic += 3

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


static func build_snake_head_node(
	body_radius: float,
	skin_mat: Material,
	eye_mat: Material,
	pupil_mat: Material,
	tongue_mat: Material
) -> Dictionary:
	## Builds a multi-part realistic viper head facing -Z with +Y up.
	var root := Node3D.new()
	root.name = "SnakeHead"

	# Upper skull + snout sculpted via profile rings along Z (from neck +Z to snout -Z)
	var head_mesh := _create_viper_skull_mesh(body_radius, true)
	var skull_inst := MeshInstance3D.new()
	skull_inst.mesh = head_mesh
	skull_inst.material_override = skin_mat
	skull_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(skull_inst)

	# Hinged lower jaw
	var jaw_pivot := Node3D.new()
	jaw_pivot.name = "JawPivot"
	jaw_pivot.position = Vector3(0.0, -body_radius * 0.16, body_radius * 0.25)
	root.add_child(jaw_pivot)

	var jaw_mesh := _create_viper_skull_mesh(body_radius, false)
	var jaw_inst := MeshInstance3D.new()
	jaw_inst.mesh = jaw_mesh
	jaw_inst.position = -jaw_pivot.position
	jaw_inst.material_override = skin_mat
	jaw_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	jaw_pivot.add_child(jaw_inst)

	# Glossy amber eyes with vertical slit pupils tucked under brow ridges
	var eye_r := body_radius * 0.32
	var eye_sphere := SphereMesh.new()
	eye_sphere.radius = eye_r
	eye_sphere.height = eye_r * 2.0
	eye_sphere.radial_segments = 16
	eye_sphere.rings = 10

	var pupil_mesh := SphereMesh.new()
	pupil_mesh.radius = eye_r * 0.65
	pupil_mesh.height = eye_r * 1.45
	pupil_mesh.radial_segments = 12
	pupil_mesh.rings = 8

	for side in [-1.0, 1.0]:
		var eye_node := MeshInstance3D.new()
		eye_node.mesh = eye_sphere
		eye_node.material_override = eye_mat
		eye_node.position = Vector3(side * body_radius * 0.78, body_radius * 0.40, -body_radius * 0.50)
		eye_node.scale = Vector3(0.78, 1.0, 1.08)
		root.add_child(eye_node)

		var pupil_node := MeshInstance3D.new()
		pupil_node.mesh = pupil_mesh
		pupil_node.material_override = pupil_mat
		# Vertical slit pupil facing outward & forward
		pupil_node.position = Vector3(side * eye_r * 0.58, 0.0, -eye_r * 0.38)
		pupil_node.scale = Vector3(0.45, 0.94, 0.30)
		eye_node.add_child(pupil_node)

	# Forked animated crimson tongue
	var tongue_pivot := Node3D.new()
	tongue_pivot.name = "TonguePivot"
	tongue_pivot.position = Vector3(0.0, -body_radius * 0.10, -body_radius * 1.32)
	root.add_child(tongue_pivot)

	var tongue_inst := MeshInstance3D.new()
	tongue_inst.mesh = _create_forked_tongue_mesh(body_radius)
	tongue_inst.material_override = tongue_mat
	tongue_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tongue_pivot.add_child(tongue_inst)

	return {
		"root": root,
		"jaw_pivot": jaw_pivot,
		"tongue_pivot": tongue_pivot,
	}


static func _create_viper_skull_mesh(body_r: float, is_upper: bool) -> ArrayMesh:
	# Profile stations from neck (z > 0) to snout tip (z < 0)
	# Each entry: [z_mult, width_mult, height_mult, y_offset_mult]
	var profile := [
		[0.52, 0.95, 0.80, 0.0],
		[0.12, 1.24, 0.86, 0.05],
		[-0.38, 1.12, 0.82, 0.04],
		[-0.88, 0.84, 0.66, -0.02],
		[-1.34, 0.50, 0.40, -0.06],
		[-1.58, 0.16, 0.16, -0.08],
	]

	var segs := 14
	var ring_stride := segs + 1
	var rings := profile.size()
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	positions.resize(rings * ring_stride)
	normals.resize(rings * ring_stride)
	uvs.resize(rings * ring_stride)

	for i in range(rings):
		var st: Array = profile[i]
		var z_val := float(st[0]) * body_r
		var rx := float(st[1]) * body_r
		var ry := float(st[2]) * body_r
		var y_off := float(st[3]) * body_r
		var v_coord := float(i) / float(rings - 1)

		for j in range(ring_stride):
			var u_frac := float(j) / float(segs)
			var theta := u_frac * TAU
			var c_th := cos(theta)
			var s_th := sin(theta)

			# Upper skull covers dorsal half + slight sides; lower jaw covers ventral half
			var local_y := -c_th * ry
			if is_upper:
				local_y = maxf(local_y, -ry * 0.28)
				# Brow ridge bulge around station 1-2
				if i == 1 or i == 2:
					local_y += maxf(0.0, absf(s_th) - 0.55) * body_r * 0.26 * maxf(0.0, -c_th)
			else:
				local_y = minf(local_y, -ry * 0.12) * 0.92

			var pos := Vector3(s_th * rx, local_y + y_off, z_val)
			var norm := Vector3(s_th, -c_th, -0.25 if i == rings - 1 else 0.0).normalized()
			var idx := i * ring_stride + j
			positions[idx] = pos
			normals[idx] = norm
			uvs[idx] = Vector2(u_frac, v_coord * 1.4)

	var indices := PackedInt32Array()
	for i in range(rings - 1):
		var r0 := i * ring_stride
		var r1 := (i + 1) * ring_stride
		for j in range(segs):
			var p00 := r0 + j
			var p01 := r0 + j + 1
			var p10 := r1 + j
			var p11 := r1 + j + 1
			# Ring moves from +Z to -Z (forward), so flip quad winding to match outward CW
			indices.append_array([p00, p01, p11, p00, p11, p10])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _create_forked_tongue_mesh(body_r: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var t_len := body_r * 0.95
	var w := body_r * 0.055
	var fork_z := -t_len * 0.58
	var tip_spread := body_r * 0.16

	# Main tongue ribbon
	var p0 := Vector3(-w, 0.0, 0.0)
	var p1 := Vector3(w, 0.0, 0.0)
	var p2 := Vector3(-w * 0.75, 0.0, fork_z)
	var p3 := Vector3(w * 0.75, 0.0, fork_z)
	_add_double_quad(st, p0, p1, p3, p2)

	# Left fork tip
	var lf0 := Vector3(-w * 0.75, 0.0, fork_z)
	var lf1 := Vector3(-w * 0.05, 0.0, fork_z)
	var lf2 := Vector3(-tip_spread, 0.0, -t_len)
	var lf3 := Vector3(-tip_spread + w * 0.55, 0.0, -t_len)
	_add_double_quad(st, lf0, lf1, lf3, lf2)

	# Right fork tip
	var rf0 := Vector3(w * 0.05, 0.0, fork_z)
	var rf1 := Vector3(w * 0.75, 0.0, fork_z)
	var rf2 := Vector3(tip_spread - w * 0.55, 0.0, -t_len)
	var rf3 := Vector3(tip_spread, 0.0, -t_len)
	_add_double_quad(st, rf0, rf1, rf3, rf2)

	st.generate_normals()
	return st.commit()


static func _add_double_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)
	# Back face
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(b)
	st.add_vertex(a)
	st.add_vertex(d)
	st.add_vertex(c)


static func build_apple_node(
	radius: float,
	apple_mat: Material,
	stem_mat: Material,
	leaf_mat: Material
) -> Node3D:
	## Builds a realistic sculpted 3D apple with dimpled stem cavity, woody stem, and leaf.
	var root := Node3D.new()

	var body := MeshInstance3D.new()
	body.mesh = _create_apple_lathe_mesh(radius)
	body.material_override = apple_mat
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(body)

	# Curved woody stem
	var stem := MeshInstance3D.new()
	var stem_cyl := CylinderMesh.new()
	stem_cyl.top_radius = radius * 0.06
	stem_cyl.bottom_radius = radius * 0.09
	stem_cyl.height = radius * 0.56
	stem_cyl.radial_segments = 8
	stem.mesh = stem_cyl
	stem.material_override = stem_mat
	stem.position = Vector3(radius * 0.05, radius * 0.84, 0.0)
	stem.rotation_degrees = Vector3(0.0, 0.0, -14.0)
	root.add_child(stem)

	# Curved green leaf
	var leaf := MeshInstance3D.new()
	leaf.mesh = _create_leaf_mesh(radius * 0.62)
	leaf.material_override = leaf_mat
	leaf.position = Vector3(radius * 0.08, radius * 0.94, 0.0)
	leaf.rotation_degrees = Vector3(18.0, 22.0, -24.0)
	root.add_child(leaf)

	return root


static func _create_apple_lathe_mesh(radius: float) -> ArrayMesh:
	var rings := 20
	var slices := 24
	var ring_stride := slices + 1
	var positions := PackedVector3Array()
	var uvs := PackedVector2Array()
	positions.resize((rings + 1) * ring_stride)
	uvs.resize((rings + 1) * ring_stride)

	for i in range(rings + 1):
		var v := float(i) / float(rings)
		var theta := v * PI # 0 = top pole (stem dimple), PI = bottom calyx
		var sin_t := sin(theta)
		var cos_t := cos(theta)

		# Classic organic apple silhouette: wider shoulders at upper half, indented poles
		var shoulder := 1.0 + 0.16 * sin(v * PI * 1.15) - 0.18 * v
		var top_dimple := 0.30 * exp(-pow(v / 0.16, 2.0))
		var bot_dimple := 0.18 * exp(-pow((1.0 - v) / 0.14, 2.0))
		var y := cos_t * radius * 0.92 - top_dimple * radius + bot_dimple * radius

		for j in range(ring_stride):
			var u := float(j) / float(slices)
			var phi := u * TAU
			# 5-lobe natural apple asymmetry
			var lobe := 1.0 + 0.045 * cos(phi * 5.0) * sin_t
			var r_ring := sin_t * radius * shoulder * lobe
			var x := cos(phi) * r_ring
			var z := sin(phi) * r_ring

			var idx := i * ring_stride + j
			positions[idx] = Vector3(x, y, z)
			uvs[idx] = Vector2(u, v)

	var indices := PackedInt32Array()
	for i in range(rings):
		var r0 := i * ring_stride
		var r1 := (i + 1) * ring_stride
		for j in range(slices):
			var p00 := r0 + j
			var p01 := r0 + j + 1
			var p10 := r1 + j
			var p11 := r1 + j + 1
			indices.append_array([p00, p01, p11, p00, p11, p10])

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for idx in indices:
		st.set_uv(uvs[idx])
		st.add_vertex(positions[idx])
	st.index()
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


static func _create_leaf_mesh(length: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := length * 0.42
	var a := Vector3(0.0, 0.0, 0.0)
	var b := Vector3(length * 0.48, length * 0.14, w)
	var c := Vector3(length, -length * 0.05, 0.0)
	var d := Vector3(length * 0.48, length * 0.14, -w)
	_add_double_quad(st, a, b, c, d)
	st.generate_normals()
	return st.commit()


static func build_boulder_mesh(radius: float, seed_val: int) -> ArrayMesh:
	## Builds a craggy realistic granite boulder slightly flattened on bottom.
	var base := SphereMesh.new()
	base.radius = radius
	base.height = radius * 1.65
	base.radial_segments = 16
	base.rings = 10

	var mdt := MeshDataTool.new()
	var arr := base.get_mesh_arrays()
	var tmp := ArrayMesh.new()
	tmp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mdt.create_from_surface(tmp, 0)

	var p_offset := Vector3(float(seed_val % 37) * 1.37, float(seed_val % 53) * 0.91, float(seed_val % 29) * 1.73)
	for v_idx in range(mdt.get_vertex_count()):
		var v := mdt.get_vertex(v_idx)
		var dir := v.normalized()
		# Deterministic layered rock angular noise
		var n := (
			sin(dir.x * 5.2 + p_offset.x) * cos(dir.y * 4.7 + p_offset.y)
			+ 0.45 * sin(dir.z * 9.3 + p_offset.z)
			+ 0.25 * cos((dir.x - dir.z) * 13.0)
		)
		var disp := 1.0 + 0.19 * n
		v *= disp
		# Flatten base so boulder embeds cleanly into the planet tile
		if v.y < -radius * 0.35:
			v.y = lerpf(v.y, -radius * 0.35, 0.65)
		mdt.set_vertex(v_idx, v)

	var out := ArrayMesh.new()
	mdt.commit_to_surface(out)
	var st := SurfaceTool.new()
	st.create_from(out, 0)
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


static func build_wall_mesh(cell_len: float, connect_mask: int, seed_val: int) -> ArrayMesh:
	## Builds a sculpted carved stone wall block with optional seamless bridges
	## along bitmask dirs (1:+fwd/up, 2:+right, 4:-fwd/up, 8:-right) on local XZ.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var h := cell_len * 0.62
	var half_w := cell_len * 0.34
	var base_y := -cell_len * 0.14 # embed cleanly into bumped terrain

	# Main carved tapered stone monolith
	_add_beveled_stone_box(st, Vector3(0.0, base_y, 0.0), half_w, h, half_w, seed_val)

	# Bridge connectors along neighboring wall cells so multi-cell walls fuse cleanly
	var reach := cell_len * 0.56
	var bridge_w := half_w * 0.98
	var bridge_h := h * 0.96
	if (connect_mask & 1) != 0: # +fwd (-Z in Godot local Basis where fwd = +Z or -Z; let's match _place_wall)
		_add_beveled_stone_box(st, Vector3(0.0, base_y, reach * 0.52), bridge_w, bridge_h, reach * 0.52, seed_val + 1)
	if (connect_mask & 2) != 0:
		_add_beveled_stone_box(st, Vector3(reach * 0.52, base_y, 0.0), reach * 0.52, bridge_h, bridge_w, seed_val + 2)
	if (connect_mask & 4) != 0:
		_add_beveled_stone_box(st, Vector3(0.0, base_y, -reach * 0.52), bridge_w, bridge_h, reach * 0.52, seed_val + 3)
	if (connect_mask & 8) != 0:
		_add_beveled_stone_box(st, Vector3(-reach * 0.52, base_y, 0.0), reach * 0.52, bridge_h, bridge_w, seed_val + 4)

	st.generate_normals()
	st.generate_tangents()
	return st.commit()


static func _add_beveled_stone_box(
	st: SurfaceTool,
	base_pos: Vector3,
	hx: float,
	height: float,
	hz: float,
	seed_val: int
) -> void:
	var top_inset := 0.84
	var tx := hx * top_inset
	var tz := hz * top_inset
	var jitter := 0.04 * sin(float(seed_val) * 1.7)
	var y0 := base_pos.y
	var y1 := base_pos.y + height * (1.0 + jitter)

	var b0 := base_pos + Vector3(-hx, 0.0, -hz)
	var b1 := base_pos + Vector3(hx, 0.0, -hz)
	var b2 := base_pos + Vector3(hx, 0.0, hz)
	var b3 := base_pos + Vector3(-hx, 0.0, hz)
	b0.y = y0; b1.y = y0; b2.y = y0; b3.y = y0

	var t0 := base_pos + Vector3(-tx, 0.0, -tz)
	var t1 := base_pos + Vector3(tx, 0.0, -tz)
	var t2 := base_pos + Vector3(tx, 0.0, tz)
	var t3 := base_pos + Vector3(-tx, 0.0, tz)
	t0.y = y1; t1.y = y1; t2.y = y1; t3.y = y1

	# Top cap
	_add_uv_quad(st, t0, t1, t2, t3)
	# 4 sloped stone faces (CW outward viewed from outside)
	_add_uv_quad(st, b0, b1, t1, t0)
	_add_uv_quad(st, b1, b2, t2, t1)
	_add_uv_quad(st, b2, b3, t3, t2)
	_add_uv_quad(st, b3, b0, t0, t3)


static func _add_uv_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(a)
	st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(b)
	st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(c)
	st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(a)
	st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(c)
	st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(d)


static func _slerp(a: Vector3, b: Vector3, t: float) -> Vector3:
	var dot_ab := clampf(a.dot(b), -1.0, 1.0)
	if dot_ab > 0.99995:
		return a.lerp(b, t).normalized()
	var omega := acos(dot_ab)
	var sin_o := sin(omega)
	return (a * sin((1.0 - t) * omega) + b * sin(t * omega)) / sin_o


static func build_shockwave_ring_mesh(inner_r: float, outer_r: float) -> ArrayMesh:
	## Builds a flat circular ring on XZ for expanding impact & collect shockwaves.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGS := 32
	for i in range(SEGS):
		var a0 := (float(i) / float(SEGS)) * TAU
		var a1 := (float(i + 1) / float(SEGS)) * TAU
		var p_o0 := Vector3(cos(a0) * outer_r, 0.0, sin(a0) * outer_r)
		var p_o1 := Vector3(cos(a1) * outer_r, 0.0, sin(a1) * outer_r)
		var p_i1 := Vector3(cos(a1) * inner_r, 0.0, sin(a1) * inner_r)
		var p_i0 := Vector3(cos(a0) * inner_r, 0.0, sin(a0) * inner_r)
		_add_uv_quad(st, p_o0, p_o1, p_i1, p_i0)
	st.generate_normals()
	return st.commit()


static func build_powerup_mesh(radius: float, ptype: int) -> ArrayMesh:
	## Builds unmistakable sculpted 3D silhouettes for Shield (0), Magnet (1), and Frost (2).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	if ptype == 0:
		# Shield: beveled hexagonal kite-shield energy core
		_add_bipyramid(st, Vector3.ZERO, radius * 0.92, radius * 1.15, radius * 0.42, 6)
		_add_box_solid(st, Vector3(0.0, 0.0, 0.0), Vector3(radius * 0.24, radius * 1.25, radius * 0.48))
	elif ptype == 1:
		# Magnet: 3D U-shaped horseshoe magnet
		var arm_w := radius * 0.28
		var arm_h := radius * 0.72
		var arm_x := radius * 0.62
		_add_box_solid(st, Vector3(-arm_x, radius * 0.22, 0.0), Vector3(arm_w, arm_h, arm_w))
		_add_box_solid(st, Vector3(arm_x, radius * 0.22, 0.0), Vector3(arm_w, arm_h, arm_w))
		_add_box_solid(st, Vector3(0.0, -radius * 0.62, 0.0), Vector3(arm_x + arm_w, arm_w * 0.95, arm_w))
		_add_box_solid(st, Vector3(-arm_x, radius * 0.95, 0.0), Vector3(arm_w * 1.12, arm_w * 0.55, arm_w * 1.12))
		_add_box_solid(st, Vector3(arm_x, radius * 0.95, 0.0), Vector3(arm_w * 1.12, arm_w * 0.55, arm_w * 1.12))
	else:
		# Frost: 6-pointed crystalline ice star
		_add_bipyramid(st, Vector3.ZERO, radius * 0.36, radius * 1.20, radius * 0.36, 4)
		for k in range(3):
			var ang := float(k) * (PI / 3.0)
			_add_rotated_rod_crystal(st, ang, radius * 1.05, radius * 0.24)

	st.generate_normals()
	return st.commit()


static func _add_box_solid(st: SurfaceTool, center: Vector3, half_ext: Vector3) -> void:
	var hx := half_ext.x
	var hy := half_ext.y
	var hz := half_ext.z
	var b0 := center + Vector3(-hx, -hy, -hz)
	var b1 := center + Vector3(hx, -hy, -hz)
	var b2 := center + Vector3(hx, -hy, hz)
	var b3 := center + Vector3(-hx, -hy, hz)
	var t0 := center + Vector3(-hx, hy, -hz)
	var t1 := center + Vector3(hx, hy, -hz)
	var t2 := center + Vector3(hx, hy, hz)
	var t3 := center + Vector3(-hx, hy, hz)
	_add_uv_quad(st, t0, t1, t2, t3)
	_add_uv_quad(st, b3, b2, b1, b0)
	_add_uv_quad(st, b0, b1, t1, t0)
	_add_uv_quad(st, b1, b2, t2, t1)
	_add_uv_quad(st, b2, b3, t3, t2)
	_add_uv_quad(st, b3, b0, t0, t3)


static func _add_bipyramid(st: SurfaceTool, center: Vector3, rx: float, ry: float, rz: float, sides: int) -> void:
	var top := center + Vector3(0.0, ry, 0.0)
	var bot := center - Vector3(0.0, ry, 0.0)
	for i in range(sides):
		var a0 := (float(i) / float(sides)) * TAU
		var a1 := (float(i + 1) / float(sides)) * TAU
		var p0 := center + Vector3(cos(a0) * rx, 0.0, sin(a0) * rz)
		var p1 := center + Vector3(cos(a1) * rx, 0.0, sin(a1) * rz)
		st.set_uv(Vector2(0.5, 0.0)); st.add_vertex(top)
		st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(p0)
		st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(p1)
		st.set_uv(Vector2(0.5, 1.0)); st.add_vertex(bot)
		st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(p1)
		st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(p0)


static func _add_rotated_rod_crystal(st: SurfaceTool, ang: float, len_half: float, rad: float) -> void:
	var axis := Vector3(cos(ang), 0.0, sin(ang)).normalized()
	var perp := Vector3(-sin(ang), 0.0, cos(ang)).normalized()
	var tip_a := axis * len_half
	var tip_b := -axis * len_half
	var ring: Array[Vector3] = [
		perp * rad,
		Vector3(0.0, rad, 0.0),
		-perp * rad,
		Vector3(0.0, -rad, 0.0),
	]
	for i in range(4):
		var p0 := ring[i]
		var p1 := ring[(i + 1) % 4]
		st.set_uv(Vector2(0.5, 0.0)); st.add_vertex(tip_a)
		st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(p0)
		st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(p1)
		st.set_uv(Vector2(0.5, 1.0)); st.add_vertex(tip_b)
		st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(p1)
		st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(p0)


static func build_street_lamp_node(cell_len: float, pole_mat: Material, bulb_mat: Material) -> Node3D:
	## Builds a miniature orbital street lamp post with warm lantern bulb to sit on grid intersections.
	var root := Node3D.new()

	var base := MeshInstance3D.new()
	var base_cyl := CylinderMesh.new()
	base_cyl.top_radius = cell_len * 0.048
	base_cyl.bottom_radius = cell_len * 0.072
	base_cyl.height = cell_len * 0.14
	base_cyl.radial_segments = 8
	base.mesh = base_cyl
	base.material_override = pole_mat
	base.position = Vector3(0.0, 0.0, 0.0)
	base.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(base)

	var post := MeshInstance3D.new()
	var post_cyl := CylinderMesh.new()
	post_cyl.top_radius = cell_len * 0.024
	post_cyl.bottom_radius = cell_len * 0.036
	post_cyl.height = cell_len * 0.54
	post_cyl.radial_segments = 8
	post.mesh = post_cyl
	post.material_override = pole_mat
	post.position = Vector3(0.0, cell_len * 0.28, 0.0)
	post.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(post)

	var hood := MeshInstance3D.new()
	var hood_cyl := CylinderMesh.new()
	hood_cyl.top_radius = cell_len * 0.035
	hood_cyl.bottom_radius = cell_len * 0.105
	hood_cyl.height = cell_len * 0.065
	hood_cyl.radial_segments = 10
	hood.mesh = hood_cyl
	hood.material_override = pole_mat
	hood.position = Vector3(0.0, cell_len * 0.56, 0.0)
	hood.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(hood)

	var bulb := MeshInstance3D.new()
	var bulb_sph := SphereMesh.new()
	bulb_sph.radius = cell_len * 0.068
	bulb_sph.height = cell_len * 0.136
	bulb_sph.radial_segments = 10
	bulb_sph.rings = 6
	bulb.mesh = bulb_sph
	bulb.material_override = bulb_mat
	bulb.position = Vector3(0.0, cell_len * 0.51, 0.0)
	bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bulb)

	return root
