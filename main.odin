package quadtree

import sa "core:container/small_array"
import "core:fmt"
import "core:math/rand"
import "core:mem"
import "core:slice"
import rl "vendor:raylib"

Vec2f :: [2]f32

QUAD_TREE_NODE_CAPACITY :: 250

Quad_Tree :: struct {
    boundary:   rl.Rectangle,
    points:     [dynamic]Vec2f,
    north_west: ^Quad_Tree,
    north_east: ^Quad_Tree,
    south_west: ^Quad_Tree,
    south_east: ^Quad_Tree,
    allocator:  mem.Allocator,
}

quad_tree_make :: proc(aabb: rl.Rectangle) -> Quad_Tree {
    return Quad_Tree{boundary = aabb, points = {}, north_west = nil, north_east = nil, south_west = nil, south_east = nil}
}

quad_tree_destroy :: proc(qt: ^Quad_Tree) {
    if qt.north_west == nil || qt.north_east == nil || qt.south_west == nil || qt.south_east == nil {
        return
    }

    quad_tree_destroy(qt.north_west)
    free(qt.north_west)

    quad_tree_destroy(qt.north_east)
    free(qt.north_east)

    quad_tree_destroy(qt.south_west)
    free(qt.south_west)

    quad_tree_destroy(qt.south_east)
    free(qt.south_east)
}

quad_tree_insert :: proc(pos: Vec2f, qt: ^Quad_Tree) -> bool {
    if !rl.CheckCollisionPointRec(pos, qt.boundary) {
        return false
    }

    if len(qt.points) < QUAD_TREE_NODE_CAPACITY && qt.north_west == nil {
        if qt.points == nil {
            qt.points = make([dynamic]Vec2f)
        }
        append(&qt.points, pos)
        fmt.printfln("Appending point")
        return true
    }

    if qt.north_west == nil {
        fmt.printfln("Subdividing")
        quad_tree_subdivide(qt)
    }

    if quad_tree_insert(pos, qt.north_west) do return true
    if quad_tree_insert(pos, qt.north_east) do return true
    if quad_tree_insert(pos, qt.south_west) do return true
    if quad_tree_insert(pos, qt.south_east) do return true

    panic("Unable to subdivide any further, and unable to insert point into quad tree. Consider adjusting qtree parameters")
}

quad_tree_subdivide :: proc(qt: ^Quad_Tree) {
    half_bounds := Vec2f{qt.boundary.width / 2., qt.boundary.height / 2.}

    err: mem.Allocator_Error
    qt.north_west, err = mem.new_clone(
        quad_tree_make({x = qt.boundary.x, y = qt.boundary.x, width = half_bounds.x, height = half_bounds.y}),
    )

    if err != .None {
        panic("Quad tree allocator error")
    }

    qt.north_east, err = mem.new_clone(
        quad_tree_make({x = qt.boundary.x + half_bounds.x, y = qt.boundary.y, width = half_bounds.x, height = half_bounds.y}),
    )

    if err != .None {
        panic("Quad tree allocator error")
    }

    qt.south_west, err = mem.new_clone(
        quad_tree_make({x = qt.boundary.x, y = qt.boundary.y + half_bounds.y, width = half_bounds.x, height = half_bounds.y}),
    )

    if err != .None {
        panic("Quad tree allocator error")
    }

    qt.south_east, err = mem.new_clone(
        quad_tree_make(
            {x = qt.boundary.x + half_bounds.x, y = qt.boundary.y + half_bounds.y, width = half_bounds.x, height = half_bounds.y},
        ),
    )

    if err != .None {
        panic("Quad tree allocator error")
    }
}

quad_tree_query :: proc(range: rl.Rectangle, qt: ^Quad_Tree) -> [dynamic]Vec2f {
    results := make([dynamic]Vec2f)

    if !rl.CheckCollisionRecs(qt.boundary, range) {
        return results
    }

    for p in qt.points {
        if rl.CheckCollisionPointRec(p, range) {
            append(&results, p)
        }
    }

    if qt.north_west == nil {
        return results
    }

    if child_results := quad_tree_query(range, qt.north_west); len(child_results) > 0 {
        defer delete(child_results)
        reserve(&results, len(results) + len(child_results))
        for p in child_results {
            append(&results, p)
        }
    }

    if child_results := quad_tree_query(range, qt.north_east); len(child_results) > 0 {
        defer delete(child_results)
        reserve(&results, len(results) + len(child_results))
        for p in child_results {
            append(&results, p)
        }
    }

    if child_results := quad_tree_query(range, qt.south_west); len(child_results) > 0 {
        defer delete(child_results)
        reserve(&results, len(results) + len(child_results))
        for p in child_results {
            append(&results, p)
        }
    }

    if child_results := quad_tree_query(range, qt.south_east); len(child_results) > 0 {
        defer delete(child_results)
        reserve(&results, len(results) + len(child_results))
        for p in child_results {
            append(&results, p)
        }
    }

    return results
}

main :: proc() {
    when ODIN_DEBUG {
        track: mem.Tracking_Allocator
        mem.tracking_allocator_init(&track, context.allocator)
        context.allocator = mem.tracking_allocator(&track)

        defer {
            if len(track.allocation_map) > 0 {
                fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
                for _, entry in track.allocation_map {
                    fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
                }
            }
            if len(track.bad_free_array) > 0 {
                fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
                for entry in track.bad_free_array {
                    fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
                }
            }
            mem.tracking_allocator_destroy(&track)
        }
    }

    WIDTH :: 640
    HEIGHT :: 480

    RECT_SIZE :: Vec2f{10, 10}

    rl.InitWindow(WIDTH, HEIGHT, "Quadtree Test")
    rl.SetTargetFPS(60)

    qt := quad_tree_make(rl.Rectangle{x = 0, y = 0, width = WIDTH, height = HEIGHT})

    arena_buffer: [25 * mem.Kilobyte]byte
    arena: mem.Arena
    mem.arena_init(&arena, arena_buffer[:])

    arena_allocator := mem.arena_allocator(&arena)

    cached := context.allocator
    context.allocator = arena_allocator

    rect_positions: [100]Vec2f

    for i in 0 ..< len(rect_positions) {
        rect_positions[i].x = rand.float32_uniform(0, WIDTH)
        rect_positions[i].y = rand.float32_uniform(0, HEIGHT)
        quad_tree_insert(rect_positions[i], &qt)
        fmt.printfln("Insert complete %v", i)
    }

    context.allocator = cached

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground(rl.BLACK)

        mouse_pos := rl.GetMousePosition()
        rl.DrawRectangleV(mouse_pos, RECT_SIZE * 2, rl.RED)

        query_results := quad_tree_query(rl.Rectangle{x = mouse_pos.x, y = mouse_pos.y, width = RECT_SIZE.x, height = RECT_SIZE.y}, &qt)

        defer {
            delete(query_results)
        }

        for p in rect_positions {
            _, result := slice.linear_search(query_results[:], p)
            if !result {
                rl.DrawRectangleV(p, RECT_SIZE, rl.WHITE)
            } else {
                rl.DrawRectangleV(p, RECT_SIZE, rl.GREEN)
            }
        }
        rl.EndDrawing()
    }

    // fmt.printfln("Allocator %v", arena)

    // results := quad_tree_query({0, 0, 100, 100}, &qt)
    // defer delete(results)

    // fmt.printfln("Results from query of {{10,10,10,10}} is \n %v with len %v", results, len(results))

    mem.arena_free_all(&arena)
}

