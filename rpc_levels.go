package main

import (
	"context"
	"crypto/sha1"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/heroiclabs/nakama-common/api"
	"github.com/heroiclabs/nakama-common/runtime"
)

func normalizeLevelVote(vote string) string {
	switch strings.ToLower(strings.TrimSpace(vote)) {
	case levelVoteLike:
		return levelVoteLike
	case levelVoteDislike:
		return levelVoteDislike
	default:
		return ""
	}
}

func levelVoteStorageKey(levelOwnerID, levelKey, voterID, levelIdentity string) string {
	digest := sha1.Sum([]byte(levelOwnerID + "\x1f" + levelKey + "\x1f" + voterID + "\x1f" + levelIdentity))
	return levelVoteKeyPrefix + "_" + hex.EncodeToString(digest[:])
}

func findStorageObject(objects []*api.StorageObject, collection, key, userID string) *api.StorageObject {
	for _, object := range objects {
		if object == nil {
			continue
		}
		if object.Collection != collection {
			continue
		}
		if object.Key != key {
			continue
		}
		if object.UserId != userID {
			continue
		}
		return object
	}
	return nil
}

func isStorageWriteVersionError(err error) bool {
	if err == nil {
		return false
	}
	message := strings.ToLower(err.Error())
	return strings.Contains(message, "version check failed") ||
		strings.Contains(message, "version check") ||
		strings.Contains(message, "version mismatch")
}

func rpcSubmitLevel(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	userID, ok := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
	if !ok || userID == "" {
		return "", runtime.NewError("authentication required", 16) // UNAUTHENTICATED
	}

	var req SubmitLevelRequest
	if err := json.Unmarshal([]byte(payload), &req); err != nil {
		return "", runtime.NewError("invalid json", 3) // INVALID_ARGUMENT
	}
	var level LevelValue
	if err := json.Unmarshal([]byte(payload), &level); err != nil {
		return "", runtime.NewError("invalid level data: "+err.Error(), 3)
	}
	currentKey := strings.TrimSpace(req.Key)
	submittedName := ""
	if level.Name != nil {
		submittedName = strings.TrimSpace(*level.Name)
	}
	key := submittedName
	if key == "" {
		key = currentKey
	}
	if key == "" {
		return "", runtime.NewError("name is required", 3)
	}
	levelName := key
	level.Name = &levelName

	publishIntent := level.PublishedAt != nil
	level.CreatedAt = nil
	level.UpdatedAt = nil
	level.PublishedAt = nil
	level.Likes = 0
	level.Dislikes = 0

	if err := validateLevelData(level, false); err != nil {
		return "", runtime.NewError("invalid level data: "+err.Error(), 3)
	}
	if err := validatePlayableLevel(level); err != nil {
		return "", runtime.NewError("invalid level data: "+err.Error(), 3)
	}

	// Read existing levels doc (or start with empty array). Any corrupted entries
	// are dropped and overwritten on save.
	allLevels := []LevelValue{}
	objects, err := nk.StorageRead(ctx, []*runtime.StorageRead{
		{Collection: LevelCollection, Key: LevelStorageKey, UserID: userID},
	})
	if err != nil {
		logger.Error("storage read error: %v", err)
		return "", runtime.NewError("failed to read levels", 13)
	}
	if len(objects) > 0 && strings.TrimSpace(objects[0].Value) != "" {
		allLevels, _, err = decodeAndSanitizeStoredLevels(logger, userID, objects[0].Value)
		if err != nil {
			logger.Error("failed to parse existing levels: %v", err)
			return "", runtime.NewError("corrupted levels data", 13)
		}
	}

	existingPublished := false
	var existingCreatedAt *UTCDateTime
	existingLikes := 0
	existingDislikes := 0
	existingIndex := -1
	if currentKey != "" {
		for i, existingLevel := range allLevels {
			if levelKey(existingLevel) != currentKey {
				continue
			}
			existingIndex = i
			break
		}
	}
	if existingIndex < 0 {
		for i, existingLevel := range allLevels {
			if levelKey(existingLevel) != key {
				continue
			}
			existingIndex = i
			break
		}
	}

	for i, existingLevel := range allLevels {
		if levelKey(existingLevel) != key {
			continue
		}
		if existingIndex >= 0 && i == existingIndex {
			continue
		}
		return "", runtime.NewError("level name already exists", 3)
	}

	if existingIndex >= 0 {
		existingLevel := allLevels[existingIndex]
		if existingLevel.PublishedAt != nil {
			existingPublished = true
		}
		if existingLevel.CreatedAt != nil {
			existingCreatedAt = existingLevel.CreatedAt
		}
		existingLikes = existingLevel.Likes
		existingDislikes = existingLevel.Dislikes
	}

	if existingPublished {
		return "", runtime.NewError("published levels are read-only; delete and recreate to change them", 3)
	}

	nowUTC := UTCDateTime{Time: time.Now().UTC()}
	if existingCreatedAt != nil {
		createdAt := *existingCreatedAt
		level.CreatedAt = &createdAt
	} else {
		createdAt := nowUTC
		level.CreatedAt = &createdAt
	}
	updatedAt := nowUTC
	level.UpdatedAt = &updatedAt
	if publishIntent {
		publishedAt := nowUTC
		level.PublishedAt = &publishedAt
	} else {
		level.PublishedAt = nil
	}
	if existingIndex >= 0 {
		level.Likes = existingLikes
		level.Dislikes = existingDislikes
	}

	if err := validateLevelData(level, true); err != nil {
		return "", runtime.NewError("invalid level data: "+err.Error(), 3)
	}

	if existingIndex >= 0 {
		allLevels[existingIndex] = level
	} else {
		if len(allLevels) >= maxLevelsPerUser {
			return "", runtime.NewError(fmt.Sprintf("maximum of %d levels reached", maxLevelsPerUser), 3) // INVALID_ARGUMENT
		}
		allLevels = append(allLevels, level)
	}

	version, err := writeStoredLevels(ctx, nk, userID, allLevels)
	if err != nil {
		logger.Error("storage write error: %v", err)
		return "", runtime.NewError("failed to save level", 13) // INTERNAL
	}

	resp, _ := json.Marshal(map[string]interface{}{
		"version": version,
	})
	return string(resp), nil
}

func rpcGetLevel(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	callerID, ok := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
	if !ok || callerID == "" {
		return "", runtime.NewError("authentication required", 16)
	}

	var req GetLevelRequest
	if err := json.Unmarshal([]byte(payload), &req); err != nil {
		return "", runtime.NewError("invalid json", 3)
	}
	req.UserID = strings.TrimSpace(req.UserID)
	req.Key = strings.TrimSpace(req.Key)
	if req.UserID == "" || req.Key == "" {
		return "", runtime.NewError("user_id and key are required", 3)
	}

	objects, err := nk.StorageRead(ctx, []*runtime.StorageRead{
		{Collection: LevelCollection, Key: LevelStorageKey, UserID: req.UserID},
	})
	if err != nil {
		logger.Error("storage read error: %v", err)
		return "", runtime.NewError("failed to read level", 13)
	}

	allLevels := []LevelValue{}
	responseVersion := ""
	if len(objects) > 0 {
		levelsChanged := false
		allLevels, levelsChanged, err = decodeAndSanitizeStoredLevels(logger, req.UserID, objects[0].Value)
		if err != nil {
			return "", runtime.NewError("corrupted levels data", 13)
		}
		responseVersion = objects[0].Version
		if levelsChanged {
			cleanedVersion, writeErr := writeStoredLevels(ctx, nk, req.UserID, allLevels)
			if writeErr != nil {
				logger.Error("failed to clean invalid levels for user %s: %v", req.UserID, writeErr)
				return "", runtime.NewError("failed to read level", 13)
			}
			if cleanedVersion != "" {
				responseVersion = cleanedVersion
			}
		}
	}

	var levelValue *LevelValue
	for i := range allLevels {
		if levelKey(allLevels[i]) != req.Key {
			continue
		}
		levelValue = &allLevels[i]
		break
	}
	if levelValue == nil && req.UserID == callerID {
		defaultLevels := loadDefaultLevels(logger)
		for i := range defaultLevels {
			if levelKey(defaultLevels[i]) != req.Key {
				continue
			}
			levelValue = &defaultLevels[i]
			break
		}
	}
	if levelValue == nil {
		return "", runtime.NewError("level not found", 5)
	}
	if req.UserID != callerID && !isPublishedLevel(*levelValue) {
		return "", runtime.NewError("level not found", 5)
	}

	ownerUsername := ""
	if ownerUsers, lookupErr := nk.UsersGetId(ctx, []string{req.UserID}, nil); lookupErr == nil {
		for _, u := range ownerUsers {
			if u != nil {
				ownerUsername = u.Username
				break
			}
		}
	}

	resp, _ := json.Marshal(GetLevelResponse{
		Key:      req.Key,
		UserID:   req.UserID,
		Username: ownerUsername,
		Value:    *levelValue,
		Version:  responseVersion,
	})
	return string(resp), nil
}

func rpcListMyLevels(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	userID, ok := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
	if !ok || userID == "" {
		return "", runtime.NewError("authentication required", 16)
	}

	objects, err := nk.StorageRead(ctx, []*runtime.StorageRead{
		{Collection: LevelCollection, Key: LevelStorageKey, UserID: userID},
	})
	if err != nil {
		logger.Error("storage read error: %v", err)
		return "", runtime.NewError("failed to list levels", 13)
	}

	entries := []LevelEntry{}
	if len(objects) > 0 {
		allLevels, levelsChanged, err := decodeAndSanitizeStoredLevels(logger, userID, objects[0].Value)
		if err != nil {
			return "", runtime.NewError("corrupted levels data", 13)
		}
		if levelsChanged {
			if _, writeErr := writeStoredLevels(ctx, nk, userID, allLevels); writeErr != nil {
				logger.Error("failed to clean invalid levels for user %s: %v", userID, writeErr)
				return "", runtime.NewError("failed to list levels", 13)
			}
		}
		entries = append(entries, buildLevelEntries(userID, allLevels, false)...)
	}

	callerUsername, _ := ctx.Value(runtime.RUNTIME_CTX_USERNAME).(string)
	for i := range entries {
		entries[i].Username = callerUsername
	}

	resp, _ := json.Marshal(ListLevelsResponse{
		Levels: entries,
	})
	return string(resp), nil
}

func rpcListSinglePlayerLevels(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	userID, ok := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
	if !ok || userID == "" {
		return "", runtime.NewError("authentication required", 16)
	}

	levels := loadDefaultLevels(logger)
	entries := buildLevelEntries(userID, levels, false)

	resp, _ := json.Marshal(ListLevelsResponse{
		Levels: entries,
	})
	return string(resp), nil
}

func rpcListAllLevels(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	userID, ok := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
	if !ok || userID == "" {
		return "", runtime.NewError("authentication required", 16)
	}

	var req ListAllLevelsRequest
	if payload != "" {
		if err := json.Unmarshal([]byte(payload), &req); err != nil {
			return "", runtime.NewError("invalid json", 3)
		}
	}

	limit := req.Limit
	if limit <= 0 {
		limit = 25
	}
	if limit > 100 {
		limit = 100
	}

	objects, nextCursor, err := nk.StorageList(ctx, userID, "", LevelCollection, limit, req.Cursor)
	if err != nil {
		logger.Error("storage list error: %v", err)
		return "", runtime.NewError("failed to list levels", 13)
	}

	entries := []LevelEntry{}
	for _, object := range objects {
		if object == nil || object.Key != LevelStorageKey {
			continue
		}

		allLevels, levelsChanged, err := decodeAndSanitizeStoredLevels(logger, object.UserId, object.Value)
		if err != nil {
			logger.Error("corrupted levels data for user %s: %v", object.UserId, err)
			continue
		}
		if levelsChanged {
			if _, writeErr := writeStoredLevels(ctx, nk, object.UserId, allLevels); writeErr != nil {
				logger.Error("failed to clean invalid levels for user %s: %v", object.UserId, writeErr)
			}
		}
		entries = append(entries, buildLevelEntries(object.UserId, allLevels, true)...)
	}

	entryUserIDs := make([]string, 0, len(entries))
	for _, e := range entries {
		entryUserIDs = append(entryUserIDs, e.UserID)
	}
	usernameMap := resolveUsernames(ctx, nk, entryUserIDs)
	for i := range entries {
		entries[i].Username = usernameMap[entries[i].UserID]
	}

	resp, _ := json.Marshal(ListLevelsResponse{
		Levels:     entries,
		NextCursor: nextCursor,
	})
	return string(resp), nil
}

func rpcListFriendLevels(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	userID, ok := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
	if !ok || userID == "" {
		return "", runtime.NewError("authentication required", 16)
	}

	var req ListFriendLevelsRequest
	if payload != "" {
		if err := json.Unmarshal([]byte(payload), &req); err != nil {
			return "", runtime.NewError("invalid json", 3)
		}
	}

	limit := req.Limit
	if limit <= 0 {
		limit = 100
	}
	if limit > 100 {
		limit = 100
	}

	friendState := 0
	friends, nextCursor, err := nk.FriendsList(ctx, userID, limit, &friendState, req.Cursor)
	if err != nil {
		logger.Error("friends list error: %v", err)
		return "", runtime.NewError("failed to list friends", 13)
	}

	reads := make([]*runtime.StorageRead, 0, len(friends))
	friendUsernames := make(map[string]string, len(friends))
	for _, friend := range friends {
		if friend == nil || friend.GetUser() == nil || friend.GetUser().Id == "" {
			continue
		}
		friendUsernames[friend.GetUser().Id] = friend.GetUser().Username
		reads = append(reads, &runtime.StorageRead{
			Collection: LevelCollection,
			Key:        LevelStorageKey,
			UserID:     friend.GetUser().Id,
		})
	}

	entries := []LevelEntry{}
	if len(reads) > 0 {
		objects, err := nk.StorageRead(ctx, reads)
		if err != nil {
			logger.Error("storage read error: %v", err)
			return "", runtime.NewError("failed to list friend levels", 13)
		}

		for _, object := range objects {
			if object == nil || object.Key != LevelStorageKey {
				continue
			}

			allLevels, levelsChanged, err := decodeAndSanitizeStoredLevels(logger, object.UserId, object.Value)
			if err != nil {
				logger.Error("corrupted levels data for user %s: %v", object.UserId, err)
				continue
			}
			if levelsChanged {
				if _, writeErr := writeStoredLevels(ctx, nk, object.UserId, allLevels); writeErr != nil {
					logger.Error("failed to clean invalid levels for user %s: %v", object.UserId, writeErr)
				}
			}
			entries = append(entries, buildLevelEntries(object.UserId, allLevels, true)...)
		}
	}

	for i := range entries {
		entries[i].Username = friendUsernames[entries[i].UserID]
	}

	resp, _ := json.Marshal(ListLevelsResponse{
		Levels:     entries,
		NextCursor: nextCursor,
	})
	return string(resp), nil
}

func rpcSubmitLevelVote(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	userID, ok := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
	if !ok || userID == "" {
		return "", runtime.NewError("authentication required", 16)
	}

	var req SubmitLevelVoteRequest
	if err := json.Unmarshal([]byte(payload), &req); err != nil {
		return "", runtime.NewError("invalid json", 3)
	}
	req.LevelOwnerID = strings.TrimSpace(req.LevelOwnerID)
	req.LevelKey = strings.TrimSpace(req.LevelKey)
	vote := normalizeLevelVote(req.Vote)
	if req.LevelOwnerID == "" || req.LevelKey == "" {
		return "", runtime.NewError("level_owner_id and level_key are required", 3)
	}
	if vote == "" {
		return "", runtime.NewError("vote must be 'like' or 'dislike'", 3)
	}
	if userID == req.LevelOwnerID {
		return "", runtime.NewError("cannot vote on your own level", 3) // INVALID_ARGUMENT
	}

	for attempt := 0; attempt < maxLevelVoteWriteAttempts; attempt++ {
		objects, err := nk.StorageRead(ctx, []*runtime.StorageRead{
			{Collection: LevelCollection, Key: LevelStorageKey, UserID: req.LevelOwnerID},
		})
		if err != nil {
			logger.Error("storage read error: %v", err)
			return "", runtime.NewError("failed to submit level vote", 13)
		}

		levelsObject := findStorageObject(objects, LevelCollection, LevelStorageKey, req.LevelOwnerID)
		if levelsObject == nil || strings.TrimSpace(levelsObject.Value) == "" {
			return "", runtime.NewError("level not found", 5)
		}

		allLevels, _, decodeErr := decodeAndSanitizeStoredLevels(logger, req.LevelOwnerID, levelsObject.Value)
		if decodeErr != nil {
			return "", runtime.NewError("corrupted levels data", 13)
		}

		levelIndex := -1
		for i := range allLevels {
			if levelKey(allLevels[i]) != req.LevelKey {
				continue
			}
			levelIndex = i
			break
		}
		if levelIndex < 0 {
			return "", runtime.NewError("level not found", 5)
		}

		targetLevel := allLevels[levelIndex]
		if !isPublishedLevel(targetLevel) {
			return "", runtime.NewError("level not found", 5)
		}
		levelIdentity := "legacy"
		if targetLevel.CreatedAt != nil {
			levelIdentity = targetLevel.CreatedAt.Time.UTC().Format(time.RFC3339Nano)
		}
		voteKey := levelVoteStorageKey(req.LevelOwnerID, req.LevelKey, userID, levelIdentity)

		voteObjects, voteReadErr := nk.StorageRead(ctx, []*runtime.StorageRead{
			{Collection: LevelVoteCollection, Key: voteKey, UserID: ""},
		})
		if voteReadErr != nil {
			logger.Error("vote storage read error: %v", voteReadErr)
			return "", runtime.NewError("failed to submit level vote", 13)
		}
		voteObject := findStorageObject(voteObjects, LevelVoteCollection, voteKey, "")
		if voteObject != nil && strings.TrimSpace(voteObject.Value) != "" {
			return "", runtime.NewError("player already voted for this level", 6)
		}

		switch vote {
		case levelVoteLike:
			targetLevel.Likes++
		case levelVoteDislike:
			targetLevel.Dislikes++
		}
		allLevels[levelIndex] = targetLevel

		levelsValue, marshalErr := marshalStoredLevels(allLevels)
		if marshalErr != nil {
			logger.Error("failed to marshal level vote update for %s/%s: %v", req.LevelOwnerID, req.LevelKey, marshalErr)
			return "", runtime.NewError("failed to submit level vote", 13)
		}

		voteValueBytes, voteMarshalErr := json.Marshal(map[string]interface{}{
			"level_owner_id": req.LevelOwnerID,
			"level_key":      req.LevelKey,
			"user_id":        userID,
			"vote":           vote,
			"level_identity": levelIdentity,
			"created_at":     time.Now().UTC().Format(time.RFC3339Nano),
		})
		if voteMarshalErr != nil {
			logger.Error("failed to marshal level vote record for %s/%s: %v", req.LevelOwnerID, req.LevelKey, voteMarshalErr)
			return "", runtime.NewError("failed to submit level vote", 13)
		}

		_, writeErr := nk.StorageWrite(ctx, []*runtime.StorageWrite{
			{
				Collection:      LevelCollection,
				Key:             LevelStorageKey,
				UserID:          req.LevelOwnerID,
				Value:           levelsValue,
				Version:         levelsObject.Version,
				PermissionRead:  2,
				PermissionWrite: 1,
			},
			{
				Collection:      LevelVoteCollection,
				Key:             voteKey,
				UserID:          "",
				Value:           string(voteValueBytes),
				Version:         "*",
				PermissionRead:  0,
				PermissionWrite: 0,
			},
		})
		if writeErr == nil {
			resp, _ := json.Marshal(SubmitLevelVoteResponse{
				Likes:    targetLevel.Likes,
				Dislikes: targetLevel.Dislikes,
				Vote:     vote,
			})
			return string(resp), nil
		}

		voteCheck, voteReadErr := nk.StorageRead(ctx, []*runtime.StorageRead{
			{Collection: LevelVoteCollection, Key: voteKey, UserID: ""},
		})
		if voteReadErr == nil {
			voteState := findStorageObject(voteCheck, LevelVoteCollection, voteKey, "")
			if voteState != nil && strings.TrimSpace(voteState.Value) != "" {
				return "", runtime.NewError("player already voted for this level", 6)
			}
		}

		if isStorageWriteVersionError(writeErr) {
			continue
		}
		logger.Error("storage write error while voting on %s/%s: %v", req.LevelOwnerID, req.LevelKey, writeErr)
		return "", runtime.NewError("failed to submit level vote", 13)
	}

	logger.Error("failed to submit level vote for %s/%s after retries", req.LevelOwnerID, req.LevelKey)
	return "", runtime.NewError("failed to submit level vote", 13)
}

func rpcDeleteLevel(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	userID, ok := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
	if !ok || userID == "" {
		return "", runtime.NewError("authentication required", 16) // UNAUTHENTICATED
	}

	var req DeleteLevelRequest
	if err := json.Unmarshal([]byte(payload), &req); err != nil {
		return "", runtime.NewError("invalid json", 3) // INVALID_ARGUMENT
	}
	req.Key = strings.TrimSpace(req.Key)
	if req.Key == "" {
		return "", runtime.NewError("key is required", 3)
	}

	objects, err := nk.StorageRead(ctx, []*runtime.StorageRead{
		{Collection: LevelCollection, Key: LevelStorageKey, UserID: userID},
	})
	if err != nil {
		logger.Error("storage read error: %v", err)
		return "", runtime.NewError("failed to read levels", 13)
	}

	allLevels := []LevelValue{}
	levelsChanged := false
	if len(objects) > 0 && strings.TrimSpace(objects[0].Value) != "" {
		allLevels, levelsChanged, err = decodeAndSanitizeStoredLevels(logger, userID, objects[0].Value)
		if err != nil {
			return "", runtime.NewError("corrupted levels data", 13)
		}
	}

	found := false
	filtered := make([]LevelValue, 0, len(allLevels))
	for _, level := range allLevels {
		if levelKey(level) == req.Key {
			found = true
			continue
		}
		filtered = append(filtered, level)
	}

	if !found {
		if levelsChanged {
			if _, writeErr := writeStoredLevels(ctx, nk, userID, filtered); writeErr != nil {
				logger.Error("storage write error while cleaning levels: %v", writeErr)
				return "", runtime.NewError("failed to delete level", 13)
			}
		}
		return "", runtime.NewError("level not found", 5) // NOT_FOUND
	}

	if _, err := writeStoredLevels(ctx, nk, userID, filtered); err != nil {
		logger.Error("storage write error: %v", err)
		return "", runtime.NewError("failed to delete level", 13)
	}

	// Clean up the associated leaderboard so scores don't persist as orphaned data.
	leaderboardID := userID + "_" + req.Key
	if err := nk.LeaderboardDelete(ctx, leaderboardID); err != nil {
		if !isLeaderboardNotFoundError(err) {
			logger.Error("leaderboard delete error: %v", err)
		}
	}

	resp, _ := json.Marshal(map[string]interface{}{"ok": true})
	return string(resp), nil
}

func rpcPublishLevel(ctx context.Context, logger runtime.Logger, db *sql.DB, nk runtime.NakamaModule, payload string) (string, error) {
	userID, ok := ctx.Value(runtime.RUNTIME_CTX_USER_ID).(string)
	if !ok || userID == "" {
		return "", runtime.NewError("authentication required", 16) // UNAUTHENTICATED
	}

	var req PublishLevelRequest
	if err := json.Unmarshal([]byte(payload), &req); err != nil {
		return "", runtime.NewError("invalid json", 3) // INVALID_ARGUMENT
	}
	req.Key = strings.TrimSpace(req.Key)
	if req.Key == "" {
		return "", runtime.NewError("key is required", 3)
	}

	objects, err := nk.StorageRead(ctx, []*runtime.StorageRead{
		{Collection: LevelCollection, Key: LevelStorageKey, UserID: userID},
	})
	if err != nil {
		logger.Error("storage read error: %v", err)
		return "", runtime.NewError("failed to read levels", 13)
	}
	if len(objects) == 0 || strings.TrimSpace(objects[0].Value) == "" {
		return "", runtime.NewError("level not found", 5) // NOT_FOUND
	}

	allLevels, levelsChanged, err := decodeAndSanitizeStoredLevels(logger, userID, objects[0].Value)
	if err != nil {
		return "", runtime.NewError("corrupted levels data", 13)
	}

	targetIndex := -1
	for i, level := range allLevels {
		if levelKey(level) == req.Key {
			targetIndex = i
			break
		}
	}
	if targetIndex < 0 {
		if levelsChanged {
			if _, writeErr := writeStoredLevels(ctx, nk, userID, allLevels); writeErr != nil {
				logger.Error("storage write error while cleaning levels: %v", writeErr)
				return "", runtime.NewError("failed to publish level", 13)
			}
		}
		return "", runtime.NewError("level not found", 5)
	}

	targetLevel := allLevels[targetIndex]
	needsWrite := levelsChanged
	nowUTC := UTCDateTime{Time: time.Now().UTC()}
	if targetLevel.CreatedAt == nil {
		createdAt := nowUTC
		targetLevel.CreatedAt = &createdAt
		needsWrite = true
	}
	if targetLevel.PublishedAt == nil {
		publishedAt := nowUTC
		targetLevel.PublishedAt = &publishedAt
		updatedAt := nowUTC
		targetLevel.UpdatedAt = &updatedAt
		needsWrite = true
	}

	if err := validateLevelData(targetLevel, true); err != nil {
		return "", runtime.NewError("invalid level data: "+err.Error(), 3)
	}
	if err := validatePlayableLevel(targetLevel); err != nil {
		return "", runtime.NewError("invalid level data: "+err.Error(), 3)
	}

	allLevels[targetIndex] = targetLevel

	version := objects[0].Version
	if needsWrite {
		writtenVersion, writeErr := writeStoredLevels(ctx, nk, userID, allLevels)
		if writeErr != nil {
			logger.Error("storage write error: %v", writeErr)
			return "", runtime.NewError("failed to publish level", 13)
		}
		if writtenVersion != "" {
			version = writtenVersion
		}
	}

	publishedAtText := ""
	if targetLevel.PublishedAt != nil {
		publishedAtText = targetLevel.PublishedAt.Time.UTC().Format(time.RFC3339Nano)
	}

	resp, _ := json.Marshal(map[string]interface{}{
		"ok":           true,
		"version":      version,
		"published_at": publishedAtText,
	})
	return string(resp), nil
}
