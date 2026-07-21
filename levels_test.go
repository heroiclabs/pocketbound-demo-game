package main

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/heroiclabs/nakama-common/runtime"
)

type noopLogger struct{}

func (noopLogger) Debug(string, ...interface{})                 {}
func (noopLogger) Info(string, ...interface{})                  {}
func (noopLogger) Warn(string, ...interface{})                  {}
func (noopLogger) Error(string, ...interface{})                 {}
func (noopLogger) WithField(string, interface{}) runtime.Logger { return noopLogger{} }
func (noopLogger) WithFields(map[string]interface{}) runtime.Logger {
	return noopLogger{}
}
func (noopLogger) Fields() map[string]interface{} { return map[string]interface{}{} }

func TestExtractStoredLevelEntriesPreservesOrder(t *testing.T) {
	entries, err := extractStoredLevelEntriesWithVisibility(noopLogger{}, "ordered-user", orderedStorageJSON, false)
	if err != nil {
		t.Fatalf("extract entries failed: %v", err)
	}
	if got, want := len(entries), 2; got != want {
		t.Fatalf("unexpected entries length: got %d want %d", got, want)
	}
	if got, want := entries[0].Key, "Alpha"; got != want {
		t.Fatalf("unexpected first entry key: got %q want %q", got, want)
	}
	if got, want := entries[1].Key, "Beta"; got != want {
		t.Fatalf("unexpected second entry key: got %q want %q", got, want)
	}
}

func TestExtractStoredLevelEntriesPublishedFilter(t *testing.T) {
	entries, err := extractStoredLevelEntriesWithVisibility(noopLogger{}, "ordered-user", orderedStorageJSON, true)
	if err != nil {
		t.Fatalf("extract published entries failed: %v", err)
	}
	if got, want := len(entries), 1; got != want {
		t.Fatalf("unexpected published entries length: got %d want %d", got, want)
	}
	if got, want := entries[0].Key, "Beta"; got != want {
		t.Fatalf("unexpected published entry key: got %q want %q", got, want)
	}
}

func TestDefaultLevelsJSONHasExpectedOrderedKeys(t *testing.T) {
	entries, err := extractStoredLevelEntries(noopLogger{}, "defaults", defaultLevelsJSON)
	if err != nil {
		t.Fatalf("extract default levels failed: %v", err)
	}
	want := []string{"Single shift", "Short Bend", "Box Shuffle", "The blocked hallway", "The worm", "Split crown"}
	if got := len(entries); got != len(want) {
		t.Fatalf("unexpected default level count: got %d want %d", got, len(want))
	}
	for i, expectedKey := range want {
		if got := entries[i].Key; got != expectedKey {
			t.Fatalf("unexpected default level key at index %d: got %q want %q", i, got, expectedKey)
		}
	}
}

func TestValidateLevelDataRejectsProfaneLevelName(t *testing.T) {
	level := validLevelForValidation()
	profaneName := "fuck"
	level.Name = &profaneName

	err := validateLevelData(level, false)
	if err == nil {
		t.Fatalf("expected profane level name to be rejected")
	}
	if !strings.Contains(err.Error(), "name contains prohibited content") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestValidateLevelDataRejectsProfaneLevelDescription(t *testing.T) {
	level := validLevelForValidation()
	profaneDescription := "this level is shit"
	level.Description = &profaneDescription

	err := validateLevelData(level, false)
	if err == nil {
		t.Fatalf("expected profane level description to be rejected")
	}
	if !strings.Contains(err.Error(), "description contains prohibited content") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestLevelValueUnmarshalDefaultsLikesDislikesToZero(t *testing.T) {
	var level LevelValue
	if err := json.Unmarshal([]byte(`{
		"name": "L0",
		"grid_size": 2,
		"x": [0, 1],
		"y": [0, 1],
		"sprite": ["portal", "cat1"]
	}`), &level); err != nil {
		t.Fatalf("unmarshal failed: %v", err)
	}
	if got, want := level.Likes, 0; got != want {
		t.Fatalf("unexpected likes: got %d want %d", got, want)
	}
	if got, want := level.Dislikes, 0; got != want {
		t.Fatalf("unexpected dislikes: got %d want %d", got, want)
	}
}

func TestLevelValueUnmarshalLikesDislikes(t *testing.T) {
	var level LevelValue
	if err := json.Unmarshal([]byte(`{
		"name": "L1",
		"grid_size": 2,
		"likes": 7,
		"dislikes": 3,
		"x": [0, 1],
		"y": [0, 1],
		"sprite": ["portal", "cat1"]
	}`), &level); err != nil {
		t.Fatalf("unmarshal failed: %v", err)
	}
	if got, want := level.Likes, 7; got != want {
		t.Fatalf("unexpected likes: got %d want %d", got, want)
	}
	if got, want := level.Dislikes, 3; got != want {
		t.Fatalf("unexpected dislikes: got %d want %d", got, want)
	}
}

func TestValidateLevelDataRejectsNegativeLikesDislikes(t *testing.T) {
	negativeLikes := validLevelForValidation()
	negativeLikes.Likes = -1
	if err := validateLevelData(negativeLikes, false); err == nil || !strings.Contains(err.Error(), "likes must be non-negative") {
		t.Fatalf("expected negative likes validation failure, got: %v", err)
	}

	negativeDislikes := validLevelForValidation()
	negativeDislikes.Dislikes = -1
	if err := validateLevelData(negativeDislikes, false); err == nil || !strings.Contains(err.Error(), "dislikes must be non-negative") {
		t.Fatalf("expected negative dislikes validation failure, got: %v", err)
	}
}

func validLevelForValidation() LevelValue {
	name := "Clean Name"
	description := "Clean description"
	return LevelValue{
		GridSize:    2,
		Name:        &name,
		Description: &description,
		X:           []int{0, 1},
		Y:           []int{0, 1},
		Sprite:      []string{"portal", "cat1"},
	}
}

const orderedStorageJSON = `[
  {
    "name": "Alpha",
    "grid_size": 2,
    "x": [0, 1],
    "y": [0, 1],
    "sprite": ["portal", "cat1"]
  },
  {
    "name": "Beta",
    "grid_size": 2,
    "x": [0, 1],
    "y": [1, 0],
    "sprite": ["portal", "cat1"],
    "published_at": "2026-01-01T00:00:00Z"
  }
]`
