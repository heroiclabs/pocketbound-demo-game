package main

import (
	"fmt"
	"strings"

	goaway "github.com/Remesh/go-away"
)

func getComponentSet(level LevelValue, component string) map[int]struct{} {
	set := make(map[int]struct{})
	for _, id := range level.Components[component] {
		set[id] = struct{}{}
	}
	return set
}

func validateLevelData(level LevelValue, requireMetadata bool) error {
	if level.GridSize < 2 || level.GridSize > 4 {
		return fmt.Errorf("grid_size must be 2-4")
	}
	if level.Likes < 0 {
		return fmt.Errorf("likes must be non-negative")
	}
	if level.Dislikes < 0 {
		return fmt.Errorf("dislikes must be non-negative")
	}
	if level.X == nil {
		return fmt.Errorf("x must be an array")
	}
	if level.Y == nil {
		return fmt.Errorf("y must be an array")
	}
	if len(level.X) != len(level.Y) {
		return fmt.Errorf("x and y must have equal length")
	}
	entityCount := len(level.X)

	if len(level.Sprite) > entityCount {
		return fmt.Errorf("sprite length cannot exceed entity count")
	}
	if level.Name != nil {
		if len(strings.TrimSpace(*level.Name)) > 80 {
			return fmt.Errorf("name must be 80 characters or fewer")
		}
		if goaway.IsProfane(*level.Name) {
			return fmt.Errorf("name contains prohibited content")
		}
	}
	if level.Description != nil {
		if len(strings.TrimSpace(*level.Description)) > 500 {
			return fmt.Errorf("description must be 500 characters or fewer")
		}
		if goaway.IsProfane(*level.Description) {
			return fmt.Errorf("description contains prohibited content")
		}
	}
	if requireMetadata && level.CreatedAt == nil {
		return fmt.Errorf("created_at is required")
	}
	if requireMetadata && level.UpdatedAt == nil {
		return fmt.Errorf("updated_at is required")
	}

	for key, ids := range level.Components {
		if _, allowed := componentAllowed[key]; !allowed {
			return fmt.Errorf("unknown component %s", key)
		}
		seen := make(map[int]struct{}, len(ids))
		for _, id := range ids {
			if id < 0 || id >= entityCount {
				return fmt.Errorf("%s contains out-of-range entity ID %d", key, id)
			}
			if _, dup := seen[id]; dup {
				return fmt.Errorf("%s contains duplicate entity ID %d", key, id)
			}
			seen[id] = struct{}{}
		}
	}

	if startIDs, exists := level.Components[compStart]; exists && len(startIDs) > 1 {
		return fmt.Errorf("%s can only contain one entity ID", compStart)
	}
	if endIDs, exists := level.Components[compEnd]; exists && len(endIDs) > 1 {
		return fmt.Errorf("%s can only contain one entity ID", compEnd)
	}

	return nil
}

func validatePlayableLevel(level LevelValue) error {
	if level.GridSize < 2 || level.GridSize > 4 {
		return fmt.Errorf("grid_size must be 2-4")
	}
	if level.X == nil {
		return fmt.Errorf("x must be an array")
	}
	if level.Y == nil {
		return fmt.Errorf("y must be an array")
	}
	if len(level.X) != len(level.Y) {
		return fmt.Errorf("x and y must have equal length")
	}
	entityCount := len(level.X)

	startIDs := level.Components[compStart]
	if len(startIDs) != 1 {
		return fmt.Errorf("level requires exactly one %s tile", compStart)
	}
	startID := startIDs[0]
	if startID < 0 || startID >= entityCount {
		return fmt.Errorf("%s contains invalid entity ID", compStart)
	}

	endIDs := level.Components[compEnd]
	if len(endIDs) != 1 {
		return fmt.Errorf("level requires exactly one %s tile", compEnd)
	}
	endID := endIDs[0]
	if endID < 0 || endID >= entityCount {
		return fmt.Errorf("%s contains invalid entity ID", compEnd)
	}

	walkableSet := getComponentSet(level, compWalkable)
	blockedSet := getComponentSet(level, compBlocked)

	if _, ok := walkableSet[startID]; !ok {
		return fmt.Errorf("%s tile must also have %s component", compStart, compWalkable)
	}
	if _, ok := walkableSet[endID]; !ok {
		return fmt.Errorf("%s tile must also have %s component", compEnd, compWalkable)
	}

	walkableCount := 0
	for id := range walkableSet {
		if id < 0 || id >= entityCount {
			continue
		}
		if id == startID || id == endID {
			continue
		}

		x := level.X[id]
		y := level.Y[id]
		if x < 0 || x >= level.GridSize || y < 0 || y >= level.GridSize {
			continue
		}
		if _, blocked := blockedSet[id]; blocked {
			continue
		}
		walkableCount++
	}

	if walkableCount < 2 {
		return fmt.Errorf("level requires at least 2 walkable room tiles")
	}

	return nil
}
