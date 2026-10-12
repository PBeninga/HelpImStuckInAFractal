extends SceneTree
## Headless CPU proxy, NOT GPU timings. Same point grid, ray fan, budgets,
## camera and horizon for each shape. Run: godot4 --headless --path . -s tools/benchmark_shape_cost.gd
## The CPU scalar implementations and single-phase march differ from the GPU.

func _initialize() -> void:
	var points: Array[Vector3] = []
	for x in 12:
		for y in 12:
			for z in 12:
				points.append(Vector3((x + 0.37) / 3.0 - 2.0, (y + 0.19) / 3.0 - 2.0, (z + 0.73) / 3.0 - 2.0))
	var rays: Array[Vector3] = []
	for y in 12:
		for x in 20:
			rays.append(Vector3((x + 0.5 - 10.0) / 12.0, (y + 0.5 - 6.0) / 12.0, -1.0).normalized())
	for cap in [8, 16]:
		for kind in 4:
			var params := FractalParams.new()
			params.fractal_iterations = cap
			params.shape().shape = kind
			params.shape().precision = 0.000025
			params.shape().kleinian_view_distance = 10.0
			var samples: Array[float] = []
			var marches: Array[float] = []
			var hits := 0
			for rep in 4:
				var start := Time.get_ticks_usec()
				for p in points:
					DistanceEstimator.estimate_at(p.x, p.y, p.z, params.shape(), cap)
				var sample_us := float(Time.get_ticks_usec() - start) / points.size()
				start = Time.get_ticks_usec()
				hits = 0
				for ray in rays:
					if DistanceEstimator.march(0.0, 0.0, 4.0, ray, params, 96) != null:
						hits += 1
				if rep > 0:
					samples.append(sample_us)
					marches.append(float(Time.get_ticks_usec() - start) / rays.size())
			samples.sort()
			marches.sort()
			print(["Mandelbox", "KIFS", "Kleinian", "Mandelbulb"][kind],
				" cap=", cap, " CPU us/sample=", snappedf(samples[1], 0.01),
				" CPU us/ray=", snappedf(marches[1], 0.01), " hits=", hits, "/", rays.size())
	quit()
