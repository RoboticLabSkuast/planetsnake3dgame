class_name SphereGrid
extends RefCounted
## Equiangular Cube-Sphere 4-connected grid topology and smooth mesh generator.
## Every face (0..5) forms an N x N quad grid with seamless edge transitions
## and consistent right-handed orientation across all 6 faces and 8 corners.

const FACE_COUNT := 6

# Orthonormal right-handed face bases where right.cross(up) == normal
const FACE_NORMALS: Array[Vector3] = [
	Vector3(1.0, 0.0, 0.0),   # 0: +X
	Vector3(-1.0, 0.0, 0.0),  # 1: -X
	Vector3(0.0, 1.0, 0.0),   # 2: +Y
	Vector3(0.0, -1.0, 0.0),  # 3: -Y
	Vector3(0.0, 0.0, 1.0),   # 4: +Z
	Vector3(0.0, 0.0, -1.0),  # 5: -Z
]

const FACE_RIGHTS: Array[Vector3] = [
	Vector3(0.0, 0.0, -1.0),  # +X -> right is -Z
	Vector3(0.0, 0.0, 1.0),   # -X -> right is +Z
	Vector3(1.0, 0.0, 0.0),   # +Y -> right is +X
	Vector3(1.0, 0.0, 0.0),   # -Y -> right is +X
	Vector3(1.0, 0.0, 0.0),   # +Z -> right is +X
	Vector3(-1.0, 0.0, 0.0),  # -Z -> right is -X
]

const FACE_UPS: Array[Vector3] = [
	Vector3(0.0, 1.0, 0.0),   # +X -> up is +Y
	Vector3(0.0, 1.0, 0.0),   # -X -> up is +Y
	Vector3(0.0, 0.0, -1.0),  # +Y -> up is -Z
	Vector3(0.0, 0.0, 1.0),   # -Y -> up is +Z
	Vector3(0.0, 1.0, 0.0),   # +Z -> up is +Y
	Vector3(0.0, 1.0, 0.0),   # -Z -> up is +Y
]

# Local directions: 0 = +up, 1 = +right, 2 = -up, 3 = -right
const DIR_DU := [0, 1, 0, -1]
const DIR_DV := [1, 0, -1, 0]

var grid_n: int = 10
var cells_per_face: int = 100
var total_cells: int = 600
var cell_arc_angle: float = 0.1570796

var cell_normals: PackedVector3Array
var neighbors: PackedInt32Array
var next_headings: PackedInt32Array
var edge_tangents: PackedVector3Array


func _init(n: int = 10) -> void:
	configure(n)


func configure(n: int) -> void:
	grid_n = clampi(n, 2, 14)
	cells_per_face = grid_n * grid_n
	total_cells = FACE_COUNT * cells_per_face
	cell_arc_angle = (PI * 0.5) / float(grid_n)

	cell_normals.resize(total_cells)
	neighbors.resize(total_cells * 4)
	next_headings.resize(total_cells * 4)
	edge_tangents.resize(total_cells * 4)

	# 1. Precompute exact unit sphere centers using equiangular projection
	for face in range(FACE_COUNT):
		for v in range(grid_n):
			for u in range(grid_n):
				var cid := cell_id(face, u, v)
				cell_normals[cid] = _cell_cube_to_sphere(face, u, v)

	# 2. Precompute exact 4-neighbor adjacency and cross-face forward heading
	for face in range(FACE_COUNT):
		for v in range(grid_n):
			for u in range(grid_n):
				var cid := cell_id(face, u, v)
				var base := cid * 4
				var c_norm := cell_normals[cid]

				for d in range(4):
					var res := _compute_neighbor(face, u, v, d)
					var n_cid: int = res["cell"]
					neighbors[base + d] = n_cid
					next_headings[base + d] = res["dir"]

					var delta := cell_normals[n_cid] - c_norm
					var tangent := (delta - c_norm * delta.dot(c_norm)).normalized()
					edge_tangents[base + d] = tangent


func cell_id(face: int, u: int, v: int) -> int:
	return face * cells_per_face + v * grid_n + u


func decode_cell(cid: int) -> Vector3i:
	var face := cid / cells_per_face
	var rem := cid % cells_per_face
	var v := rem / grid_n
	var u := rem % grid_n
	return Vector3i(face, u, v)


func step(cid: int, dir: int) -> Dictionary:
	var idx := cid * 4 + (dir & 3)
	return {
		"cell": neighbors[idx],
		"dir": next_headings[idx],
	}


func get_neighbor(cid: int, dir: int) -> int:
	return neighbors[cid * 4 + (dir & 3)]


func get_next_heading(cid: int, dir: int) -> int:
	return next_headings[cid * 4 + (dir & 3)]


func get_edge_tangent(cid: int, dir: int) -> Vector3:
	return edge_tangents[cid * 4 + (dir & 3)]


static func turn_left(dir: int) -> int:
	return (dir + 3) & 3


static func turn_right(dir: int) -> int:
	return (dir + 1) & 3


static func opposite_dir(dir: int) -> int:
	return (dir + 2) & 3


func screen_tangent_to_dir(cid: int, current_dir: int, desired_world_dir: Vector3, allow_reverse: bool = false) -> int:
	var norm := cell_normals[cid]
	var proj := desired_world_dir - norm * desired_world_dir.dot(norm)
	if proj.length_squared() < 1e-6:
		return -1
	proj = proj.normalized()

	var rev := opposite_dir(current_dir)
	# Reject inputs aimed backward toward the snake's neck (within ~45 deg cone)
	if not allow_reverse and edge_tangents[cid * 4 + rev].dot(proj) > 0.70:
		return -1

	var best_dir := -1
	var best_dot := -2.0
	for d in range(4):
		if not allow_reverse and d == rev:
			continue
		var dot_val := edge_tangents[cid * 4 + d].dot(proj)
		if dot_val > best_dot:
			best_dot = dot_val
			best_dir = d

	return best_dir


func slerp_surface(a: Vector3, b: Vector3, t: float) -> Vector3:
	var na := a.normalized()
	var nb := b.normalized()
	var dot_ab := clampf(na.dot(nb), -1.0, 1.0)
	if dot_ab > 0.99995:
		return na.lerp(nb, t).normalized()
	var omega := acos(dot_ab)
	var sin_omega := sin(omega)
	var w0 := sin((1.0 - t) * omega) / sin_omega
	var w1 := sin(t * omega) / sin_omega
	return (na * w0 + nb * w1).normalized()


static func equiangular_to_sphere(face: int, cu: float, cv: float) -> Vector3:
	var tx := tan(cu * (PI * 0.25))
	var ty := tan(cv * (PI * 0.25))
	return (FACE_NORMALS[face] + FACE_RIGHTS[face] * tx + FACE_UPS[face] * ty).normalized()


static func surface_bump(dir: Vector3) -> float:
	## Smooth continuous rolling terrain elevation bumps across the entire 3D sphere.
	var n := dir.normalized()
	var h := sin(n.x * 6.5 + n.z * 4.2) * cos(n.y * 5.8 - n.x * 3.1)
	h += 0.45 * sin(n.z * 11.0 - n.y * 7.5 + n.x * 2.4)
	return h * 0.055


static func bumped_normal(dir: Vector3, radius: float) -> Vector3:
	var n := dir.normalized()
	var up_ref := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var t1 := up_ref.cross(n).normalized()
	var t2 := n.cross(t1).normalized()
	var eps := 0.015
	var p0 := n * (radius + surface_bump(n))
	var p1 := (n + t1 * eps).normalized()
	p1 *= (radius + surface_bump(p1))
	var p2 := (n + t2 * eps).normalized()
	p2 *= (radius + surface_bump(p2))
	return (p1 - p0).cross(p2 - p0).normalized()


func _cell_cube_to_sphere(face: int, u: int, v: int) -> Vector3:
	var step_size := 2.0 / float(grid_n)
	var cu := -1.0 + (float(u) + 0.5) * step_size
	var cv := -1.0 + (float(v) + 0.5) * step_size
	return equiangular_to_sphere(face, cu, cv)


func _compute_neighbor(face: int, u: int, v: int, dir: int) -> Dictionary:
	var du: int = DIR_DU[dir]
	var dv: int = DIR_DV[dir]
	var nu := u + du
	var nv := v + dv
	if nu >= 0 and nu < grid_n and nv >= 0 and nv < grid_n:
		return {"cell": cell_id(face, nu, nv), "dir": dir}

	# Fold across the cube edge onto the adjacent face
	var step_size := 2.0 / float(grid_n)
	var cu := -1.0 + (float(u) + 0.5) * step_size
	var cv := -1.0 + (float(v) + 0.5) * step_size

	var f_norm := FACE_NORMALS[face]
	var f_right := FACE_RIGHTS[face]
	var f_up := FACE_UPS[face]

	var step_3d := f_right * float(du) + f_up * float(dv)
	var new_face := _find_face_by_normal(step_3d)

	var unchanged := f_up * cv if du != 0 else f_right * cu
	var cube_pt := step_3d + f_norm * (1.0 - 1.0 / float(grid_n)) + unchanged

	var cu2 := cube_pt.dot(FACE_RIGHTS[new_face])
	var cv2 := cube_pt.dot(FACE_UPS[new_face])
	var u2 := clampi(int(floor((cu2 + 1.0) * 0.5 * float(grid_n))), 0, grid_n - 1)
	var v2 := clampi(int(floor((cv2 + 1.0) * 0.5 * float(grid_n))), 0, grid_n - 1)

	# Forward vector folds 90 degrees onto -f_norm on the new face
	var fwd2_3d := -f_norm
	var new_dir := _match_face_dir(new_face, fwd2_3d)
	return {"cell": cell_id(new_face, u2, v2), "dir": new_dir}


func _find_face_by_normal(n: Vector3) -> int:
	for f in range(FACE_COUNT):
		if FACE_NORMALS[f].dot(n) > 0.9:
			return f
	return 0


func _match_face_dir(face: int, vec: Vector3) -> int:
	var best := 0
	var best_dot := -2.0
	var dirs := [FACE_UPS[face], FACE_RIGHTS[face], -FACE_UPS[face], -FACE_RIGHTS[face]]
	for d in range(4):
		var dt: float = dirs[d].dot(vec)
		if dt > best_dot:
			best_dot = dt
			best = d
	return best


func build_planet_mesh(radius: float, sub_per_cell: int = 4) -> ArrayMesh:
	## Builds a smooth high-resolution subdivided equiangular cube-sphere mesh
	## where each grid cell spans [i, i+1] x [j, j+1] in UV space.
	var subdivs := grid_n * sub_per_cell
	var verts_per_face := (subdivs + 1) * (subdivs + 1)
	var total_verts := FACE_COUNT * verts_per_face
	var tris_per_face := subdivs * subdivs * 2
	var total_indices := FACE_COUNT * tris_per_face * 3

	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var tangents := PackedFloat32Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	positions.resize(total_verts)
	normals.resize(total_verts)
	tangents.resize(total_verts * 4)
	uvs.resize(total_verts)
	indices.resize(total_indices)

	var v_cursor := 0
	var i_cursor := 0
	for face in range(FACE_COUNT):
		var face_base := v_cursor
		for j in range(subdivs + 1):
			var fy := float(j) / float(subdivs)
			var cv := -1.0 + fy * 2.0
			for i in range(subdivs + 1):
				var fx := float(i) / float(subdivs)
				var cu := -1.0 + fx * 2.0
				var dir := equiangular_to_sphere(face, cu, cv)
				positions[v_cursor] = dir * (radius + surface_bump(dir))
				normals[v_cursor] = bumped_normal(dir, radius)
				uvs[v_cursor] = Vector2(fx * float(grid_n), fy * float(grid_n))

				# Exact tangent pointing along +cu (UV.x) projected onto tangent plane
				var raw_t := FACE_RIGHTS[face]
				var tan_vec := (raw_t - dir * raw_t.dot(dir)).normalized()
				# Ensure binormal sign matches +cv (UV.y)
				var raw_b := FACE_UPS[face]
				var sign_b := 1.0 if dir.cross(tan_vec).dot(raw_b) >= 0.0 else -1.0
				var t_idx := v_cursor * 4
				tangents[t_idx] = tan_vec.x
				tangents[t_idx + 1] = tan_vec.y
				tangents[t_idx + 2] = tan_vec.z
				tangents[t_idx + 3] = sign_b
				v_cursor += 1

		var stride := subdivs + 1
		for j in range(subdivs):
			for i in range(subdivs):
				var p00 := face_base + j * stride + i
				var p10 := p00 + 1
				var p01 := p00 + stride
				var p11 := p01 + 1
				# Clockwise winding viewed from outside (+normal)
				indices[i_cursor] = p00
				indices[i_cursor + 1] = p01
				indices[i_cursor + 2] = p11
				indices[i_cursor + 3] = p00
				indices[i_cursor + 4] = p11
				indices[i_cursor + 5] = p10
				i_cursor += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
