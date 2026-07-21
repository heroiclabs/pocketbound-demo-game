package main

import (
	_ "embed"
	"encoding/json"
	"strconv"
	"strings"
)

type (
	componentRegistry struct {
		Components []componentRegistryComponent `json:"components"`
	}

	componentRegistryComponent struct {
		ID   string `json:"id"`
		Name string `json:"name"`
		Kind string `json:"kind"`
		Bit  string `json:"bit"`
	}
)

const (
	defaultWalkable = "walkable"
	defaultBlocked  = "blocked"
	defaultStart    = "start"
	defaultEnd      = "end"
	defaultNorth    = "north"
	defaultEast     = "east"
	defaultSouth    = "south"
	defaultWest     = "west"
)

//go:embed shared/component_registry.json
var componentRegistryJSON string

var (
	componentAllowed   = map[string]struct{}{}
	componentIDByName  = map[string]int{}
	directionBitByName = map[string]int{}

	compWalkable = defaultWalkable
	compBlocked  = defaultBlocked
	compStart    = defaultStart
	compEnd      = defaultEnd
	compNorth    = defaultNorth
	compEast     = defaultEast
	compSouth    = defaultSouth
	compWest     = defaultWest
)

func registryNumberAsInt(value string) (int, bool) {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return 0, false
	}
	i, err := strconv.Atoi(trimmed)
	if err != nil {
		return 0, false
	}
	return i, true
}

func loadComponentRegistry() {
	seedDefaultComponents()
	if strings.TrimSpace(componentRegistryJSON) == "" {
		return
	}

	var registry componentRegistry
	if err := json.Unmarshal([]byte(componentRegistryJSON), &registry); err != nil {
		return
	}
	if len(registry.Components) == 0 {
		return
	}

	componentAllowed = map[string]struct{}{}
	componentIDByName = map[string]int{}
	directionBitByName = map[string]int{}

	for _, row := range registry.Components {
		name := strings.TrimSpace(row.Name)
		if name == "" {
			continue
		}
		id, ok := registryNumberAsInt(row.ID)
		if !ok {
			continue
		}
		kind := strings.TrimSpace(row.Kind)
		bit, _ := registryNumberAsInt(row.Bit)

		componentAllowed[name] = struct{}{}
		componentIDByName[name] = id
		if kind == "direction" && bit > 0 {
			directionBitByName[name] = bit
		}
	}

	// Keep canonical aliases stable; schema still drives allowed/IDs.
	compWalkable = defaultWalkable
	compBlocked = defaultBlocked
	compStart = defaultStart
	compEnd = defaultEnd
	compNorth = defaultNorth
	compEast = defaultEast
	compSouth = defaultSouth
	compWest = defaultWest
}

func seedDefaultComponents() {
	componentAllowed = map[string]struct{}{
		defaultWalkable: {},
		defaultBlocked:  {},
		defaultStart:    {},
		defaultEnd:      {},
		defaultNorth:    {},
		defaultEast:     {},
		defaultSouth:    {},
		defaultWest:     {},
	}
	componentIDByName = map[string]int{
		defaultWalkable: 1,
		defaultBlocked:  2,
		defaultStart:    3,
		defaultEnd:      4,
		defaultNorth:    5,
		defaultEast:     6,
		defaultSouth:    7,
		defaultWest:     8,
	}
	directionBitByName = map[string]int{
		defaultNorth: 1,
		defaultEast:  2,
		defaultSouth: 4,
		defaultWest:  8,
	}
}
