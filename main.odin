package quadtree

import sa "core:container/small_array"
import "core:fmt"
import "core:math/rand"
import "core:mem"
import rl "vendor:raylib"

Vec2f :: [2]f32

QUAD_TREE_NODE_CAPACITY :: 4

Quad_Tree :: struct {
    boundary:   rl.Rectangle,
    points:     sa.Small_Array(QUAD_TREE_NODE_CAPACITY, Vec2f),
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

    if sa.len(qt.points) < QUAD_TREE_NODE_CAPACITY && qt.north_west == nil {
        sa.append(&qt.points, pos)
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

    return false
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

quad_tree_query :: proc(range: rl.Rectangle) {
}

main :: proc() {
    qt := quad_tree_make(rl.Rectangle{x = 0, y = 0, width = 100, height = 100})

    arena_buffer: [25 * mem.Kilobyte]byte
    arena: mem.Arena
    mem.arena_init(&arena, arena_buffer[:])

    arena_allocator := mem.arena_allocator(&arena)

    cached := context.allocator
    context.allocator = arena_allocator
    for i in 0 ..< 500 {
        quad_tree_insert({rand.float32_uniform(0, 100), rand.float32_uniform(0, 100)}, &qt)
        fmt.printfln("Insert complete %v", i)
    }
    context.allocator = cached
    fmt.printfln("Allocator %v", arena)

    mem.arena_free_all(&arena)
}

