package main

import (
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"math"
	"strings"
	"time"

	"github.com/heroiclabs/nakama-common/runtime"
)

const (
	LevelCollection = "levels"
	LevelStorageKey = "levels"

	LevelVoteCollection       = "level_votes"
	levelVoteKeyPrefix        = "vote"
	levelVoteLike             = "like"
	levelVoteDislike          = "dislike"
	maxLevelVoteWriteAttempts = 6
	maxLevelsPerUser          = 50
)

type (
	UTCDateTime struct {
		time.Time
	}

	LevelValue struct {
		GridSize    int              `json:"-"`
		Name        *string          `json:"-"`
		Description *string          `json:"-"`
		Likes       int              `json:"-"`
		Dislikes    int              `json:"-"`
		X           []int            `json:"-"`
		Y           []int            `json:"-"`
		Sprite      []string         `json:"-"`
		CreatedAt   *UTCDateTime     `json:"-"`
		UpdatedAt   *UTCDateTime     `json:"-"`
		PublishedAt *UTCDateTime     `json:"-"`
		Components  map[string][]int `json:"-"`
	}

	LevelEntry struct {
		Key      string     `json:"key"`
		UserID   string     `json:"user_id"`
		Username string     `json:"username,omitempty"`
		Value    LevelValue `json:"value"`
	}

	SubmitLevelRequest struct {
		Key string `json:"key"`
	}

	GetLevelRequest struct {
		UserID string `json:"user_id"`
		Key    string `json:"key"`
	}

	GetLevelResponse struct {
		Key      string     `json:"key"`
		UserID   string     `json:"user_id"`
		Username string     `json:"username,omitempty"`
		Value    LevelValue `json:"value"`
		Version  string     `json:"version"`
	}

	ListAllLevelsRequest struct {
		Limit  int    `json:"limit"`
		Cursor string `json:"cursor"`
	}

	ListFriendLevelsRequest struct {
		Limit  int    `json:"limit"`
		Cursor string `json:"cursor"`
	}

	ListLevelsResponse struct {
		Levels     []LevelEntry `json:"levels"`
		NextCursor string       `json:"next_cursor,omitempty"`
	}

	DeleteLevelRequest struct {
		Key string `json:"key"`
	}

	PublishLevelRequest struct {
		Key string `json:"key"`
	}

	GetLeaderboardRequest struct {
		LevelOwnerID string `json:"level_owner_id"`
		LevelKey     string `json:"level_key"`
		Filter       string `json:"filter"` // "all_time" | "this_week" | "friends"
	}

	LeaderboardEntry struct {
		Rank       int64  `json:"rank"`
		Username   string `json:"username"`
		TimeMs     int64  `json:"time_ms"`
		SlideCount int64  `json:"slide_count"`
	}

	GetLeaderboardResponse struct {
		Entries        []LeaderboardEntry `json:"entries"`
		PlayerRank     int64              `json:"player_rank"`
		BestTimeMs     int64              `json:"best_time_ms"`
		BestSlideCount int64              `json:"best_slide_count"`
		PlayCount      int64              `json:"play_count"`
	}

	SubmitScoreRequest struct {
		LevelOwnerID string `json:"level_owner_id"`
		LevelKey     string `json:"level_key"`
		TimeMs       int64  `json:"time_ms"`
		SlideCount   int64  `json:"slide_count"`
	}

	SubmitLevelVoteRequest struct {
		LevelOwnerID string `json:"level_owner_id"`
		LevelKey     string `json:"level_key"`
		Vote         string `json:"vote"` // "like" | "dislike"
	}

	SubmitLevelVoteResponse struct {
		Likes    int    `json:"likes"`
		Dislikes int    `json:"dislikes"`
		Vote     string `json:"vote"`
	}
)

//go:embed shared/default_levels.json
var defaultLevelsJSON string

func parseStoredLevels(storedValue string) ([]LevelValue, error) {
	raw := strings.TrimSpace(storedValue)
	if raw == "" {
		return []LevelValue{}, nil
	}

	// Nakama storage values must be JSON objects, so persisted data is wrapped
	// in {"levels":[...]} while default data can still be a raw array.
	if strings.HasPrefix(raw, "{") {
		var payload map[string]json.RawMessage
		if err := json.Unmarshal([]byte(raw), &payload); err != nil {
			return nil, err
		}
		rawLevels, ok := payload["levels"]
		if !ok {
			return nil, fmt.Errorf("levels field is required")
		}

		var levelValues []LevelValue
		if err := json.Unmarshal(rawLevels, &levelValues); err != nil {
			return nil, fmt.Errorf("levels must be an array: %w", err)
		}
		return levelValues, nil
	}

	var levelValues []LevelValue
	if err := json.Unmarshal([]byte(raw), &levelValues); err != nil {
		return nil, err
	}
	return levelValues, nil
}

func marshalStoredLevels(levels []LevelValue) (string, error) {
	value, err := json.Marshal(map[string]interface{}{
		"levels": levels,
	})
	if err != nil {
		return "", err
	}
	return string(value), nil
}

func levelKey(level LevelValue) string {
	if level.Name == nil {
		return ""
	}
	return strings.TrimSpace(*level.Name)
}

func sanitizeStoredLevels(logger runtime.Logger, ownerID string, levels []LevelValue) ([]LevelValue, bool) {
	cleaned := make([]LevelValue, 0, len(levels))
	changed := false
	seen := map[string]struct{}{}

	for _, level := range levels {
		key := levelKey(level)
		if key == "" {
			logger.Error("invalid level entry for user %s: missing name", ownerID)
			changed = true
			continue
		}
		if _, exists := seen[key]; exists {
			logger.Error("invalid level %s/%s payload: duplicate name", ownerID, key)
			changed = true
			continue
		}
		if err := validateLevelData(level, false); err != nil {
			logger.Error("invalid level %s/%s payload: %v", ownerID, key, err)
			changed = true
			continue
		}
		if level.Name == nil || strings.TrimSpace(*level.Name) != key {
			keyCopy := key
			level.Name = &keyCopy
			changed = true
		}
		cleaned = append(cleaned, level)
		seen[key] = struct{}{}
	}

	return cleaned, changed
}

func decodeAndSanitizeStoredLevels(logger runtime.Logger, ownerID string, storedValue string) ([]LevelValue, bool, error) {
	if strings.TrimSpace(storedValue) == "" {
		return []LevelValue{}, false, nil
	}

	levels, err := parseStoredLevels(storedValue)
	if err != nil {
		logger.Error("invalid levels document for user %s: %v", ownerID, err)
		// Hard-clean invalid documents by treating them as empty.
		return []LevelValue{}, true, nil
	}

	cleaned, changed := sanitizeStoredLevels(logger, ownerID, levels)
	return cleaned, changed, nil
}

func buildLevelEntries(ownerID string, levels []LevelValue, publishedOnly bool) []LevelEntry {
	entries := make([]LevelEntry, 0, len(levels))
	for _, level := range levels {
		key := levelKey(level)
		if key == "" {
			continue
		}
		if publishedOnly && !isPublishedLevel(level) {
			continue
		}
		entries = append(entries, LevelEntry{
			Key:    key,
			UserID: ownerID,
			Value:  level,
		})
	}
	return entries
}

func resolveUsernames(ctx context.Context, nk runtime.NakamaModule, userIDs []string) map[string]string {
	result := make(map[string]string, len(userIDs))
	if len(userIDs) == 0 {
		return result
	}
	unique := make([]string, 0, len(userIDs))
	seen := make(map[string]struct{}, len(userIDs))
	for _, id := range userIDs {
		if _, exists := seen[id]; exists {
			continue
		}
		seen[id] = struct{}{}
		unique = append(unique, id)
	}
	users, err := nk.UsersGetId(ctx, unique, nil)
	if err != nil {
		return result
	}
	for _, user := range users {
		if user == nil {
			continue
		}
		result[user.Id] = user.Username
	}
	return result
}

func writeStoredLevels(ctx context.Context, nk runtime.NakamaModule, userID string, levels []LevelValue) (string, error) {
	value, err := marshalStoredLevels(levels)
	if err != nil {
		return "", err
	}

	acks, err := nk.StorageWrite(ctx, []*runtime.StorageWrite{
		{
			Collection:      LevelCollection,
			Key:             LevelStorageKey,
			UserID:          userID,
			Value:           value,
			PermissionRead:  2, // public read
			PermissionWrite: 1, // owner write
		},
	})
	if err != nil {
		return "", err
	}
	if len(acks) == 0 {
		return "", nil
	}
	return acks[0].Version, nil
}

func loadDefaultLevels(logger runtime.Logger) []LevelValue {
	sourceEntries, err := extractStoredLevelEntries(logger, "defaults", defaultLevelsJSON)
	if err != nil {
		logger.Error("failed to parse default levels json: %v", err)
		return []LevelValue{}
	}
	levels := make([]LevelValue, 0, len(sourceEntries))
	for _, entry := range sourceEntries {
		levels = append(levels, entry.Value)
	}
	levels, _ = sanitizeStoredLevels(logger, "defaults", levels)
	return levels
}

// ── Level Serialization ─────────────────────────────────────────────────────

func (t UTCDateTime) MarshalJSON() ([]byte, error) {
	return json.Marshal(t.Time.UTC().Format(time.RFC3339Nano))
}

func (t *UTCDateTime) UnmarshalJSON(data []byte) error {
	var raw string
	if err := json.Unmarshal(data, &raw); err != nil {
		return fmt.Errorf("must be an RFC3339 UTC timestamp")
	}
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return fmt.Errorf("must be an RFC3339 UTC timestamp")
	}
	parsed, err := time.Parse(time.RFC3339Nano, raw)
	if err != nil {
		return fmt.Errorf("must be an RFC3339 UTC timestamp")
	}
	_, offset := parsed.Zone()
	if offset != 0 {
		return fmt.Errorf("must be an RFC3339 UTC timestamp")
	}
	t.Time = parsed.UTC()
	return nil
}

func (v LevelValue) MarshalJSON() ([]byte, error) {
	payload := map[string]interface{}{
		"grid_size": v.GridSize,
		"likes":     v.Likes,
		"dislikes":  v.Dislikes,
		"x":         v.X,
		"y":         v.Y,
	}

	if v.Name != nil {
		payload["name"] = *v.Name
	}
	if v.Description != nil {
		payload["description"] = *v.Description
	}
	if v.Sprite != nil {
		payload["sprite"] = v.Sprite
	}
	if v.CreatedAt != nil {
		payload["created_at"] = v.CreatedAt.Time.UTC().Format(time.RFC3339Nano)
	}
	if v.UpdatedAt != nil {
		payload["updated_at"] = v.UpdatedAt.Time.UTC().Format(time.RFC3339Nano)
	}
	if v.PublishedAt != nil {
		payload["published_at"] = v.PublishedAt.Time.UTC().Format(time.RFC3339Nano)
	}
	for component, ids := range v.Components {
		payload[component] = ids
	}

	return json.Marshal(payload)
}

func parseJSONInteger(raw json.RawMessage, fieldName string) (int, error) {
	var numeric float64
	if err := json.Unmarshal(raw, &numeric); err != nil {
		return 0, fmt.Errorf("%s must be an integer", fieldName)
	}
	if math.IsNaN(numeric) || math.IsInf(numeric, 0) {
		return 0, fmt.Errorf("%s must be an integer", fieldName)
	}
	if math.Trunc(numeric) != numeric {
		return 0, fmt.Errorf("%s must be an integer", fieldName)
	}

	maxInt := int64(^uint(0) >> 1)
	minInt := -maxInt - 1
	if numeric < float64(minInt) || numeric > float64(maxInt) {
		return 0, fmt.Errorf("%s is out of range", fieldName)
	}

	return int(numeric), nil
}

func parseJSONIntegerArray(raw json.RawMessage, fieldName string) ([]int, error) {
	var rawValues []json.RawMessage
	if err := json.Unmarshal(raw, &rawValues); err != nil {
		return nil, fmt.Errorf("%s must be an array of entity IDs", fieldName)
	}

	values := make([]int, 0, len(rawValues))
	for _, rawValue := range rawValues {
		value, err := parseJSONInteger(rawValue, fieldName)
		if err != nil {
			return nil, fmt.Errorf("%s must be an array of entity IDs", fieldName)
		}
		values = append(values, value)
	}
	return values, nil
}

func (v *LevelValue) UnmarshalJSON(data []byte) error {
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		return err
	}

	type knownFields struct {
		Name        *string      `json:"name"`
		Description *string      `json:"description"`
		Sprite      []string     `json:"sprite"`
		CreatedAt   *UTCDateTime `json:"created_at"`
		UpdatedAt   *UTCDateTime `json:"updated_at"`
		PublishedAt *UTCDateTime `json:"published_at"`
	}

	var known knownFields
	if err := json.Unmarshal(data, &known); err != nil {
		return err
	}

	rawGridSize, ok := raw["grid_size"]
	if !ok {
		return fmt.Errorf("grid_size is required")
	}
	gridSize, err := parseJSONInteger(rawGridSize, "grid_size")
	if err != nil {
		return err
	}

	rawX, ok := raw["x"]
	if !ok {
		return fmt.Errorf("x is required")
	}
	x, err := parseJSONIntegerArray(rawX, "x")
	if err != nil {
		return err
	}

	rawY, ok := raw["y"]
	if !ok {
		return fmt.Errorf("y is required")
	}
	y, err := parseJSONIntegerArray(rawY, "y")
	if err != nil {
		return err
	}

	likes := 0
	if rawLikes, hasLikes := raw["likes"]; hasLikes {
		likes, err = parseJSONInteger(rawLikes, "likes")
		if err != nil {
			return err
		}
		if likes < 0 {
			return fmt.Errorf("likes must be non-negative")
		}
	}

	dislikes := 0
	if rawDislikes, hasDislikes := raw["dislikes"]; hasDislikes {
		dislikes, err = parseJSONInteger(rawDislikes, "dislikes")
		if err != nil {
			return err
		}
		if dislikes < 0 {
			return fmt.Errorf("dislikes must be non-negative")
		}
	}

	var submittedAt *UTCDateTime
	if rawSubmittedAt, ok := raw["submitted_at"]; ok {
		submittedAtUnix, err := parseJSONInteger(rawSubmittedAt, "submitted_at")
		if err != nil {
			return fmt.Errorf("submitted_at must be a unix timestamp")
		}
		parsed := UTCDateTime{Time: time.Unix(int64(submittedAtUnix), 0).UTC()}
		submittedAt = &parsed
	}

	components := map[string][]int{}
	for key, rawValue := range raw {
		switch key {
		case "key", "grid_size", "name", "description", "likes", "dislikes", "x", "y", "sprite", "created_at", "updated_at", "published_at", "submitted_at":
			continue
		}
		if _, ok := componentAllowed[key]; !ok {
			return fmt.Errorf("unknown component %s", key)
		}
		ids, err := parseJSONIntegerArray(rawValue, key)
		if err != nil {
			return fmt.Errorf("%s must be an array of entity IDs", key)
		}
		components[key] = ids
	}

	result := LevelValue{
		GridSize:    gridSize,
		Name:        known.Name,
		Description: known.Description,
		Likes:       likes,
		Dislikes:    dislikes,
		X:           x,
		Y:           y,
		Sprite:      known.Sprite,
		CreatedAt:   known.CreatedAt,
		UpdatedAt:   known.UpdatedAt,
		PublishedAt: known.PublishedAt,
	}
	if submittedAt != nil {
		if result.CreatedAt == nil {
			createdAt := *submittedAt
			result.CreatedAt = &createdAt
		}
		if result.UpdatedAt == nil {
			updatedAt := *submittedAt
			result.UpdatedAt = &updatedAt
		}
	}
	if len(components) > 0 {
		result.Components = components
	}
	*v = result
	return nil
}

func extractStoredLevelEntries(logger runtime.Logger, ownerID string, storedValue string) ([]LevelEntry, error) {
	return extractStoredLevelEntriesWithVisibility(logger, ownerID, storedValue, false)
}

func isPublishedLevel(level LevelValue) bool {
	return level.PublishedAt != nil
}

func extractStoredLevelEntriesWithVisibility(logger runtime.Logger, ownerID string, storedValue string, publishedOnly bool) ([]LevelEntry, error) {
	entries := []LevelEntry{}

	if strings.TrimSpace(storedValue) == "" {
		return entries, nil
	}

	allLevels, err := parseStoredLevels(storedValue)
	if err != nil {
		return nil, err
	}

	cleaned, _ := sanitizeStoredLevels(logger, ownerID, allLevels)
	entries = buildLevelEntries(ownerID, cleaned, publishedOnly)

	return entries, nil
}
